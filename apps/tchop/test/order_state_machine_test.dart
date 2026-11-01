import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/orders/order_state_machine.dart';

void main() {
  group('OrderFlow.legalTransitions', () {
    test('happy path: placed → … → delivered', () {
      expect(OrderFlow.canTransition(OrderStatus.placed, OrderStatus.accepted),
          isTrue);
      expect(
          OrderFlow.canTransition(
              OrderStatus.accepted, OrderStatus.preparing),
          isTrue);
      expect(
          OrderFlow.canTransition(
              OrderStatus.preparing, OrderStatus.ready),
          isTrue);
      expect(OrderFlow.canTransition(OrderStatus.ready, OrderStatus.pickedUp),
          isTrue);
      expect(
          OrderFlow.canTransition(
              OrderStatus.pickedUp, OrderStatus.delivered),
          isTrue);
    });

    test('cancellation allowed from placed/accepted/preparing only', () {
      expect(OrderFlow.isCancellable(OrderStatus.placed), isTrue);
      expect(OrderFlow.isCancellable(OrderStatus.accepted), isTrue);
      expect(OrderFlow.isCancellable(OrderStatus.preparing), isTrue);
      expect(OrderFlow.isCancellable(OrderStatus.ready), isFalse);
      expect(OrderFlow.isCancellable(OrderStatus.pickedUp), isFalse);
      expect(OrderFlow.isCancellable(OrderStatus.delivered), isFalse);
      expect(OrderFlow.isCancellable(OrderStatus.cancelled), isFalse);
    });

    test('no backward or skip transitions', () {
      expect(
          OrderFlow.canTransition(OrderStatus.accepted, OrderStatus.placed),
          isFalse);
      expect(OrderFlow.canTransition(OrderStatus.ready, OrderStatus.preparing),
          isFalse);
      // No skipping the kitchen: placed → preparing is illegal.
      expect(
          OrderFlow.canTransition(OrderStatus.placed, OrderStatus.preparing),
          isFalse);
      expect(OrderFlow.canTransition(OrderStatus.placed, OrderStatus.ready),
          isFalse);
      expect(
          OrderFlow.canTransition(
              OrderStatus.preparing, OrderStatus.delivered),
          isFalse);
    });

    test('terminal states have no outgoing transitions', () {
      for (final to in OrderStatus.values) {
        expect(OrderFlow.canTransition(OrderStatus.delivered, to), isFalse);
        expect(OrderFlow.canTransition(OrderStatus.cancelled, to), isFalse);
      }
      expect(OrderFlow.isTerminal(OrderStatus.delivered), isTrue);
      expect(OrderFlow.isTerminal(OrderStatus.cancelled), isTrue);
      expect(OrderFlow.isTerminal(OrderStatus.ready), isFalse);
    });

    test('transitionOrThrow returns the target or throws', () {
      expect(
        OrderFlow.transitionOrThrow(
            OrderStatus.placed, OrderStatus.accepted),
        OrderStatus.accepted,
      );
      expect(
        () => OrderFlow.transitionOrThrow(
            OrderStatus.ready, OrderStatus.cancelled),
        throwsA(isA<IllegalOrderTransition>()),
      );
      expect(
        () => OrderFlow.transitionOrThrow(
            OrderStatus.delivered, OrderStatus.cancelled),
        throwsA(isA<IllegalOrderTransition>()),
      );
    });
  });

  group('OrderStatus wire values', () {
    test('round-trips snake_case', () {
      expect(OrderStatus.pickedUp.wire, 'picked_up');
      expect(OrderStatusWire.fromWire('picked_up'), OrderStatus.pickedUp);
      for (final s in OrderStatus.values) {
        expect(OrderStatusWire.fromWire(s.wire), s);
      }
    });

    test('unknown wire value throws', () {
      expect(() => OrderStatusWire.fromWire('shipped'), throwsArgumentError);
    });

    test('French labels', () {
      expect(OrderStatus.placed.labelFr, 'Reçue');
      expect(OrderStatus.accepted.labelFr, 'Acceptée');
      expect(OrderStatus.preparing.labelFr, 'En préparation');
      expect(OrderStatus.ready.labelFr, 'Prête');
      expect(OrderStatus.pickedUp.labelFr, 'En livraison');
      expect(OrderStatus.delivered.labelFr, 'Livrée');
      expect(OrderStatus.cancelled.labelFr, 'Annulée');
    });
  });

  group('OrderPermissions', () {
    test('secretary: accept + cancel only', () {
      expect(
        OrderPermissions.allowedFrom('secretary', OrderStatus.placed),
        {OrderStatus.accepted, OrderStatus.cancelled},
      );
      expect(
        OrderPermissions.allowedFrom('secretary', OrderStatus.accepted),
        {OrderStatus.cancelled},
      );
      expect(
        OrderPermissions.canTransitionRole(
          role: 'secretary',
          from: OrderStatus.ready,
          to: OrderStatus.pickedUp,
        ),
        isFalse,
      );
    });

    test('kitchen / head_chef: preparing + ready', () {
      expect(
        OrderPermissions.allowedFrom('kitchen', OrderStatus.accepted),
        {OrderStatus.preparing},
      );
      expect(
        OrderPermissions.allowedFrom('head_chef', OrderStatus.preparing),
        {OrderStatus.ready},
      );
      expect(
        OrderPermissions.canTransitionRole(
          role: 'kitchen',
          from: OrderStatus.placed,
          to: OrderStatus.accepted,
        ),
        isFalse,
      );
    });

    test('driver: picked_up + delivered', () {
      expect(
        OrderPermissions.allowedFrom('driver', OrderStatus.ready),
        {OrderStatus.pickedUp},
      );
      expect(
        OrderPermissions.allowedFrom('driver', OrderStatus.pickedUp),
        {OrderStatus.delivered},
      );
      expect(
        OrderPermissions.canTransitionRole(
          role: 'driver',
          from: OrderStatus.preparing,
          to: OrderStatus.ready,
        ),
        isFalse,
      );
    });

    test('owner / manager: everything legal', () {
      for (final from in OrderStatus.values) {
        expect(
          OrderPermissions.allowedFrom('owner', from),
          OrderFlow.legalTransitions[from],
        );
        expect(
          OrderPermissions.allowedFrom('manager', from),
          OrderFlow.legalTransitions[from],
        );
      }
    });

    test('unknown / null role: nothing', () {
      expect(
          OrderPermissions.allowedFrom(null, OrderStatus.placed), isEmpty);
      expect(
          OrderPermissions.allowedFrom('customer', OrderStatus.placed),
          isEmpty);
    });

    test('action labels are French', () {
      expect(OrderPermissions.actionLabelFr(OrderStatus.accepted), 'Accepter');
      expect(
          OrderPermissions.actionLabelFr(OrderStatus.ready), 'Marquer prête');
      expect(
          OrderPermissions.actionLabelFr(OrderStatus.pickedUp), 'Récupérée');
      expect(
          OrderPermissions.actionLabelFr(OrderStatus.cancelled), 'Annuler');
    });
  });
}
