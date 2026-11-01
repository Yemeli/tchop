import 'package:flutter/foundation.dart';

import '../../data/database/tchop_database.dart';

/// Device-level app preferences: accessibility + performance.
///
/// Persisted with the same raw-SQL key/value pattern as [KdsSettings]
/// (Feature 5) — one row per key inside the app's Drift SQLite file, no
/// codegen table, no extra package. These are *device* settings, not
/// per-workspace: they apply to every flavor on this phone/tablet.
///
/// Honored by:
/// - [reducedMotion]: kitchen ticking timers → 30 s text refresh, the
///   new-ticket beep/flash is silenced, page transitions become instant
///   (see `buildTchopTheme(reducedMotion:)`), the mascot shows a static
///   frame instead of playing its Rive animation.
/// - [liteMode]: disables gradients/shadows/blur, mascot animation, the
///   live map (tracking falls back to the `MapPlaceholder` list mode),
///   slows the kitchen timer tick to 30 s, and keeps image caching to
///   thumbnails only.
class AppSettings {
  const AppSettings({
    this.reducedMotion = false,
    this.liteMode = false,
    this.customerOnboardingSeen = false,
    this.liteSuggested = false,
  });

  /// "Réduire les animations" — accessibility toggle.
  final bool reducedMotion;

  /// "Mode allégé" — manual toggle for low-end devices.
  final bool liteMode;

  /// Customer flavor first-run onboarding shown once.
  final bool customerOnboardingSeen;

  /// Set once by the startup jank heuristic ([StartupJankMeter]) when the
  /// first frames render slowly. Drives the one-time suggestion banner in
  /// the Paramètres screen — never auto-enables lite mode.
  final bool liteSuggested;

  AppSettings copyWith({
    bool? reducedMotion,
    bool? liteMode,
    bool? customerOnboardingSeen,
    bool? liteSuggested,
  }) =>
      AppSettings(
        reducedMotion: reducedMotion ?? this.reducedMotion,
        liteMode: liteMode ?? this.liteMode,
        customerOnboardingSeen:
            customerOnboardingSeen ?? this.customerOnboardingSeen,
        liteSuggested: liteSuggested ?? this.liteSuggested,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.reducedMotion == reducedMotion &&
      other.liteMode == liteMode &&
      other.customerOnboardingSeen == customerOnboardingSeen &&
      other.liteSuggested == liteSuggested;

  @override
  int get hashCode => Object.hash(
      reducedMotion, liteMode, customerOnboardingSeen, liteSuggested);
}

/// Raw-SQL key/value store for [AppSettings] (mirrors `KdsSettingsStore`).
class AppSettingsStore {
  AppSettingsStore(this._db);

  final TchopDatabase _db;

  static const _createTable = '''
CREATE TABLE IF NOT EXISTS app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''';

  Future<void> _ensureTable() => _db.customStatement(_createTable);

  Future<AppSettings> load() async {
    await _ensureTable();
    final rows =
        await _db.customSelect('SELECT key, value FROM app_settings').get();
    final map = {
      for (final r in rows) r.read<String>('key'): r.read<String>('value')
    };
    bool flag(String key) => (map[key] ?? 'false') == 'true';
    return AppSettings(
      reducedMotion: flag('reduced_motion'),
      liteMode: flag('lite_mode'),
      customerOnboardingSeen: flag('customer_onboarding_seen'),
      liteSuggested: flag('lite_suggested'),
    );
  }

  Future<void> save(AppSettings settings) async {
    await _ensureTable();
    Future<void> put(String key, String value) => _db.customStatement(
          'INSERT INTO app_settings (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        );
    await put('reduced_motion', settings.reducedMotion.toString());
    await put('lite_mode', settings.liteMode.toString());
    await put(
        'customer_onboarding_seen', settings.customerOnboardingSeen.toString());
    await put('lite_suggested', settings.liteSuggested.toString());
  }
}

/// Loads once (await [load] before first build so the customer onboarding
/// gate reads the persisted flag), then notifies on every change.
/// Owned by `bootstrap.dart` and exposed via [AppSettingsScope].
class AppSettingsController extends ValueNotifier<AppSettings> {
  AppSettingsController(this._store) : super(const AppSettings());

  final AppSettingsStore _store;

  /// True once [load] has read the persisted row values.
  bool loaded = false;

  Future<void> load() async {
    value = await _store.load();
    loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    value = settings;
    await _store.save(settings);
  }

  Future<void> markCustomerOnboardingSeen() =>
      update(value.copyWith(customerOnboardingSeen: true));

  /// Records the startup heuristic's suggestion exactly once — never
  /// flips [AppSettings.liteMode] on its own; the user decides.
  Future<void> suggestLiteMode() async {
    if (value.liteSuggested || value.liteMode) return;
    await update(value.copyWith(liteSuggested: true));
  }
}
