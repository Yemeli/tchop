import 'package:drift/drift.dart';

part 'tchop_database.g.dart';

// TODO(codegen): this file's part file is hand-written (no Flutter SDK on
// this VM). Regenerate for real with:
//   cd apps/tchop && dart run build_runner build --delete-conflicting-outputs

/// Local SQLite schema (via Drift). This database is the source of truth on
/// device; the [SyncEngine] replicates mutations to the backend.
///
/// Multi-tenancy: every tenant-scoped table carries `tenant_id`, mirroring
/// the server's Row-Level-Security model (see
/// supabase/migrations/20260927_init.sql).
class Tenants extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Cached brand JSON (see TenantBrand.toJson) for offline white-labeling.
  TextColumn get brandJson =>
      text().named('brand_json').withDefault(const Constant('{}'))();

  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Immutable, versioned menu snapshots. Publishing = insert new row.
/// Clients render the snapshot version they fetched and send it back at
/// checkout for stale-version rejection (server-side).
class MenuSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().named('tenant_id')();
  IntColumn get version => integer()();
  TextColumn get itemsJson =>
      text().named('items_json').withDefault(const Constant('[]'))();
  DateTimeColumn get publishedAt =>
      dateTime().named('published_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local copy of the editable menu draft (mirrors server `menu_drafts`).
///
/// One JSON document per tenant: categories + items + dayparts + the
/// approvals inbox. Edits write here instantly (offline-first) and are
/// replicated with the debounced `menu/draft_save` outbox op. Publishing
/// reads this document and freezes it into a new `menu_snapshots` row.
class MenuDrafts extends Table {
  TextColumn get tenantId => text().named('tenant_id')();
  TextColumn get docJson =>
      text().named('doc_json').withDefault(const Constant('{}'))();
  TextColumn get updatedBy => text().named('updated_by').nullable()();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {tenantId};
}

/// Fast-path item availability (the "86" / sold-out toggle), separate from
/// menu publishing so it propagates in seconds, not minutes.
class ItemAvailabilities extends Table {
  TextColumn get tenantId => text().named('tenant_id')();
  TextColumn get itemId => text().named('item_id')();
  BoolColumn get available =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {tenantId, itemId};
}

/// Orders use an append-only status state machine:
/// placed → accepted → preparing → ready → picked_up → delivered.
/// The server rejects backward transitions, which doubles as the conflict
/// resolution policy for offline retries.
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().named('tenant_id')();
  TextColumn get status => text().withDefault(const Constant('placed'))();
  TextColumn get paymentStatus =>
      text().named('payment_status').withDefault(const Constant('pending'))();
  TextColumn get paymentMethod =>
      text().named('payment_method').nullable()();
  IntColumn get menuVersion =>
      integer().named('menu_version').withDefault(const Constant(1))();
  TextColumn get linesJson =>
      text().named('lines_json').withDefault(const Constant('[]'))();
  IntColumn get subtotalCents =>
      integer().named('subtotal_cents').withDefault(const Constant(0))();
  IntColumn get deliveryFeeCents =>
      integer().named('delivery_fee_cents').withDefault(const Constant(0))();
  IntColumn get totalCents =>
      integer().named('total_cents').withDefault(const Constant(0))();

  /// Client-generated UUID; the server upserts on it so retried submissions
  /// never create duplicate orders.
  TextColumn get clientMutationId => text().named('client_mutation_id')();

  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  // --- Kitchen ticket metadata (Feature 5) --------------------------------
  // Mirrors the server `orders` columns of the same name. Filled by the
  // kitchen order sync (Realtime + PostgREST pull) so the ticket board can
  // render channel badges and customer info fully offline. Nullable: rows
  // created locally by the POS (Feature 4) only learn them on the next
  // server round-trip.
  /// Intake channel wire value (app|whatsapp|phone|walkin|qr_table).
  TextColumn get channel => text().nullable()();

  TextColumn get customerName => text().named('customer_name').nullable()();
  TextColumn get customerPhone => text().named('customer_phone').nullable()();
  IntColumn get tableNumber => integer().named('table_number').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {clientMutationId},
      ];
}

