/// Cameroonian phone-number helpers (WhatsApp / mobile, MTN & Orange).
///
/// Pure Dart (no Flutter import) so it can be unit-tested without the SDK.
///
/// Supabase phone auth requires E.164, so every sign-in / invite path
/// normalizes through [normalizeCmPhone] before touching the network.
library;

/// Normalizes a Cameroonian mobile number to E.164 (`+2376XXXXXXXX`).
///
/// Accepts `6XXXXXXXX`, `06XXXXXXXX`, `2376XXXXXXXX`, `+2376XXXXXXXX` and
/// anything in between with spaces, dots or dashes. Returns null when the
/// digits do not form a valid Cameroonian mobile number (9 digits starting
/// with 6 — MTN, Orange and Camtel mobile ranges).
String? normalizeCmPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('237')) digits = digits.substring(3);
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  if (!RegExp(r'^6\d{8}$').hasMatch(digits)) return null;
  return '+237$digits';
}

/// Pretty display form: `+237612345678` → `+237 6 12 34 56 78`.
/// Returns the input unchanged when it is not a normalized CM mobile.
String prettyCmPhone(String e164) {
  final match = RegExp(r'^\+237(6)(\d{2})(\d{2})(\d{2})(\d{2})$')
      .firstMatch(e164.replaceAll(' ', ''));
  if (match == null) return e164;
  return '+237 ${match.group(1)} ${match.group(2)} ${match.group(3)} '
      '${match.group(4)} ${match.group(5)}';
}
