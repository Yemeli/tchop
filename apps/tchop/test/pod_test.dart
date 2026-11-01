import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/dispatch/dispatch_models.dart';

void main() {
  group('buildDeliveryAssignPayload', () {
    test('shape is snake_case with order_id + driver_id', () {
      final p = buildDeliveryAssignPayload(
        orderId: 'order-1',
        driverId: 'driver-9',
      );
      expect(p['order_id'], 'order-1');
      expect(p['driver_id'], 'driver-9');
      expect(p.containsKey('dropoff_lat'), isFalse);
    });

    test('includes dropoff metadata when provided', () {
      final p = buildDeliveryAssignPayload(
        orderId: 'order-1',
        driverId: 'driver-9',
        dropoffLat: 4.05,
        dropoffLng: 9.76,
        dropoffAddress: 'Akwa, Douala',
      );
      expect(p['dropoff_lat'], 4.05);
      expect(p['dropoff_lng'], 9.76);
      expect(p['dropoff_address'], 'Akwa, Douala');
    });

    test('rejects empty ids', () {
      expect(
        () => buildDeliveryAssignPayload(orderId: '', driverId: 'd'),
        throwsArgumentError,
      );
      expect(
        () => buildDeliveryAssignPayload(orderId: 'o', driverId: ''),
        throwsArgumentError,
      );
    });

    test('op name constant matches the Edge Function route', () {
      expect(DispatchOps.assign, 'delivery/assign');
      expect(DispatchOps.complete, 'delivery/complete');
      expect(DispatchOps.entity, 'delivery');
    });
  });

  group('buildDeliveryCompletePayload', () {
    test('shape carries every PoD field, snake_case', () {
      final p = buildDeliveryCompletePayload(
        deliveryId: 'del-1',
        orderId: 'order-1',
        podPhotoUrl: 'https://cdn/del-1.jpg',
        podLat: 4.05,
        podLng: 9.76,
        signatureSvg: '<svg/>',
      );
      expect(
        p.keys.toSet(),
        {
          'delivery_id',
          'order_id',
          'pod_photo_url',
          'pod_photo_pending_path',
          'pod_lat',
          'pod_lng',
          'signature_svg',
        },
      );
      expect(p['pod_photo_url'], 'https://cdn/del-1.jpg');
      expect(p['pod_lat'], 4.05);
      expect(p['signature_svg'], '<svg/>');
    });

    test('offline photo queues the local path, url stays null', () {
      final p = buildDeliveryCompletePayload(
        deliveryId: 'del-1',
        orderId: 'order-1',
        podPhotoPendingPath: '/data/photo.jpg',
        signatureSvg: '<svg/>',
      );
      expect(p['pod_photo_url'], isNull);
      expect(p['pod_photo_pending_path'], '/data/photo.jpg');
    });

    test('rejects an empty signature', () {
      expect(
        () => buildDeliveryCompletePayload(
          deliveryId: 'del-1',
          orderId: 'order-1',
          signatureSvg: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('signatureStrokesToSvg', () {
    test('encodes strokes as path data inside an svg document', () {
      final svg = signatureStrokesToSvg([
        [const SigPoint(10, 20), const SigPoint(30.5, 40)],
        [const SigPoint(50, 60)],
      ]);
      expect(svg, startsWith('<svg'));
      expect(svg, endsWith('</svg>'));
      expect(svg, contains('<path d="M10,20 L30.5,40"'));
      // A single tap still renders (1px nudge segment).
      expect(svg, contains('M50,60 L51,60'));
      expect(svg.split('<path').length - 1, 2);
    });

    test('rounds coordinates to 1 decimal', () {
      final svg = signatureStrokesToSvg([
        [const SigPoint(10.05, 20.04)],
      ]);
      // 10.05 rounds to 10.1 at 1 decimal (banker's? no — (v*10).round()).
      expect(svg, contains('M10.1,20'));
    });

    test('empty strokes produce an empty string', () {
      expect(signatureStrokesToSvg(const []), isEmpty);
      expect(signatureStrokesToSvg(const [[]]), isEmpty);
    });

    test('non-finite points are skipped', () {
      final svg = signatureStrokesToSvg([
        [const SigPoint(double.nan, 1), const SigPoint(2, 3)],
      ]);
      expect(svg, contains('M2,3'));
      expect(svg, isNot(contains('NaN')));
    });

    test('SigPoint serializes to {x, y}', () {
      expect(const SigPoint(1.5, 2.5).toJson(), {'x': 1.5, 'y': 2.5});
    });
  });
}
