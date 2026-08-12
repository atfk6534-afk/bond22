import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

class SettingsRepository {
  final AppDatabase db;
  SettingsRepository(this.db);

  // ---- Teacher profile (first-launch setup, rule #8) ----
  Future<TeacherProfileData?> getProfile() =>
      db.select(db.teacherProfile).getSingleOrNull();

  Future<void> saveProfile({required String name, String? subject, String? phone}) async {
    final existing = await getProfile();
    if (existing == null) {
      await db.into(db.teacherProfile).insert(TeacherProfileCompanion.insert(
            name: name,
            mainSubject: Value(subject),
            phone: Value(phone),
          ));
    } else {
      await (db.update(db.teacherProfile)..where((t) => t.id.equals(existing.id)))
          .write(TeacherProfileCompanion(
        name: Value(name),
        mainSubject: Value(subject),
        phone: Value(phone),
      ));
    }
  }

  // ---- Academic years ----
  Stream<List<AcademicYear>> watchAcademicYears() =>
      (db.select(db.academicYears)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<String> addAcademicYear(String name) async {
    final id = IdGenerator.newId();
    await db.into(db.academicYears).insert(
        AcademicYearsCompanion.insert(id: id, name: name));
    return id;
  }

  // ---- Subjects ----
  Stream<List<Subject>> watchSubjects() => db.select(db.subjects).watch();

  Future<String> addSubject(String name) async {
    final id = IdGenerator.newId();
    await db.into(db.subjects).insert(SubjectsCompanion.insert(id: id, name: name));
    return id;
  }

  // ---- App settings (single row) ----
  Future<AppSetting> getOrCreateSettings() async {
    final existing = await db.select(db.appSettings).getSingleOrNull();
    if (existing != null) return existing;
    final id = await db.into(db.appSettings).insert(const AppSettingsCompanion());
    return (db.select(db.appSettings)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> setThemeMode(String mode) async {
    final s = await getOrCreateSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(s.id)))
        .write(AppSettingsCompanion(themeMode: Value(mode)));
  }

  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<void> enablePin(String pin) async {
    final s = await getOrCreateSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(s.id))).write(
      AppSettingsCompanion(pinEnabled: const Value(true), pinHash: Value(_hashPin(pin))),
    );
  }

  Future<void> disablePin() async {
    final s = await getOrCreateSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(s.id))).write(
      const AppSettingsCompanion(pinEnabled: Value(false), pinHash: Value(null)),
    );
  }

  Future<bool> verifyPin(String pin) async {
    final s = await getOrCreateSettings();
    return s.pinHash == _hashPin(pin);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final teacherProfileProvider = FutureProvider<TeacherProfileData?>((ref) {
  return ref.watch(settingsRepositoryProvider).getProfile();
});

final appSettingsProvider = FutureProvider<AppSetting>((ref) {
  return ref.watch(settingsRepositoryProvider).getOrCreateSettings();
});

final academicYearsProvider = StreamProvider<List<AcademicYear>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAcademicYears();
});

final subjectsProvider = StreamProvider<List<Subject>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchSubjects();
});
