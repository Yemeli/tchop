import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';
import '../menu/availability_broadcaster.dart';
import '../menu/menu_models.dart';
import '../menu/daypart.dart';
import 'cart.dart';
import 'order_models.dart';
import 'order_state_machine.dart';

/// Outbox op names for orders (see supabase/functions/sync/index.ts).
///
/// Kitchen / dispatch features MUST use these exact ops:
/// - `order/create`     — entity `order`, entity_id = client-generated order
///   UUID, payload = canonical `order/create` payload (see
///   [buildOrderCreatePayload]).
/// - `order/transition` — entity `order`, entity_id = order UUID, payload
///   `{order_id, to}` where `to` is the target status wire value.
/// - `order/void`       — entity `order`, entity_id = order UUID, payload
///   `{order_id, reason?}`. Secretary/manager/owner only; cancels from any
///   non-delivered state and audit-logs `order.void`.
abstract final class OrderOps {
  static const String create = 'order/create';
  static const String transition = 'order/transition';
  static const String orderVoid = 'order/void';
}

/// One menu item as rendered by the storefront: snapshot data merged with
/// the live 86 state.
class OrderMenuItem {
  const OrderMenuItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.priceFcfa,
    this.photoUrl,
    required this.available,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final String name;
  final String description;
  final int priceFcfa;
  final String? photoUrl;
  final bool available;
}

/// Published menu ready for the storefront: snapshot version + items.
class PublishedMenu {
  const PublishedMenu({
    required this.version,
    required this.items,
    required this.categories,
    this.dayparts = const [],
  });

  final int version;
  final List<OrderMenuItem> items;
  final List<MenuCategory> categories;

  /// Service windows from the snapshot (for the "service en cours" banner).
  final List<Daypart> dayparts;

  List<OrderMenuItem> itemsIn(String categoryId) =>
      items.where((i) => i.categoryId == categoryId).toList();
}

/// An order as shown in lists/detail: the local row merged with its
/// optimistic state (a pending `order/create` outbox entry means the server
/// hasn't confirmed it yet).
class OrderCard {
  const OrderCard({
    required this.id,
    required this.tenantId,
    required this.status,
    required this.lines,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.address,
    this.channel = OrderChannel.app,
    this.tableNumber,
    this.paymentMethod,
    this.paymentStatus = 'pending',
    this.clientMutationId,
    this.pendingSync = false,
  });

  final String id;
  final String tenantId;
  final OrderStatus status;
  final List<OrderLine> lines;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final String channel;
  final int? tableNumber;
  final String? paymentMethod;
  final String paymentStatus;
  final String? clientMutationId;

  /// True while an `order/create` (or `order/transition`) outbox entry for
  /// this order is still unsent — the UI shows "En attente de synchro".
  final bool pendingSync;

  String get channelLabelFr => OrderChannel.labelFr(channel);

  String get statusLabelFr => status.labelFr;

  factory OrderCard.fromLocal(
    Order row, {
    String? customerName,
    String? customerPhone,
    String? address,
    String channel = OrderChannel.app,
    int? tableNumber,
    bool pendingSync = false,
  }) {
    final lines = <OrderLine>[];
    try {
      final decoded = jsonDecode(row.linesJson);
      if (decoded is List) {
        for (final l in decoded) {
          if (l is Map<String, dynamic>) lines.add(OrderLine.fromJson(l));
        }
      }
    } catch (_) {
      // keep empty — a corrupt local row never breaks the list
    }
    return OrderCard(
      id: row.id,
      tenantId: row.tenantId,
      status: OrderStatusWire.fromWire(row.status),
      lines: lines,
      subtotal: row.subtotalCents,
      deliveryFee: row.deliveryFeeCents,
      total: row.totalCents,
      createdAt: row.createdAt,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      channel: channel,
      tableNumber: tableNumber,
      paymentMethod: row.paymentMethod,
      paymentStatus: row.paymentStatus,
      clientMutationId: row.clientMutationId,
      pendingSync: pendingSync,
    );
  }

