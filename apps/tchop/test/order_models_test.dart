import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/orders/order_models.dart';

void main() {
  group('buildOrderCreatePayload', () {
    Map<String, Object?> payload() => buildOrderCreatePayload(
          menuVersion: 12,
          lines: const [
            OrderLine(itemId: 'ndole', qty: 2, unitPrice: 3000),
          ],
          subtotal: 6000,
          deliveryFee: 1000,
          total: 7000,
          channel: OrderChannel.app,
          customerName: 'Amina',
          customerPhone: '+237690000000',
          paymentMethod: OrderPaymentMethod.mtnMomo,
          clientMutationId: 'cmid-1',
        );

    test('canonical shape: snake_case keys, FCFA minor units', () {
      final p = payload();
      expect(p['op'], 'order/create');
      expect(p['menu_version'], 12);
      expect(p['lines'], [
        {'item_id': 'ndole', 'qty': 2, 'unit_price': 3000},
      ]);
      expect(p['subtotal'], 6000);
      expect(p['delivery_fee'], 1000);
      expect(p['total'], 7000);
      expect(p['channel'], 'app');
      expect(p['customer'], {'name': 'Amina', 'phone': '+237690000000'});
      expect(p['payment_method'], 'mtn_momo');
      expect(p['client_mutation_id'], 'cmid-1');
      expect(p.containsKey('table_number'), isFalse);
    });

    test('qr_table requires table_number', () {
      expect(
        () => buildOrderCreatePayload(
          menuVersion: 1,
          lines: const [OrderLine(itemId: 'x', qty: 1, unitPrice: 100)],
          subtotal: 100,
          deliveryFee: 0,
          total: 100,
          channel: OrderChannel.qrTable,
          customerName: 'Table 3',
          customerPhone: '+237600000000',
          paymentMethod: OrderPaymentMethod.cash,
          clientMutationId: 'cmid-2',
        ),
        throwsArgumentError,
      );
      final p = buildOrderCreatePayload(
        menuVersion: 1,
        lines: const [OrderLine(itemId: 'x', qty: 1, unitPrice: 100)],
        subtotal: 100,
        deliveryFee: 0,
        total: 100,
        channel: OrderChannel.qrTable,
        customerName: 'Table 3',
        customerPhone: '+237600000000',
        tableNumber: 3,
        paymentMethod: OrderPaymentMethod.cash,
        clientMutationId: 'cmid-2',
      );
      expect(p['table_number'], 3);
    });

    test('rejects empty lines / unknown channel / unknown payment', () {
      Object? build({String channel = 'app', String pm = 'mtn_momo'}) =>
          buildOrderCreatePayload(
            menuVersion: 1,
            lines: const [],
            subtotal: 0,
            deliveryFee: 0,
            total: 0,
            channel: channel,
            customerName: 'A',
            customerPhone: '+237600000000',
            paymentMethod: pm,
            clientMutationId: 'x',
          );
      expect(() => build(), throwsArgumentError);
      expect(() => build(channel: 'pigeon'), throwsArgumentError);
      expect(() => build(pm: 'bitcoin'), throwsArgumentError);
    });

    test('French labels', () {
      expect(OrderChannel.labelFr(OrderChannel.walkin), 'Sur place');
      expect(OrderChannel.labelFr(OrderChannel.qrTable), 'QR Table');
      expect(OrderPaymentMethod.labelFr(OrderPaymentMethod.mtnMomo),
          'MTN MoMo');
      expect(
          OrderPaymentMethod.labelFr(OrderPaymentMethod.cash), 'Espèces');
    });
  });

  group('QrTableLink', () {
    test('parses tchop://order?tenant={slug}&table={n}', () {
      final link =
          QrTableLink.tryParse('tchop://order?tenant=la-palmeraie&table=12');
      expect(link, isNotNull);
      expect(link!.tenantSlug, 'la-palmeraie');
      expect(link.tableNumber, 12);
    });

    test('round-trips through build()', () {
      final raw =
          QrTableLink.build(tenantSlug: 'chez-maman', tableNumber: 3);
      final link = QrTableLink.tryParse(raw);
      expect(link?.tenantSlug, 'chez-maman');
      expect(link?.tableNumber, 3);
    });

    test('rejects malformed links', () {
      expect(QrTableLink.tryParse('https://example.com'), isNull);
      expect(QrTableLink.tryParse('tchop://menu?tenant=x&table=1'), isNull);
      expect(QrTableLink.tryParse('tchop://order?table=1'), isNull);
      expect(QrTableLink.tryParse('tchop://order?tenant=x'), isNull);
      expect(
          QrTableLink.tryParse('tchop://order?tenant=x&table=0'), isNull);
      expect(
          QrTableLink.tryParse('tchop://order?tenant=x&table=abc'), isNull);
      expect(QrTableLink.tryParse('not a uri at all %%'), isNull);
    });
  });

  group('formatFcfa', () {
    test('thousands separated, FCFA suffix', () {
      expect(formatFcfa(4500), '4 500 FCFA');
      expect(formatFcfa(1000000), '1 000 000 FCFA');
      expect(formatFcfa(500), '500 FCFA');
      expect(formatFcfa(0), '0 FCFA');
    });
  });
}
