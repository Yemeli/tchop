import 'package:flutter/material.dart';

/// Per-workspace brand definition.
///
/// Stored per restaurant in the backend (`tenants.brand_json`) and applied at
/// runtime — this is what lets thousands of restaurants share one binary while
/// each looking like their own app.
///
/// Tenants control *brand* tokens only (name, logo, brand colors). Functional
/// colors (error/success/warning) stay fixed so a bad theme can't break
/// usability.
@immutable
class TenantBrand {
  const TenantBrand({
    required this.restaurantId,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
    this.tagline,
    this.logoUrl,
    this.subdomain,
    this.currency = 'XAF',
    this.locale = 'fr_CM',
  });

  final String restaurantId;
  final String name;
  final String? tagline;
  final String? logoUrl;
  final String? subdomain;
  final Color primary;
  final Color secondary;
  final Color accent;
  final String currency;
  final String locale;

  /// Neutral fallback used before any workspace is loaded.
  factory TenantBrand.fallback() => const TenantBrand(
        restaurantId: 'unassigned',
        name: 'Tchop',
        primary: Color(0xFFE8641B),
        secondary: Color(0xFF2A2118),
        accent: Color(0xFFD4AF37),
      );

  factory TenantBrand.fromJson(Map<String, dynamic> json) {    final colors = (json['colors'] as Map?)?.cast<String, dynamic>() ?? {};
    return TenantBrand(
      restaurantId: json['restaurantId'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Restaurant',
      tagline: json['tagline'] as String?,
      logoUrl: json['logoUrl'] as String?,
      subdomain: json['subdomain'] as String?,
      primary: _parseHex(colors['primary'] as String?, const Color(0xFFE8641B)),
      secondary:
          _parseHex(colors['secondary'] as String?, const Color(0xFF2A2118)),
      accent: _parseHex(colors['accent'] as String?, const Color(0xFFD4AF37)),
      currency: json['currency'] as String? ?? 'XAF',
      locale: json['locale'] as String? ?? 'fr_CM',
    );
  }

  /// Builds a brand from a Supabase `tenants` row (PostgREST, snake_case).
  ///
  /// The server stores brand tokens as individual columns (`name`,
  /// `logo_url`, `primary_color`, …) rather than a JSON blob; this maps
  /// them onto the same [TenantBrand] the rest of the app consumes.
  /// Unknown/missing columns fall back to the neutral defaults so a
  /// partially-provisioned tenant still renders.
  factory TenantBrand.fromTenantRow(Map<String, dynamic> row) {
    return TenantBrand.fromJson({
      'restaurantId':
          row['id'] as String? ?? row['restaurant_id'] as String? ?? 'unknown',
      'name': row['name'] as String? ?? 'Restaurant',
      'tagline': row['tagline'] as String?,
      'logoUrl': row['logo_url'] as String? ?? row['logoUrl'] as String?,
      'subdomain': row['slug'] as String? ?? row['subdomain'] as String?,
      'colors': {
        'primary': row['primary_color'] as String?,
        'secondary': row['secondary_color'] as String?,
        'accent': row['accent_color'] as String?,
      },
      'currency': row['currency'] as String? ?? 'XAF',
      'locale': 'fr_CM',
    });
  }

  Map<String, dynamic> toJson() => {
        'restaurantId': restaurantId,
        'name': name,
        'tagline': tagline,
        'logoUrl': logoUrl,
        'subdomain': subdomain,
        'colors': {
          'primary': _toHex(primary),
          'secondary': _toHex(secondary),
          'accent': _toHex(accent),
        },
        'currency': currency,
        'locale': locale,
      };

  static Color _parseHex(String? hex, Color fallback) {
    if (hex == null) return fallback;
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? fallback : Color(value);
  }

  static String _toHex(Color color) =>
      // ignore: deprecated_member_use — `.value` compiles on every Flutter
      // version in our SDK range; `toARGB32()` needs Flutter >= 3.27.
      '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
