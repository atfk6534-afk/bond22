import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/core/services/file_storage_service.dart';
import 'package:bond2/features/materials/materials_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory dir;
  _FakePathProviderPlatform(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  late Directory tempDir;
  late Directory externalSourceDir;
  late AppDatabase db;
  late MaterialsRepository materialsRepo;
  late StudentsRepository studentsRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bond2_files_test_docs_');
    externalSourceDir = await Directory.systemTemp.createTemp('bond2_files_test_external_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    db = openTestDatabase();
    materialsRepo = MaterialsRepository(db);
    studentsRepo = StudentsRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await externalSourceDir.exists()) await externalSourceDir.delete(recursive: true);
  });

  group('FileStorageService (fix #3)', () {
    test('copies an external file into bond2_files/materials/<materialId>.ext', () async {
      final externalFile = File(p.join(externalSourceDir.path, 'كتاب الفيزياء.pdf'));
      await externalFile.writeAsBytes([1, 2, 3, 4]);

      final persistentPath = await FileStorageService.storeMaterialFile(
        materialId: 'material-abc-123',
        sourcePath: externalFile.path,
      );

      // Stored under BOND2's own directory, not the external location.
      expect(persistentPath, contains('bond2_files'));
      expect(persistentPath, contains('materials'));
      // Named after the material ID, never the (possibly Arabic) original name.
      expect(p.basename(persistentPath), 'material-abc-123.pdf');
      expect(persistentPath, isNot(contains('كتاب الفيزياء')));

      expect(await File(persistentPath).exists(), isTrue);
      expect(await File(persistentPath).readAsBytes(), [1, 2, 3, 4]);

      // The original external file is untouched (copy, not move).
      expect(await externalFile.exists(), isTrue);
    });

    test('re-storing a file for the same material id replaces the old one (no duplicates)', () async {
      final firstSource = File(p.join(externalSourceDir.path, 'v1.pdf'));
      await firstSource.writeAsBytes([1]);
      final secondSource = File(p.join(externalSourceDir.path, 'v2.docx'));
      await secondSource.writeAsBytes([2, 2]);

      final firstPath = await FileStorageService.storeMaterialFile(
        materialId: 'mat-1', sourcePath: firstSource.path,
      );
      expect(await File(firstPath).exists(), isTrue);

      final secondPath = await FileStorageService.storeMaterialFile(
        materialId: 'mat-1', sourcePath: secondSource.path,
      );

      // Old file (different extension) must be gone, not left orphaned.
      expect(await File(firstPath).exists(), isFalse);
      expect(await File(secondPath).exists(), isTrue);
      expect(await File(secondPath).readAsBytes(), [2, 2]);
    });

    test('deleteMaterialFile removes the stored file', () async {
      final source = File(p.join(externalSourceDir.path, 'x.pdf'));
      await source.writeAsBytes([9]);
      final path = await FileStorageService.storeMaterialFile(materialId: 'mat-del', sourcePath: source.path);
      expect(await File(path).exists(), isTrue);

      await FileStorageService.deleteMaterialFile('mat-del');
      expect(await File(path).exists(), isFalse);
    });
  });

  group('MaterialsRepository + file storage integration (fixes #2, #3)', () {
    test('addMaterial with a sourceFilePath stores the PERSISTENT path in the database', () async {
      final externalFile = File(p.join(externalSourceDir.path, 'مذكرة.pdf'));
      await externalFile.writeAsBytes([5, 5, 5]);

      final materialId = await materialsRepo.addMaterial(
        name: 'مذكرة أحياء',
        type: MaterialType.note,
        pricePiastres: 3000,
        sourceFilePath: externalFile.path,
      );

      final row = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingle();
      expect(row.filePath, isNotNull);
      expect(row.filePath, isNot(externalFile.path)); // not the external path
      expect(row.filePath, contains('bond2_files'));
      expect(p.basenameWithoutExtension(row.filePath!), materialId); // named by material id
      expect(await File(row.filePath!).exists(), isTrue);
    });

    test('addMaterial saves academic year, grade, and subject (fix #2)', () async {
      final materialId = await materialsRepo.addMaterial(
        name: 'كتاب كيمياء',
        type: MaterialType.book,
        academicYearId: 'year-1',
        grade: 'الصف الثالث الثانوي',
        subjectId: 'subject-chem',
        pricePiastres: 12000,
      );

      final row = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingle();
      expect(row.academicYearId, 'year-1');
      expect(row.grade, 'الصف الثالث الثانوي');
      expect(row.subjectId, 'subject-chem');
    });

    test('deleteMaterial removes both the DB row and the stored file', () async {
      final externalFile = File(p.join(externalSourceDir.path, 'note.pdf'));
      await externalFile.writeAsBytes([7]);
      final materialId = await materialsRepo.addMaterial(
        name: 'مذكرة تُحذف', type: MaterialType.note, pricePiastres: 0, sourceFilePath: externalFile.path,
      );
      final row = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingle();
      final storedPath = row.filePath!;
      expect(await File(storedPath).exists(), isTrue);

      await materialsRepo.deleteMaterial(materialId);

      final remaining = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingleOrNull();
      expect(remaining, isNull);
      expect(await File(storedPath).exists(), isFalse);
    });

    test('a material that already has a student purchase cannot be deleted (protects financial history)', () async {
      final materialId = await materialsRepo.addMaterial(name: 'كتاب مُباع', type: MaterialType.book, pricePiastres: 5000);
      final studentId = await studentsRepo.addStudent(name: 'طالب مشترٍ');
      await materialsRepo.purchaseMaterial(studentId: studentId, materialId: materialId);

      expect(() => materialsRepo.deleteMaterial(materialId), throwsA(anything));

      final stillThere = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingleOrNull();
      expect(stillThere, isNotNull);
    });
  });
}