  /// Builds the optimistic card for a not-yet-synced `order/create` outbox
  /// entry (the full customer/channel metadata lives in the payload).
  factory OrderCard.fromPendingCreate(OutboxEntry entry) {
    final payload =
        jsonDecode(entry.payloadJson) as Map<String, dynamic>? ?? {};
    final lines = <OrderLine>[];
    final rawLines = payload['lines'];
    if (rawLines is List) {
      for (final l in rawLines) {
        if (l is Map<String, dynamic>) lines.add(OrderLine.fromJson(l));
      }
    }
    final customer = payload['customer'];
    final customerMap = customer is Map<String, dynamic> ? customer : null;
    return OrderCard(
      id: entry.entityId,
      tenantId: entry.tenantId,
      status: OrderStatus.placed,
      lines: lines,
      subtotal: (payload['subtotal'] as num?)?.toInt() ?? 0,
      deliveryFee: (payload['delivery_fee'] as num?)?.toInt() ?? 0,
      total: (payload['total'] as num?)?.toInt() ?? 0,
      createdAt: entry.createdAt,
      customerName: customerMap?['name'] as String?,
      customerPhone: customerMap?['phone'] as String?,
      address: customerMap?['address'] as String?,
      channel: payload['channel'] as String? ?? OrderChannel.app,
      tableNumber: (payload['table_number'] as num?)?.toInt(),
      paymentMethod: payload['payment_method'] as String?,
      clientMutationId: entry.clientMutationId,
      pendingSync: true,
    );
  }
}

/// Emitted when the server rejects an `order/create` with a 409 conflict
/// (stale menu / unavailable item / price change). The optimistic order is
/// deleted locally (it never existed server-side); the UI should surface
/// [conflicts] and let the customer rebuild the cart.
class OrderCreateConflict {
  const OrderCreateConflict({
    required this.clientMutationId,
    required this.orderId,
    required this.conflicts,
    required this.lines,
  });

  final String clientMutationId;
  final String orderId;
  final List<OrderConflict> conflicts;
  final List<OrderLine> lines;
}

/// Persistence + sync for orders. Every mutation goes through the outbox —
/// never straight to the network.
///
/// Write path (fully offline-capable):
/// 1. optimistic local write into `orders` (status `placed`), so the order
///    appears instantly as "En attente de synchro";
/// 2. [SyncEngine.enqueue] with op `order/create` / `order/transition`;
/// 3. best-effort [SyncEngine.drain].
///
/// Conflict handling: the engine's [SyncEngine.onEdgeResponse] hook feeds
/// 409 validation conflicts here → the optimistic row is removed and
/// [createConflicts] emits the structured conflicts for the UI.
class OrderRepository {
  OrderRepository({
    required TchopDatabase db,
    required SyncEngine syncEngine,
    Uuid? uuids,
  })  : _db = db,
        _sync = syncEngine,
        _uuids = uuids ?? const Uuid() {
    // Single canonical instance is wired in bootstrap(); the hook is
    // last-writer-wins, so screens must reuse ServicesScope's repository
    // rather than constructing their own.
    _sync.onEdgeResponse = _handleEdgeResponse;
  }

  final TchopDatabase _db;
  final SyncEngine _sync;
  final Uuid _uuids;

  final _conflictController = StreamController<OrderCreateConflict>.broadcast();

  /// 409 validation conflicts from the server (see [OrderCreateConflict]).
  Stream<OrderCreateConflict> get createConflicts =>
      _conflictController.stream;

  // ------------------------------------------------------------------
  // Storefront reads
  // ------------------------------------------------------------------

  /// Latest published snapshot merged with the live 86 map, ready for the
  /// menu browser / POS item pad. Returns null when nothing is published.
  Future<PublishedMenu?> loadPublishedMenu(String tenantId) async {
    final snapshot = await _db.latestMenuSnapshot(tenantId);
    if (snapshot == null) return null;
    final decoded = jsonDecode(snapshot.itemsJson);
    final map =
        decoded is Map<String, dynamic> ? decoded : {'items': decoded};
    final doc = MenuDraftDoc.fromJson(map);
    final availability = {
      for (final a in await _db.availabilityForTenant(tenantId)) a.itemId: a.available,
    };
    final categoryNames = {for (final c in doc.categories) c.id: c.name};
    return PublishedMenu(
      version: snapshot.version,
      categories: doc.sortedCategories,
      dayparts: doc.dayparts,
      items: [
        for (final item in doc.items)
          OrderMenuItem(
            id: item.id,
            categoryId: item.categoryId,
            categoryName: categoryNames[item.categoryId] ?? '',
            name: item.name,
            description: item.description,
            priceFcfa: item.priceFcfa,
            photoUrl: item.photoUrl,
            available: availability[item.id] ?? true,
          ),
      ],
    );
  }

