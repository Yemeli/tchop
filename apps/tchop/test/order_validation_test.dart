import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/orders/order_models.dart';
import 'package:tchop/features/orders/order_validation.dart';

/// Tests the client-side mirror of the server's `order/create` validation
/// (`public.create_order_validated` — the SQL function implements the same
/// algorithm inside one transaction; see
/// supabase/migrations/20260927_order_validation.sql).
OrderValidationResult validate({
  int clientVersion = 7,
  int? currentVersion = 7,
  List<OrderLineInput> lines = const [
    OrderLineInput(itemId: 'ndole', qty: 2, unitPrice: 3000),
    OrderLineInput(itemId: 'poulet-dg', qty: 1, unitPrice: 4500),
  ],
  Map<String, int> prices = const {'ndole': 3000, 'poulet-dg': 4500},
  Set<String> unavailable = const {},
  int deliveryFee = 1000,
}) =>
    validateOrderForCreate(
      clientMenuVersion: clientVersion,
      currentMenuVersion: currentVersion,
      lines: lines,
      snapshotPrices: prices,
      unavailableItemIds: unavailable,
      deliveryFeeFcfa: deliveryFee,
    );

void main() {
  group('validateOrderForCreate — happy path', () {
    test('valid order: no conflicts, totals recomputed', () {
      final result = validate();
      expect(result.ok, isTrue);
      expect(result.conflicts, isEmpty);
      expect(result.subtotal, 2 * 3000 + 4500);
      expect(result.deliveryFee, 1000);
      expect(result.total, 2 * 3000 + 4500 + 1000);
    });

    test('empty lines validate (client guards this earlier)', () {
      final result = validate(lines: const []);
      expect(result.ok, isTrue);
      expect(result.subtotal, 0);
      expect(result.total, 1000); // delivery fee only
    });
  });

  group('stale menu_version', () {
    test('version mismatch → single stale_menu conflict', () {
      final result = validate(clientVersion: 6, currentVersion: 7);
      expect(result.ok, isFalse);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.reason, OrderConflictReason.staleMenu);
      expect(conflict.currentMenuVersion, 7);
      // Conflict shape matches the 409 body: {item_id, reason, …}
      final json = conflict.toJson();
      expect(json['reason'], 'stale_menu');
      expect(json.containsKey('item_id'), isTrue);
      expect(OrderConflict.fromJson(json).reason, 'stale_menu');
    });

    test('no published snapshot → no_menu_published conflict', () {
      final result = validate(currentVersion: null);
      expect(result.ok, isFalse);
      expect(result.conflicts.single.reason,
          OrderConflictReason.noMenuPublished);
    });
  });

  group('line validation', () {
    test('price mismatch → price_changed with current_price', () {
      final result = validate(
        lines: const [
          OrderLineInput(itemId: 'ndole', qty: 1, unitPrice: 2500),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.itemId, 'ndole');
      expect(conflict.reason, OrderConflictReason.priceChanged);
      expect(conflict.currentPrice, 3000);
      expect(conflict.toJson(), {
        'item_id': 'ndole',
        'reason': 'price_changed',
        'current_price': 3000,
      });
    });

    test('86’d item → unavailable', () {
      final result = validate(unavailable: {'poulet-dg'});
      expect(result.ok, isFalse);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.itemId, 'poulet-dg');
      expect(result.conflicts.single.reason, OrderConflictReason.unavailable);
    });

    test('item missing from snapshot → unavailable', () {
      final result = validate(
        lines: const [
          OrderLineInput(itemId: 'ghost-item', qty: 1, unitPrice: 999),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.conflicts.single.reason, OrderConflictReason.unavailable);
    });

    test('zero qty → invalid_qty', () {
      final result = validate(
        lines: const [
          OrderLineInput(itemId: 'ndole', qty: 0, unitPrice: 3000),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.conflicts.single.reason, OrderConflictReason.invalidQty);
    });

    test('multiple bad lines → one conflict per line', () {
      final result = validate(
        lines: const [
          OrderLineInput(itemId: 'ndole', qty: 1, unitPrice: 2500),
          OrderLineInput(itemId: 'poulet-dg', qty: 1, unitPrice: 4500),
        ],
        unavailable: {'poulet-dg'},
      );
      expect(result.ok, isFalse);
      expect(result.conflicts, hasLength(2));
      expect(
        result.conflicts.map((c) => c.reason),
        ['price_changed', 'unavailable'],
      );
    });
  });

  group('totals recompute', () {
    test('client totals are ignored — server recomputes from snapshot', () {
      // Simulate a client that sent stale/wrong totals: validation must
      // produce the server-side numbers regardless.
      final result = validateOrderForCreate(
        clientMenuVersion: 7,
        currentMenuVersion: 7,
        lines: const [
          // client claims unit_price 3000 — matches, but totals below are
          // deliberately NOT passed to the validator at all.
          OrderLineInput(itemId: 'ndole', qty: 3, unitPrice: 3000),
        ],
        snapshotPrices: const {'ndole': 3000},
        unavailableItemIds: const {},
        deliveryFeeFcfa: 500,
      );
      expect(result.ok, isTrue);
      expect(result.subtotal, 9000);
      expect(result.deliveryFee, 500);
      expect(result.total, 9500);
    });
  });

  group('OrderConflict.messageFr', () {
    test('French messages per reason', () {
      String nameOf(String id) => {'ndole': 'Ndolé'}[id] ?? id;
      expect(
        const OrderConflict(reason: OrderConflictReason.staleMenu)
            .messageFr(nameOf),
        contains('menu a changé'),
      );
      expect(
        const OrderConflict(
                itemId: 'ndole', reason: OrderConflictReason.unavailable)
            .messageFr(nameOf),
        contains('Ndolé'),
      );
      expect(
        const OrderConflict(
          itemId: 'ndole',
          reason: OrderConflictReason.priceChanged,
          currentPrice: 3000,
        ).messageFr(nameOf),
        contains('3 000 FCFA'),
      );
    });
  });
}
