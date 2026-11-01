import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';
import 'menu_models.dart';

/// Outbox op names for the menu studio (see supabase/functions/sync/index.ts).
abstract final class MenuOps {
  static const String draftSave = 'menu/draft_save';
  static const String publish = 'menu/publish';
  static const String setAvailability = 'menu/set_availability';
  static const String approvePrice = 'menu/approve_price';
  static const String request86 = 'menu/request_86';

  /// Storage bucket holding item photos at `{tenant_id}/{item_id}.jpg`.
  static const String photoBucket = 'menu';
}

/// Persistence + sync for the menu studio.
///
/// Write path (fully offline-capable):
/// 1. mutate the local Drift tables (draft doc / snapshot / availability),
/// 2. [SyncEngine.enqueue] the intent — every mutation goes through the
///    outbox, never straight to the network.
///
/// Draft saves are debounced (default 2s): rapid typing collapses into a
/// single `menu/draft_save` entry per tenant (older pending draft_saves are
/// replaced, so the queue never fills with stale docs).
class MenuRepository {
  MenuRepository({
    required TchopDatabase db,
    required SyncEngine syncEngine,
    Uuid? uuids,
    this.draftDebounce = const Duration(seconds: 2),
  })  : _db = db,
        _sync = syncEngine,
        _uuids = uuids ?? const Uuid();

  final TchopDatabase _db;
  final SyncEngine _sync;
  final Uuid _uuids;
  final Duration draftDebounce;

  final Map<String, Timer> _draftTimers = {};
  final Map<String, _PendingDraft> _pendingDrafts = {};

  /// Live draft document (local source of truth while editing).
  Stream<MenuDraftDoc> watchDraft(String tenantId) =>
      _db.watchMenuDraft(tenantId).map(
            (row) => row == null
                ? MenuDraftDoc.empty()
                : MenuDraftDoc.fromJson(
                    jsonDecode(row.docJson) as Map<String, dynamic>),
          );

  /// Loads the draft, seeding it from the latest published snapshot when the
  /// tenant has no draft yet (so the studio opens with the live menu).
  Future<MenuDraftDoc> loadDraft(String tenantId) async {
    final row = await _db.menuDraftByTenant(tenantId);
    if (row != null) {
      return MenuDraftDoc.fromJson(
          jsonDecode(row.docJson) as Map<String, dynamic>);
    }
    final snapshot = await _db.latestMenuSnapshot(tenantId);
    if (snapshot != null) {
      final items = jsonDecode(snapshot.itemsJson);
      final doc = MenuDraftDoc.fromJson(
          items is Map<String, dynamic> ? items : {'items': items});
      await _db.upsertMenuDraft(
        MenuDraftsCompanion.insert(
          tenantId: tenantId,
          docJson: Value(jsonEncode(doc.toJson())),
        ),
      );
      return doc;
    }
    return MenuDraftDoc.empty();
  }

