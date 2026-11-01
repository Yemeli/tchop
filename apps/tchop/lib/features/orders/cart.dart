import 'package:flutter/foundation.dart';

import '../menu/availability_broadcaster.dart';
import 'order_models.dart';

/// One line in the customer's cart.
class CartLine {
  const CartLine({
    required this.itemId,
    required this.name,
    required this.unitPriceFcfa,
    required this.qty,
  });

  final String itemId;
  final String name;
  final int unitPriceFcfa;
  final int qty;

  int get lineTotal => qty * unitPriceFcfa;

  CartLine withQty(int qty) => CartLine(
        itemId: itemId,
        name: name,
        unitPriceFcfa: unitPriceFcfa,
        qty: qty,
      );
}

/// The customer cart. Carries the [menuVersion] of the snapshot it was
/// rendered from — the server rejects the order when the menu has been
/// republished since (stale_menu conflict).
///
/// Availability-aware: feed 86 events via [applyAvailabilityEvent] (wired by
/// [AvailabilityCartBinder] in order_repository.dart). An item that goes 86
/// while the cart is open is removed and [notice] carries the French message
/// "Épuisé — retiré du panier : {name}".
class OrderCart extends ChangeNotifier {
  OrderCart({required this.tenantId});

  final String tenantId;

  /// Snapshot version the menu was rendered from (set on first add).
  int? menuVersion;

  int deliveryFeeFcfa = 0;

  final Map<String, CartLine> _lines = {};

  /// Last user-facing notice (86 removal, …). Cleared on [consumeNotice].
  String? notice;

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  int get itemCount => _lines.values.fold(0, (n, l) => n + l.qty);

  bool get isEmpty => _lines.isEmpty;

  int get subtotal => _lines.values.fold(0, (n, l) => n + l.lineTotal);

  int get total => subtotal + deliveryFeeFcfa;

  int qtyOf(String itemId) => _lines[itemId]?.qty ?? 0;

  /// Adds one unit (or sets the snapshot version on first add).
  void addItem({
    required String itemId,
    required String name,
    required int unitPriceFcfa,
    required int menuVersion,
  }) {
    // A cart is bound to one snapshot; starting a fresh cart on a newer
    // menu keeps `menu_version` honest for the server check.
    if (_lines.isEmpty) this.menuVersion = menuVersion;
    final existing = _lines[itemId];
    _lines[itemId] = existing == null
        ? CartLine(
            itemId: itemId, name: name, unitPriceFcfa: unitPriceFcfa, qty: 1)
        : existing.withQty(existing.qty + 1);
    notice = null;
    notifyListeners();
  }

  void setQty(String itemId, int qty) {
    if (qty <= 0) {
      _lines.remove(itemId);
    } else {
      final existing = _lines[itemId];
      if (existing != null) _lines[itemId] = existing.withQty(qty);
    }
    notifyListeners();
  }

  void removeItem(String itemId) {
    _lines.remove(itemId);
    notifyListeners();
  }

  void setDeliveryFee(int fee) {
    deliveryFeeFcfa = fee;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    menuVersion = null;
    notice = null;
    notifyListeners();
  }

  /// Applies one 86 broadcast event. Returns true when a cart line was
  /// removed because the item just went out of stock.
  bool applyAvailabilityEvent(AvailabilityEvent event) {
    if (event.available) return false;
    final removed = _lines.remove(event.itemId);
    if (removed == null) return false;
    notice = 'Épuisé — retiré du panier : ${removed.name}';
    notifyListeners();
    return true;
  }

  /// Reconciles the whole cart against a fresh availability map
  /// (item_id → available), e.g. after reopening the app.
  List<String> reconcileAvailability(Map<String, bool> availableByItem) {
    final removedNames = <String>[];
    for (final entry in availableByItem.entries) {
      if (!entry.value) {
        final removed = _lines.remove(entry.key);
        if (removed != null) removedNames.add(removed.name);
      }
    }
    if (removedNames.isNotEmpty) {
      notice =
          'Épuisé — retiré du panier : ${removedNames.join(', ')}';
      notifyListeners();
    }
    return removedNames;
  }

  String? consumeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  /// Lines in the canonical `order/create` shape.
  List<OrderLine> toOrderLines() => [
        for (final l in _lines.values)
          OrderLine(itemId: l.itemId, qty: l.qty, unitPrice: l.unitPriceFcfa),
      ];
}
