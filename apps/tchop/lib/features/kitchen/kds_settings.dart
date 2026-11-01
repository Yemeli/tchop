import 'package:flutter/foundation.dart';

import '../../data/database/tchop_database.dart';

/// KDS (kitchen display) per-device settings: station name, high-contrast
/// night mode, and the auto-advance toggle.
///
/// Persisted as a tiny key/value table inside the same Drift SQLite file —
/// no codegen table, no extra package. One row per key.
class KdsSettings {
  const KdsSettings({
    this.stationName = '',
    this.nightMode = false,
    this.autoAdvance = false,
  });

  /// Free-form label shown in the board header ("Cuisine · Poste grillades").
  final String stationName;

  /// "Mode nuit cuisine": pure-black high-contrast board for night service.
  final bool nightMode;

  /// When true, tickets sitting in "Nouveau" auto-transition to
  /// "En préparation" 60 s after arrival (still via `order/transition`,
  /// still role-gated — it's a stub convenience, not a server rule).
  final bool autoAdvance;

  KdsSettings copyWith({
    String? stationName,
    bool? nightMode,
    bool? autoAdvance,
  }) =>
      KdsSettings(
        stationName: stationName ?? this.stationName,
        nightMode: nightMode ?? this.nightMode,
        autoAdvance: autoAdvance ?? this.autoAdvance,
      );
}

/// Raw-SQL key/value store for [KdsSettings] (keeps the hand-written
/// `.g.dart` untouched — this table has no generated row class).
class KdsSettingsStore {
  KdsSettingsStore(this._db);

  final TchopDatabase _db;

  static const _createTable = '''
CREATE TABLE IF NOT EXISTS kds_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''';

  Future<void> _ensureTable() => _db.customStatement(_createTable);

  Future<KdsSettings> load() async {
    await _ensureTable();
    final rows =
        await _db.customSelect('SELECT key, value FROM kds_settings').get();
    final map = {
      for (final r in rows) r.read<String>('key'): r.read<String>('value')
    };
    return KdsSettings(
      stationName: map['station_name'] ?? '',
      nightMode: (map['night_mode'] ?? 'false') == 'true',
      autoAdvance: (map['auto_advance'] ?? 'false') == 'true',
    );
  }

  Future<void> save(KdsSettings settings) async {
    await _ensureTable();
    Future<void> put(String key, String value) => _db.customStatement(
          'INSERT INTO kds_settings (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        );
    await put('station_name', settings.stationName);
    await put('night_mode', settings.nightMode.toString());
    await put('auto_advance', settings.autoAdvance.toString());
  }
}

/// Loads once, then notifies the board on every change. Owned by the
/// ticket board screen's state.
class KdsSettingsController extends ValueNotifier<KdsSettings> {
  KdsSettingsController(this._store) : super(const KdsSettings()) {
    _init();
  }

  final KdsSettingsStore _store;

  Future<void> _init() async {
    value = await _store.load();
  }

  Future<void> update(KdsSettings settings) async {
    value = settings;
    await _store.save(settings);
  }
}
