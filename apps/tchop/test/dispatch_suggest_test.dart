import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/dispatch/dispatch_models.dart';
import 'package:tchop/features/dispatch/mqtt_dispatch_service.dart';

void main() {
  group('suggestDriver', () {
    test('returns null for an empty roster', () {
      expect(suggestDriver(const []), isNull);
    });

    test('prefers the driver with the fewest active deliveries', () {
      final busy = DriverCandidate(
        driverId: 'driver-busy',
        activeDeliveries: 3,
        lastActivityAt: DateTime(2026, 9, 27, 10),
      );
      final free = DriverCandidate(
        driverId: 'driver-free',
        activeDeliveries: 0,
        lastActivityAt: DateTime(2026, 9, 27, 12),
      );
      expect(suggestDriver([busy, free])?.driverId, 'driver-free');
    });

    test('breaks ties by longest idle (oldest last activity)', () {
      final recent = DriverCandidate(
        driverId: 'driver-recent',
        activeDeliveries: 1,
        lastActivityAt: DateTime(2026, 9, 27, 14),
      );
      final idle = DriverCandidate(
        driverId: 'driver-idle',
        activeDeliveries: 1,
        lastActivityAt: DateTime(2026, 9, 27, 9),
      );
      expect(suggestDriver([recent, idle])?.driverId, 'driver-idle');
    });

    test('null last activity counts as the longest idle', () {
      final active = DriverCandidate(
        driverId: 'driver-active',
        activeDeliveries: 0,
        lastActivityAt: DateTime(2026, 9, 27, 14),
      );
      final never = DriverCandidate(
        driverId: 'driver-never',
        activeDeliveries: 0,
      );
      expect(suggestDriver([active, never])?.driverId, 'driver-never');
    });

    test('active-delivery count wins over idleness', () {
      final idleButBusy = DriverCandidate(
        driverId: 'driver-idle-busy',
        activeDeliveries: 2,
      );
      final busyButRecent = DriverCandidate(
        driverId: 'driver-busy-recent',
        activeDeliveries: 1,
        lastActivityAt: DateTime(2026, 9, 27, 14, 30),
      );
      expect(
          suggestDriver([idleButBusy, busyButRecent])?.driverId,
          'driver-busy-recent');
    });

    test('full tie breaks deterministically on driverId', () {
      final b = DriverCandidate(driverId: 'b');
      final a = DriverCandidate(driverId: 'a');
      expect(suggestDriver([b, a])?.driverId, 'a');
      // Stable across input order.
      expect(suggestDriver([a, b])?.driverId, 'a');
    });

    test('single candidate is suggested', () {
      final only = DriverCandidate(driverId: 'solo');
      expect(suggestDriver([only]), same(only));
    });
  });

  group('GeoUtils', () {
    test('haversineKm: Douala Akwa → Bonanjo is a few km', () {
      // Akwa (4.0511, 9.7679) → Bonanjo (4.0483, 9.6843): ~9.3 km.
      final km = GeoUtils.haversineKm(4.0511, 9.7679, 4.0483, 9.6843);
      expect(km, greaterThan(8));
      expect(km, lessThan(11));
    });

    test('haversineKm: same point is zero', () {
      expect(GeoUtils.haversineKm(4.05, 9.76, 4.05, 9.76), 0);
    });

    test('etaLabelFr is labeled as an estimation', () {
      expect(GeoUtils.etaLabelFr(5.0), contains('estimation'));
      expect(GeoUtils.etaLabelFr(0), contains('estimation'));
    });

    test('etaMinutes: 25 km at 25 km/h ≈ 60 min', () {
      expect(GeoUtils.etaMinutes(25), 60);
    });
  });

  group('DriverPosition', () {
    test('MQTT payload round-trips {lat, lng, at, speed}', () {
      final pos = DriverPosition(
        lat: 4.0511,
        lng: 9.7679,
        at: DateTime.utc(2026, 9, 27, 13, 0, 0),
        speedKmh: 22.5,
      );
      final json = pos.toJson();
      expect(json.keys.toSet(), {'lat', 'lng', 'at', 'speed'});
      final back = DriverPosition.fromJson(
          Map<String, dynamic>.from(json));
      expect(back.lat, 4.0511);
      expect(back.lng, 9.7679);
      expect(back.speedKmh, 22.5);
      expect(back.at.toUtc(), DateTime.utc(2026, 9, 27, 13, 0, 0));
    });

    test('MqttConfig.topicFor follows the contract', () {
      expect(
        MqttConfig.topicFor(tenantId: 't1', driverId: 'd9'),
        'tchop/t1/drivers/d9/pos',
      );
    });

    test('unset broker URL is detected as not configured', () {
      // Default value documents "unset"; isConfigured must be false unless
      // --dart-define=MQTT_BROKER_URL overrides it at build time.
      expect(MqttConfig.defaultBrokerUrl, isNotEmpty);
      expect(MqttConfig.isConfigured,
          MqttConfig.brokerUrl != MqttConfig.defaultBrokerUrl);
    });
  });
}
