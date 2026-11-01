/// Order lifecycle state machine for Project Tchop.
///
/// Pure Dart — no Flutter dependency — so the transition rules are
/// unit-testable and identical on every flavor (customer, kitchen, driver,
/// manager).
///
/// Lifecycle:
///   placed → accepted → preparing → ready → picked_up → delivered
/// Cancellation is allowed from `placed`, `accepted` and `preparing` only —
/// once the kitchen marks an order `ready` it can no longer be cancelled.
///
/// The server enforces the SAME map in `supabase/functions/sync/index.ts`
/// (`LEGAL_TRANSITIONS`, flagged as a manual mirror of this file). Any
/// change here MUST be mirrored there.
enum OrderStatus {
  placed,
  accepted,
  preparing,
  ready,
  pickedUp,
  delivered,
  cancelled,
}

/// Wire value ↔ enum conversion (the API and Postgres use snake_case).
extension OrderStatusWire on OrderStatus {
  String get wire {
    switch (this) {
      case OrderStatus.placed:
        return 'placed';
      case OrderStatus.accepted:
        return 'accepted';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.ready:
        return 'ready';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  /// French label shown in timelines, lists and notifications.
  String get labelFr {
    switch (this) {
      case OrderStatus.placed:
        return 'Reçue';
      case OrderStatus.accepted:
        return 'Acceptée';
      case OrderStatus.preparing:
        return 'En préparation';
      case OrderStatus.ready:
        return 'Prête';
      case OrderStatus.pickedUp:
        return 'En livraison';
      case OrderStatus.delivered:
        return 'Livrée';
      case OrderStatus.cancelled:
        return 'Annulée';
    }
  }

  static OrderStatus fromWire(String wire) {
    switch (wire) {
      case 'placed':
        return OrderStatus.placed;
      case 'accepted':
        return OrderStatus.accepted;
      case 'preparing':
        return OrderStatus.preparing;
      case 'ready':
        return OrderStatus.ready;
      case 'picked_up':
        return OrderStatus.pickedUp;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        throw ArgumentError('Unknown order status: $wire');
    }
  }
}

/// Thrown when code attempts a transition the state machine forbids.
class IllegalOrderTransition implements Exception {
  IllegalOrderTransition(this.from, this.to);

  final OrderStatus from;
  final OrderStatus to;

  @override
  String toString() =>
      'Transition de commande interdite : ${from.wire} → ${to.wire}';
}

/// The legal transition graph. SOURCE OF TRUTH for the client; mirrored in
/// TypeScript inside `supabase/functions/sync/index.ts` (search for
/// `LEGAL_TRANSITIONS`).
abstract final class OrderFlow {
  /// Every status → the statuses it may move to next.
  static const Map<OrderStatus, Set<OrderStatus>> legalTransitions = {
    OrderStatus.placed: {OrderStatus.accepted, OrderStatus.cancelled},
    OrderStatus.accepted: {OrderStatus.preparing, OrderStatus.cancelled},
    OrderStatus.preparing: {OrderStatus.ready, OrderStatus.cancelled},
    OrderStatus.ready: {OrderStatus.pickedUp},
    OrderStatus.pickedUp: {OrderStatus.delivered},
    OrderStatus.delivered: {},
    OrderStatus.cancelled: {},
  };

  /// Ordered timeline for the tracking UI (excludes `cancelled`).
  static const List<OrderStatus> timeline = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.pickedUp,
    OrderStatus.delivered,
  ];

  static bool canTransition(OrderStatus from, OrderStatus to) =>
      legalTransitions[from]?.contains(to) ?? false;

  /// Returns [to] when the transition is legal, throws
  /// [IllegalOrderTransition] otherwise.
  static OrderStatus transitionOrThrow(OrderStatus from, OrderStatus to) {
    if (!canTransition(from, to)) throw IllegalOrderTransition(from, to);
    return to;
  }

  /// Cancellation is only possible before the kitchen marks the order
  /// `ready` — i.e. from placed / accepted / preparing.
  static bool isCancellable(OrderStatus from) =>
      canTransition(from, OrderStatus.cancelled);

  static bool isTerminal(OrderStatus status) =>
      status == OrderStatus.delivered || status == OrderStatus.cancelled;
}

/// Role-gated order actions (mirrors the server-side `ROLE_OK` map in
/// `supabase/functions/sync/index.ts`).
///
/// - secretary: accept + cancel (the POS / order-desk role);
/// - kitchen / head_chef: preparing + ready;
/// - driver: picked_up + delivered;
/// - owner / manager: everything.
abstract final class OrderPermissions {
  /// All transitions [role] is allowed to perform from [from].
  static Set<OrderStatus> allowedFrom(String? role, OrderStatus from) {
    final legal = OrderFlow.legalTransitions[from] ?? const {};
    switch (role) {
      case 'owner':
      case 'manager':
        return legal;
      case 'secretary':
        return legal
            .where((to) =>
                to == OrderStatus.accepted || to == OrderStatus.cancelled)
            .toSet();
      case 'kitchen':
      case 'head_chef':
        return legal
            .where((to) =>
                to == OrderStatus.preparing || to == OrderStatus.ready)
            .toSet();
      case 'driver':
        return legal
            .where((to) =>
                to == OrderStatus.pickedUp || to == OrderStatus.delivered)
            .toSet();
      default:
        return const {};
    }
  }

  static bool canTransitionRole({
    required String? role,
    required OrderStatus from,
    required OrderStatus to,
  }) =>
      allowedFrom(role, from).contains(to);

  /// French verb for the action button, e.g. "Accepter", "Marquer prête".
  static String actionLabelFr(OrderStatus to) {
    switch (to) {
      case OrderStatus.accepted:
        return 'Accepter';
      case OrderStatus.preparing:
        return 'En préparation';
      case OrderStatus.ready:
        return 'Marquer prête';
      case OrderStatus.pickedUp:
        return 'Récupérée';
      case OrderStatus.delivered:
        return 'Livrée';
      case OrderStatus.cancelled:
        return 'Annuler';
      case OrderStatus.placed:
        return 'Reçue';
    }
  }
}
