import 'dart:convert';

import '../../core/branding/tenant_brand.dart';
import '../database/tchop_database.dart';
import '../supabase_client.dart';

/// Loads a workspace's brand with an offline-first strategy:
///
/// 1. **Network** — the tenant's own `tenants` row via PostgREST
///    (RLS: members can read their own tenant). No edge function needed
///    for reads.
/// 2. **Drift cache** — the last successfully fetched brand JSON, so the
///    restaurant keeps its white-label look with zero connectivity.
/// 3. Returns null when offline *and* uncached — the caller
///    ([TenantBrandingController]) then falls back to bundled sample brands
///    so the app always renders.
///
/// Every successful network fetch refreshes the cache.
class TenantBrandRepository {
  TenantBrandRepository(this._db);

  final TchopDatabase _db;

  Future<TenantBrand?> loadWorkspace(String tenantId) async {
    final remote = await _fetchRemote(tenantId);
    if (remote != null) {
      await _cache(tenantId, remote);
      return remote;
    }
    return _cached(tenantId);
  }

  Future<TenantBrand?> _fetchRemote(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return null;
    try {
      final row = await client
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .maybeSingle();
      if (row == null) return null;
      return TenantBrand.fromTenantRow(row);
    } catch (_) {
      // Offline, expired session, or RLS denial — caller uses the cache.
      return null;
    }
  }

  Future<void> _cache(String tenantId, TenantBrand brand) {
    return _db.upsertTenant(
      id: tenantId,
      name: brand.name,
      brandJson: jsonEncode(brand.toJson()),
    );
  }

  Future<TenantBrand?> _cached(String tenantId) async {
    final row = await _db.tenantById(tenantId);
    if (row == null) return null;
    try {
      final json = jsonDecode(row.brandJson) as Map<String, dynamic>;
      return TenantBrand.fromJson({...json, 'restaurantId': tenantId});
    } catch (_) {
      return null;
    }
  }
}
