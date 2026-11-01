/// Order domain models + the canonical `order/create` payload builder.
///
/// Pure Dart — no Flutter dependency.
///
/// CANONICAL ORDER PAYLOAD (client + Edge Function must use exactly this —
/// resolves the earlier inconsistency between features):
/// ```json
/// {
///   "op": "order/create",
///   "menu_version": 12,
///   "lines": [{"item_id": "uuid", "qty": 2, "unit_price": 4500}],
///   "subtotal": 9000,
///   "delivery_fee": 1000,
///   "total": 10000,
///   "channel": "app|whatsapp|phone|walkin|qr_table",
///   "customer": {"name": "Amina", "phone": "+237690000000"},
///   "payment_method": "mtn_momo",
///   "client_mutation_id": "uuid-v4"
/// }
/// ```
/// All money in FCFA minor units (integer), keys snake_case. The server
/// RECOMPUTES totals and ignores the client-sent amounts; the client sends
/// them so the optimistic UI renders instantly.
///
/// Transition op (outbox): `order/transition`, payload `{order_id, to}`.
library;

/// One order line. Wire keys are snake_case per the canonical payload.
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.qty,
    required this.unitPrice,
  });

  final String itemId;
  final int qty;

  /// Unit price in FCFA (minor units) as rendered from the menu snapshot.
  /// The server re-checks this against the snapshot price.
  final int unitPrice;

  int get lineTotal => qty * unitPrice;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        itemId: json['item_id'] as String,
        qty: (json['qty'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toInt(),
      );

  Map<String, Object?> toJson() => {
        'item_id': itemId,
        'qty': qty,
        'unit_price': unitPrice,
      };
}

/// Intake channels (matches the Postgres CHECK on `orders.channel`).
abstract final class OrderChannel {
  static const String app = 'app';
  static const String whatsapp = 'whatsapp';
  static const String phone = 'phone';
  static const String walkin = 'walkin';
  static const String qrTable = 'qr_table';

  static const List<String> all = [app, whatsapp, phone, walkin, qrTable];

  /// Channels taken at the counter / over the phone — staff-only on the
  /// server (`order/create` requires a workspace membership for these).
  static const List<String> staffOnly = [phone, walkin, whatsapp];

  static String labelFr(String channel) {
    switch (channel) {
      case app:
        return 'Application';
      case whatsapp:
        return 'WhatsApp';
      case phone:
        return 'Téléphone';
      case walkin:
        return 'Sur place';
      case qrTable:
        return 'QR Table';
      default:
        return channel;
    }
  }
}

/// Payment methods (matches the Postgres CHECK on `orders.payment_method`).
abstract final class OrderPaymentMethod {
  static const String mtnMomo = 'mtn_momo';
  static const String orangeMoney = 'orange_money';
  static const String wave = 'wave';
  static const String cash = 'cash';
  static const String card = 'card';

  static const List<String> all = [mtnMomo, orangeMoney, wave, cash, card];

  static String labelFr(String method) {
    switch (method) {
      case mtnMomo:
        return 'MTN MoMo';
      case orangeMoney:
        return 'Orange Money';
      case wave:
        return 'Wave';
      case cash:
        return 'Espèces';
      case card:
        return 'Carte bancaire';
      default:
        return method;
    }
  }
}

/// Reasons a server-side `order/create` validation can fail (the `reason`
/// field of each entry in the 409 `conflicts` array).
abstract final class OrderConflictReason {
  /// Client's menu_version != current published version.
  static const String staleMenu = 'stale_menu';

  /// Item missing from the snapshot, or 86'd (item_availability = false).
  static const String unavailable = 'unavailable';

  /// Client's unit_price != snapshot price.
  static const String priceChanged = 'price_changed';

  /// The restaurant has no published menu snapshot at all.
  static const String noMenuPublished = 'no_menu_published';

  /// qty <= 0 (defensive; the client never sends this).
  static const String invalidQty = 'invalid_qty';
}

/// One entry of the 409 `conflicts` array returned by `order/create`.
class OrderConflict {
  const OrderConflict({
    this.itemId,
    required this.reason,
    this.currentPrice,
    this.currentMenuVersion,
  });

  /// Null for menu-level conflicts (`stale_menu`, `no_menu_published`).
  final String? itemId;
  final String reason;

  /// Set when [reason] == `price_changed`: the live snapshot price (FCFA).
  final int? currentPrice;

  /// Set when [reason] == `stale_menu`: the current published version.
  final int? currentMenuVersion;

