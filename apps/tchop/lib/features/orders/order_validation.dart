/// Client-side mirror of the server's `order/create` validation.
///
/// The authoritative implementation lives in Postgres
/// (`public.create_order_validated`, see
/// `supabase/migrations/20260927_order_validation.sql`) and runs inside a
/// single transaction in the `sync` Edge Function. This Dart copy implements
/// the EXACT same algorithm so it can be unit-tested without a database —
/// any change here MUST be mirrored in the SQL function and vice versa.
///
/// Rules (in order):
/// 1. `menu_version` must equal the current published snapshot version —
///    otherwise a single `stale_menu` conflict (the whole cart was built on
///    an old menu).
/// 2. Every line: the item must exist in the snapshot AND be available
///    (`item_availability`, default true) — else `unavailable`.
/// 3. `unit_price` must equal the snapshot price — else `price_changed`
///    with `current_price`.
/// 4. Totals are RECOMPUTED from snapshot prices; client-sent totals are
///    ignored (the client sends them only for the optimistic UI).
library;

import 'order_models.dart';

/// One line as sent by the client (before server validation).
class OrderLineInput {
  const OrderLineInput({
    required this.itemId,
    required this.qty,
    required this.unitPrice,
  });

  final String itemId;
  final int qty;
  final int unitPrice;
}

/// Result of [validateOrderForCreate].
class OrderValidationResult {
  const OrderValidationResult({
    required this.conflicts,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
  });

  /// Empty when the order is valid.
  final List<OrderConflict> conflicts;

  /// Recomputed from snapshot prices — never trust the client's totals.
  final int subtotal;
  final int deliveryFee;
  final int total;

  bool get ok => conflicts.isEmpty;
}

/// Runs the server's `order/create` validation algorithm (pure function).
///
/// - [clientMenuVersion]: the snapshot version the cart was rendered from.
/// - [currentMenuVersion]: the live published version (null = no snapshot).
/// - [snapshotPrices]: item_id → price (FCFA) from the current snapshot.
/// - [unavailableItemIds]: item_ids with `item_availability.available=false`
///   (absence from this set means available).
/// - [deliveryFeeFcfa]: the tenant's configured delivery fee.
OrderValidationResult validateOrderForCreate({
  required int clientMenuVersion,
  required int? currentMenuVersion,
  required List<OrderLineInput> lines,
  required Map<String, int> snapshotPrices,
  required Set<String> unavailableItemIds,
  required int deliveryFeeFcfa,
}) {
  if (currentMenuVersion == null) {
    return OrderValidationResult(
      conflicts: const [
        OrderConflict(reason: OrderConflictReason.noMenuPublished),
      ],
      subtotal: 0,
      deliveryFee: 0,
      total: 0,
    );
  }
  if (clientMenuVersion != currentMenuVersion) {
    return OrderValidationResult(
      conflicts: [
        OrderConflict(
          reason: OrderConflictReason.staleMenu,
          currentMenuVersion: currentMenuVersion,
        ),
      ],
      subtotal: 0,
      deliveryFee: 0,
      total: 0,
    );
  }

  final conflicts = <OrderConflict>[];
  var subtotal = 0;
  for (final line in lines) {
    if (line.qty <= 0) {
      conflicts.add(OrderConflict(
          itemId: line.itemId, reason: OrderConflictReason.invalidQty));
      continue;
    }
    final price = snapshotPrices[line.itemId];
    if (price == null || unavailableItemIds.contains(line.itemId)) {
      conflicts.add(OrderConflict(
          itemId: line.itemId, reason: OrderConflictReason.unavailable));
      continue;
    }
    if (line.unitPrice != price) {
      conflicts.add(OrderConflict(
        itemId: line.itemId,
        reason: OrderConflictReason.priceChanged,
        currentPrice: price,
      ));
      continue;
    }
    subtotal += line.qty * price;
  }
  if (conflicts.isNotEmpty) {
    return OrderValidationResult(
      conflicts: conflicts,
      subtotal: 0,
      deliveryFee: 0,
      total: 0,
    );
  }
  return OrderValidationResult(
    conflicts: const [],
    subtotal: subtotal,
    deliveryFee: deliveryFeeFcfa,
    total: subtotal + deliveryFeeFcfa,
  );
}
