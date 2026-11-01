import 'tenant_brand.dart';

/// Hardcoded demo workspaces so white-label switching can be exercised
/// before the backend exists.
///
/// TODO: replace with `GET /tenants/mine` — the memberships of the signed-in
/// user, each carrying its `brand_json`.
final List<TenantBrand> sampleWorkspaces = [
  TenantBrand.fromJson(const {
    'restaurantId': 'rest_baobab_001',
    'name': 'Le Baobab Gourmand',
    'tagline': 'Cuisine camerounaise authentique — Douala, Akwa',
    'logoUrl': 'https://example.com/logos/baobab-gourmand.png',
    'colors': {'primary': '#E8641B', 'secondary': '#2A2118', 'accent': '#D4AF37'},
    'currency': 'XAF',
    'locale': 'fr_CM',
  }),
  TenantBrand.fromJson(const {
    'restaurantId': 'rest_maman_ngassa_002',
    'name': 'Chez Maman Ngassa',
    'tagline': 'Le goût du terroir — Yaoundé, Mvan',
    'logoUrl': 'https://example.com/logos/maman-ngassa.png',
    'colors': {'primary': '#1E7A34', 'secondary': '#14231A', 'accent': '#E8B931'},
    'currency': 'XAF',
    'locale': 'fr_CM',
  }),
  TenantBrand.fromJson(const {
    'restaurantId': 'rest_ocean_grill_003',
    'name': 'Ocean Grill Kribi',
    'tagline': 'Poisson braisé face à la mer — Kribi',
    'logoUrl': 'https://example.com/logos/ocean-grill.png',
    'colors': {'primary': '#0E7CC4', 'secondary': '#10222F', 'accent': '#F2A03D'},
    'currency': 'XAF',
    'locale': 'fr_CM',
  }),
];
