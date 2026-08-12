import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

class StudentBalance {
  final int totalCharged;
  final int totalPaid;
  int get outstanding => totalCharged - totalPaid;
  const StudentBalance({required this.totalCharged, required this.totalPaid});
}

class AttendanceSummary {
  final int total;
  final int present;
  final int absent;
  const AttendanceSummary({
    required this.total,
    required this.present,
    required this.absent,
  });
  double get percentage => total == 0 ? 0 : (present / total) * 100;
}

class StudentsRepository {
  final AppDatabase db;
  StudentsRepository(this.db);

  Stream<List<Student>> watchActive() {
    return (db.select(db.students)
          ..where((t) => t.status.equalsValue(StudentStatus.active))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Stream<List<Student>> watchArchived() {
    return (db.select(db.students)
          ..where((t) => t.status.equalsValue(StudentStatus.archived)))
        .watch();
  }

  Future<Student?> byId(String id) =>
      (db.select(db.students)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<Student>> search(String query) {
    final q = '%$query%';
    return (db.select(db.students)
          ..where((t) =>
              t.status.equalsValue(StudentStatus.active) &
              (t.name.like(q) |
                  t.studentPhone.like(q) |
                  t.guardianPhone.like(q) |
                  t.id.like(q))))
        .watch();
  }

  /// Creates a student and returns the new student id.
  /// A QR code is derived from this id automatically — the teacher
  /// never generates it manually (rule #13).
  Future<String> addStudent({
    required String name,
    String? studentPhone,
    String? guardianName,
    String? guardianPhone,
    String? academicYearId,
    String? grade,
    String? groupId,
    String? subjectId,
    int? defaultLessonPricePiastres,
    String? notes,
  }) async {
    final id = IdGenerator.newId();
    await db.into(db.students).insert(StudentsCompanion.insert(
          id: id,
          name: name,
          studentPhone: Value(studentPhone),
          guardianName: Value(guardianName),
          guardianPhone: Value(guardianPhone),
          academicYearId: Value(academicYearId),
          grade: Value(grade),
          groupId: Value(groupId),
          subjectId: Value(subjectId),
          defaultLessonPricePiastres: Value(defaultLessonPricePiastres),
          notes: Value(notes),
        ));
    return id;
  }

  Future<void> updateStudent(Student student) => db.update(db.students).replace(student);

  Future<void> setArchived(String studentId, bool archived) async {
    await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(
      StudentsCompanion(
        status: Value(archived ? StudentStatus.archived : StudentStatus.active),
      ),
    );
  }

  Future<void> moveToGroup(String studentId, String? newGroupId) async {
    // History (attendance, charges, payments) is untouched by design
    // (rule #44) — only the group pointer changes.
    await (db.update(db.students)..where((t) => t.id.equals(studentId)))
        .write(StudentsCompanion(groupId: Value(newGroupId)));
  }

  /// Financial summary computed from Charges/PaymentAllocations —
  /// the database is always the source of truth, never a cached UI number.
  Future<StudentBalance> balanceFor(String studentId) async {
    final charged = await _sumCharges(studentId);
    final paid = await _sumAllocations(studentId);
    return StudentBalance(totalCharged: charged, totalPaid: paid);
  }

  Future<int> _sumCharges(String studentId) async {
    final sum = db.charges.amountPiastres.sum();
    final query = db.selectOnly(db.charges)
      ..addColumns([sum])
      ..where(db.charges.studentId.equals(studentId));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  Future<int> _sumAllocations(String studentId) async {
    final query = db.selectOnly(db.paymentAllocations).join([
      innerJoin(
        db.charges,
        db.charges.id.equalsExp(db.paymentAllocations.chargeId),
      ),
    ])
      ..addColumns([db.paymentAllocations.amountPiastres.sum()])
      ..where(db.charges.studentId.equals(studentId));
    final row = await query.getSingle();
    return row.read(db.paymentAllocations.amountPiastres.sum()) ?? 0;
  }

  Future<AttendanceSummary> attendanceSummaryFor(String studentId) async {
    final rows = await (db.select(db.attendanceRecords)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    final present = rows.where((r) => r.status == AttendanceStatus.present).length;
    return AttendanceSummary(
      total: rows.length,
      present: present,
      absent: rows.length - present,
    );
  }
}

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.watch(databaseProvider));
});

final activeStudentsProvider = StreamProvider<List<Student>>((ref) {
  return ref.watch(studentsRepositoryProvider).watchActive();
});

final studentBalanceProvider =
    FutureProvider.family<StudentBalance, String>((ref, studentId) {
  return ref.watch(studentsRepositoryProvider).balanceFor(studentId);
});

final studentAttendanceSummaryProvider =
    FutureProvider.family<AttendanceSummary, String>((ref, studentId) {
  return ref.watch(studentsRepositoryProvider).attendanceSummaryFor(studentId);
});
