import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';
import 'menu_repository.dart';

/// The 86 (sold-out) fast path: local write + outbox + Realtime broadcast.
///
/// `setAvailability` does three things, in order:
/// 1. **optimistic local write** — `item_availability` in Drift, so the UI
///    flips instantly even offline;
/// 2. **durable outbox op** `menu/set_availability` — replayed by the sync
///    engine, applied server-side by the `sync` Edge Function;
/// 3. **Realtime broadcast intent** — when Supabase is configured, a
///    broadcast message on the tenant channel so customer apps see the
///    change in ~1–2s without waiting for the outbox round-trip.
///
/// Realtime contract (for the orders/customer feature — DO NOT rename
/// without coordinating):
/// - channel: `tenant:{tenant_id}:availability`
/// - event:   `availability_changed`
/// - payload: `{tenant_id, item_id, available, at}` (`at` = ISO-8601 UTC).
class AvailabilityBroadcaster {
  AvailabilityBroadcaster({
    required TchopDatabase db,
    required SyncEngine syncEngine,
  })  : _db = db,
        _sync = syncEngine;

  final TchopDatabase _db;
  final SyncEngine _sync;

  static String channelName(String tenantId) => 'tenant:$tenantId:availability';
  static const String eventAvailabilityChanged = 'availability_changed';

  Future<void> setAvailability({
    required String tenantId,
    required String itemId,
    required bool available,
    String? requestedBy,
  }) async {
    // (a) optimistic local write
    await _db.setItemAvailability(
      tenantId: tenantId,
      itemId: itemId,
      available: available,
    );
    // (b) durable outbox op
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.setAvailability,
      entity: 'item_availability',
      entityId: itemId,
      payload: {
        'item_id': itemId,
        'available': available,
        'requested_by': requestedBy,
      },
    );
    // (c) Realtime broadcast intent (best-effort, never throws)
    _broadcast(tenantId: tenantId, itemId: itemId, available: available);
  }

  void _broadcast({
    required String tenantId,
    required String itemId,
    required bool available,
  }) {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return; // offline: the outbox carries the change.
    unawaited(
      Future(() async {
        final channel = client.channel(channelName(tenantId));
        channel.subscribe();
        await channel.sendBroadcastMessage(
          event: eventAvailabilityChanged,
          payload: {
            'tenant_id': tenantId,
            'item_id': itemId,
            'available': available,
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }).catchError((_) {
        // Broadcast is a latency optimization; the outbox is the source of
        // truth. Swallow so a Realtime hiccup never breaks the toggle.
      }),
    );
  }
}

/// One 86 change received over Realtime.
class AvailabilityEvent {
  const AvailabilityEvent({
    required this.tenantId,
    required this.itemId,
    required this.available,
    this.at,
  });

  final String tenantId;
  final String itemId;
  final bool available;
  final DateTime? at;

  factory AvailabilityEvent.fromBroadcast(Map<String, dynamic> payload) =>
      AvailabilityEvent(
        tenantId: payload['tenant_id'] as String? ?? '',
        itemId: payload['item_id'] as String? ?? '',
        available: payload['available'] as bool? ?? true,
        at: payload['at'] == null
            ? null
            : DateTime.tryParse(payload['at'] as String),
      );
}

/// CUSTOMER APP / ORDERS FEATURE — subscribe to 86 updates.
///
/// ```dart
/// final channel = AvailabilityListener.subscribe(
///   client: Supabase.instance.client,
///   tenantId: tenantId,
///   onEvent: (event) {
///     // event.itemId just flipped to event.available —
///     // refresh the menu item's "Épuisé" badge / disable add-to-cart.
///   },
/// );
/// // …and on dispose:
/// await client.removeChannel(channel);
/// ```
///
/// Channel: `tenant:{tenant_id}:availability`
/// Event:   `availability_changed`
/// Payload: `{tenant_id, item_id, available, at}`
abstract final class AvailabilityListener {
  static RealtimeChannel subscribe({
    required SupabaseClient client,
    required String tenantId,
    required void Function(AvailabilityEvent event) onEvent,
  }) {
    final channel =
        client.channel(AvailabilityBroadcaster.channelName(tenantId));
    channel.onBroadcast(
      event: AvailabilityBroadcaster.eventAvailabilityChanged,
      callback: (payload, {ref}) =>
          onEvent(AvailabilityEvent.fromBroadcast(payload)),
    );
    channel.subscribe();
    return channel;
  }
}
