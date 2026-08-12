import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';

/// Single shared database instance for the whole app lifetime.
/// The database is the source of truth (rule #6) — no important
/// screen should compute financial numbers from anywhere else.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
