/// Encodes/decodes the BOND2 student QR payload.
///
/// Rule #14 / #73: the QR must only carry a stable, non-sensitive
/// identifier — never guardian phone numbers, balances, or other
/// private data.
class QrService {
  const QrService._();

  static const String _prefix = 'BOND2:STUDENT:';

  static String encodeStudent(String studentId) => '$_prefix$studentId';

  /// Returns the student id if [raw] is a valid BOND2 QR payload,
  /// otherwise null (caller should show "Invalid QR Code", rule #25).
  static String? decodeStudentId(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(_prefix)) return null;
    final id = trimmed.substring(_prefix.length);
    if (id.isEmpty) return null;
    return id;
  }
}
