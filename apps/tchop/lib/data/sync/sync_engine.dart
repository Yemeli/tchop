import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/tchop_database.dart';
import '../supabase_client.dart';
import 'sync_envelope.dart';

/// Report of one Edge Function delivery attempt, handed to
/// [SyncEngine.onEdgeResponse] after each try.
class EdgeDeliveryReport {
  const EdgeDeliveryReport({required this.status, this.body});

  /// HTTP status of the attempt (2xx applied, 409 duplicate/conflict, …).
  final int status;

  /// Decoded JSON body when the function returned one (e.g. the 409
  /// `conflicts` array from `order/create` validation), null otherwise.
  final Map<String, dynamic>? body;
}

/// Offline-first sync engine: durable outbox + idempotent replay.
///
/// Write path (works with zero connectivity):
///   1. mutate the local Drift tables (optimistic UI renders instantly),
///   2. [enqueue] the same intent into `outbox_entries` with a UUID
///      idempotency key,
///   3. [start] wires a connectivity listener + periodic retry timer so
///      [drain] replays entries oldest-first whenever we're back online.
///
/// Retry policy: exponential backoff — 2s, 4s, 8s … capped at 5 minutes —
/// persisted as `next_retry_at` so retries survive app restarts. After
/// [maxAttempts] failures an entry is parked as a dead letter for manual
/// review in the manager dashboard ([deadLetters]/[requeueDeadLetter]).
///
/// Degraded mode: when Supabase isn't configured (no `--dart-define` keys),
/// [drain] is a no-op — mutations accumulate locally and the pending-count
/// stream keeps driving the "pending sync" badges.
class SyncEngine {
  SyncEngine({
    required TchopDatabase db,
    Future<bool> Function(OutboxEntry entry)? deliver,
    Stream<List<ConnectivityResult>>? connectivityStream,
    bool Function()? backendConfigured,
    this.retryCheckInterval = const Duration(seconds: 30),
  })  : _db = db,
        _deliverOverride = deliver,
        _connectivityStream = connectivityStream,
        _backendConfigured = backendConfigured ?? (() => TchopSupabase.isConfigured);

  final TchopDatabase _db;
  final Future<bool> Function(OutboxEntry entry)? _deliverOverride;
  final Stream<List<ConnectivityResult>>? _connectivityStream;
  final bool Function() _backendConfigured;
  final Duration retryCheckInterval;

  /// Optional hook invoked with the Edge Function's HTTP status + decoded
  /// body after every delivery attempt (success, duplicate, conflict or
  /// failure). Null by default — retry/drop semantics are unchanged.
  ///
  /// Used by the orders feature to surface 409 validation conflicts
  /// (`order/create`) to the UI. Never throws into [drain].
  FutureOr<void> Function(OutboxEntry entry, EdgeDeliveryReport report)?
      onEdgeResponse;

  static const _uuid = Uuid();

  /// Backoff: base 2s, doubling, capped at 5 minutes, then dead-lettered.
  static const int maxAttempts = 10;
  static const Duration baseBackoff = Duration(seconds: 2);
  static const Duration maxBackoff = Duration(minutes: 5);

  /// Pure backoff math (no jitter) — deterministic, unit-tested.
  /// attempt 0 → 2s, 1 → 4s, 2 → 8s … capped at 5 minutes.
  static Duration backoffForAttempt(int attempt) {
    // 2s * 2^8 = 512s already exceeds the 5-minute cap, so any attempt >= 8
    // returns maxBackoff directly. This also avoids 64-bit overflow of
    // `1 << attempt` for large attempt counts (which would wrap to 0).
    if (attempt >= 8) return maxBackoff;
    final shifted = baseBackoff * (1 << attempt);
    return shifted <= maxBackoff ? shifted : maxBackoff;
  }

  /// 2xx = applied; 409 = already applied on the server (idempotent replay)
  /// → safe to drop locally. Anything else → retry later.
  static bool isDeliveredStatus(int status) =>
      (status >= 200 && status < 300) || status == 409;

  bool _started = false;
  bool _draining = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;

  /// Mutations still waiting for the server (excludes dead letters).
  /// Broadcast stream — drives the "pending sync" badge in UI.
  late final Stream<int> pendingCount = _db.watchOutboxCount();

  /// Dead-lettered mutations awaiting manual review. Broadcast stream.
  late final Stream<int> deadLetterCount = _db.watchDeadLetterCount();

  /// Last-known connectivity state (true = online), broadcast.
  /// Driven by the same source as [start]'s connectivity listener, so the
  /// kitchen ticket board can show its "Hors ligne" banner from the sync
  /// engine's own state instead of wiring a second listener.
  late final Stream<bool> online =
      (_connectivityStream ?? Connectivity().onConnectivityChanged)
          .map((results) =>
              results.any((r) => r != ConnectivityResult.none))
          .asBroadcastStream();

