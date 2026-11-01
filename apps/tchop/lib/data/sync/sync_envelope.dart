import 'dart:convert';

import '../database/tchop_database.dart';

/// The mutation envelope POSTed to the Supabase Edge Function `/sync`.
///
/// Server contract (see supabase/functions/sync/index.ts):
/// - Header `Idempotency-Key: <outbox entry id>` (UUID v4, per attempt batch).
/// - Body: this envelope as JSON.
/// - The server applies the mutation keyed on `client_mutation_id`
///   (`INSERT … ON CONFLICT (client_mutation_id) DO NOTHING`) and answers:
///   - `2xx` — applied now,
///   - `409` — already applied earlier (safe to drop locally),
///   - anything else — not applied, retry with backoff.
class SyncEnvelope {
  const SyncEnvelope({
    required this.clientMutationId,
    required this.tenantId,
    required this.op,
    required this.entity,
    required this.entityId,
    required this.payload,
  });

  /// UUID v4 shared by client + server for idempotent replay.
  final String clientMutationId;

  final String tenantId;

  /// One of: `create` | `update` | `delete` | `transition`.
  final String op;

  /// One of: `order` | `menu_snapshot` | `item_availability` | `delivery` |
  /// `payment`.
  final String entity;

  final String entityId;

  /// Entity-specific fields (e.g. order lines, the new status).
  final Map<String, dynamic> payload;

  factory SyncEnvelope.fromOutbox(OutboxEntry entry) => SyncEnvelope(
        clientMutationId: entry.clientMutationId,
        tenantId: entry.tenantId,
        op: entry.op,
        entity: entry.entity,
        entityId: entry.entityId,
        payload: jsonDecode(entry.payloadJson) as Map<String, dynamic>,
      );

  Map<String, dynamic> toJson() => {
        'client_mutation_id': clientMutationId,
        'tenant_id': tenantId,
        'op': op,
        'entity': entity,
        'entity_id': entityId,
        'payload': payload,
      };
}
