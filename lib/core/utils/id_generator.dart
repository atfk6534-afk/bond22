import 'package:uuid/uuid.dart';

/// Generates permanent, unique identifiers used as primary keys and
/// encoded into student QR codes (rule #14).
class IdGenerator {
  const IdGenerator._();

  static const Uuid _uuid = Uuid();

  static String newId() => _uuid.v4();
}
