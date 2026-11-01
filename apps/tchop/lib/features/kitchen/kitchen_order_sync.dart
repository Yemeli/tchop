import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/database/tchop_database.dart';
import '../orders/order_models.dart';
import '../orders/order_repository.dart';
import '../orders/order_state_machine.dart';
import 'ticket_alert_beep.dart';

/// A ticket as rendered on the kitchen display board.
///
/// Built from the local Drift `orders` row (which the [KitchenOrderSync]
/// keeps fresh via Realtime + the 60 s pull), merged with the pending
/// `order/transition` outbox state. The board renders entirely from these —
/// never from the network.
class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.tenantId,
    required this.status,
    required this.lines,
    required this.createdAt,
    this.channel = OrderChannel.app,
    this.customerName,
    this.customerPhone,
    this.tableNumber,
    this.totalCents = 0,
    this.pendingSync = false,
  });

  final String id;
  final String tenantId;
  final OrderStatus status;
  final List<OrderLine> lines;
  final DateTime createdAt;

  /// Wire value (`app|whatsapp|phone|walkin|qr_table`).
  final String channel;
  final String? customerName;
  final String? customerPhone;
  final int? tableNumber;
  final int totalCents;

  /// True while an `order/transition` outbox entry for this ticket is
  /// still unsent — the board shows the "En attente de synchro" badge.
  final bool pendingSync;

  /// Short human reference for the board ("#A3F9"). There is no server-side
  /// sequential order number, so this derives from the order UUID —
  /// stable per order, unique enough for a service.
  String get shortRef => KitchenTicketShortRef.of(id);

  /// Time since the order was placed, clamped at zero.
  Duration elapsed({DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(createdAt);
    return d.isNegative ? Duration.zero : d;
  }

  /// Compact channel badge label (French-first).
  String get channelBadgeFr {
    switch (channel) {
      case OrderChannel.app:
        return 'App';
      case OrderChannel.whatsapp:
        return 'WhatsApp';
      case OrderChannel.phone:
        return 'Tél.';
      case OrderChannel.walkin:
        return 'Comptoir';
      case OrderChannel.qrTable:
        return 'QR';
      default:
        return channel;
    }
  }

  /// One-line customer summary for the ticket card ("Note client" row).
  /// The server has no free-text note column, so this surfaces what exists:
  /// name + phone, and the table number for QR dine-in orders.
  String? get customerSummary {
    final parts = <String>[];
    if (customerName != null && customerName!.isNotEmpty) {
      parts.add(customerName!);
    }
    if (customerPhone != null && customerPhone!.isNotEmpty) {
      parts.add(customerPhone!);
    }
    if (tableNumber != null) parts.add('Table $tableNumber');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  int get totalQty => lines.fold(0, (n, l) => n + l.qty);
}

/// Emitted when a queued local transition loses to another device:
/// the server state made our `order/transition` illegal, so the op was
/// dropped and the server state adopted.
class KitchenTransitionConflict {
  const KitchenTransitionConflict({
    required this.orderId,
    required this.shortRef,
    required this.serverStatus,
    required this.droppedTarget,
  });

  final String orderId;
  final String shortRef;
  final OrderStatus serverStatus;
  final OrderStatus droppedTarget;

  String get messageFr =>
      'La commande $shortRef est passée à « ${serverStatus.labelFr} » sur un '
      'autre appareil — votre action a été annulée.';
}

/// Order fan-in for the kitchen display (Feature 5's explicit job).
///
/// Keeps the local Drift `orders` table fresh for one tenant:
/// - **push**: subscribes to Supabase Realtime `postgres_changes` on the
///   `orders` table (event `*`, schema `public`), filtered by
///   `tenant_id`; every change is reconciled into Drift. New KDS-status
///   inserts trigger [TicketAlertBeep.beep].
/// - **pull**: on start, on every app-foreground resume, and every 60 s,
///   fetches orders with status in (accepted, preparing, ready) created in
///   the last 12 h via PostgREST and reconciles them into Drift.
///
/// When the backend is unconfigured ([client] == null) the service is a
/// no-op and the board operates from the local cache only — still fully
/// usable (transitions queue in the outbox, 86 works, timers tick).
///
/// Every mutation still goes through [OrderRepository.transitionOrder]
/// (optimistic local flip + `order/transition` outbox op) — this service
/// only *reads* the server into the cache.
///
/// Conflict strategy (two kitchen tablets, same ticket):
/// the server is the source of truth, but a tablet's own not-yet-acked
/// `order/transition` outbox op is treated as newer intent — the pull /
/// Realtime echo must not clobber an optimistic flip. Reconciliation rules:
/// 1. server status == local status → adopt the server row (metadata
///    refresh; converges after our op is acked);
/// 2. pending transition op whose target == server status → adopt (the
///    server just applied it — idempotent replay converges);
/// 3. pending op whose target is no longer legal from the server status
///    (e.g. another tablet cancelled while we were offline) → drop the
///    doomed op, adopt the server state, emit [conflicts];
/// 4. otherwise → keep the optimistic local status, refresh everything
///    else (the op will apply when the outbox drains; the Edge Function
///    itself rejects illegal transitions with 422, which the pull then
///    resolves via rule 3).
class KitchenOrderSync {
  KitchenOrderSync({
    required TchopDatabase db,
    SupabaseClient? client,
  })  : _db = db,
        _client = client;

  final TchopDatabase _db;

  /// Null when the backend is unconfigured (offline mode).
  final SupabaseClient? _client;

  /// Order statuses shown on the board (== the three columns).
  static const List<String> kdsStatuses = ['accepted', 'preparing', 'ready'];

  static const Duration pullInterval = Duration(seconds: 60);
  static const Duration pullWindow = Duration(hours: 12);

  final _newTicketController = StreamController<String>.broadcast();
  final _conflictController =
      StreamController<KitchenTransitionConflict>.broadcast();

  /// Order ids of tickets that just arrived in a KDS status. The board
  /// uses this for the new-ticket flash (the beep fires inside the sync).
  Stream<String> get newTickets => _newTicketController.stream;

  /// Transitions that lost to another device (see rule 3 above).
  Stream<KitchenTransitionConflict> get conflicts =>
      _conflictController.stream;

  bool _started = false;
  bool _pulling = false;

  /// True until the first pull of the session completes — the priming pull
  /// must not beep for the whole backlog, only genuinely new arrivals do.
  bool _primed = false;
  String? _tenantId;
  RealtimeChannel? _channel;
  Timer? _timer;

  bool get isOnlineCapable => _client != null;

  /// Starts Realtime + the pull timer for [tenantId]. Idempotent.
  void start(String tenantId) {
    if (_started) return;
    _started = true;
    _tenantId = tenantId;
    _subscribe(tenantId);
    unawaited(refresh());
    _timer = Timer.periodic(pullInterval, (_) => unawaited(refresh()));
  }

  /// Manual / foreground-resume refresh. No-op when offline or mid-pull.
  Future<void> refresh() => _pull();

  Future<void> dispose() async {
    _timer?.cancel();
    final channel = _channel;
    final client = _client;
    _channel = null;
    if (channel != null && client != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {
        // best-effort
      }
    }
    await _newTicketController.close();
    await _conflictController.close();
    _started = false;
  }

  // ------------------------------------------------------------------
  // Board reads (Drift only)
  // ------------------------------------------------------------------

  /// Live tickets for the three board columns, oldest first.
  Stream<List<KitchenTicket>> watchTickets(String tenantId) {
    late final StreamController<List<KitchenTicket>> controller;
    StreamSubscription? ordersSub;
    StreamSubscription? outboxSub;

    Future<void> emit() async {
      final rows = await (_db.select(_db.orders)
            ..where((o) =>
                o.tenantId.equals(tenantId) &
                (o.status.equals('accepted') |
                    o.status.equals('preparing') |
                    o.status.equals('ready')))
            ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
          .get();
      final pendingIds = await _pendingTransitionIds(tenantId);
      final tickets = <KitchenTicket>[];
      for (final row in rows) {
        try {
          tickets.add(await _ticketFromRow(row, pendingIds.contains(row.id)));
        } catch (_) {
          // A corrupt local row never breaks the board — skip it.
        }
      }
      if (!controller.isClosed) controller.add(tickets);
    }

    controller = StreamController<List<KitchenTicket>>(
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

  Future<KitchenTicket> _ticketFromRow(Order row, bool pendingSync) async {
    final lines = <OrderLine>[];
    try {
      final decoded = jsonDecode(row.linesJson);
      if (decoded is List) {
        for (final l in decoded) {
          if (l is Map<String, dynamic>) lines.add(OrderLine.fromJson(l));
        }
      }
    } catch (_) {
      // a corrupt local row never breaks the board
    }
    var channel = row.channel;
    var customerName = row.customerName;
    var customerPhone = row.customerPhone;
    var tableNumber = row.tableNumber;
    // Rows created on this device by the POS (Feature 4) only learn the
    // channel/customer metadata on the next server round-trip; meanwhile
    // recover it from the pending `order/create` payload.
    if (channel == null) {
      final meta = await _pendingCreateMetadata(row.id);
      channel = meta.channel ?? channel;
      customerName = customerName ?? meta.customerName;
      customerPhone = customerPhone ?? meta.customerPhone;
      tableNumber = tableNumber ?? meta.tableNumber;
    }
    return KitchenTicket(
      id: row.id,
      tenantId: row.tenantId,
      status: OrderStatusWire.fromWire(row.status),
      lines: lines,
      createdAt: row.createdAt,
      channel: channel ?? OrderChannel.app,
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumber: tableNumber,
      totalCents: row.totalCents,
      pendingSync: pendingSync,
    );
  }

  Future<
      ({
        String? channel,
        String? customerName,
        String? customerPhone,
        int? tableNumber
      })> _pendingCreateMetadata(String orderId) async {
    const empty = (
      channel: null,
      customerName: null,
      customerPhone: null,
      tableNumber: null
    );
    final entries = await (_db.select(_db.outboxEntries)
          ..where((e) =>
              e.entityId.equals(orderId) &
              e.op.equals(OrderOps.create) &
              e.deadLetter.equals(false))
          ..limit(1))
        .get();
    if (entries.isEmpty) return empty;
    try {
      final payload =
          jsonDecode(entries.first.payloadJson) as Map<String, dynamic>;
      final customer = payload['customer'];
      final cmap = customer is Map<String, dynamic> ? customer : null;
      return (
        channel: payload['channel'] as String?,
        customerName: cmap?['name'] as String?,
        customerPhone: cmap?['phone'] as String?,
        tableNumber: (payload['table_number'] as num?)?.toInt(),
      );
    } catch (_) {
      return empty;
    }
  }

  Future<Set<String>> _pendingTransitionIds(String tenantId) async {
    final rows = await (_db.select(_db.outboxEntries)
          ..where((e) =>
              e.tenantId.equals(tenantId) &
              e.op.equals(OrderOps.transition) &
              e.deadLetter.equals(false)))
        .get();
    return {for (final r in rows) r.entityId};
  }

  // ------------------------------------------------------------------
  // Realtime push
  // ------------------------------------------------------------------

  void _subscribe(String tenantId) {
    final client = _client;
    if (client == null || _channel != null) return; // offline: pull/cache only
    _channel = client.channel('kds:orders:$tenantId');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'tenant_id',
        value: tenantId,
      ),
      callback: (PostgresChangePayload payload) {
        final record = payload.newRecord;
        if (record.isEmpty) return;
        // Belt & braces: the channel filter already scopes by tenant.
        if (record['tenant_id'] != _tenantId) return;
        unawaited(_reconcile(record).then((enteredKds) {
          // A "new ticket" is anything entering a board column — this
          // covers INSERTs straight into `accepted` AND the
          // placed→accepted UPDATE when the secretary accepts on the POS.
          if (enteredKds && _primed) {
            TicketAlertBeep.beep();
            if (!_newTicketController.isClosed) {
              _newTicketController.add(record['id'] as String? ?? '');
            }
          }
        }));
      },
    );
    _channel!.subscribe();
  }

  // ------------------------------------------------------------------
  // PostgREST pull
  // ------------------------------------------------------------------

  Future<void> _pull() async {
    final client = _client;
    final tenantId = _tenantId;
    if (client == null || tenantId == null || _pulling) return;
    _pulling = true;
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(pullWindow)
          .toIso8601String();
      final response = await client
          .from('orders')
          .select(
            'id, tenant_id, status, channel, customer_name, customer_phone, '
            'table_number, lines, menu_version, subtotal, delivery_fee, total, '
            'payment_method, payment_status, client_mutation_id, created_at',
          )
          .eq('tenant_id', tenantId)
          .inFilter('status', kdsStatuses)
          .gte('created_at', cutoff)
          .order('created_at', ascending: true)
          .limit(200);
      for (final row in response) {
        final enteredKds = await _reconcile(row);
        // The priming pull stays silent; later pulls announce genuinely
        // new arrivals (e.g. tickets placed while this tablet was
        // offline — Realtime never delivered them).
        if (enteredKds && _primed) {
          TicketAlertBeep.beep();
          if (!_newTicketController.isClosed) {
            _newTicketController.add(row['id'] as String? ?? '');
          }
        }
      }
    } catch (_) {
      // Best-effort fan-in: the board keeps rendering the local cache.
    } finally {
      _pulling = false;
      _primed = true;
    }
  }

  // ------------------------------------------------------------------
  // Reconciliation (the conflict strategy — see class docs)
  //
  // Returns true when the row newly entered a board column (absent before
  // or previously in a non-KDS status) — the caller beeps for those.
  // ------------------------------------------------------------------

  Future<bool> _reconcile(Map<String, dynamic> server) async {
    final id = server['id'] as String?;
    final serverStatusWire = server['status'] as String?;
    if (id == null || serverStatusWire == null) return false;
    late final OrderStatus serverStatus;
    try {
      serverStatus = OrderStatusWire.fromWire(serverStatusWire);
    } catch (_) {
      return false; // unknown status — never break the board on it
    }

    final local = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    final enteredKds = (local == null ||
            !kdsStatuses.contains(local.status)) &&
        kdsStatuses.contains(serverStatus.wire);
    if (local == null) {
      await _db.upsertOrder(_companionFromServer(server, serverStatus));
      return enteredKds;
    }

    final localStatus = OrderStatusWire.fromWire(local.status);
    if (localStatus == serverStatus) {
      await _db.upsertOrder(_companionFromServer(server, serverStatus));
      return enteredKds;
    }

    final pendingTarget = await _pendingTransitionTarget(id);
    if (pendingTarget == null) {
      // No local intent outstanding — another device moved the ticket.
      await _db.upsertOrder(_companionFromServer(server, serverStatus));
      return enteredKds;
    }
    if (serverStatus == pendingTarget) {
      // The server just applied our tap (Realtime echo / pull).
      await _db.upsertOrder(_companionFromServer(server, serverStatus));
      return enteredKds;
    }
    if (!OrderFlow.canTransition(serverStatus, pendingTarget)) {
      // CONFLICT: our queued transition is illegal from the server's
      // state — drop the doomed op, adopt the server state, notify.
      await _dropPendingTransitions(id);
      await _db.upsertOrder(_companionFromServer(server, serverStatus));
      if (!_conflictController.isClosed) {
        _conflictController.add(KitchenTransitionConflict(
          orderId: id,
          shortRef: KitchenTicketShortRef.of(id),
          serverStatus: serverStatus,
          droppedTarget: pendingTarget,
        ));
      }
      return enteredKds;
    }
    // Our tap is still ahead of the server copy (op not yet drained or the
    // echo hasn't arrived): keep the optimistic local status, refresh
    // everything else.
    await _db.upsertOrder(
        _companionFromServer(server, serverStatus, statusOverride: localStatus));
    return enteredKds;
  }

  /// Newest pending `order/transition` target for [orderId], or null.
  Future<OrderStatus?> _pendingTransitionTarget(String orderId) async {
    final rows = await (_db.select(_db.outboxEntries)
          ..where((e) =>
              e.entityId.equals(orderId) &
              e.op.equals(OrderOps.transition) &
              e.deadLetter.equals(false))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    try {
      final payload =
          jsonDecode(rows.first.payloadJson) as Map<String, dynamic>;
      final to = payload['to'] as String?;
      return to == null ? null : OrderStatusWire.fromWire(to);
    } catch (_) {
      return null;
    }
  }

  Future<void> _dropPendingTransitions(String orderId) async {
    await (_db.delete(_db.outboxEntries)
          ..where((e) =>
              e.entityId.equals(orderId) &
              e.op.equals(OrderOps.transition) &
              e.deadLetter.equals(false)))
        .go();
  }

  OrdersCompanion _companionFromServer(
    Map<String, dynamic> s,
    OrderStatus serverStatus, {
    OrderStatus? statusOverride,
  }) {
    final lines = s['lines'];
    return OrdersCompanion.insert(
      id: s['id'] as String,
      tenantId: s['tenant_id'] as String,
      status: Value((statusOverride ?? serverStatus).wire),
      paymentStatus: Value((s['payment_status'] as String?) ?? 'pending'),
      paymentMethod: Value(s['payment_method'] as String?),
      menuVersion: Value((s['menu_version'] as num?)?.toInt() ?? 1),
      linesJson: Value(lines == null ? '[]' : jsonEncode(lines)),
      subtotalCents: Value((s['subtotal'] as num?)?.toInt() ?? 0),
      deliveryFeeCents: Value((s['delivery_fee'] as num?)?.toInt() ?? 0),
      totalCents: Value((s['total'] as num?)?.toInt() ?? 0),
      clientMutationId:
          s['client_mutation_id'] as String? ?? 'server:${s['id']}',
      createdAt: Value(_parseTime(s['created_at'] as String?)),
      updatedAt: Value(DateTime.now()),
      channel: Value(s['channel'] as String?),
      customerName: Value(s['customer_name'] as String?),
      customerPhone: Value(s['customer_phone'] as String?),
      tableNumber: Value((s['table_number'] as num?)?.toInt()),
    );
  }

  DateTime _parseTime(String? iso) {
    if (iso == null) return DateTime.now();
    return DateTime.tryParse(iso)?.toLocal() ?? DateTime.now();
  }
}

/// Short board reference for an order id ("#A3F9") — shared by the ticket
/// model and the conflict notice.
abstract final class KitchenTicketShortRef {
  static String of(String orderId) {
    final hex = orderId.replaceAll('-', '');
    return '#${hex.substring(0, hex.length >= 4 ? 4 : hex.length).toUpperCase()}';
  }
}