/// Driver assignment + proof of delivery milestones.
/// Raw GPS pings stream over MQTT (never touch this table).
class Deliveries extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().named('tenant_id')();
  TextColumn get orderId => text().named('order_id')();
  TextColumn get driverId => text().named('driver_id').nullable()();
  DateTimeColumn get pickedUpAt =>
      dateTime().named('picked_up_at').nullable()();
  DateTimeColumn get deliveredAt =>
      dateTime().named('delivered_at').nullable()();
  TextColumn get podPhotoUrl =>
      text().named('pod_photo_url').nullable()();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached memberships of the signed-in user (server: `memberships`).
///
/// Lets the workspace picker and the route gate work offline: rows are
/// refreshed from Supabase on every sign-in / workspace switch. `is_active`
/// marks the workspace selected before the last restart so the session can
/// resume it without connectivity. `invited_phone` mirrors the server column
/// for pending invites (always claimed locally — never null here).
class Memberships extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().named('tenant_id')();
  TextColumn get userId => text().named('user_id')();
  TextColumn get role => text()();

  /// Cached tenant display name for the offline workspace picker.
  TextColumn get tenantName =>
      text().named('tenant_name').withDefault(const Constant(''))();

  /// E.164 phone of a pending invite (mirrors the server column).
  TextColumn get invitedPhone => text().named('invited_phone').nullable()();

  BoolColumn get isActive =>
      boolean().named('is_active').withDefault(const Constant(false))();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Durable outbox: every local mutation also inserts a row here.
/// The sync engine drains it oldest-first with retry + idempotency keys.
///
/// `id` is a UUID v4 and doubles as the `Idempotency-Key` header;
/// `client_mutation_id` is the business-level dedupe key shared with the
/// server (UNIQUE — enqueueing the same key twice stores one row).
class OutboxEntries extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().named('tenant_id')();

  /// create | update | delete | transition
  TextColumn get op => text()();

  /// order | menu_snapshot | item_availability | delivery | payment
  TextColumn get entity => text()();
  TextColumn get entityId => text().named('entity_id')();

  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get clientMutationId => text().named('client_mutation_id')();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt =>
      dateTime().named('next_retry_at').nullable()();
  BoolColumn get deadLetter =>
      boolean().named('dead_letter').withDefault(const Constant(false))();
  TextColumn get lastError => text().named('last_error').nullable()();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {clientMutationId},
      ];
}

