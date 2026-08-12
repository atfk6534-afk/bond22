import 'package:flutter_test/flutter_test.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/features/groups/groups_repository.dart';
import 'package:bond2/features/lessons/lessons_repository.dart';
import 'package:bond2/features/settings/settings_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

void main() {
  late AppDatabase db;
  late StudentsRepository studentsRepo;
  late GroupsRepository groupsRepo;
  late LessonsRepository lessonsRepo;
  late SettingsRepository settingsRepo;

  setUp(() {
    db = openTestDatabase();
    studentsRepo = StudentsRepository(db);
    groupsRepo = GroupsRepository(db);
    lessonsRepo = LessonsRepository(db);
    settingsRepo = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Groups & lessons (rules #20-21, #43-44)', () {
    test('creating a lesson from a group auto-adds its students and charges', () async {
      final yearId = await settingsRepo.addAcademicYear('2025/2026');
      final groupId = await groupsRepo.addGroup(name: 'مجموعة السبت', academicYearId: yearId);

      final s1 = await studentsRepo.addStudent(name: 'طالب أ', groupId: groupId);
      final s2 = await studentsRepo.addStudent(name: 'طالب ب', groupId: groupId);
      // A student in a different group should NOT be included.
      await studentsRepo.addStudent(name: 'طالب ج');

      final lessonId = await lessonsRepo.createLesson(
        groupId: groupId,
        date: DateTime.now(),
        startTime: '19:00',
        pricePiastres: 7500,
      );

      final roster = await lessonsRepo.rosterFor(lessonId);
      expect(roster.length, 2);
      expect(roster.map((r) => r.student.id).toSet(), {s1, s2});
      for (final entry in roster) {
        expect(entry.chargeAmount, 7500);
      }

      final balance1 = await studentsRepo.balanceFor(s1);
      expect(balance1.totalCharged, 7500);
    });

    test('recurring lessons generate one lesson per matching weekday (rule #21)', () async {
      final yearId = await settingsRepo.addAcademicYear('2025/2026');
      final first = DateTime(2026, 1, 1); // Thursday
      final last = DateTime(2026, 1, 31);

      // Saturday=6, Monday=1 in DateTime.weekday (Mon=1..Sun=7)
      final ids = await lessonsRepo.createRecurringLessons(
        academicYearId: yearId,
        weekdays: const [6, 1],
        firstDate: first,
        lastDate: last,
        startTime: '19:00',
        pricePiastres: 5000,
      );

      // January 2026 has 4 Saturdays and 4 Mondays within the range.
      expect(ids.length, greaterThanOrEqualTo(8));
      for (final id in ids) {
        final lesson = await (db.select(db.lessons)..where((t) => t.id.equals(id))).getSingle();
        expect([1, 6].contains(lesson.date.weekday), isTrue);
      }
    });

    test('moving a student to another group preserves attendance/financial history (rule #44)', () async {
      final yearId = await settingsRepo.addAcademicYear('2025/2026');
      final groupA = await groupsRepo.addGroup(name: 'مجموعة أ', academicYearId: yearId);
      final groupB = await groupsRepo.addGroup(name: 'مجموعة ب', academicYearId: yearId);
      final studentId = await studentsRepo.addStudent(name: 'طالب منتقل', groupId: groupA);

      await lessonsRepo.createLesson(
        groupId: groupA, date: DateTime.now(), startTime: '18:00', pricePiastres: 6000,
      );
      final balanceBefore = await studentsRepo.balanceFor(studentId);

      await studentsRepo.moveToGroup(studentId, groupB);

      final balanceAfter = await studentsRepo.balanceFor(studentId);
      expect(balanceAfter.totalCharged, balanceBefore.totalCharged); // history intact

      final student = await studentsRepo.byId(studentId);
      expect(student?.groupId, groupB);
    });
  });
}
