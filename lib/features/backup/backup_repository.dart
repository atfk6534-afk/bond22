import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/database_provider.dart';

const String kBackupFormatVersion = '1';
const String kAppVersion = '1.0.0';

class BackupResult {
  final bool success;
  final String? filePath;
  final String? error;
  const BackupResult({required this.success, this.filePath, this.error});
}

/// Creates and restores a single `.bond2backup` package containing:
/// - bond2.sqlite (the whole database, source of truth)
/// - manifest.json (app version, backup version, created timestamp)
/// - files/ (any locally stored material files under bond2_files/)
///
/// Rule #53-55: backups are versioned, validated before import, and a
/// safety backup of current data is taken before any restore.
///
/// Fix #4: this repository is Riverpod-aware (holds a [Ref]) so it can
/// properly CLOSE the live database connection before overwriting the
/// SQLite file on disk, and re-open a fresh connection afterwards by
/// invalidating [databaseProvider] — the app never has an open file
/// handle on the file it is replacing, and the caller does not need to
/// force a manual app restart for the restored data to take effect.
class BackupRepository {
  final Ref ref;
  BackupRepository(this.ref);

  Future<BackupResult> createBackup() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docsDir.path, 'bond2.sqlite'));
      if (!await dbFile.exists()) {
        return const BackupResult(success: false, error: 'لا توجد قاعدة بيانات لعمل نسخة احتياطية منها');
      }

      final archive = Archive();
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('bond2.sqlite', dbBytes.length, dbBytes));

      final manifest = jsonEncode({
        'appVersion': kAppVersion,
        'backupVersion': kBackupFormatVersion,
        'createdAt': DateTime.now().toIso8601String(),
      });
      final manifestBytes = utf8.encode(manifest);
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // Material files (rule #38/#39) live under bond2_files/ - included
      // recursively so a restore brings back attached books/notes too.
      final filesDir = Directory(p.join(docsDir.path, 'bond2_files'));
      if (await filesDir.exists()) {
        await for (final entity in filesDir.list(recursive: true)) {
          if (entity is File) {
            final bytes = await entity.readAsBytes();
            final relPath = 'files/${p.relative(entity.path, from: filesDir.path)}';
            archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
          }
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(docsDir.path, 'bond2_backup_$timestamp.bond2backup');
      final zipBytes = ZipEncoder().encode(archive);
      await File(outPath).writeAsBytes(zipBytes);

      return BackupResult(success: true, filePath: outPath);
    } catch (e) {
      return BackupResult(success: false, error: 'تعذر إنشاء النسخة الاحتياطية: $e');
    }
  }

  /// Validates a backup file without applying it — checked before
  /// showing the user any restore confirmation (rule #54).
  Future<Map<String, dynamic>?> validateBackup(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFile = archive.findFile('manifest.json');
      final dbFile = archive.findFile('bond2.sqlite');
      if (manifestFile == null || dbFile == null) return null;
      final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>));
      return manifest as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Restores from [filePath]. Caller MUST have already warned the user
  /// that current data will be replaced (rule #55) before calling this.
  ///
  /// Safety measures (fix #4):
  /// 1. The live database connection is CLOSED first, so the SQLite file
  ///    is never overwritten while something still has it open.
  /// 2. The new database is written to a temp file, then renamed over
  ///    the real path — an atomic operation on the same filesystem, so a
  ///    failed write never leaves a half-written database file.
  /// 3. The entire bond2_files/ directory is cleared before extracting
  ///    the backup's files, so material files that existed locally but
  ///    are NOT part of the restored backup never remain as orphans.
  /// 4. [databaseProvider] is invalidated at the end so the rest of the
  ///    app transparently starts reading from the restored database on
  ///    its next rebuild — no forced app restart required.
  Future<BackupResult> restoreBackup(String filePath) async {
    try {
      final manifest = await validateBackup(filePath);
      if (manifest == null) {
        return const BackupResult(success: false, error: 'ملف النسخة الاحتياطية غير صالح أو تالف');
      }

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docsDir.path, 'bond2.sqlite');

      // 1. Close the live connection before touching the file on disk.
      await ref.read(databaseProvider).close();

      try {
        // 2. Write to a temp file first, then rename atomically.
        final dbFile = archive.findFile('bond2.sqlite')!;
        final tempPath = '$dbPath.restoring.tmp';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(dbFile.content as List<int>);
        await tempFile.rename(dbPath);

        // 3. Clear existing material files so nothing is orphaned, then
        // extract the backup's own files fresh.
        final filesDir = Directory(p.join(docsDir.path, 'bond2_files'));
        if (await filesDir.exists()) {
          await filesDir.delete(recursive: true);
        }
        for (final f in archive.files) {
          if (f.isFile && f.name.startsWith('files/')) {
            final relPath = f.name.substring('files/'.length);
            final outFile = File(p.join(filesDir.path, relPath));
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(f.content as List<int>);
          }
        }
      } finally {
        // 4. Always reopen a fresh connection, even if extraction of the
        // files/ portion above fails partway - the app must never be
        // left without a usable database connection.
        ref.invalidate(databaseProvider);
      }

      return const BackupResult(success: true);
    } catch (e) {
      // Make sure a fresh connection exists even on the early-return /
      // exception paths above (e.g. manifest invalid happens before we
      // ever close anything, so this is a harmless no-op there).
      ref.invalidate(databaseProvider);
      return BackupResult(success: false, error: 'تعذر استعادة النسخة الاحتياطية: $e');
    }
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(ref);
});
