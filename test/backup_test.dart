import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/core/database/database_provider.dart';
import 'package:bond2/features/backup/backup_repository.dart';

/// Fakes path_provider so tests run on a plain Dart VM (no Android/iOS
/// platform channels available) and point at a real temp directory.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory dir;
  _FakePathProviderPlatform(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bond2_backup_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    // Simulate an existing database file, since createBackup() reads it
    // directly from disk (the source of truth on the filesystem).
    await File(p.join(tempDir.path, 'bond2.sqlite')).writeAsString('fake-sqlite-bytes');

    // Drive BackupRepository through a real ProviderContainer, exactly
    // like production (backupRepositoryProvider -> BackupRepository(ref)),
    // but with an in-memory AppDatabase so restoreBackup()'s
    // ref.read(databaseProvider).close() is safe and never touches a
    // real native sqlite file (fix #4 test coverage).
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(openTestDatabase())],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Backup & restore (rules #53-55, #80 flow 8)', () {
    test('createBackup produces a validated .bond2backup package', () async {
      final repo = container.read(backupRepositoryProvider);
      final result = await repo.createBackup();

      expect(result.success, isTrue);
      expect(result.filePath, isNotNull);
      expect(File(result.filePath!).existsSync(), isTrue);

      final manifest = await repo.validateBackup(result.filePath!);
      expect(manifest, isNotNull);
      expect(manifest!['backupVersion'], kBackupFormatVersion);
      expect(manifest['appVersion'], kAppVersion);
    });

    test('validateBackup rejects a corrupt/invalid file without throwing', () async {
      final repo = container.read(backupRepositoryProvider);
      final badFile = File(p.join(tempDir.path, 'not_a_backup.bond2backup'));
      await badFile.writeAsString('this is not a zip archive');

      final manifest = await repo.validateBackup(badFile.path);
      expect(manifest, isNull);
    });

    test('restoreBackup replaces the database file from a valid package', () async {
      final repo = container.read(backupRepositoryProvider);
      final backupResult = await repo.createBackup();
      expect(backupResult.success, isTrue);

      // Simulate current data changing after the backup was taken.
      await File(p.join(tempDir.path, 'bond2.sqlite')).writeAsString('different-bytes-now');

      final restoreResult = await repo.restoreBackup(backupResult.filePath!);
      expect(restoreResult.success, isTrue);

      final restoredContent = await File(p.join(tempDir.path, 'bond2.sqlite')).readAsString();
      expect(restoredContent, 'fake-sqlite-bytes'); // back to the backed-up state
    });

    test('FIX #4: restoreBackup closes the old DB connection before overwriting the file', () async {
      final repo = container.read(backupRepositoryProvider);
      final backupResult = await repo.createBackup();

      // Reading the live db now proves it is open and usable.
      final dbBefore = container.read(databaseProvider);
      await dbBefore.customSelect('SELECT 1').get();

      await repo.restoreBackup(backupResult.filePath!);

      // After restore, databaseProvider must have been invalidated and
      // rebuilt into a NEW, independent, still-usable connection - the
      // old one is closed, not silently left dangling or reused.
      final dbAfter = container.read(databaseProvider);
      expect(identical(dbBefore, dbAfter), isFalse);
      await dbAfter.customSelect('SELECT 1').get(); // still usable
    });

    test('FIX #4: restoreBackup clears local material files not present in the backup (no orphans)', () async {
      final repo = container.read(backupRepositoryProvider);

      // Take a backup with NO material files present.
      final backupResult = await repo.createBackup();
      expect(backupResult.success, isTrue);

      // Now simulate a material file that was added locally AFTER that
      // backup was taken (so it is not part of the backup package).
      final materialsDir = Directory(p.join(tempDir.path, 'bond2_files', 'materials'));
      await materialsDir.create(recursive: true);
      final orphanFile = File(p.join(materialsDir.path, 'some-material-id.pdf'));
      await orphanFile.writeAsBytes([1, 2, 3]);
      expect(await orphanFile.exists(), isTrue);

      await repo.restoreBackup(backupResult.filePath!);

      // The orphaned file (not part of the restored backup) must be gone.
      expect(await orphanFile.exists(), isFalse);
    });

    test('FIX #4: restoreBackup brings back material files that WERE in the backup', () async {
      final repo = container.read(backupRepositoryProvider);

      final materialsDir = Directory(p.join(tempDir.path, 'bond2_files', 'materials'));
      await materialsDir.create(recursive: true);
      final materialFile = File(p.join(materialsDir.path, 'abc-123.pdf'));
      await materialFile.writeAsBytes([9, 9, 9]);

      final backupResult = await repo.createBackup();
      expect(backupResult.success, isTrue);

      // Delete the local file to simulate data loss, then restore.
      await materialFile.delete();
      expect(await materialFile.exists(), isFalse);

      await repo.restoreBackup(backupResult.filePath!);

      expect(await materialFile.exists(), isTrue);
      expect(await materialFile.readAsBytes(), [9, 9, 9]);
    });
  });
}
