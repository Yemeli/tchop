import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/menu/daypart.dart';

DateTime at(int hour, int minute) => DateTime(2026, 9, 27, hour, minute);

void main() {
  group('Daypart.defaults', () {
    test('Cameroon service windows', () {
      final defaults = Daypart.defaults();
      expect(defaults.map((d) => d.id),
          ['petit_dej', 'dejeuner', 'diner']);
      expect(defaults.map((d) => d.name),
          ['Petit-déjeuner', 'Déjeuner', 'Dîner']);
      expect(defaults[0].startMinutes, 6 * 60 + 30);
      expect(defaults[0].endMinutes, 10 * 60 + 30);
      expect(defaults[1].startMinutes, 11 * 60);
      expect(defaults[1].endMinutes, 15 * 60);
      expect(defaults[2].startMinutes, 18 * 60);
      expect(defaults[2].endMinutes, 23 * 60);
    });
  });

  group('activeDaypart', () {
    final dayparts = Daypart.defaults();

    test('resolves the live window', () {
      expect(activeDaypart(dayparts, at(8, 0))?.id, 'petit_dej');
      expect(activeDaypart(dayparts, at(12, 30))?.id, 'dejeuner');
      expect(activeDaypart(dayparts, at(20, 0))?.id, 'diner');
    });

    test('null between windows and at night', () {
      expect(activeDaypart(dayparts, at(16, 0)), isNull);
      expect(activeDaypart(dayparts, at(2, 0)), isNull);
      expect(activeDaypart(dayparts, at(5, 0)), isNull);
    });

    test('start inclusive, end exclusive', () {
      expect(activeDaypart(dayparts, at(6, 30))?.id, 'petit_dej');
      expect(activeDaypart(dayparts, at(10, 29))?.id, 'petit_dej');
      expect(activeDaypart(dayparts, at(10, 30)), isNull);
      expect(activeDaypart(dayparts, at(11, 0))?.id, 'dejeuner');
    });

    test('empty list → null', () {
      expect(activeDaypart(const [], at(12, 0)), isNull);
    });
  });

  group('Daypart.contains overnight windows', () {
    const night = Daypart(
        id: 'nuit', name: 'Nuit', startMinutes: 22 * 60, endMinutes: 2 * 60);

    test('wraps past midnight', () {
      expect(night.contains(at(23, 30)), isTrue);
      expect(night.contains(at(0, 0)), isTrue);
      expect(night.contains(at(1, 59)), isTrue);
      expect(night.contains(at(2, 0)), isFalse);
      expect(night.contains(at(21, 59)), isFalse);
      expect(night.contains(at(12, 0)), isFalse);
    });

    test('overnight window wins in activeDaypart', () {
      expect(activeDaypart([night], at(0, 30))?.id, 'nuit');
    });
  });

  group('Daypart JSON', () {
    test('round-trips through HH:MM strings', () {
      const original = Daypart(
          id: 'dejeuner',
          name: 'Déjeuner',
          startMinutes: 11 * 60,
          endMinutes: 15 * 60);
      final json = original.toJson();
      expect(json['start'], '11:00');
      expect(json['end'], '15:00');
      final restored = Daypart.fromJson(json);
      expect(restored.id, 'dejeuner');
      expect(restored.startMinutes, 11 * 60);
      expect(restored.endMinutes, 15 * 60);
    });
  });
}