@DriftDatabase(
  tables: [
    Tenants,
    MenuSnapshots,
    MenuDrafts,
    ItemAvailabilities,
    Orders,
    Deliveries,
    OutboxEntries,
    Memberships,
  ],
)
class TchopDatabase extends _$TchopDatabase {
  TchopDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 → v2: menu studio needs a local draft store.
          if (from < 2) await m.createTable(menuDrafts);
          // v2 → v3: session membership cache (Feature 2).
          if (from < 3) await m.createTable(memberships);
          // v3 → v4: kitchen ticket metadata on orders (Feature 5:
          // channel badge + customer info for the offline ticket board).
          if (from < 4) {
            await m.addColumn(orders, orders.channel);
            await m.addColumn(orders, orders.customerName);
            await m.addColumn(orders, orders.customerPhone);
            await m.addColumn(orders, orders.tableNumber);
          }
        },
      );

  // ------------------------------------------------------------------
  // Tenants (brand cache for offline white-labeling)
  // ------------------------------------------------------------------

  Future<void> upsertTenant({
    required String id,
    required String name,
    required String brandJson,
  }) =>
      into(tenants).insert(
        TenantsCompanion.insert(
          id: id,
          name: name,
          brandJson: Value(brandJson),
        ),
        mode: InsertMode.insertOrReplace,
      );

  Future<Tenant?> tenantById(String id) =>
      (select(tenants)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ------------------------------------------------------------------
  // Menu snapshots
  // ------------------------------------------------------------------

  Future<void> upsertMenuSnapshot(MenuSnapshotsCompanion companion) =>
      into(menuSnapshots).insert(companion, mode: InsertMode.insertOrReplace);

  Future<MenuSnapshot?> latestMenuSnapshot(String tenantId) => (select(
        menuSnapshots,
      )
            ..where((m) => m.tenantId.equals(tenantId))
            ..orderBy([(m) => OrderingTerm.desc(m.version)])
            ..limit(1))
          .getSingleOrNull();

  /// Publish history for the studio ("Version 12 — publiée le 27/09…").
  Future<List<MenuSnapshot>> menuSnapshotsForTenant(String tenantId) =>
      (select(menuSnapshots)
            ..where((m) => m.tenantId.equals(tenantId))
            ..orderBy([(m) => OrderingTerm.desc(m.version)]))
          .get();

  // ------------------------------------------------------------------
  // Menu drafts (local editable document)
  // ------------------------------------------------------------------

  Future<MenuDraft?> menuDraftByTenant(String tenantId) =>
      (select(menuDrafts)..where((d) => d.tenantId.equals(tenantId)))
          .getSingleOrNull();

  Future<void> upsertMenuDraft(MenuDraftsCompanion companion) =>
      into(menuDrafts).insert(companion, mode: InsertMode.insertOrReplace);

  Stream<MenuDraft?> watchMenuDraft(String tenantId) =>
      (select(menuDrafts)..where((d) => d.tenantId.equals(tenantId)))
          .watchSingleOrNull();

  // ------------------------------------------------------------------
  // Item availability (86 toggle)
  // ------------------------------------------------------------------

  Future<void> setItemAvailability({
    required String tenantId,
    required String itemId,
    required bool available,
  }) =>
      into(itemAvailabilities).insert(
        ItemAvailabilitiesCompanion.insert(
          tenantId: tenantId,
          itemId: itemId,
          available: Value(available),
        ),
        mode: InsertMode.insertOrReplace,
      );

  Future<List<ItemAvailability>> availabilityForTenant(String tenantId) =>
      (select(itemAvailabilities)
            ..where((a) => a.tenantId.equals(tenantId)))
          .get();

  /// Live 86 state for the studio / kitchen screens.
  Stream<List<ItemAvailability>> watchAvailabilityForTenant(String tenantId) =>
      (select(itemAvailabilities)
            ..where((a) => a.tenantId.equals(tenantId)))
          .watch();

  // ------------------------------------------------------------------
  // Orders
  // ------------------------------------------------------------------

  Future<void> upsertOrder(OrdersCompanion companion) =>
      into(orders).insert(companion, mode: InsertMode.insertOrReplace);

  Future<List<Order>> ordersForTenant(String tenantId, {int limit = 100}) =>
      (select(orders)
            ..where((o) => o.tenantId.equals(tenantId))
            ..orderBy([(o) => OrderingTerm.desc(o.createdAt)])
            ..limit(limit))
          .get();

  Future<Order?> orderByClientMutationId(String clientMutationId) =>
      (select(orders)
            ..where((o) => o.clientMutationId.equals(clientMutationId)))
          .getSingleOrNull();

  // ------------------------------------------------------------------
  // Deliveries
  // ------------------------------------------------------------------

  Future<void> upsertDelivery(DeliveriesCompanion companion) =>
      into(deliveries).insert(companion, mode: InsertMode.insertOrReplace);

  /// Targeted UPDATE of a delivery row (unlike [upsertDelivery], this never
  /// wipes columns the caller didn't set — e.g. `driver_id` survives a
  /// proof-of-delivery update). No-op when the row doesn't exist yet.
  Future<void> updateDelivery(
    String id,
    DeliveriesCompanion companion,
  ) =>
      (update(deliveries)..where((d) => d.id.equals(id))).write(companion);

  Future<List<Delivery>> deliveriesForTenant(String tenantId) =>
      (select(deliveries)
            ..where((d) => d.tenantId.equals(tenantId))
            ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .get();

  // ------------------------------------------------------------------
  // Memberships (session workspace cache)
  // ------------------------------------------------------------------

  Future<void> upsertMembership(MembershipsCompanion companion) =>
      into(memberships).insert(companion, mode: InsertMode.insertOrReplace);

  Future<List<Membership>> membershipsForUser(String userId) =>
      (select(memberships)..where((m) => m.userId.equals(userId))).get();

  Future<List<Membership>> allMemberships() => select(memberships).get();

  Future<Membership?> activeMembership(String userId) =>
      (select(memberships)
            ..where(
                (m) => m.userId.equals(userId) & m.isActive.equals(true)))
          .getSingleOrNull();

  /// Marks [tenantId] as the active workspace, clearing every other flag.
  Future<void> setActiveMembership(
    String tenantId, {
    required String? userId,
  }) async {
    if (userId != null) {
      await (update(memberships)..where((m) => m.userId.equals(userId)))
          .write(
        const MembershipsCompanion(isActive: Value(false)),
      );
    } else {
      await update(memberships).write(
        const MembershipsCompanion(isActive: Value(false)),
      );
    }
    await (update(memberships)..where((m) => m.tenantId.equals(tenantId)))
        .write(
      const MembershipsCompanion(isActive: Value(true)),
    );
  }

  Future<void> clearActiveMemberships() =>
      update(memberships).write(
        const MembershipsCompanion(isActive: Value(false)),
      );

  // ------------------------------------------------------------------
  // Outbox
  // ------------------------------------------------------------------

  Future<OutboxEntry?> outboxEntryByClientMutationId(
    String clientMutationId,
  ) =>
      (select(outboxEntries)
            ..where((e) => e.clientMutationId.equals(clientMutationId)))
          .getSingleOrNull();

  /// Entries ready to send: not dead-lettered and past their retry time,
  /// oldest first.
  Future<List<OutboxEntry>> pendingOutboxEntries({required DateTime now}) =>
      (select(outboxEntries)
            ..where(
              (e) =>
                  e.deadLetter.equals(false) &
                  (e.nextRetryAt.isNull() |
                      e.nextRetryAt.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
          .get();

  Future<void> deleteOutboxEntry(String id) =>
      (delete(outboxEntries)..where((e) => e.id.equals(id))).go();

  Future<void> recordOutboxFailure({
    required String id,
    required int attempts,
    required DateTime nextRetryAt,
    String? lastError,
  }) =>
      (update(outboxEntries)..where((e) => e.id.equals(id))).write(
        OutboxEntriesCompanion(
          attempts: Value(attempts),
          nextRetryAt: Value(nextRetryAt),
          lastError: Value(lastError),
        ),
      );

  Future<void> markOutboxDeadLetter(String id, String reason) =>
      (update(outboxEntries)..where((e) => e.id.equals(id))).write(
        OutboxEntriesCompanion(
          deadLetter: const Value(true),
          lastError: Value(reason),
        ),
      );

  Future<List<OutboxEntry>> deadLetters() {
    final query = select(outboxEntries)
      ..where((e) => e.deadLetter.equals(true))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    return query.get();
  }

  Future<void> requeueDeadLetter(String id) =>
      (update(outboxEntries)..where((e) => e.id.equals(id))).write(
        OutboxEntriesCompanion(
          deadLetter: const Value(false),
          attempts: const Value(0),
          nextRetryAt: const Value<DateTime?>(null),
          lastError: Value<String?>(null),
        ),
      );

  /// Collapses stale entries: deletes non-dead-lettered rows for one
  /// tenant+op (used to keep a single latest `menu/draft_save` in queue).
  Future<int> deleteOutboxByOp({
    required String tenantId,
    required String op,
  }) =>
      (delete(outboxEntries)
            ..where((e) =>
                e.tenantId.equals(tenantId) &
                e.op.equals(op) &
                e.deadLetter.equals(false)))
          .go();

  /// Live count for the "pending sync" badge. Broadcast stream.
  Stream<int> watchOutboxCount({bool includeDeadLetters = false}) {
    final filter = includeDeadLetters ? '' : 'WHERE dead_letter = 0';
    return customSelect(
      'SELECT COUNT(*) AS c FROM outbox_entries $filter',
      readsFrom: {outboxEntries},
    ).watchSingle().map((row) => row.read<int>('c'));
  }

  /// Live count of dead-lettered mutations (manager review queue).
  Stream<int> watchDeadLetterCount() => customSelect(
        'SELECT COUNT(*) AS c FROM outbox_entries WHERE dead_letter = 1',
        readsFrom: {outboxEntries},
      ).watchSingle().map((row) => row.read<int>('c'));
}
