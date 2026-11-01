import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';
import '../orders/order_state_machine.dart';
import 'dispatch_models.dart';

/// A delivery joined with its order, as shown on the driver home and the
/// customer tracking screen. Everything comes from the local Drift cache
/// (+ a JSON sidecar for assign-time dropoff metadata — see below).
class DeliveryCard {
  const DeliveryCard({
    required this.deliveryId,
    required this.orderId,
    required this.tenantId,
    required this.driverId,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.pickedUpAt,
    this.deliveredAt,
    this.podPhotoUrl,
    this.orderStatus = OrderStatus.placed,
    this.orderTotal = 0,
    this.customerName,
    this.customerPhone,
  });

  final String deliveryId;
  final String orderId;
  final String tenantId;
  final String driverId;
  final String? dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? podPhotoUrl;
  final OrderStatus orderStatus;
  final int orderTotal;
  final String? customerName;
  final String? customerPhone;

  bool get isPickedUp => pickedUpAt != null;
  bool get isDelivered => deliveredAt != null;

  /// Driver-home section: "En attente" (assigned, not picked up),
  /// "En cours" (picked up, on the way), "Livrée".
  String get sectionLabelFr {
    if (isDelivered) return 'Livrée';
    if (isPickedUp) return 'En cours';
    return 'En attente';
  }
}

/// Persistence + sync for dispatch (Feature 6). Every mutation goes through
/// the outbox — never straight to the network.
///
/// Write path (fully offline-capable):
/// 1. optimistic local write into `deliveries`;
/// 2. [SyncEngine.enqueue] with op `delivery/assign` / `delivery/complete`;
/// 3. best-effort [SyncEngine.drain].
///
/// HONESTY NOTES
/// - The local `deliveries` Drift table has no dropoff columns and no
///   codegen can run in this environment, so assign-time dropoff
///   metadata is kept in a per-tenant JSON sidecar file under the app
///   support directory. A future Drift migration should promote it to
///   real columns.
/// - The driver roster is assembled from (a) drivers seen in cached
///   deliveries and (b) an online `memberships` query (role = driver),
///   cached back to a JSON sidecar. There is intentionally no display
///   name yet: auth.users is not readable and no staff-directory
///   endpoint exists — the sheet shows a shortened id until then
///   (TODO: server `staff_directory` view).
class DispatchRepository {
  DispatchRepository({
    required TchopDatabase db,
    required SyncEngine syncEngine,
    Uuid? uuids,
  })  : _db = db,
        _sync = syncEngine,
        _uuids = uuids ?? const Uuid();

  final TchopDatabase _db;
  final SyncEngine _sync;
  final Uuid _uuids;

  // ------------------------------------------------------------------
  // Driver assignment
  // ------------------------------------------------------------------

  /// Drivers of this tenant available for assignment.
  ///
  /// Merges cached delivery history with an opportunistic online refresh
  /// of `memberships` (role = driver). Never throws — offline simply
  /// returns the cached roster.
  Future<List<DriverCandidate>> driverCandidates(String tenantId) async {
    final cached = await _readRosterCache(tenantId);
    final byId = <String, DriverCandidate>{
      for (final c in cached) c.driverId: c,
    };

    // Drivers seen in this device's delivery cache (keeps the roster
    // useful even before any online refresh).
    try {
      final deliveries = await _db.deliveriesForTenant(tenantId);
      final active = <String, int>{};
      final lastSeen = <String, DateTime>{};
      for (final d in deliveries) {
        final id = d.driverId;
        if (id == null || id.isEmpty) continue;
        final done = d.deliveredAt != null;
        if (!done) active[id] = (active[id] ?? 0) + 1;
        final seen = d.deliveredAt ?? d.pickedUpAt ?? d.createdAt;
        final prev = lastSeen[id];
        if (prev == null || seen.isAfter(prev)) lastSeen[id] = seen;
        byId.putIfAbsent(
          id,
          () => DriverCandidate(driverId: id),
        );
      }
      byId.updateAll(
        (id, candidate) => DriverCandidate(
          driverId: id,
          displayName: candidate.displayName,
          activeDeliveries: active[id] ?? 0,
          lastActivityAt: lastSeen[id] ?? candidate.lastActivityAt,
        ),
      );
    } catch (_) {
      // cache read is best-effort
    }

    // Opportunistic online refresh (RLS may forbid listing other members —
    // in that case the cached roster stands; see the TODO above).
    final client = TchopSupabase.clientOrNull;
    if (client != null) {
      try {
        final rows = await client
            .from('memberships')
            .select('user_id')
            .eq('tenant_id', tenantId)
            .eq('role', 'driver');
        for (final row in (rows as List)) {
          final id = (row as Map)['user_id'] as String?;
          if (id != null && id.isNotEmpty) {
            byId.putIfAbsent(id, () => DriverCandidate(driverId: id));
          }
        }
        await _writeRosterCache(tenantId, byId.values.toList());
      } catch (_) {
        // offline or forbidden — cached roster stands
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) => a.labelFr().compareTo(b.labelFr()));
    return list;
  }

