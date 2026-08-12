import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

class GroupsRepository {
  final AppDatabase db;
  GroupsRepository(this.db);

  Stream<List<Group>> watchActive() {
    return (db.select(db.groups)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<String> addGroup({
    required String name,
    required String academicYearId,
    String? grade,
    String? subjectId,
    String? schedule,
  }) async {
    final id = IdGenerator.newId();
    await db.into(db.groups).insert(GroupsCompanion.insert(
          id: id,
          name: name,
          academicYearId: academicYearId,
          grade: Value(grade),
          subjectId: Value(subjectId),
          schedule: Value(schedule),
        ));
    return id;
  }

  /// All active students currently in [groupId] — used to auto-populate
  /// a new lesson's roster (rule #20, #43).
  Future<List<Student>> studentsIn(String groupId) {
    return (db.select(db.students)
          ..where((t) =>
              t.groupId.equals(groupId) &
              t.status.equalsValue(StudentStatus.active)))
        .get();
  }

  Future<void> setActive(String groupId, bool active) async {
    await (db.update(db.groups)..where((t) => t.id.equals(groupId)))
        .write(GroupsCompanion(isActive: Value(active)));
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(databaseProvider));
});

final activeGroupsProvider = StreamProvider<List<Group>>((ref) {
  return ref.watch(groupsRepositoryProvider).watchActive();
});
