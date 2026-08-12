import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// sqlite3_flutter_libs bundles the native sqlite3 library for Android;
// it only needs to be a declared dependency, no direct import required.

part 'database.g.dart';

// ---------------------------------------------------------------------------
// All money amounts are stored as INTEGER PIASTRES (1 EGP = 100 piastres).
// This avoids floating point rounding errors in financial calculations.
// See lib/core/utils/money.dart for conversion helpers.
// ---------------------------------------------------------------------------

class TeacherProfile extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get mainSubject => text().nullable()();
  TextColumn get phone => text().nullable()();
}

class AcademicYears extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get name => text()(); // e.g. "2025/2026"
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Subjects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get academicYearId =>
      text().references(AcademicYears, #id, onDelete: KeyAction.restrict)();
  TextColumn get grade => text().nullable()();
  TextColumn get subjectId =>
      text().nullable().references(Subjects, #id, onDelete: KeyAction.setNull)();
  TextColumn get schedule => text().nullable()(); // free text e.g. "Sat,Mon 19:00"
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

enum StudentStatus { active, archived }

class Students extends Table {
  TextColumn get id => text()(); // uuid - encoded in QR
  TextColumn get name => text()();
  TextColumn get studentPhone => text().nullable()();
  TextColumn get guardianName => text().nullable()();
  TextColumn get guardianPhone => text().nullable()();
  TextColumn get academicYearId =>
      text().nullable().references(AcademicYears, #id, onDelete: KeyAction.setNull)();
  TextColumn get grade => text().nullable()();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  TextColumn get subjectId =>
      text().nullable().references(Subjects, #id, onDelete: KeyAction.setNull)();
  IntColumn get defaultLessonPricePiastres => integer().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status =>
      textEnum<StudentStatus>().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Lessons extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get subjectId =>
      text().nullable().references(Subjects, #id, onDelete: KeyAction.setNull)();
  TextColumn get academicYearId =>
      text().nullable().references(AcademicYears, #id, onDelete: KeyAction.setNull)();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  TextColumn get grade => text().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get startTime => text()(); // "HH:mm"
  TextColumn get endTime => text().nullable()();
  IntColumn get pricePiastres => integer().withDefault(const Constant(0))();
  // if this lesson was generated from a recurring rule, keep a group tag
  TextColumn get recurrenceGroupId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Join table: which students belong to a lesson, with a price SNAPSHOT
/// (so later price changes never alter historical lessons - rule #67).
class LessonStudents extends Table {
  TextColumn get id => text()();
  TextColumn get lessonId =>
      text().references(Lessons, #id, onDelete: KeyAction.cascade)();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  IntColumn get priceAtLessonPiastres => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

enum AttendanceStatus { present, absent }

enum AttendanceMethod { qr, manual }

class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get lessonId =>
      text().references(Lessons, #id, onDelete: KeyAction.cascade)();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => textEnum<AttendanceStatus>()();
  TextColumn get method => textEnum<AttendanceMethod>()();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A Charge is any billable obligation a student owes: a lesson fee,
/// a material/book purchase, or a manual "other" charge.
/// Payments are allocated against Charges (never against a vague total).
enum ChargeSourceType { lesson, material, other }

class Charges extends Table {
  TextColumn get id => text()();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceType => textEnum<ChargeSourceType>()();
  // references LessonStudents.id or MaterialPurchases.id, null for "other"
  TextColumn get sourceId => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get amountPiastres => integer()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPiastres => integer()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// How a single payment was distributed across one or more charges.
class PaymentAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get paymentId =>
      text().references(Payments, #id, onDelete: KeyAction.cascade)();
  TextColumn get chargeId =>
      text().references(Charges, #id, onDelete: KeyAction.restrict)();
  IntColumn get amountPiastres => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

enum MaterialType { note, book, other }

// Named MaterialItem (not "Material") to avoid colliding with Flutter's
// own Material widget class when both are imported in UI files.
@DataClassName('MaterialItem')
class Materials extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<MaterialType>()();
  TextColumn get academicYearId =>
      text().nullable().references(AcademicYears, #id, onDelete: KeyAction.setNull)();
  TextColumn get grade => text().nullable()();
  TextColumn get subjectId =>
      text().nullable().references(Subjects, #id, onDelete: KeyAction.setNull)();
  IntColumn get pricePiastres => integer().withDefault(const Constant(0))();
  TextColumn get filePath => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class MaterialPurchases extends Table {
  TextColumn get id => text()();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get materialId =>
      text().references(Materials, #id, onDelete: KeyAction.restrict)();
  IntColumn get pricePiastresAtPurchase => integer()(); // snapshot, rule #39
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class FileAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get materialId =>
      text().nullable().references(Materials, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text()();
  TextColumn get originalName => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  BoolColumn get pinEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get pinHash => text().nullable()();
  TextColumn get whatsappQrTemplate => text().nullable()();
  TextColumn get whatsappReminderTemplate => text().nullable()();
}

class BackupMetadataTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get appVersion => text()();
  TextColumn get backupVersion => text()();
  TextColumn get filePath => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  TeacherProfile,
  AcademicYears,
  Subjects,
  Groups,
  Students,
  Lessons,
  LessonStudents,
  AttendanceRecords,
  Charges,
  Payments,
  PaymentAllocations,
  Materials,
  MaterialPurchases,
  FileAttachments,
  AppSettings,
  BackupMetadataTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // IMPORTANT: never destroy existing data. Add step-by-step
          // migrations here as schemaVersion increases. Example pattern:
          // if (from < 2) { await m.addColumn(students, students.someNew); }
        },
      );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'bond2.sqlite'));
      // Ensure native sqlite3 is used on Android (bundled via
      // sqlite3_flutter_libs) rather than relying on a system library.
      return NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db.execute('PRAGMA foreign_keys = ON;');
        },
      );
    });
  }
}

/// Only used by unit tests to get a fast in-memory database.
///
/// IMPORTANT: enables `PRAGMA foreign_keys = ON` explicitly, matching
/// the production connection in [_openConnection] - without this, an
/// in-memory NativeDatabase does NOT enforce foreign key constraints
/// (e.g. the RESTRICT on MaterialPurchases -> Materials), which would
/// make tests pass even for logic that violates referential integrity.
AppDatabase openTestDatabase() {
  return AppDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    ),
  );
}
