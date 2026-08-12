import 'package:intl/intl.dart';

/// All money in BOND2 is stored and calculated as integer PIASTRES.
/// 1 EGP = 100 piastres. This file is the ONLY place that should ever
/// convert between piastres and a human-readable EGP string, so that
/// floating-point arithmetic never leaks into financial logic (rule #66).
class Money {
  const Money._();

  static int egpToPiastres(num egp) => (egp * 100).round();

  static double piastresToEgp(int piastres) => piastres / 100.0;

  static final NumberFormat _formatter = NumberFormat.decimalPattern('ar_EG');

  /// Formats piastres as a clean Arabic-friendly EGP string, e.g. "150 جنيه".
  static String format(int piastres) {
    final egp = piastres / 100.0;
    final isWhole = piastres % 100 == 0;
    final numberText = isWhole
        ? _formatter.format(egp.round())
        : egp.toStringAsFixed(2);
    return '$numberText جنيه';
  }
}