  factory OrderConflict.fromJson(Map<String, dynamic> json) => OrderConflict(
        itemId: json['item_id'] as String?,
        reason: json['reason'] as String? ?? '',
        currentPrice: (json['current_price'] as num?)?.toInt(),
        currentMenuVersion: (json['current_menu_version'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
        'item_id': itemId,
        'reason': reason,
        if (currentPrice != null) 'current_price': currentPrice,
        if (currentMenuVersion != null)
          'current_menu_version': currentMenuVersion,
      };

  /// French message for the customer, e.g. on the conflict sheet.
  String messageFr(String Function(String itemId)? itemNameOf) {
    final name = itemId == null ? null : (itemNameOf?.call(itemId!) ?? itemId);
    switch (reason) {
      case OrderConflictReason.staleMenu:
        return 'Le menu a changé depuis votre visite — vérifiez votre panier.';
      case OrderConflictReason.noMenuPublished:
        return 'Le restaurant n’a pas encore publié son menu.';
      case OrderConflictReason.unavailable:
        return '« $name » n’est plus disponible.';
      case OrderConflictReason.priceChanged:
        return 'Le prix de « $name » a changé'
            '${currentPrice == null ? '' : ' (${formatFcfa(currentPrice!)})'}.';
      case OrderConflictReason.invalidQty:
        return 'Quantité invalide pour « $name ».';
      default:
        return 'Article indisponible : $name.';
    }
  }
}

/// Builds the canonical `order/create` payload — the single place the shape
/// is constructed, so client and docs can never drift.
///
/// Throws [ArgumentError] on obviously invalid input (empty lines,
/// unknown channel/payment method); the server re-validates everything.
///
/// [discountFcfa] is the POS counter discount (staff channels only — the
/// Edge Function zeroes it for app/qr_table); the server clamps it to the
/// subtotal and audit-logs it as `order.discount`.
Map<String, Object?> buildOrderCreatePayload({
  required int menuVersion,
  required List<OrderLine> lines,
  required int subtotal,
  required int deliveryFee,
  required int total,
  required String channel,
  required String customerName,
  required String customerPhone,
  String? address,
  int? tableNumber,
  required String paymentMethod,
  required String clientMutationId,
  int discountFcfa = 0,
  String? discountReason,
}) {
  if (lines.isEmpty) throw ArgumentError('lines must not be empty');
  if (!OrderChannel.all.contains(channel)) {
    throw ArgumentError('unknown channel: $channel');
  }
  if (!OrderPaymentMethod.all.contains(paymentMethod)) {
    throw ArgumentError('unknown payment_method: $paymentMethod');
  }
  if (channel == OrderChannel.qrTable && tableNumber == null) {
    throw ArgumentError('qr_table orders require table_number');
  }
  if (discountFcfa < 0) throw ArgumentError('discountFcfa must be >= 0');
  if (discountFcfa > subtotal) {
    throw ArgumentError('discountFcfa must not exceed the subtotal');
  }
  return {
    'op': 'order/create',
    'menu_version': menuVersion,
    'lines': [for (final l in lines) l.toJson()],
    'subtotal': subtotal,
    'delivery_fee': deliveryFee,
    'total': total,
    'channel': channel,
    'customer': {
      'name': customerName,
      'phone': customerPhone,
      if (address != null && address.isNotEmpty) 'address': address,
    },
    if (tableNumber != null) 'table_number': tableNumber,
    'payment_method': paymentMethod,
    'client_mutation_id': clientMutationId,
    if (discountFcfa > 0) 'discount_fcfa': discountFcfa,
    if (discountFcfa > 0 &&
        discountReason != null &&
        discountReason.trim().isNotEmpty)
      'discount_reason': discountReason.trim(),
  };
}

/// Deep link for QR-table ordering: `tchop://order?tenant={slug}&table={n}`.
///
/// Printed on table stickers; scanning opens the customer app straight into
/// the menu with the table pre-selected.
///
/// TODO(camera): wire a real scanner (e.g. `mobile_scanner`) in the
/// customer flavor — on scan, feed the raw string to [QrTableLink.tryParse]
/// and route to the menu with [tenantSlug]/[tableNumber].
class QrTableLink {
  const QrTableLink({required this.tenantSlug, required this.tableNumber});

  final String tenantSlug;
  final int tableNumber;

  /// Builds the link printed on a table sticker.
  static String build({required String tenantSlug, required int tableNumber}) =>
      'tchop://order?tenant=${Uri.encodeComponent(tenantSlug)}'
      '&table=$tableNumber';

  /// Parses a scanned link. Returns null when the string is not a valid
  /// `tchop://order` link (wrong scheme/host, missing tenant, bad table).
  static QrTableLink? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'tchop') return null;
    if (uri.host != 'order') return null;
    final tenant = uri.queryParameters['tenant'];
    if (tenant == null || tenant.isEmpty) return null;
    final table = int.tryParse(uri.queryParameters['table'] ?? '');
    if (table == null || table <= 0) return null;
    return QrTableLink(tenantSlug: tenant, tableNumber: table);
  }
}

/// "4500" → "4 500 FCFA". Plain grouping — no intl locale needed.
String formatFcfa(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buf FCFA';
}
