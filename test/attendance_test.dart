import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart';
import 'package:bond2/core/database/database.dart';
import 'package:bond2/core/services/qr_service.dart';
import 'package:bond2/features/attendance/attendance_repository.dart';
import 'package:bond2/features/lessons/lessons_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

void main() {
  late AppDatabase db;
  late StudentsRepository studentsRepo;
  late LessonsRepository lessonsRepo;
  late AttendanceRepository attendanceRepo;

  setUp(() {
    db = openTestDatabase();
    studentsRepo = StudentsRepository(db);
    lessonsRepo = LessonsRepository(db);
    attendanceRepo = AttendanceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('QR attendance (rules #23-27)', () {
    test('valid QR scan for a student in the lesson records attendance', () async {
      final studentId = await studentsRepo.addStudent(name: 'أحمد علي');
      final lessonId = await lessonsRepo.createLesson(
        date: DateTime.now(), startTime: '19:00', pricePiastres: 5000,
        explicitStudentIds: [studentId],
      );

      final result = await attendanceRepo.handleScan(
        rawQrPayload: QrService.encodeStudent(studentId),
        lessonId: lessonId,
        decode: QrService.decodeStudentId,
      );

      expect(result.outcome, ScanOutcome.recorded);
      expect(result.student?.id, studentId);
    });

    test('scanning the same student twice does not duplicate attendance', () async {
      final studentId = await studentsRepo.addStudent(name: 'سارة محمد');
      final lessonId = await lessonsRepo.createLesson(
        date: DateTime.now(), startTime: '18:00', pricePiastres: 5000,
        explicitStudentIds: [studentId],
      );
      final payload = QrService.encodeStudent(studentId);

      final first = await attendanceRepo.handleScan(
          rawQrPayload: payload, lessonId: lessonId, decode: QrService.decodeStudentId);
      final second = await attendanceRepo.handleScan(
          rawQrPayload: payload, lessonId: lessonId, decode: QrService.decodeStudentId);

      expect(first.outcome, ScanOutcome.recorded);
      expect(second.outcome, ScanOutcome.alreadyRecorded);

      final records = await (db.select(db.attendanceRecords)
            ..where((t) => Expression.and([t.lessonId.equals(lessonId), t.studentId.equals(studentId)])))
          .get();
      expect(records.length, 1); // never duplicated
    });

    test('invalid QR payload is rejected without crashing', () async {
      final lessonId = await lessonsRepo.createLesson(
        date: DateTime.now(), startTime: '17:00', pricePiastres: 0,
      );

      final result = await attendanceRepo.handleScan(
        rawQrPayload: 'NOT_A_BOND2_QR_CODE',
        lessonId: lessonId,
        decode: QrService.decodeStudentId,
      );

      expect(result.outcome, ScanOutcome.invalidQr);
    });

    test('valid student not registered in this lesson is flagged, not silently added', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب خارج الحصة');
      final lessonId = await lessonsRepo.createLesson(date: DateTime.now(), startTime: '20:00', pricePiastres: 0);

      final result = await attendanceRepo.handleScan(
        rawQrPayload: QrService.encodeStudent(studentId),
        lessonId: lessonId,
        decode: QrService.decodeStudentId,
      );

      expect(result.outcome, ScanOutcome.studentNotInLesson);

      final records = await (db.select(db.attendanceRecords)..where((t) => t.lessonId.equals(lessonId))).get();
      expect(records, isEmpty); // nothing recorded without explicit confirmation
    });

    test('manual attendance marking is idempotent (upsert, not duplicate)', () async {
      final studentId = await studentsRepo.addStudent(name: 'منى خالد');
      final lessonId = await lessonsRepo.createLesson(
        date: DateTime.now(), startTime: '16:00', pricePiastres: 0,
        explicitStudentIds: [studentId],
      );

      await attendanceRepo.markAttendance(
          lessonId: lessonId, studentId: studentId, status: AttendanceStatus.present, method: AttendanceMethod.manual);
      await attendanceRepo.markAttendance(
          lessonId: lessonId, studentId: studentId, status: AttendanceStatus.absent, method: AttendanceMethod.manual);

      final records = await (db.select(db.attendanceRecords)
            ..where((t) => Expression.and([t.lessonId.equals(lessonId), t.studentId.equals(studentId)])))
          .get();
      expect(records.length, 1);
      expect(records.first.status, AttendanceStatus.absent); // latest status wins
    });
  });

  group('Attendance summary', () {
    test('student attendance percentage is calculated correctly', () async {
      final studentId = await studentsRepo.addStudent(name: 'خالد يوسف');
      for (var i = 0; i < 4; i++) {
        final lessonId = await lessonsRepo.createLesson(
          date: DateTime.now().add(Duration(days: i)), startTime: '19:00', pricePiastres: 0,
          explicitStudentIds: [studentId],
        );
        await attendanceRepo.markAttendance(
          lessonId: lessonId,
          studentId: studentId,
          status: i < 3 ? AttendanceStatus.present : AttendanceStatus.absent,
          method: AttendanceMethod.manual,
        );
      }

      final summary = await studentsRepo.attendanceSummaryFor(studentId);
      expect(summary.total, 4);
      expect(summary.present, 3);
      expect(summary.absent, 1);
      expect(summary.percentage, 75.0);
    });
  });
}