  /// Records an intent to sync. Idempotent on [clientMutationId]: enqueueing
  /// twice with the same key stores exactly one row and returns the same
  /// entry id. Returns the outbox entry id (= `Idempotency-Key` header).
  Future<String> enqueue({
    required String tenantId,
    required String op,
    required String entity,
    required String entityId,
    required Map<String, Object?> payload,
    String? clientMutationId,
  }) async {
    final key = clientMutationId ?? _uuid.v4();
    final existing = await _db.outboxEntryByClientMutationId(key);
    if (existing != null) return existing.id;

    final id = _uuid.v4();
    await _db.into(_db.outboxEntries).insert(
          OutboxEntriesCompanion.insert(
            id: id,
            tenantId: tenantId,
            op: op,
            entity: entity,
            entityId: entityId,
            payloadJson: jsonEncode(payload),
            clientMutationId: key,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // Another writer may have won the race; return the canonical row.
    final row = await _db.outboxEntryByClientMutationId(key);
    return row?.id ?? id;
  }

  /// Replays pending entries oldest-first. Safe to call on every reconnect;
  /// already-acked entries are deleted, failures reschedule via
  /// `next_retry_at`, and exhausted entries become dead letters.
  Future<void> drain() async {
    if (_draining) return;
    // Degraded mode: no backend configured → stay idle, keep badges.
    if (!_backendConfigured()) return;
    _draining = true;
    try {
      final pending = await _db.pendingOutboxEntries(now: DateTime.now());
      for (final entry in pending) {
        if (entry.attempts >= maxAttempts) {
          await _db.markOutboxDeadLetter(
            entry.id,
            'Abandonné après $maxAttempts tentatives',
          );
          continue;
        }
        String? error;
        bool delivered;
        try {
          delivered = await (_deliverOverride ?? _defaultDeliver)(entry);
        } catch (e) {
          delivered = false;
          error = e.toString();
        }
        if (delivered) {
          await _db.deleteOutboxEntry(entry.id);
        } else {
          await _db.recordOutboxFailure(
            id: entry.id,
            attempts: entry.attempts + 1,
            nextRetryAt: _retryAt(entry.attempts),
            lastError: error,
          );
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Starts the connectivity listener + periodic retry timer.
  /// Idempotent — safe to call once per engine lifetime.
  void start() {
    if (_started) return;
    _started = true;
    _connectivitySub =
        (_connectivityStream ?? Connectivity().onConnectivityChanged)
            .listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(drain());
    });
    _retryTimer = Timer.periodic(
      retryCheckInterval,
      (_) => unawaited(drain()),
    );
    // Best-effort immediate attempt (no-op when offline/unconfigured).
    unawaited(drain());
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _connectivitySub = null;
    _retryTimer = null;
    _started = false;
  }

  /// Dead-lettered entries for the manager review queue.
  Future<List<OutboxEntry>> deadLetters() => _db.deadLetters();

  /// Puts a dead letter back into the retry loop (attempts reset).
  Future<void> requeueDeadLetter(String id) => _db.requeueDeadLetter(id);

  /// POSTs the envelope to the `sync` Edge Function.
  /// Returns true only when the server confirms the write (2xx) or reports
  /// it was already applied (409 — idempotent replay).
  Future<bool> _defaultDeliver(OutboxEntry entry) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return false;
    final envelope = SyncEnvelope.fromOutbox(entry);
    try {
      final response = await client.functions.invoke(
        'sync',
        body: envelope.toJson(),
        headers: {'Idempotency-Key': entry.id},
      );
      await _reportEdgeResponse(
        entry,
        EdgeDeliveryReport(
          status: response.status,
          body: _asBodyMap(response.data),
        ),
      );
      return isDeliveredStatus(response.status);
    } on FunctionException catch (e) {
      // 409: the server already applied this client_mutation_id — or, for
      // order/create, rejected it with a validation `conflicts` array
      // (the hook lets the orders feature tell them apart via the body).
      // The status field was renamed across supabase major versions
      // (v2 `status` → v3 `statusCode` on FunctionsApiException); read it
      // dynamically so the engine compiles against either.
      final status = _edgeStatus(e);
      await _reportEdgeResponse(
        entry,
        EdgeDeliveryReport(status: status, body: _exceptionBody(e)),
      );
      return isDeliveredStatus(status);
    }
  }

  /// Invokes [onEdgeResponse] when set. Never lets a hook failure break
  /// the drain loop.
  Future<void> _reportEdgeResponse(
    OutboxEntry entry,
    EdgeDeliveryReport report,
  ) async {
    final hook = onEdgeResponse;
    if (hook == null) return;
    try {
      await hook(entry, report);
    } catch (_) {
      // A reporting hook must never break sync.
    }
  }

  static Map<String, dynamic>? _asBodyMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Best-effort extraction of the error response body from a
  /// [FunctionException] (supabase-js surfaces it on `details`).
  static Map<String, dynamic>? _exceptionBody(FunctionException e) {
    try {
      final dynamic error = e;
      return _asBodyMap(error.details);
    } catch (_) {
      return null;
    }
  }

  static int _edgeStatus(FunctionException e) {
    try {
      final dynamic error = e;
      final value = error.statusCode ?? error.status;
      if (value is int) return value;
    } catch (_) {
      // fall through to 500 below
    }
    return 500;
  }

  DateTime _retryAt(int attempt) {
    final jitter = Random().nextInt(1000);
    return DateTime.now().add(
      backoffForAttempt(attempt) + Duration(milliseconds: jitter),
    );
  }
}
