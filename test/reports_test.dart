import 'package:flutter_test/flutter_test.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/features/groups/groups_repository.dart';
import 'package:bond2/features/materials/materials_repository.dart';
import 'package:bond2/features/payments/payments_repository.dart';
import 'package:bond2/features/reports/reports_repository.dart';
import 'package:bond2/features/settings/settings_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

void main() {
  late AppDatabase db;
  late StudentsRepository studentsRepo;
  late MaterialsRepository materialsRepo;
  late PaymentsRepository paymentsRepo;
  late GroupsRepository groupsRepo;
  late SettingsRepository settingsRepo;
  late ReportsRepository reportsRepo;

  setUp(() {
    db = openTestDatabase();
    studentsRepo = StudentsRepository(db);
    materialsRepo = MaterialsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    groupsRepo = GroupsRepository(db);
    settingsRepo = SettingsRepository(db);
    reportsRepo = ReportsRepository(db, studentsRepo, materialsRepo);
  });

  tearDown(() async {
    await db.close();
  });

  group('ReportsRepository (fix #6)', () {
    test('outstandingBalancesReport lists only students with a positive balance', () async {
      final s1 = await studentsRepo.addStudent(name: 'مدين');
      final s2 = await studentsRepo.addStudent(name: 'سدد بالكامل');

      final chargeId1 = await _addCharge(db, s1, 5000);
      await _addCharge(db, s2, 5000);
      final openS2 = await paymentsRepo.openChargesFor(s2);
      await paymentsRepo.recordPayment(
        studentId: s2, amountPiastres: 5000, allocations: {openS2.first.charge.id: 5000},
      );

      final report = await reportsRepo.outstandingBalancesReport(const ReportFilters());
      expect(report.length, 1);
      expect(report.first.student.id, s1);
      expect(report.first.outstanding, 5000);
      expect((await paymentsRepo.openChargesFor(s1)).first.charge.id, chargeId1);
    });

    test('outstandingBalancesReport respects the academic year filter', () async {
      final yearA = await settingsRepo.addAcademicYear('2025/2026');
      final yearB = await settingsRepo.addAcademicYear('2026/2027');
      final sA = await studentsRepo.addStudent(name: 'طالب سنة أ', academicYearId: yearA);
      final sB = await studentsRepo.addStudent(name: 'طالب سنة ب', academicYearId: yearB);
      await _addCharge(db, sA, 3000);
      await _addCharge(db, sB, 4000);

      final reportA = await reportsRepo.outstandingBalancesReport(ReportFilters(academicYearId: yearA));
      expect(reportA.length, 1);
      expect(reportA.first.student.id, sA);
    });

    test('outstandingBalancesReport respects the group filter', () async {
      final yearId = await settingsRepo.addAcademicYear('2025/2026');
      final groupA = await groupsRepo.addGroup(name: 'مجموعة أ', academicYearId: yearId);
      final groupB = await groupsRepo.addGroup(name: 'مجموعة ب', academicYearId: yearId);
      final sA = await studentsRepo.addStudent(name: 'طالب أ', groupId: groupA);
      final sB = await studentsRepo.addStudent(name: 'طالب ب', groupId: groupB);
      await _addCharge(db, sA, 2000);
      await _addCharge(db, sB, 2000);

      final report = await reportsRepo.outstandingBalancesReport(ReportFilters(groupId: groupA));
      expect(report.length, 1);
      expect(report.first.student.id, sA);
    });

    test('financialSummary breaks down charges by source type and sums payments', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب تقرير مالي');
      await _addCharge(db, studentId, 10000, type: ChargeSourceType.lesson);
      await _addCharge(db, studentId, 4000, type: ChargeSourceType.material);

      final open = await paymentsRepo.openChargesFor(studentId);
      final lessonCharge = open.firstWhere((c) => c.charge.sourceType == ChargeSourceType.lesson);
      await paymentsRepo.recordPayment(
        studentId: studentId, amountPiastres: 10000, allocations: {lessonCharge.charge.id: 10000},
      );

      final summary = await reportsRepo.financialSummary(const ReportFilters());
      expect(summary.lessonCharges, 10000);
      expect(summary.materialCharges, 4000);
      expect(summary.chargedInRange, 14000);
      expect(summary.collectedInRange, 10000);
      expect(summary.outstandingAllTime, 4000);
    });

    test('materialSalesReport only includes materials that were actually sold', () async {
      final soldId = await materialsRepo.addMaterial(name: 'مباع', type: MaterialType.note, pricePiastres: 1000);
      await materialsRepo.addMaterial(name: 'غير مباع', type: MaterialType.note, pricePiastres: 1000);
      final studentId = await studentsRepo.addStudent(name: 'مشترٍ');
      await materialsRepo.purchaseMaterial(studentId: studentId, materialId: soldId);

      final report = await reportsRepo.materialSalesReport();
      expect(report.length, 1);
      expect(report.first.material.id, soldId);
      expect(report.first.report.count, 1);
    });

    test('attendanceReport filters by date range', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب حضور');
      final inRangeLesson = await db.into(db.lessons).insertReturning(
            LessonsCompanion.insert(id: 'lesson-in', date: DateTime(2026, 3, 10), startTime: '19:00'),
          );
      final outOfRangeLesson = await db.into(db.lessons).insertReturning(
            LessonsCompanion.insert(id: 'lesson-out', date: DateTime(2026, 1, 1), startTime: '19:00'),
          );
      await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
            id: 'att-in', lessonId: inRangeLesson.id, studentId: studentId,
            status: AttendanceStatus.present, method: AttendanceMethod.manual,
          ));
      await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
            id: 'att-out', lessonId: outOfRangeLesson.id, studentId: studentId,
            status: AttendanceStatus.absent, method: AttendanceMethod.manual,
          ));

      final report = await reportsRepo.attendanceReport(
        ReportFilters(from: DateTime(2026, 3, 1), to: DateTime(2026, 4, 1)),
      );
      expect(report.length, 1);
      expect(report.first.total, 1);
      expect(report.first.present, 1);
      expect(report.first.absent, 0);
    });

    test('paymentsReport filters by date range', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب مدفوعات');
      await _addCharge(db, studentId, 10000);
      final open = await paymentsRepo.openChargesFor(studentId);
      await paymentsRepo.recordPayment(
        studentId: studentId, amountPiastres: 10000, allocations: {open.first.charge.id: 10000},
      );

      final allTime = await reportsRepo.paymentsReport(const ReportFilters());
      expect(allTime.length, 1);

      final farFuture = await reportsRepo.paymentsReport(ReportFilters(from: DateTime(2999, 1, 1)));
      expect(farFuture, isEmpty);
    });
  });
}

Future<String> _addCharge(
  AppDatabase db,
  String studentId,
  int amountPiastres, {
  ChargeSourceType type = ChargeSourceType.lesson,
}) async {
  final id = 'charge-${DateTime.now().microsecondsSinceEpoch}-${studentId.hashCode}-$amountPiastres';
  await db.into(db.charges).insert(ChargesCompanion.insert(
        id: id,
        studentId: studentId,
        sourceType: type,
        amountPiastres: amountPiastres,
      ));
  return id;
}
