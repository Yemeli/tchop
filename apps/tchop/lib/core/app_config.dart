import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where a configuration value currently comes from.
enum ConfigSource {
  /// Pasted at runtime via the super-admin Configuration screen.
  runtime,

  /// Baked in at build time via `--dart-define`.
  build,

  /// Not set anywhere — the feature runs in degraded/offline mode.
  none,
}

/// Runtime platform configuration — paste-and-go API keys, no rebuild.
///
/// Load order for every key:
///   1. runtime override from secure storage (Keychain / Keystore), set via
///      the super-admin **Configuration** screen;
///   2. `String.fromEnvironment` build-time default (`--dart-define=…`).
///
/// [load] is called once in [bootstrap] BEFORE [TchopSupabase.initialize],
/// so the backend picks up pasted keys. Afterwards [current] is
/// synchronously readable everywhere (MQTT reconnects, the map screen, …).
///
/// Nothing here is ever hardcoded: the only values in the repo are empty
/// defaults. Secrets live in the OS secure storage, never in Drift, never
/// in logs.
class AppConfig extends ChangeNotifier {
  AppConfig._();

  static final AppConfig _instance = AppConfig._();

  /// The singleton — always readable; call [load] once at startup first.
  static AppConfig get current => _instance;

  static const _storage = FlutterSecureStorage();

  // Secure-storage keys (namespaced so they never collide with anything).
  static const _kSupabaseUrl = 'tchop.cfg.supabase_url';
  static const _kSupabaseAnonKey = 'tchop.cfg.supabase_anon_key';
  static const _kMapsApiKey = 'tchop.cfg.maps_api_key';
  static const _kMqttBrokerUrl = 'tchop.cfg.mqtt_broker_url';

  // Layer (b): build-time defaults. Empty when the flag was not passed.
  static const _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _envMapsApiKey = String.fromEnvironment('MAPS_API_KEY');
  static const _envMqttBrokerUrl = String.fromEnvironment('MQTT_BROKER_URL');

  // Layer (a): runtime overrides. Empty string == no override.
  String _rtSupabaseUrl = '';
  String _rtSupabaseAnonKey = '';
  String _rtMapsApiKey = '';
  String _rtMqttBrokerUrl = '';

  bool _loaded = false;

  /// True after [load] completed (called in bootstrap).
  bool get loaded => _loaded;

  /// Reads the four overrides from secure storage. Idempotent.
  Future<void> load() async {
    try {
      _rtSupabaseUrl = (await _storage.read(key: _kSupabaseUrl)) ?? '';
      _rtSupabaseAnonKey = (await _storage.read(key: _kSupabaseAnonKey)) ?? '';
      _rtMapsApiKey = (await _storage.read(key: _kMapsApiKey)) ?? '';
      _rtMqttBrokerUrl = (await _storage.read(key: _kMqttBrokerUrl)) ?? '';
    } catch (_) {
      // Secure storage unavailable (e.g. some test harnesses) — the app
      // simply falls back to build-time values.
      _rtSupabaseUrl = '';
      _rtSupabaseAnonKey = '';
      _rtMapsApiKey = '';
      _rtMqttBrokerUrl = '';
    }
    _loaded = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Effective values (runtime override → build-time default)
  // ------------------------------------------------------------------

  /// Effective Supabase project URL.
  String get supabaseUrl =>
      _rtSupabaseUrl.isNotEmpty ? _rtSupabaseUrl : _envSupabaseUrl;

  /// Effective Supabase anon (publishable) key.
  String get supabaseAnonKey =>
      _rtSupabaseAnonKey.isNotEmpty ? _rtSupabaseAnonKey : _envSupabaseAnonKey;

  /// Effective Google Maps API key.
  String get mapsApiKey =>
      _rtMapsApiKey.isNotEmpty ? _rtMapsApiKey : _envMapsApiKey;

  /// Effective MQTT broker URL (may be empty → simulation mode).
  String get mqttBrokerUrl =>
      _rtMqttBrokerUrl.isNotEmpty ? _rtMqttBrokerUrl : _envMqttBrokerUrl;

  bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  bool get mapsConfigured => mapsApiKey.isNotEmpty;
  bool get mqttOverridden => _rtMqttBrokerUrl.isNotEmpty;

  ConfigSource _source(String runtime, String env) {
    if (runtime.isNotEmpty) return ConfigSource.runtime;
    if (env.isNotEmpty) return ConfigSource.build;
    return ConfigSource.none;
  }

  ConfigSource get supabaseUrlSource => _source(_rtSupabaseUrl, _envSupabaseUrl);
  ConfigSource get supabaseAnonKeySource =>
      _source(_rtSupabaseAnonKey, _envSupabaseAnonKey);
  ConfigSource get mapsApiKeySource => _source(_rtMapsApiKey, _envMapsApiKey);
  ConfigSource get mqttBrokerUrlSource =>
      _source(_rtMqttBrokerUrl, _envMqttBrokerUrl);

  /// Short French label for a [ConfigSource], shown as a badge in the UI.
  static String sourceLabelFr(ConfigSource s) => switch (s) {
        ConfigSource.runtime => 'Application',
        ConfigSource.build => 'Build',
        ConfigSource.none => 'Non configuré',
      };

  // ------------------------------------------------------------------
  // Masked display — never render a raw secret in the UI.
  // ------------------------------------------------------------------

  /// `••••9f2a` style masking: only the last 4 characters are visible.
  static String mask(String value) {
    final v = value.trim();
    if (v.isEmpty) return '—';
    if (v.length <= 8) return '••••';
    return '••••${v.substring(v.length - 4)}';
  }

  String get supabaseUrlMasked => mask(supabaseUrl);
  String get supabaseAnonKeyMasked => mask(supabaseAnonKey);
  String get mapsApiKeyMasked => mask(mapsApiKey);
  String get mqttBrokerUrlMasked =>
      mqttBrokerUrl.isEmpty ? '— (mode simulation)' : mask(mqttBrokerUrl);

  // ------------------------------------------------------------------
  // Mutation
  // ------------------------------------------------------------------

  /// Persists overrides. `null` = leave unchanged; empty/blank string =
  /// CLEAR the runtime override (falls back to the `--dart-define` value).
  /// Notifies listeners so every reader picks the new values up live.
  Future<void> updateAndPersist({
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? mapsApiKey,
    String? mqttBrokerUrl,
  }) async {
    await _write(_kSupabaseUrl, supabaseUrl, (v) => _rtSupabaseUrl = v);
    await _write(
        _kSupabaseAnonKey, supabaseAnonKey, (v) => _rtSupabaseAnonKey = v);
    await _write(_kMapsApiKey, mapsApiKey, (v) => _rtMapsApiKey = v);
    await _write(_kMqttBrokerUrl, mqttBrokerUrl, (v) => _rtMqttBrokerUrl = v);
    notifyListeners();
  }

  Future<void> _write(
    String key,
    String? value,
    void Function(String) assign,
  ) async {
    if (value == null) return; // unchanged
    final v = value.trim();
    try {
      if (v.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: v);
      }
    } catch (_) {
      // Storage failure must never lose the in-memory intent for this
      // session; the value simply won't survive a restart.
    }
    assign(v);
  }
}
