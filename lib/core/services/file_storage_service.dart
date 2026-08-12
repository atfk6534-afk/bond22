import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies files the teacher picks (e.g. from Downloads) into BOND2's own
/// persistent app storage, so backups are complete and the app never
/// depends on an external file staying in place (rule #38, fix #3).
///
/// Files are named after a stable internal ID (never the student's or
/// material's Arabic name) to avoid filesystem-unsafe characters and
/// duplicate-name collisions entirely.
class FileStorageService {
  const FileStorageService._();

  static Future<Directory> _materialsDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'bond2_files', 'materials'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies [sourcePath] into persistent storage under a filename based
  /// on [materialId] (e.g. `<materialId>.pdf`), replacing any previous
  /// file stored for the same material id first (safe re-upload, no
  /// orphaned duplicates left behind). Returns the new persistent path.
  static Future<String> storeMaterialFile({
    required String materialId,
    required String sourcePath,
  }) async {
    final dir = await _materialsDir();

    // Remove any existing file(s) previously stored for this material -
    // handles duplicate filenames / re-uploads safely.
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && p.basenameWithoutExtension(entity.path) == materialId) {
          await entity.delete();
        }
      }
    }

    final extension = p.extension(sourcePath); // includes the dot, may be ''
    final destPath = p.join(dir.path, '$materialId$extension');
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static Future<void> deleteMaterialFile(String materialId) async {
    final dir = await _materialsDir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && p.basenameWithoutExtension(entity.path) == materialId) {
        await entity.delete();
      }
    }
  }
}