  /// The tenant's configured delivery fee (FCFA). Server value is
  /// authoritative at `order/create` time; this is indicative for the cart.
  /// Falls back to 0 offline.
  Future<int> deliveryFeeFor(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return 0;
    try {
      final row = await client
          .from('tenants')
          .select('delivery_fee_fcfa')
          .eq('id', tenantId)
          .maybeSingle();
      return (row?['delivery_fee_fcfa'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------------
  // Mutations
  // ------------------------------------------------------------------

  /// Creates an order: optimistic local insert + `order/create` outbox op
  /// with the canonical payload. Returns the client-generated order id and
  /// the idempotency key.
  ///
  /// [discountFcfa] is the POS counter discount — clamped to the subtotal
  /// (optimistic total never goes negative); the server recomputes and
  /// audit-logs it as `order.discount`.
  Future<({String orderId, String clientMutationId})> createOrder({
    required String tenantId,
    required String channel,
    required List<OrderLine> lines,
    required int menuVersion,
    required int deliveryFee,
    required String customerName,
    required String customerPhone,
    String? address,
    int? tableNumber,
    required String paymentMethod,
    String? clientMutationId,
    int discountFcfa = 0,
    String? discountReason,
  }) async {
    final key = clientMutationId ?? _uuids.v4();
    final orderId = _uuids.v4();
    final subtotal = lines.fold(0, (n, l) => n + l.lineTotal);
    final discount =
        discountFcfa.clamp(0, subtotal); // mirror of the server clamp
    final total = subtotal + deliveryFee - discount;
    final payload = buildOrderCreatePayload(
      menuVersion: menuVersion,
      lines: lines,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      total: total,
      channel: channel,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      tableNumber: tableNumber,
      paymentMethod: paymentMethod,
      clientMutationId: key,
      discountFcfa: discount,
      discountReason: discountReason,
    );
    // (1) optimistic local write — renders instantly, even offline.
    await _db.upsertOrder(
      OrdersCompanion.insert(
        id: orderId,
        tenantId: tenantId,
        status: const Value('placed'),
        menuVersion: Value(menuVersion),
        linesJson: Value(jsonEncode([for (final l in lines) l.toJson()])),
        subtotalCents: Value(subtotal),
        deliveryFeeCents: Value(deliveryFee),
        totalCents: Value(total),
        paymentMethod: Value(paymentMethod),
        clientMutationId: key,
      ),
    );
    // (2) durable outbox op — the Edge Function validates + inserts.
    await _sync.enqueue(
      tenantId: tenantId,
      op: OrderOps.create,
      entity: 'order',
      entityId: orderId,
      payload: payload,
      clientMutationId: key,
    );
    unawaited(_sync.drain());
    return (orderId: orderId, clientMutationId: key);
  }

  /// Moves an order forward (or cancels it). Guards the transition locally
  /// with [OrderFlow.transitionOrThrow] first — the server re-validates.
  Future<void> transitionOrder({
    required String tenantId,
    required String orderId,
    required OrderStatus to,
  }) async {
    final row = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (row == null) throw StateError('Commande introuvable sur cet appareil.');
    final from = OrderStatusWire.fromWire(row.status);
    if (from == to) return; // idempotent replay of our own tap
    OrderFlow.transitionOrThrow(from, to);
    // Optimistic local status flip.
    await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
        .write(OrdersCompanion(status: Value(to.wire)));
    await _sync.enqueue(
      tenantId: tenantId,
      op: OrderOps.transition,
      entity: 'order',
      entityId: orderId,
      payload: {'order_id': orderId, 'to': to.wire},
      clientMutationId: _uuids.v4(),
    );
    unawaited(_sync.drain());
  }

  /// Voids an order (Feature 8 — POS/manager): cancels from ANY
  /// non-delivered state and audit-logs `order.void` with the reason.
  ///
  /// Unlike [transitionOrder], this does not enforce the early-cancel-only
  /// rule — the server re-checks (delivered orders are rejected with 422).
  /// Optimistic local flip to `cancelled` so the UI reacts instantly.
  Future<void> voidOrder({
    required String tenantId,
    required String orderId,
    String? reason,
  }) async {
    final row = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (row == null) throw StateError('Commande introuvable sur cet appareil.');
    final from = OrderStatusWire.fromWire(row.status);
    if (from == OrderStatus.cancelled) return; // idempotent replay
    if (from == OrderStatus.delivered) {
      throw StateError(
          'Commande déjà livrée — faites un remboursement, pas une annulation.');
    }
    await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
        .write(const OrdersCompanion(status: Value('cancelled')));
    await _sync.enqueue(
      tenantId: tenantId,
      op: OrderOps.orderVoid,
      entity: 'order',
      entityId: orderId,
      payload: {
        'order_id': orderId,
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
      clientMutationId: _uuids.v4(),
    );
    unawaited(_sync.drain());
  }

  // ------------------------------------------------------------------
  // Reads (merged local + pending)
  // ------------------------------------------------------------------

  /// Live order cards for a tenant: synced local rows + optimistic pending
  /// `order/create` entries (shown with "En attente de synchro").
  ///
  /// NOTE: customer/channel metadata for synced rows comes from the
  /// server on the next pull (kitchen/dispatch feature); locally we only
  /// know what this device created (pending entries carry full metadata).
  Stream<List<OrderCard>> watchOrderCards(String tenantId) {
    late final StreamController<List<OrderCard>> controller;
    StreamSubscription? ordersSub;
    StreamSubscription? outboxSub;

    Future<void> emit() async {
      final rows = await _db.ordersForTenant(tenantId, limit: 200);
      final pending = await _pendingCreates(tenantId);
      final pendingIds = {for (final p in pending) p.entityId};
      final pendingKeys = {for (final p in pending) p.clientMutationId};
      final cards = <OrderCard>[
        // Pending creates first (newest first), then synced rows, skipping
        // rows already represented by a pending entry.
        for (final p in pending) OrderCard.fromPendingCreate(p),
        for (final r in rows)
          if (!pendingIds.contains(r.id) && !pendingKeys.contains(r.clientMutationId))
            OrderCard.fromLocal(r,
                pendingSync: await _hasPendingTransition(r.id)),
      ];
      if (!controller.isClosed) controller.add(cards);
    }

    controller = StreamController<List<OrderCard>>(
      onListen: () {
        ordersSub = (_db.select(_db.orders)
              ..where((o) => o.tenantId.equals(tenantId)))
            .watch()
            .listen((_) => emit());
        outboxSub = (_db.select(_db.outboxEntries)
              ..where((e) =>
                  e.tenantId.equals(tenantId) & e.deadLetter.equals(false)))
            .watch()
            .listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await ordersSub?.cancel();
        await outboxSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// One-shot version of [watchOrderCards].
  Future<List<OrderCard>> orderCards(String tenantId) async {
    final rows = await _db.ordersForTenant(tenantId, limit: 200);
    final pending = await _pendingCreates(tenantId);
    final pendingIds = {for (final p in pending) p.entityId};
    final pendingKeys = {for (final p in pending) p.clientMutationId};
    return [
      for (final p in pending) OrderCard.fromPendingCreate(p),
      for (final r in rows)
        if (!pendingIds.contains(r.id) &&
            !pendingKeys.contains(r.clientMutationId))
          OrderCard.fromLocal(r,
              pendingSync: await _hasPendingTransition(r.id)),
    ];
  }

  Future<List<OutboxEntry>> _pendingCreates(String tenantId) =>
      (_db.select(_db.outboxEntries)
            ..where((e) =>
                e.tenantId.equals(tenantId) &
                e.op.equals(OrderOps.create) &
                e.deadLetter.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .get();

  Future<bool> _hasPendingTransition(String orderId) async {
    final rows = await (_db.select(_db.outboxEntries)
          ..where((e) =>
              e.entityId.equals(orderId) &
              e.op.equals(OrderOps.transition) &
              e.deadLetter.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  // ------------------------------------------------------------------
  // Server conflict handling (via the sync engine's edge-response hook)
  // ------------------------------------------------------------------

  Future<void> _handleEdgeResponse(
      OutboxEntry entry, EdgeDeliveryReport report) async {
    if (entry.op != OrderOps.create) return;
    final body = report.body;
    if (body == null || body['duplicate'] == true) return;
    final rawConflicts = body['conflicts'];
    // 409 with a `conflicts` array = validation failure (NOT a duplicate):
    // the order never existed server-side. Remove the optimistic row and
    // surface the conflicts so the UI can offer to rebuild the cart.
    if (report.status == 409 && rawConflicts is List) {
      await (_db.delete(_db.orders)
            ..where((o) => o.clientMutationId.equals(entry.clientMutationId)))
          .go();
      final payload =
          jsonDecode(entry.payloadJson) as Map<String, dynamic>? ?? {};
      final lines = <OrderLine>[];
      final rawLines = payload['lines'];
      if (rawLines is List) {
        for (final l in rawLines) {
          if (l is Map<String, dynamic>) lines.add(OrderLine.fromJson(l));
        }
      }
      if (!_conflictController.isClosed) {
        _conflictController.add(OrderCreateConflict(
          clientMutationId: entry.clientMutationId,
          orderId: entry.entityId,
          conflicts: [
            for (final c in rawConflicts)
              if (c is Map<String, dynamic>) OrderConflict.fromJson(c),
          ],
          lines: lines,
        ));
      }
    }
  }

  // ------------------------------------------------------------------
  // Customer directory (stub)
  // ------------------------------------------------------------------

  /// Phone lookup for the POS: searches this device's pending `order/create`
  /// payloads for a matching customer phone and returns the last used name.
  ///
  /// TODO(customer-directory): replace with a server `customer/search` op
  /// (tenant-scoped customer directory with consent + retention policy).
  Future<({String name, String phone})?> lookupCustomerByPhone(
    String tenantId,
    String phone,
  ) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return null;
    final pending = await _pendingCreates(tenantId);
    for (final entry in pending) {
      try {
        final payload =
            jsonDecode(entry.payloadJson) as Map<String, dynamic>;
        final customer = payload['customer'];
        if (customer is Map<String, dynamic>) {
          final p = (customer['phone'] as String? ?? '')
              .replaceAll(RegExp(r'\D'), '');
          if (p.isNotEmpty && (p == digits || p.endsWith(digits) || digits.endsWith(p))) {
            final name = customer['name'] as String?;
            if (name != null && name.isNotEmpty) {
              return (name: name, phone: customer['phone'] as String);
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  void dispose() {
    _conflictController.close();
    // NOTE: the edge-response hook is intentionally left attached —
    // clearing it here could detach a newer repository's hook
    // (last-writer-wins by design; bootstrap wires a single instance).
  }
}

/// Binds an [OrderCart] to the 86 Realtime channel so items that go 86
/// while the cart is open are removed with the French "Épuisé" notice.
///
/// Channel contract (Feature 3 — do not rename):
/// `tenant:{tenant_id}:availability` / `availability_changed`.
class AvailabilityCartBinder {
  AvailabilityCartBinder({required this.cart, this.onNotice});

  final OrderCart cart;
  final void Function(String notice)? onNotice;

  RealtimeChannel? _channel;
  SupabaseClient? _client;

  /// Subscribes. No-op when the backend isn't configured (offline) — the
  /// outbox remains the source of truth.
  void attach(String tenantId) {
    final client = TchopSupabase.clientOrNull;
    if (client == null || _channel != null) return;
    _client = client;
    _channel = AvailabilityListener.subscribe(
      client: client,
      tenantId: tenantId,
      onEvent: (event) {
        if (cart.applyAvailabilityEvent(event)) {
          final notice = cart.consumeNotice();
          if (notice != null) onNotice?.call(notice);
        }
      },
    );
  }

  Future<void> detach() async {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    if (channel != null && client != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {
        // best-effort
      }
    }
  }
}
