import '../../data/supabase_client.dart';

/// Super-admin (platform owner) gate — Feature 8.
///
/// The `platform_admins` table carries a service-level RLS policy
/// ("platform admins read admin list" USING `is_platform_admin()`), so a
/// plain authenticated query works: non-admins simply see zero rows and
/// this returns false. Fail-closed everywhere: any error (offline, no
/// backend, no session) means "not an admin".
///
/// The result is cached for 5 minutes per app session to avoid a PostgREST
/// round-trip on every navigation; pass `refresh: true` (or call
/// [invalidate]) after a role change.
abstract final class PlatformAdmin {
  static bool? _cached;
  static DateTime? _cachedAt;
  static const _ttl = Duration(minutes: 5);

  /// True when the signed-in user is a platform admin.
  static Future<bool> isAdmin({bool refresh = false}) async {
    if (!refresh && _cached != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _ttl) return _cached!;
    }
    final result = await _query();
    _cached = result;
    _cachedAt = DateTime.now();
    return result;
  }

  /// Drops the cached verdict so the next [isAdmin] re-queries.
  static void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  static Future<bool> _query() async {
    final client = TchopSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;
    try {
      final row = await client
          .from('platform_admins')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false; // fail closed: offline / RLS denial = not an admin
    }
  }
}
