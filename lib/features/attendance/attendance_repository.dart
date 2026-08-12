import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

enum ScanOutcome { recorded, alreadyRecorded, invalidQr, studentNotInLesson }

class ScanResult {
  final ScanOutcome outcome;
  final Student? student;
  const ScanResult(this.outcome, [this.student]);
}

class AttendanceRepository {
  final AppDatabase db;
  AttendanceRepository(this.db);

  Future<bool> _isStudentInLesson(String lessonId, String studentId) async {
    final row = await (db.select(db.lessonStudents)
          ..where((t) => t.lessonId.equals(lessonId) & t.studentId.equals(studentId)))
        .getSingleOrNull();
    return row != null;
  }

  Future<AttendanceRecord?> _existingRecord(String lessonId, String studentId) {
    return (db.select(db.attendanceRecords)
          ..where((t) => t.lessonId.equals(lessonId) & t.studentId.equals(studentId)))
        .getSingleOrNull();
  }

  /// Adds a student who scanned a valid QR but isn't on the lesson
  /// roster yet — only when the teacher explicitly confirms (rule #26).
  Future<void> addStudentToLesson(String lessonId, String studentId, int pricePiastres) async {
    await db.transaction(() async {
      final lessonStudentId = IdGenerator.newId();
      await db.into(db.lessonStudents).insert(LessonStudentsCompanion.insert(
            id: lessonStudentId,
            lessonId: lessonId,
            studentId: studentId,
            priceAtLessonPiastres: pricePiastres,
          ));
      if (pricePiastres > 0) {
        await db.into(db.charges).insert(ChargesCompanion.insert(
              id: IdGenerator.newId(),
              studentId: studentId,
              sourceType: ChargeSourceType.lesson,
              sourceId: Value(lessonStudentId),
              amountPiastres: pricePiastres,
            ));
      }
    });
  }

  /// Core QR scan handler (rules #23-#26). Never throws for bad input —
  /// always returns a clear outcome so the scanner UI can keep running.
  Future<ScanResult> handleScan({
    required String rawQrPayload,
    required String lessonId,
    required String? Function(String raw) decode,
  }) async {
    final studentId = decode(rawQrPayload);
    if (studentId == null) {
      return const ScanResult(ScanOutcome.invalidQr);
    }

    final student =
        await (db.select(db.students)..where((t) => t.id.equals(studentId)))
            .getSingleOrNull();
    if (student == null) {
      return const ScanResult(ScanOutcome.invalidQr);
    }

    final inLesson = await _isStudentInLesson(lessonId, studentId);
    if (!inLesson) {
      return ScanResult(ScanOutcome.studentNotInLesson, student);
    }

    final existing = await _existingRecord(lessonId, studentId);
    if (existing != null) {
      return ScanResult(ScanOutcome.alreadyRecorded, student);
    }

    await markAttendance(
      lessonId: lessonId,
      studentId: studentId,
      status: AttendanceStatus.present,
      method: AttendanceMethod.qr,
    );
    return ScanResult(ScanOutcome.recorded, student);
  }

  /// Manual present/absent toggle (rule #27). Upserts — re-marking a
  /// student simply updates their existing record rather than
  /// duplicating it.
  Future<void> markAttendance({
    required String lessonId,
    required String studentId,
    required AttendanceStatus status,
    required AttendanceMethod method,
  }) async {
    final existing = await _existingRecord(lessonId, studentId);
    if (existing != null) {
      await (db.update(db.attendanceRecords)..where((t) => t.id.equals(existing.id)))
          .write(AttendanceRecordsCompanion(
        status: Value(status),
        method: Value(method),
        recordedAt: Value(DateTime.now()),
      ));
      return;
    }
    await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
          id: IdGenerator.newId(),
          lessonId: lessonId,
          studentId: studentId,
          status: status,
          method: method,
        ));
  }

  Stream<List<AttendanceRecord>> watchForLesson(String lessonId) {
    return (db.select(db.attendanceRecords)
          ..where((t) => t.lessonId.equals(lessonId)))
        .watch();
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(databaseProvider));
});