  /// Assigns [driverId] to a ready [orderId]: optimistic local delivery
  /// row + `delivery/assign` outbox op.
  ///
  /// The order status is NOT changed here — it stays `ready` until the
  /// driver marks it `picked_up` via `order/transition` (Feature 4).
  /// The caller must hold an owner/manager/secretary role; the server
  /// re-checks.
  Future<String> assignDriver({
    required String tenantId,
    required String orderId,
    required String driverId,
    double? dropoffLat,
    double? dropoffLng,
    String? dropoffAddress,
  }) async {
    final deliveryId = _uuids.v4();
    final payload = buildDeliveryAssignPayload(
      orderId: orderId,
      driverId: driverId,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      dropoffAddress: dropoffAddress,
    );
    await _db.upsertDelivery(
      DeliveriesCompanion.insert(
        id: deliveryId,
        tenantId: tenantId,
        orderId: orderId,
        driverId: Value(driverId),
      ),
    );
    await _writeDropoffCache(tenantId, deliveryId, {
      if (dropoffAddress != null) 'address': dropoffAddress,
      if (dropoffLat != null) 'lat': dropoffLat,
      if (dropoffLng != null) 'lng': dropoffLng,
    });
    await _sync.enqueue(
      tenantId: tenantId,
      op: DispatchOps.assign,
      entity: DispatchOps.entity,
      entityId: deliveryId,
      payload: payload,
      clientMutationId: _uuids.v4(),
    );
    unawaited(_sync.drain());
    return deliveryId;
  }

  // ------------------------------------------------------------------
  // Proof of delivery
  // ------------------------------------------------------------------

  /// Persists proof of delivery: local milestone update + the
  /// `delivery/complete` outbox op. The order itself must already have
  /// been transitioned to `delivered` via `order/transition` (Feature 4);
  /// the Edge Function additionally reconciles the milestones idempotently.
  Future<void> completeDelivery({
    required String tenantId,
    required String deliveryId,
    required String orderId,
    String? podPhotoUrl,
    String? podPhotoPendingPath,
    double? podLat,
    double? podLng,
    required String signatureSvg,
  }) async {
    final payload = buildDeliveryCompletePayload(
      deliveryId: deliveryId,
      orderId: orderId,
      podPhotoUrl: podPhotoUrl,
      podPhotoPendingPath: podPhotoPendingPath,
      podLat: podLat,
      podLng: podLng,
      signatureSvg: signatureSvg,
    );
    final now = DateTime.now();
    // Targeted update — keeps driver_id / picked_up_at intact
    // (insertOrReplace would wipe them).
    await _db.updateDelivery(
      deliveryId,
      DeliveriesCompanion(
        deliveredAt: Value(now),
        podPhotoUrl: Value(podPhotoUrl ?? podPhotoPendingPath),
      ),
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: DispatchOps.complete,
      entity: DispatchOps.entity,
      entityId: deliveryId,
      payload: payload,
      clientMutationId: _uuids.v4(),
    );
    unawaited(_sync.drain());
  }

