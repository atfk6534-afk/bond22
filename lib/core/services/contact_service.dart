import 'package:url_launcher/url_launcher.dart';

/// Opens the device's phone dialer or WhatsApp using simple intents/deep
/// links (rule #17). No internal chat system is built — BOND2 stays
/// fully offline for its own data; these actions only fire when the
/// teacher explicitly taps a button.
class ContactService {
  const ContactService._();

  static String _normalizePhone(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (!p.startsWith('+') && p.startsWith('0')) {
      // Default to Egypt country code for local numbers (01xxxxxxxxx).
      p = '+2$p';
    }
    return p;
  }

  static Future<bool> call(String phone) async {
    final uri = Uri(scheme: 'tel', path: _normalizePhone(phone));
    return launchUrl(uri);
  }

  /// Opens WhatsApp with [phone] and a pre-filled [message].
  /// Returns false if WhatsApp / a handler could not be launched —
  /// callers must handle this gracefully (rule #17) and never crash.
  static Future<bool> openWhatsApp(String phone, String message) async {
    final normalized = _normalizePhone(phone).replaceAll('+', '');
    final uri = Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(message)}',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
