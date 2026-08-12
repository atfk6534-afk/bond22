import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../materials/materials_repository.dart';
import '../students/students_repository.dart';

class ReportFilters {
  final DateTime? from;
  final DateTime? to;
  final String? academicYearId;
  final String? groupId;
  const ReportFilters({this.from, this.to, this.academicYearId, this.groupId});

  ReportFilters copyWith({
    DateTime? from,
    DateTime? to,
    String? academicYearId,
    String? groupId,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearYear = false,
    bool clearGroup = false,
  }) {
    return ReportFilters(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      academicYearId: clearYear ? null : (academicYearId ?? this.academicYearId),
      groupId: clearGroup ? null : (groupId ?? this.groupId),
    );
  }
}

class StudentAttendanceRow {
  final Student student;
  final int total;
  final int present;
  final int absent;
  const StudentAttendanceRow({
    required this.student,
    required this.total,
    required this.present,
    required this.absent,
  });
  double get percentage => total == 0 ? 0 : (present / total) * 100;
}

class StudentOutstandingRow {
  final Student student;
  final int outstanding;
  const StudentOutstandingRow({required this.student, required this.outstanding});
}

class StudentFinancialRow {
  final Student student;
  final StudentBalance balance;
  const StudentFinancialRow({required this.student, required this.balance});
}

class FinancialSummary {
  final int chargedInRange;
  final int lessonCharges;
  final int materialCharges;
  final int otherCharges;
  final int collectedInRange;
  final int outstandingAllTime;
  const FinancialSummary({
    required this.chargedInRange,
    required this.lessonCharges,
    required this.materialCharges,
    required this.otherCharges,
    required this.collectedInRange,
    required this.outstandingAllTime,
  });
}

class MaterialSalesRow {
  final MaterialItem material;
  final MaterialSalesReport report;
  const MaterialSalesRow({required this.material, required this.report});
}

/// Aggregates data across Students/Lessons/Attendance/Charges/Payments/
/// Materials for the unified Reports screen (rule #50, fix #6). All
/// numbers are always derived live from the same source-of-truth tables
/// the rest of the app uses (rule #6) — nothing here is a separately
/// cached figure that could drift out of sync.
class ReportsRepository {
  final AppDatabase db;
  final StudentsRepository studentsRepo;
  final MaterialsRepository materialsRepo;
  ReportsRepository(this.db, this.studentsRepo, this.materialsRepo);

  Future<List<Student>> _filteredActiveStudents(ReportFilters f) {
    final q = db.select(db.students)..where((t) => t.status.equalsValue(StudentStatus.active));
    if (f.academicYearId != null) {
      q.where((t) => t.academicYearId.equals(f.academicYearId!));
    }
    if (f.groupId != null) {
      q.where((t) => t.groupId.equals(f.groupId!));
    }
    return q.get();
  }

  /// Attendance + absence report (rule #50 "Attendance Report").
  Future<List<StudentAttendanceRow>> attendanceReport(ReportFilters f) async {
    final students = await _filteredActiveStudents(f);
    final rows = <StudentAttendanceRow>[];

    for (final s in students) {
      final query = db.select(db.attendanceRecords).join([
        innerJoin(db.lessons, db.lessons.id.equalsExp(db.attendanceRecords.lessonId)),
      ])
        ..where(db.attendanceRecords.studentId.equals(s.id));
      if (f.from != null) query.where(db.lessons.date.isBiggerOrEqualValue(f.from!));
      if (f.to != null) query.where(db.lessons.date.isSmallerThanValue(f.to!));

      final results = await query.get();
      final present = results
          .where((r) => r.readTable(db.attendanceRecords).status == AttendanceStatus.present)
          .length;
      rows.add(StudentAttendanceRow(
        student: s,
        total: results.length,
        present: present,
        absent: results.length - present,
      ));
    }
    // Students with at least one recorded lesson first, most-absent first.
    rows.sort((a, b) => b.absent.compareTo(a.absent));
    return rows;
  }

