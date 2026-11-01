/// Slug helpers for workspace URLs (`lapalmeraie` → `lapalmeraie.tchop.cm`).
///
/// Pure Dart (no Flutter import) so it can be unit-tested without the SDK.
library;

/// "Chez Maman Ngassa" → "chez-maman-ngassa".
///
/// Lowercases, strips French accents, replaces every run of non-alphanumeric
/// characters with a single `-`, trims leading/trailing dashes, and caps the
/// length at 40 characters (the server enforces the same shape).
String slugify(String input) {
  var slug = input.toLowerCase().trim();
  slug = _stripAccents(slug);
  slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  slug = slug.replaceAll(RegExp(r'-{2,}'), '-');
  slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 40) {
    slug = slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  }
  return slug;
}

/// Server-side slug shape (mirrors the `create_workspace` SQL guard and the
/// `tenants.slug` check): 3–40 chars, lowercase alphanumerics and dashes,
/// never starting or ending with a dash.
bool isValidSlug(String slug) =>
    RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$').hasMatch(slug);

const Map<String, String> _accentReplacements = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

String _stripAccents(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentReplacements[char] ?? char);
  }
  return buffer.toString();
}
