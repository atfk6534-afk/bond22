import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

class LessonRosterEntry {
  final Student student;
  final AttendanceStatus? attendanceStatus; // null = not recorded yet
  final int chargeAmount;
  final int paidForCharge;
  const LessonRosterEntry({
    required this.student,
    required this.attendanceStatus,
    required this.chargeAmount,
    required this.paidForCharge,
  });
  int get remaining => chargeAmount - paidForCharge;
}

class LessonsRepository {
  final AppDatabase db;
  LessonsRepository(this.db);

  Stream<List<Lesson>> watchOnDate(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (db.select(db.lessons)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

  Stream<List<Lesson>> watchUpcoming() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return (db.select(db.lessons)
          ..where((t) => t.date.isBiggerOrEqualValue(start))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  Stream<List<Lesson>> watchPast() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return (db.select(db.lessons)
          ..where((t) => t.date.isSmallerThanValue(start))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  /// Creates one lesson. If [groupId] is set, every active student in
  /// that group is automatically added to the roster with a snapshot
  /// price and a matching Charge (rules #20, #67, #68) — all inside one
  /// transaction so the lesson never exists half-built.
  Future<String> createLesson({
    String? name,
    String? subjectId,
    String? academicYearId,
    String? groupId,
    String? grade,
    required DateTime date,
    required String startTime,
    String? endTime,
    required int pricePiastres,
    List<String>? explicitStudentIds,
    String? recurrenceGroupId,
  }) async {
    return db.transaction<String>(() async {
      final lessonId = IdGenerator.newId();
      await db.into(db.lessons).insert(LessonsCompanion.insert(
            id: lessonId,
            name: Value(name),
            subjectId: Value(subjectId),
            academicYearId: Value(academicYearId),
            groupId: Value(groupId),
            grade: Value(grade),
            date: date,
            startTime: startTime,
            endTime: Value(endTime),
            pricePiastres: Value(pricePiastres),
            recurrenceGroupId: Value(recurrenceGroupId),
          ));

      var studentIds = explicitStudentIds ?? const <String>[];
      if (groupId != null && studentIds.isEmpty) {
        final groupStudents = await (db.select(db.students)
              ..where((t) =>
                  t.groupId.equals(groupId) &
                  t.status.equalsValue(StudentStatus.active)))
            .get();
        studentIds = groupStudents.map((s) => s.id).toList();
      }

      for (final studentId in studentIds) {
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
                description: Value(name ?? 'حصة بتاريخ ${date.toIso8601String().split('T').first}'),
                amountPiastres: pricePiastres,
                date: Value(date),
              ));
        }
      }

      return lessonId;
    });
  }

  /// Creates a recurring series of lessons on the given [weekdays]
  /// (1=Mon..7=Sun) between [firstDate] and [lastDate] inclusive
  /// (rule #21). Each generated lesson shares a recurrenceGroupId.
  Future<List<String>> createRecurringLessons({
    String? name,
    String? subjectId,
    String? academicYearId,
    String? groupId,
    String? grade,
    required List<int> weekdays,
    required DateTime firstDate,
    required DateTime lastDate,
    required String startTime,
    String? endTime,
    required int pricePiastres,
  }) async {
    final seriesId = IdGenerator.newId();
    final ids = <String>[];
    for (var d = firstDate;
        !d.isAfter(lastDate);
        d = d.add(const Duration(days: 1))) {
      if (weekdays.contains(d.weekday)) {
        final id = await createLesson(
          name: name,
          subjectId: subjectId,
          academicYearId: academicYearId,
          groupId: groupId,
          grade: grade,
          date: d,
          startTime: startTime,
          endTime: endTime,
          pricePiastres: pricePiastres,
          recurrenceGroupId: seriesId,
        );
        ids.add(id);
      }
    }
    return ids;
  }

  /// Full roster for a lesson with attendance + payment status per
  /// student, used by the Lesson Details screen (rule #22).
  Future<List<LessonRosterEntry>> rosterFor(String lessonId) async {
    final lessonStudents = await (db.select(db.lessonStudents)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();

    final attendance = await (db.select(db.attendanceRecords)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();
    final attendanceByStudent = {for (final a in attendance) a.studentId: a.status};

    final entries = <LessonRosterEntry>[];
    for (final ls in lessonStudents) {
      final student = await (db.select(db.students)
            ..where((t) => t.id.equals(ls.studentId)))
          .getSingle();

      final charge = await (db.select(db.charges)
            ..where((t) => t.sourceId.equals(ls.id)))
          .getSingleOrNull();

      var paid = 0;
      if (charge != null) {
        final sum = db.paymentAllocations.amountPiastres.sum();
        final q = db.selectOnly(db.paymentAllocations)
          ..addColumns([sum])
          ..where(db.paymentAllocations.chargeId.equals(charge.id));
        paid = (await q.getSingle()).read(sum) ?? 0;
      }

      entries.add(LessonRosterEntry(
        student: student,
        attendanceStatus: attendanceByStudent[ls.studentId],
        chargeAmount: charge?.amountPiastres ?? ls.priceAtLessonPiastres,
        paidForCharge: paid,
      ));
    }
    return entries;
  }
}

final lessonsRepositoryProvider = Provider<LessonsRepository>((ref) {
  return LessonsRepository(ref.watch(databaseProvider));
});

final todaysLessonsProvider = StreamProvider<List<Lesson>>((ref) {
  return ref.watch(lessonsRepositoryProvider).watchOnDate(DateTime.now());
});

final lessonRosterProvider =
    FutureProvider.family<List<LessonRosterEntry>, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).rosterFor(lessonId);
});