  /// Persists the draft locally *immediately* and enqueues a debounced
  /// `menu/draft_save`. Safe to call on every keystroke.
  Future<void> saveDraft({
    required String tenantId,
    required MenuDraftDoc doc,
    String? actorUserId,
  }) async {
    final stamped = doc.copyWith(
      updatedBy: actorUserId ?? doc.updatedBy,
      updatedAt: DateTime.now(),
    );
    await _db.upsertMenuDraft(
      MenuDraftsCompanion.insert(
        tenantId: tenantId,
        docJson: Value(jsonEncode(stamped.toJson())),
        updatedBy: Value(actorUserId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _pendingDrafts[tenantId] =
        _PendingDraft(doc: stamped, actorUserId: actorUserId);
    _draftTimers[tenantId]?.cancel();
    _draftTimers[tenantId] = Timer(draftDebounce, () {
      unawaited(flushDraft(tenantId));
    });
  }

  /// True while a debounced draft save hasn't hit the outbox yet — drives
  /// the "Enregistrement…" state of the save indicator.
  bool hasUnflushedDraft(String tenantId) => _pendingDrafts.containsKey(tenantId);

  /// Immediately enqueues the latest pending draft (e.g. before publish or
  /// when leaving the screen).
  Future<void> flushDraft(String tenantId) async {
    _draftTimers[tenantId]?.cancel();
    _draftTimers.remove(tenantId);
    final pending = _pendingDrafts.remove(tenantId);
    if (pending == null) return;
    // Collapse: only the newest doc per tenant waits in the queue.
    await _db.deleteOutboxByOp(tenantId: tenantId, op: MenuOps.draftSave);
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.draftSave,
      entity: 'menu_draft',
      entityId: tenantId,
      payload: {
        'doc': pending.doc.toJson(),
        'updated_by': pending.actorUserId,
      },
    );
  }

  /// Publishes the current draft as an immutable snapshot.
  ///
  /// The client computes the advisory next version as local `max(version)+1`.
  /// ATOMICITY NOTE (server): the `sync` Edge Function MUST NOT trust this
  /// number. It applies `menu/publish` through the
  /// `public.publish_menu_snapshot(...)` RPC (see
  /// supabase/migrations/20260927_menu_ops.sql), which takes a
  /// per-tenant advisory lock inside one transaction, recomputes
  /// `max(version)+1` itself, and inserts — so two managers publishing at
  /// the same second can never collide on the `(tenant_id, version)` unique
  /// key. The server-computed version is authoritative; the device converges
  /// on the next draft pull.
  ///
  /// Returns the locally assumed version.
  Future<int> publish({
    required String tenantId,
    required MenuDraftDoc doc,
    String? actorUserId,
    String? actorLabel,
  }) async {
    await flushDraft(tenantId);
    final latest = await _db.latestMenuSnapshot(tenantId);
    final version = (latest?.version ?? 0) + 1;
    final snapshotId = _uuids.v4();
    await _db.upsertMenuSnapshot(
      MenuSnapshotsCompanion.insert(
        id: snapshotId,
        tenantId: tenantId,
        version: version,
        itemsJson: Value(jsonEncode(doc.toJson())),
        publishedAt: Value(DateTime.now()),
      ),
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.publish,
      entity: 'menu_snapshot',
      entityId: snapshotId,
      payload: {
        'version': version,
        'items': doc.toJson(),
        'published_by': actorUserId,
        'published_by_label': actorLabel,
      },
    );
    return version;
  }

  /// Version history, newest first ("Version 12 — publiée le 27/09…").
  Future<List<MenuSnapshot>> versionHistory(String tenantId) =>
      _db.menuSnapshotsForTenant(tenantId);

  /// item_id → price (FCFA) from the latest published snapshot.
  /// The >10% approval check compares against these, not the draft.
  Future<Map<String, int>> publishedPrices(String tenantId) async {
    final snapshot = await _db.latestMenuSnapshot(tenantId);
    if (snapshot == null) return {};
    final decoded = jsonDecode(snapshot.itemsJson);
    final map = decoded is Map<String, dynamic> ? decoded : {'items': decoded};
    final doc = MenuDraftDoc.fromJson(map);
    return {for (final item in doc.items) item.id: item.priceFcfa};
  }

  // ------------------------------------------------------------------
  // Approvals inbox
  // ------------------------------------------------------------------

  /// Kitchen role: request an 86. Lands in the owner/manager approvals
  /// inbox (local draft doc + `menu/request_86` op); the server merges it
  /// into `menu_drafts` so it reaches the manager's other devices.
  Future<void> request86({
    required String tenantId,
    required String itemId,
    required String itemName,
    String? requestedBy,
  }) async {
    final approval = MenuApproval(
      id: _uuids.v4(),
      kind: MenuApproval.kindRequest86,
      itemId: itemId,
      itemName: itemName,
      requestedBy: requestedBy,
      requestedAt: DateTime.now(),
    );
    final doc = await loadDraft(tenantId);
    await saveDraft(
      tenantId: tenantId,
      doc: doc.copyWith(approvals: [...doc.approvals, approval]),
      actorUserId: requestedBy,
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.request86,
      entity: 'menu_approval',
      entityId: approval.id,
      payload: {
        'item_id': itemId,
        'item_name': itemName,
        'requested_by': requestedBy,
      },
    );
  }

  /// Owner/manager: accept a >10% price change — applies the new price to
  /// the draft and clears the pending flag.
  Future<void> approvePrice({
    required String tenantId,
    required String approvalId,
    String? actorUserId,
  }) async {
    final doc = await loadDraft(tenantId);
    final approval = _findApproval(doc, approvalId);
    if (approval == null || !approval.isPending) return;
    final items = doc.items.map((item) {
      if (item.id != approval.itemId) return item;
      return item.copyWith(
        priceFcfa: approval.newPriceFcfa ?? item.priceFcfa,
        clearApproval: true,
      );
    }).toList();
    final approvals = doc.approvals
        .map((a) => a.id == approvalId
            ? a.copyWith(status: MenuApproval.approvalApproved)
            : a)
        .toList();
    await saveDraft(
      tenantId: tenantId,
      doc: doc.copyWith(items: items, approvals: approvals),
      actorUserId: actorUserId,
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.approvePrice,
      entity: 'menu_approval',
      entityId: approvalId,
      payload: {
        'item_id': approval.itemId,
        'decision': 'approved',
        'new_price_fcfa': approval.newPriceFcfa,
        'decided_by': actorUserId,
      },
    );
  }

  /// Owner/manager: reject a >10% price change — the draft keeps the last
  /// applied price and the pending flag is cleared.
  Future<void> rejectPrice({
    required String tenantId,
    required String approvalId,
    String? actorUserId,
  }) async {
    final doc = await loadDraft(tenantId);
    final approval = _findApproval(doc, approvalId);
    if (approval == null || !approval.isPending) return;
    final items = doc.items
        .map((item) => item.id == approval.itemId
            ? item.copyWith(clearApproval: true)
            : item)
        .toList();
    final approvals = doc.approvals
        .map((a) => a.id == approvalId
            ? a.copyWith(status: MenuApproval.approvalRejected)
            : a)
        .toList();
    await saveDraft(
      tenantId: tenantId,
      doc: doc.copyWith(items: items, approvals: approvals),
      actorUserId: actorUserId,
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.approvePrice,
      entity: 'menu_approval',
      entityId: approvalId,
      payload: {
        'item_id': approval.itemId,
        'decision': 'rejected',
        'decided_by': actorUserId,
      },
    );
  }

  /// Owner/manager: resolve a kitchen 86 request. Approving flips the fast
  /// availability toggle (via [AvailabilityBroadcaster]); rejecting just
  /// closes the request.
  Future<void> resolve86Request({
    required String tenantId,
    required String approvalId,
    required bool approve,
    String? actorUserId,
    required Future<void> Function({required String itemId, required bool available})
        applyAvailability,
  }) async {
    final doc = await loadDraft(tenantId);
    final approval = _findApproval(doc, approvalId);
    if (approval == null || !approval.isPending) return;
    if (approve) {
      await applyAvailability(itemId: approval.itemId, available: false);
    }
    final approvals = doc.approvals
        .map((a) => a.id == approvalId
            ? a.copyWith(
                status: approve
                    ? MenuApproval.approvalApproved
                    : MenuApproval.approvalRejected)
            : a)
        .toList();
    await saveDraft(
      tenantId: tenantId,
      doc: doc.copyWith(approvals: approvals),
      actorUserId: actorUserId,
    );
    await _sync.enqueue(
      tenantId: tenantId,
      op: MenuOps.approvePrice,
      entity: 'menu_approval',
      entityId: approvalId,
      payload: {
        'item_id': approval.itemId,
        'decision': approve ? 'approved' : 'rejected',
        'decided_by': actorUserId,
      },
    );
  }

  // ------------------------------------------------------------------
  // Item photos
  // ------------------------------------------------------------------

  /// Uploads an item photo to Storage at
  /// `menu/{tenant_id}/{item_id}.jpg` (bucket [MenuOps.photoBucket]) and
  /// returns its public URL.
  ///
  /// Returns null when the backend isn't configured (offline mode) — the
  /// caller should then keep whatever photo URL the draft already has.
  /// Never throws: upload failures surface as null so editing never blocks.
  Future<String?> uploadItemPhoto({
    required String tenantId,
    required String itemId,
    required XFile file,
  }) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final path = '$tenantId/$itemId.jpg';
      await client.storage.from(MenuOps.photoBucket).uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      return client.storage.from(MenuOps.photoBucket).getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  MenuApproval? _findApproval(MenuDraftDoc doc, String approvalId) {
    for (final approval in doc.approvals) {
      if (approval.id == approvalId) return approval;
    }
    return null;
  }

  void dispose() {
    for (final timer in _draftTimers.values) {
      timer.cancel();
    }
    _draftTimers.clear();
    _pendingDrafts.clear();
  }
}

class _PendingDraft {
  _PendingDraft({required this.doc, this.actorUserId});
  final MenuDraftDoc doc;
  final String? actorUserId;
}