  /// Payments report — every payment recorded in the date range,
  /// regardless of student filters (a payments ledger, rule #50).
  Future<List<Payment>> paymentsReport(ReportFilters f) async {
    final q = db.select(db.payments);
    if (f.from != null) q.where((t) => t.date.isBiggerOrEqualValue(f.from!));
    if (f.to != null) q.where((t) => t.date.isSmallerThanValue(f.to!));
    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  /// Outstanding balances report (rule #48/#50), filterable by academic
  /// year and group.
  Future<List<StudentOutstandingRow>> outstandingBalancesReport(ReportFilters f) async {
    final students = await _filteredActiveStudents(f);
    final rows = <StudentOutstandingRow>[];
    for (final s in students) {
      final balance = await studentsRepo.balanceFor(s.id);
      if (balance.outstanding > 0) {
        rows.add(StudentOutstandingRow(student: s, outstanding: balance.outstanding));
      }
    }
    rows.sort((a, b) => b.outstanding.compareTo(a.outstanding));
    return rows;
  }

  /// Per-student full financial summary (rule #50 "Student Report").
  Future<List<StudentFinancialRow>> studentFinancialSummaries(ReportFilters f) async {
    final students = await _filteredActiveStudents(f);
    final rows = <StudentFinancialRow>[];
    for (final s in students) {
      final balance = await studentsRepo.balanceFor(s.id);
      rows.add(StudentFinancialRow(student: s, balance: balance));
    }
    return rows;
  }

  /// Materials/books sales report across every material (rule #41/#50).
  Future<List<MaterialSalesRow>> materialSalesReport() async {
    final materials = await materialsRepo.watchAll().first;
    final rows = <MaterialSalesRow>[];
    for (final m in materials) {
      final report = await materialsRepo.salesReportFor(m.id);
      if (report.count > 0) {
        rows.add(MaterialSalesRow(material: m, report: report));
      }
    }
    return rows;
  }

  /// Overall financial summary for the whole filtered cohort (rule #50
  /// "Financial Report"). `chargedInRange` sums Charges CREATED within
  /// [from, to); `collectedInRange` sums Payments RECORDED within the
  /// same window (a payment can settle a charge from before the window,
  /// so these two figures intentionally describe different things and
  /// are labelled separately in the UI rather than implied to net out
  /// to the same total).
  Future<FinancialSummary> financialSummary(ReportFilters f) async {
    final students = await _filteredActiveStudents(f);
    final studentIds = students.map((s) => s.id).toList();

    var chargedTotal = 0, lessonTotal = 0, materialTotal = 0, otherTotal = 0;
    for (final s in students) {
      final chargesQuery = db.select(db.charges)..where((t) => t.studentId.equals(s.id));
      if (f.from != null) chargesQuery.where((t) => t.date.isBiggerOrEqualValue(f.from!));
      if (f.to != null) chargesQuery.where((t) => t.date.isSmallerThanValue(f.to!));
      final charges = await chargesQuery.get();
      for (final c in charges) {
        chargedTotal += c.amountPiastres;
        switch (c.sourceType) {
          case ChargeSourceType.lesson:
            lessonTotal += c.amountPiastres;
            break;
          case ChargeSourceType.material:
            materialTotal += c.amountPiastres;
            break;
          case ChargeSourceType.other:
            otherTotal += c.amountPiastres;
            break;
        }
      }
    }

    var collectedTotal = 0;
    if (studentIds.isNotEmpty) {
      final paymentsQuery = db.select(db.payments)..where((t) => t.studentId.isIn(studentIds));
      if (f.from != null) paymentsQuery.where((t) => t.date.isBiggerOrEqualValue(f.from!));
      if (f.to != null) paymentsQuery.where((t) => t.date.isSmallerThanValue(f.to!));
      final payments = await paymentsQuery.get();
      collectedTotal = payments.fold<int>(0, (sum, p) => sum + p.amountPiastres);
    }

    var outstandingTotal = 0;
    for (final s in students) {
      final balance = await studentsRepo.balanceFor(s.id);
      if (balance.outstanding > 0) outstandingTotal += balance.outstanding;
    }

    return FinancialSummary(
      chargedInRange: chargedTotal,
      lessonCharges: lessonTotal,
      materialCharges: materialTotal,
      otherCharges: otherTotal,
      collectedInRange: collectedTotal,
      outstandingAllTime: outstandingTotal,
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(
    ref.watch(databaseProvider),
    ref.watch(studentsRepositoryProvider),
    ref.watch(materialsRepositoryProvider),
  );
});
