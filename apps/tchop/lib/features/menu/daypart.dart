/// Daypart (service window) scheduling for the menu studio.
///
/// A daypart is a named availability window — Petit-déjeuner, Déjeuner,
/// Dîner — stored on the menu draft as a `dayparts` array. The storefront
/// resolves which window is live with [activeDaypart].
///
/// Pure Dart: no Flutter dependency, fully unit-tested.
class Daypart {
  const Daypart({
    required this.id,
    required this.name,
    required this.startMinutes,
    required this.endMinutes,
  })  : assert(startMinutes >= 0 && startMinutes < 24 * 60),
        assert(endMinutes >= 0 && endMinutes <= 24 * 60);

  final String id;
  final String name;

  /// Minutes since midnight, local restaurant time. `endMinutes` may be
  /// smaller than `startMinutes` for overnight windows (e.g. 22:00–02:00).
  final int startMinutes;
  final int endMinutes;

  /// True when [now] falls inside this window (inclusive start, exclusive
  /// end). Overnight windows wrap past midnight.
  bool contains(DateTime now) {
    final m = now.hour * 60 + now.minute;
    if (startMinutes <= endMinutes) {
      return m >= startMinutes && m < endMinutes;
    }
    // Overnight: e.g. 22:00–02:00 covers 22:00–23:59 and 00:00–01:59.
    return m >= startMinutes || m < endMinutes;
  }

  String get startLabel => _label(startMinutes);
  String get endLabel => _label(endMinutes);

  static String _label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Sensible Cameroon defaults: Petit-déjeuner 06:30–10:30,
  /// Déjeuner 11:00–15:00, Dîner 18:00–23:00.
  static List<Daypart> defaults() => const [
        Daypart(
            id: 'petit_dej',
            name: 'Petit-déjeuner',
            startMinutes: 6 * 60 + 30,
            endMinutes: 10 * 60 + 30),
        Daypart(
            id: 'dejeuner',
            name: 'Déjeuner',
            startMinutes: 11 * 60,
            endMinutes: 15 * 60),
        Daypart(
            id: 'diner',
            name: 'Dîner',
            startMinutes: 18 * 60,
            endMinutes: 23 * 60),
      ];

  factory Daypart.fromJson(Map<String, dynamic> json) => Daypart(
        id: json['id'] as String,
        name: json['name'] as String,
        startMinutes: _parseMinutes(json['start']),
        endMinutes: _parseMinutes(json['end']),
      );

  /// Accepts `"HH:MM"` strings (draft storage format) or raw minute ints.
  static int _parseMinutes(Object? value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': startLabel,
        'end': endLabel,
      };

  Daypart copyWith({String? name, int? startMinutes, int? endMinutes}) =>
      Daypart(
        id: id,
        name: name ?? this.name,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );
}

/// Resolves the currently active daypart for the storefront.
///
/// Returns the first window (in list order) containing [now], or null when
/// no window is live (e.g. between Déjeuner and Dîner) — the storefront
/// should then show the menu as "fermé" or the next upcoming window.
Daypart? activeDaypart(List<Daypart> dayparts, DateTime now) {
  for (final daypart in dayparts) {
    if (daypart.contains(now)) return daypart;
  }
  return null;
}
