import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/data/database/tchop_database.dart';
import 'package:tchop/data/sync/sync_engine.dart';

/// In-memory database — no filesystem, no platform channels.
TchopDatabase openTestDb() => TchopDatabase(NativeDatabase.memory());

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

SyncEngine testEngine(
  TchopDatabase db, {
  Future<bool> Function(OutboxEntry entry)? deliver,
  Stream<List<ConnectivityResult>>? connectivityStream,
}) =>
    SyncEngine(
      db: db,
      deliver: deliver,
      connectivityStream: connectivityStream ?? const Stream.empty(),
      // Pretend the backend is configured; transport is faked per test.
      backendConfigured: () => true,
    );

Future<String> enqueueOrder(
  SyncEngine engine, {
  String? clientMutationId,
  String entityId = 'order-1',
}) =>
    engine.enqueue(
      tenantId: 'tenant-1',
      op: 'create',
      entity: 'order',
      entityId: entityId,
      payload: {
        'total_cents': 2500,
        'lines': [
          {'item_id': 'ndole', 'qty': 1},
        ],
      },
      clientMutationId: clientMutationId,
    );

void main() {
  group('SyncEngine.enqueue', () {
    test('is idempotent on client_mutation_id (one row, same id)', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db);

      final first = await enqueueOrder(engine, clientMutationId: 'cmid-1');
      final second = await enqueueOrder(engine, clientMutationId: 'cmid-1');

      expect(second, first);
      expect(first, matches(_uuidV4)); // entry id is a UUID v4
      final rows = await db.pendingOutboxEntries(now: DateTime.now());
      expect(rows, hasLength(1));
      expect(rows.single.clientMutationId, 'cmid-1');
    });

    test('generates a UUID v4 client_mutation_id when omitted', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db);

      await enqueueOrder(engine);
      final rows = await db.pendingOutboxEntries(now: DateTime.now());
      expect(rows, hasLength(1));
      expect(rows.single.clientMutationId, matches(_uuidV4));
    });

    test('different keys create separate rows', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db);

      await enqueueOrder(engine, clientMutationId: 'a', entityId: 'o-a');
      await enqueueOrder(engine, clientMutationId: 'b', entityId: 'o-b');
      expect(await db.pendingOutboxEntries(now: DateTime.now()), hasLength(2));
    });
  });

  group('SyncEngine.drain', () {
    test('deletes entries that deliver successfully', () async {
      final db = openTestDb();
      addTearDown(db.close);
      var calls = 0;
      final engine = testEngine(db, deliver: (_) async {
        calls++;
        return true;
      });

      await enqueueOrder(engine);
      expect(await engine.pendingCount.first, 1);

      await engine.drain();

      expect(calls, 1);
      expect(await db.pendingOutboxEntries(now: DateTime.now()), isEmpty);
      expect(await engine.pendingCount.first, 0);
    });

    test('failed delivery increments attempts and schedules retry with backoff',
        () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db, deliver: (_) async => false);

      await enqueueOrder(engine);
      final before = DateTime.now();
      await engine.drain();

      // The entry is still there but gated behind next_retry_at…
      expect(await db.pendingOutboxEntries(now: before), isEmpty);

      final row = (await db.select(db.outboxEntries).get()).single;
      expect(row.attempts, 1);
      expect(row.nextRetryAt, isNotNull);
      final delay = row.nextRetryAt!.difference(before);
      // backoffForAttempt(0) == 2s, plus up to 999ms jitter. 250ms tolerance
      // for wall-clock granularity/skew between the `before` capture and the
      // retry timestamp computed inside drain().
      expect(delay >= const Duration(milliseconds: 1750), isTrue,
          reason: 'expected >= ~2s backoff, got $delay');
      expect(delay < const Duration(seconds: 4), isTrue,
          reason: 'expected < 4s (2s + jitter), got $delay');
      // …and becomes eligible again once the retry time passes.
      final eligible = await db.pendingOutboxEntries(
        now: before.add(const Duration(minutes: 10)),
      );
      expect(eligible, hasLength(1));
    });

    test('throwing transport is recorded as a failure, not a crash',
        () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db, deliver: (_) async {
        throw Exception('transport down');
      });

      await enqueueOrder(engine);
      await engine.drain(); // must not throw

      final row = (await db.select(db.outboxEntries).get()).single;
      expect(row.attempts, 1);
      expect(row.lastError, isNotNull);
    });

    test('stays idle when the backend is not configured', () async {
      final db = openTestDb();
      addTearDown(db.close);
      var calls = 0;
      final engine = SyncEngine(
        db: db,
        deliver: (_) async {
          calls++;
          return true;
        },
        connectivityStream: const Stream.empty(),
        backendConfigured: () => false, // no --dart-define keys
      );

      await enqueueOrder(engine);
      await engine.drain();

      expect(calls, 0); // nothing attempted
      expect(await engine.pendingCount.first, 1); // badge stays on
    });

    test('entries past maxAttempts become dead letters', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db, deliver: (_) async => false);

      await db.into(db.outboxEntries).insert(
            OutboxEntriesCompanion.insert(
              id: 'entry-doomed',
              tenantId: 'tenant-1',
              op: 'create',
              entity: 'order',
              entityId: 'o-doomed',
              payloadJson: '{}',
              clientMutationId: 'cmid-doomed',
              attempts: Value(SyncEngine.maxAttempts),
            ),
          );

      await engine.drain();

      final dead = await engine.deadLetters();
      expect(dead, hasLength(1));
      expect(dead.single.id, 'entry-doomed');
      // Dead letters are excluded from the pending badge…
      expect(await engine.pendingCount.first, 0);
      expect(await engine.deadLetterCount.first, 1);

      // …until a manager requeues them.
      await engine.requeueDeadLetter('entry-doomed');
      expect(await engine.deadLetterCount.first, 0);
      expect(
        await db.pendingOutboxEntries(now: DateTime.now().add(
          const Duration(minutes: 10),
        )),
        hasLength(1),
      );
    });
  });

  group('SyncEngine.backoffForAttempt', () {
    test('doubles from 2s and caps at 5 minutes', () {
      expect(SyncEngine.backoffForAttempt(0), const Duration(seconds: 2));
      expect(SyncEngine.backoffForAttempt(1), const Duration(seconds: 4));
      expect(SyncEngine.backoffForAttempt(2), const Duration(seconds: 8));
      expect(SyncEngine.backoffForAttempt(5), const Duration(seconds: 64));
      expect(SyncEngine.backoffForAttempt(7), const Duration(seconds: 256));
      expect(SyncEngine.backoffForAttempt(8), const Duration(minutes: 5));
      expect(SyncEngine.backoffForAttempt(100), const Duration(minutes: 5));
    });
  });

  group('SyncEngine.isDeliveredStatus', () {
    test('treats 2xx and 409 as delivered', () {
      expect(SyncEngine.isDeliveredStatus(200), isTrue);
      expect(SyncEngine.isDeliveredStatus(201), isTrue);
      expect(SyncEngine.isDeliveredStatus(204), isTrue);
      expect(SyncEngine.isDeliveredStatus(409), isTrue); // idempotent replay
      expect(SyncEngine.isDeliveredStatus(400), isFalse);
      expect(SyncEngine.isDeliveredStatus(401), isFalse);
      expect(SyncEngine.isDeliveredStatus(500), isFalse);
    });
  });

  group('SyncEngine connectivity', () {
    test('drains when connectivity returns', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);
      var delivered = 0;
      final engine = SyncEngine(
        db: db,
        deliver: (_) async {
          delivered++;
          return true;
        },
        connectivityStream: connectivity.stream,
        backendConfigured: () => true,
        retryCheckInterval: const Duration(hours: 1), // no timer interference
      );
      addTearDown(engine.dispose);

      await enqueueOrder(engine);
      engine.start(); // best-effort immediate drain
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delivered, 1);

      await enqueueOrder(engine, entityId: 'order-2');
      connectivity.add([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delivered, 1); // offline: no attempt

      connectivity.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delivered, 2); // back online: drained
      expect(await engine.pendingCount.first, 0);
    });
  });

  group('SyncEngine.pendingCount', () {
    test('is a broadcast stream that tracks the outbox', () async {
      final db = openTestDb();
      addTearDown(db.close);
      final engine = testEngine(db, deliver: (_) async => true);

      final seen = <int>[];
      final sub = engine.pendingCount.listen(seen.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await enqueueOrder(engine);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.drain();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(seen, contains(0)); // initial
      expect(seen, contains(1)); // after enqueue
      expect(seen.last, 0); // after drain
    });
  });
}
