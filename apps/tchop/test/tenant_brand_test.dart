import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/core/branding/tenant_brand.dart';

void main() {
  group('TenantBrand', () {
    test('parses the sample workspace JSON', () {
      final brand = TenantBrand.fromJson(const {
        'restaurantId': 'rest_baobab_001',
        'name': 'Le Baobab Gourmand',
        'tagline': 'Cuisine camerounaise authentique — Douala, Akwa',
        'colors': {
          'primary': '#E8641B',
          'secondary': '#2A2118',
          'accent': '#D4AF37',
        },
        'currency': 'XAF',
        'locale': 'fr_CM',
      });

      expect(brand.restaurantId, 'rest_baobab_001');
      expect(brand.name, 'Le Baobab Gourmand');
      expect(brand.primary, const Color(0xFFE8641B));
      expect(brand.currency, 'XAF');
    });

    test('falls back gracefully on malformed colors', () {
      final brand = TenantBrand.fromJson(const {
        'restaurantId': 'x',
        'name': 'Broken',
        'colors': {'primary': 'not-a-color'},
      });

      expect(brand.primary, const Color(0xFFE8641B));
    });

    test('fallback brand is renderable', () {
      final brand = TenantBrand.fallback();
      expect(brand.name.isNotEmpty, isTrue);
    });

    test('round-trips through JSON', () {
      final original = TenantBrand.fromJson(const {
        'restaurantId': 'rest_ocean_grill_003',
        'name': 'Ocean Grill Kribi',
        'colors': {
          'primary': '#0E7CC4',
          'secondary': '#10222F',
          'accent': '#F2A03D',
        },
      });
      final restored = TenantBrand.fromJson(original.toJson());
      expect(restored.primary, original.primary);
      expect(restored.name, original.name);
    });
  });

  group('TenantBrand.fromTenantRow (PostgREST tenants row)', () {
    test('maps snake_case server columns', () {
      final brand = TenantBrand.fromTenantRow({
        'id': '9f0c1a2b-3c4d-4e5f-8a9b-0c1d2e3f4a5b',
        'name': 'Le Baobab Gourmand',
        'slug': 'le-baobab-gourmand',
        'logo_url': 'https://example.com/logos/baobab.png',
        'primary_color': '#E8641B',
        'secondary_color': '#2A2118',
        'currency': 'XAF',
        'country': 'CM',
        'timezone': 'Africa/Douala',
      });

      expect(brand.restaurantId, '9f0c1a2b-3c4d-4e5f-8a9b-0c1d2e3f4a5b');
      expect(brand.name, 'Le Baobab Gourmand');
      expect(brand.subdomain, 'le-baobab-gourmand');
      expect(brand.logoUrl, 'https://example.com/logos/baobab.png');
      expect(brand.primary, const Color(0xFFE8641B));
      expect(brand.secondary, const Color(0xFF2A2118));
      expect(brand.currency, 'XAF');
    });

    test('falls back gracefully on missing/partial rows', () {
      final brand = TenantBrand.fromTenantRow(const {'name': 'Sans Couleurs'});

      expect(brand.restaurantId, 'unknown');
      expect(brand.name, 'Sans Couleurs');
      expect(brand.primary, const Color(0xFFE8641B)); // neutral default
      expect(brand.currency, 'XAF');
    });

    test('round-trips through the Drift brand cache', () {
      final remote = TenantBrand.fromTenantRow(const {
        'id': 'tenant-cache-1',
        'name': 'Chez Maman Ngassa',
        'primary_color': '#1E7A34',
      });
      // Repository caches brand.toJson() and re-parses with fromJson.
      final restored = TenantBrand.fromJson(remote.toJson());
      expect(restored.name, remote.name);
      expect(restored.primary, remote.primary);
      expect(restored.restaurantId, 'tenant-cache-1');
    });
  });
}