  /// Marks the local delivery row picked up (optimistic mirror of the
  /// `order/transition` → `picked_up` op the driver enqueues alongside).
  Future<void> markPickedUpLocal({
    required String deliveryId,
  }) async {
    await _db.updateDelivery(
      deliveryId,
      DeliveriesCompanion(pickedUpAt: Value(DateTime.now())),
    );
  }

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  /// Live delivery cards for one driver (driver home). Joins cached
  /// deliveries with cached orders; dropoff metadata merged from the
  /// JSON sidecar.
  Stream<List<DeliveryCard>> watchDriverDeliveries(
      String tenantId, String driverId) {
    late final StreamController<List<DeliveryCard>> controller;
    StreamSubscription? sub;
    Future<void> emit() async {
      final cards = await driverDeliveries(tenantId, driverId);
      if (!controller.isClosed) controller.add(cards);
    }

    controller = StreamController<List<DeliveryCard>>(
      onListen: () {
        sub = (_db.select(_db.deliveries)
              ..where((d) => d.tenantId.equals(tenantId)))
            .watch()
            .listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<List<DeliveryCard>> driverDeliveries(
      String tenantId, String driverId) async {
    final deliveries = await (_db.select(_db.deliveries)
          ..where((d) =>
              d.tenantId.equals(tenantId) & d.driverId.equals(driverId))
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
        .get();
    final dropoffs = await _readDropoffCache(tenantId);
    final cards = <DeliveryCard>[];
    for (final d in deliveries) {
      final order = await (_db.select(_db.orders)
            ..where((o) => o.id.equals(d.orderId)))
          .getSingleOrNull();
      final drop = dropoffs[d.id];
      cards.add(DeliveryCard(
        deliveryId: d.id,
        orderId: d.orderId,
        tenantId: d.tenantId,
        driverId: driverId,
        dropoffAddress: drop?['address'] as String?,
        dropoffLat: (drop?['lat'] as num?)?.toDouble(),
        dropoffLng: (drop?['lng'] as num?)?.toDouble(),
        pickedUpAt: d.pickedUpAt,
        deliveredAt: d.deliveredAt,
        podPhotoUrl: d.podPhotoUrl,
        orderStatus: order == null
            ? OrderStatus.placed
            : OrderStatusWire.fromWire(order.status),
        orderTotal: order?.totalCents ?? 0,
      ));
    }
    return cards;
  }

  /// Delivery card for the customer tracking screen (any member of the
  /// tenant may watch their own order; RLS + the UI gate this).
  Future<DeliveryCard?> deliveryForOrder(String tenantId, String orderId) async {
    final rows = await (_db.select(_db.deliveries)
          ..where((d) =>
              d.tenantId.equals(tenantId) & d.orderId.equals(orderId))
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    final d = rows.first;
    final order = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
    final dropoffs = await _readDropoffCache(tenantId);
    final drop = dropoffs[d.id];
    return DeliveryCard(
      deliveryId: d.id,
      orderId: d.orderId,
      tenantId: d.tenantId,
      driverId: d.driverId ?? '',
      dropoffAddress: drop?['address'] as String?,
      dropoffLat: (drop?['lat'] as num?)?.toDouble(),
      dropoffLng: (drop?['lng'] as num?)?.toDouble(),
      pickedUpAt: d.pickedUpAt,
      deliveredAt: d.deliveredAt,
      podPhotoUrl: d.podPhotoUrl,
      orderStatus:
          order == null ? OrderStatus.placed : OrderStatusWire.fromWire(order.status),
      orderTotal: order?.totalCents ?? 0,
    );
  }

  // ------------------------------------------------------------------
  // JSON sidecars (temporary — see class docs)
  // ------------------------------------------------------------------

  Future<Directory> _supportDir() async =>
      getApplicationSupportDirectory();

  Future<List<DriverCandidate>> _readRosterCache(String tenantId) async {
    try {
      final f = File('${(await _supportDir()).path}/roster_$tenantId.json');
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      return [
        for (final e in raw)
          if (e is Map<String, dynamic>)
            DriverCandidate(
              driverId: e['driver_id'] as String? ?? '',
              displayName: e['display_name'] as String?,
              activeDeliveries:
                  (e['active_deliveries'] as num?)?.toInt() ?? 0,
              lastActivityAt: e['last_activity_at'] == null
                  ? null
                  : DateTime.tryParse(e['last_activity_at'] as String),
            ),
      ].where((c) => c.driverId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeRosterCache(
      String tenantId, List<DriverCandidate> candidates) async {
    try {
      final f = File('${(await _supportDir()).path}/roster_$tenantId.json');
      await f.writeAsString(jsonEncode([
        for (final c in candidates)
          {
            'driver_id': c.driverId,
            'display_name': c.displayName,
            'active_deliveries': c.activeDeliveries,
            'last_activity_at': c.lastActivityAt?.toIso8601String(),
          },
      ]));
    } catch (_) {
      // cache is best-effort
    }
  }

  Future<Map<String, Map<String, Object?>>> _readDropoffCache(
      String tenantId) async {
    try {
      final f = File('${(await _supportDir()).path}/dropoffs_$tenantId.json');
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return {};
      return {
        for (final e in (raw as Map).entries)
          if (e.value is Map) e.key: Map<String, Object?>.from(
              e.value.map((k, v) => MapEntry(k.toString(), v))),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeDropoffCache(String tenantId, String deliveryId,
      Map<String, Object?> drop) async {
    if (drop.isEmpty) return;
    try {
      final all = await _readDropoffCache(tenantId);
      all[deliveryId] = drop;
      final f = File('${(await _supportDir()).path}/dropoffs_$tenantId.json');
      await f.writeAsString(jsonEncode(all));
    } catch (_) {
      // cache is best-effort
    }
  }

  /// Uploads a PoD photo to Supabase Storage.
  ///
  /// Returns the public URL on success, null when offline/misconfigured —
  /// the caller then enqueues the local path as `pod_photo_pending_path`
  /// (a background uploader retries these later; TODO).
  /// Bucket `deliveries` must exist (see README ops section).
  Future<String?> uploadPodPhoto({
    required String tenantId,
    required String deliveryId,
    required File photo,
  }) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return null;
    try {
      final path = 'deliveries/$tenantId/$deliveryId.jpg';
      await client.storage.from('deliveries').upload(
            path,
            photo,
            fileOptions: const FileOptions(upsert: true),
          );
      return client.storage.from('deliveries').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }
}
