import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';

/// Backend access for the Tchop app.
///
/// Credentials resolve through [AppConfig] with two layers:
///   1. runtime overrides pasted in the super-admin **Configuration** screen
///      (secure storage — no rebuild needed);
///   2. `--dart-define` build-time defaults (the original behavior, kept as
///      the fallback layer):
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// When no credentials exist anywhere ([isConfigured] == false) the app runs
/// fully offline: [clientOrNull] is null, [SyncEngine] stays idle, and every
/// screen keeps working against the local Drift database with pending-sync
/// badges.
///
/// When the super-admin pastes new keys at runtime, [reinitialize] swaps in
/// a fresh client built from the effective values — the old client is
/// disposed. The new client carries no auth session, so the user must sign
/// in again after a backend change.
class TchopSupabase {
  TchopSupabase._();

  /// Effective credentials: runtime override first, build-time fallback.
  static String get url => AppConfig.current.supabaseUrl;
  static String get anonKey => AppConfig.current.supabaseAnonKey;

  /// True when credentials exist in either layer.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static bool _initialized = false;

  /// True after a successful [initialize] or [reinitialize].
  static bool get initialized => _initialized;

  /// Client built from runtime-pasted keys. Takes precedence over the
  /// singleton created by [initialize] when present.
  static SupabaseClient? _runtimeClient;

  /// Initializes the Supabase singleton. Safe to call when unconfigured —
  /// it simply no-ops so the app boots in offline demo mode. Must be called
  /// after `AppConfig.current.load()` (done in bootstrap).
  static Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(url: url, publishableKey: anonKey);
    _initialized = true;
  }

  /// Re-creates the backend client from the CURRENT effective config
  /// (call after [AppConfig.updateAndPersist]). Previous runtime client is
  /// disposed; the build-time singleton is left alone as the fallback.
  /// No-op when unconfigured. Never throws.
  static Future<void> reinitialize() async {
    if (!isConfigured) return;
    try {
      _runtimeClient?.dispose();
    } catch (_) {
      // a half-dead client must not block the swap
    }
    try {
      _runtimeClient = SupabaseClient(url, anonKey);
      _initialized = true;
    } catch (_) {
      _runtimeClient = null;
    }
  }

  /// Drops the runtime client (e.g. when the override is cleared) so the
  /// build-time singleton / offline mode takes over again. Never throws.
  static void dropRuntimeClient() {
    try {
      _runtimeClient?.dispose();
    } catch (_) {}
    _runtimeClient = null;
  }

  /// The shared client, or null when running unconfigured (offline mode).
  /// Never throws: callers must handle the null (degraded) case.
  static SupabaseClient? get clientOrNull {
    if (!isConfigured) return null;
    final rt = _runtimeClient;
    if (rt != null) return rt;
    if (!_initialized) return null;
    return Supabase.instance.client;
  }
}
