import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'availability_broadcaster.dart';
import 'daypart.dart';
import 'menu_models.dart';
import 'menu_permissions.dart';
import 'menu_repository.dart';
import 'price_approval.dart';
import '../../data/database/tchop_database.dart';
import '../../data/sync/sync_engine.dart';

/// State for the menu studio (manager flavor).
///
/// Holds the draft document in memory, persists every mutation locally via
/// [MenuRepository.saveDraft] (debounced `menu/draft_save` outbox op), and
/// exposes:
/// - [syncPending]: true while a draft save hasn't reached the outbox or
///   outbox entries are still queued — drives the pending-sync badge;
/// - [availability]: live 86 state per item id;
/// - RBAC getters so the UI can hide price fields / publish for head chefs.
class MenuStudioController extends ChangeNotifier {
  MenuStudioController({
    required MenuRepository repository,
    required AvailabilityBroadcaster availabilityBroadcaster,
    required TchopDatabase db,
    required SyncEngine syncEngine,
    required this.tenantId,
    required this.role,
    required this.userId,
    Uuid? uuids,
  })  : _repository = repository,
        _broadcaster = availabilityBroadcaster,
        _db = db,
        _uuids = uuids ?? const Uuid() {
    _pendingSub = syncEngine.pendingCount.listen((count) {
      final next = count > 0;
      if (next != _outboxPending) {
        _outboxPending = next;
        notifyListeners();
      }
    });
    _availabilitySub =
        _db.watchAvailabilityForTenant(tenantId).listen((rows) {
      availability = {for (final r in rows) r.itemId: r.available};
      notifyListeners();
    });
  }

  final MenuRepository _repository;
  final AvailabilityBroadcaster _broadcaster;
  final TchopDatabase _db;
  final Uuid _uuids;

  final String tenantId;
  final String? role;
  final String? userId;

  MenuDraftDoc? doc;
  bool loading = true;
  String? error;
  bool publishing = false;
  String? notice;

  /// item_id → available (defaults to true when absent).
  Map<String, bool> availability = {};

  /// Last published prices (item_id → FCFA) — the >10% check compares
  /// against these.
  Map<String, int> _publishedPrices = {};

  bool _outboxPending = false;
  StreamSubscription<int>? _pendingSub;
  StreamSubscription<List<ItemAvailability>>? _availabilitySub;

  // -- RBAC -------------------------------------------------------------
  bool get canEditItems => MenuPermissions.canEditItems(role);
  bool get canEditPrices => MenuPermissions.canEditPrices(role);
  bool get canPublish => MenuPermissions.canPublish(role);
  bool get canToggle86 => MenuPermissions.canToggle86(role);
  bool get canReviewApprovals => MenuPermissions.canReviewApprovals(role);

  /// Pending-sync badge: debounced save not yet flushed, or outbox non-empty.
  bool get syncPending =>
      _outboxPending || _repository.hasUnflushedDraft(tenantId);

  bool isAvailable(String itemId) => availability[itemId] ?? true;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      doc = await _repository.loadDraft(tenantId);
      _publishedPrices = await _repository.publishedPrices(tenantId);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _persist(MenuDraftDoc next) async {
    doc = next;
    notifyListeners();
    try {
      await _repository.saveDraft(
        tenantId: tenantId,
        doc: next,
        actorUserId: userId,
      );
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
    // The debounced flag changes on a timer — refresh the badge shortly
    // after the debounce window.
    Timer(_repository.draftDebounce + const Duration(milliseconds: 300), () {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _pendingSub?.cancel();
    _availabilitySub?.cancel();
    super.dispose();
  }

  // -- Categories ---------------------------------------------------------
  Future<void> addCategory(String name) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final nextSort = current.categories.isEmpty
        ? 0
        : current.categories
                .map((c) => c.sort)
                .reduce((a, b) => a > b ? a : b) +
            1;
    await _persist(current.copyWith(categories: [
      ...current.categories,
      MenuCategory(id: _uuids.v4(), name: trimmed, sort: nextSort),
    ]));
  }

  Future<void> renameCategory(String id, String name) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _persist(current.copyWith(
      categories: [
        for (final c in current.categories)
          if (c.id == id) c.copyWith(name: trimmed) else c,
      ],
    ));
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    final sorted = current.sortedCategories;
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, moved);
    final reindexed = [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(sort: i),
    ];
    await _persist(current.copyWith(categories: reindexed));
  }

  /// Returns false when the category still holds items (delete those first).
  Future<bool> deleteCategory(String id) async {
    final current = doc;
    if (current == null || !canEditItems) return false;
    if (current.items.any((i) => i.categoryId == id)) return false;
    await _persist(current.copyWith(
      categories: [for (final c in current.categories) if (c.id != id) c],
    ));
    return true;
  }

  // -- Items --------------------------------------------------------------
  Future<void> addItem(String categoryId, String name) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final inCategory = current.itemsInCategory(categoryId);
    final nextSort =
        inCategory.isEmpty ? 0 : inCategory.map((i) => i.sort).reduce((a, b) => a > b ? a : b) + 1;
    await _persist(current.copyWith(items: [
      ...current.items,
      MenuItem(
        id: _uuids.v4(),
        categoryId: categoryId,
        name: trimmed,
        sort: nextSort,
      ),
    ]));
  }

  Future<void> updateItem(MenuItem updated) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    await _persist(current.copyWith(items: [
      for (final i in current.items) if (i.id == updated.id) updated else i,
    ]));
  }

  /// Price edit with the >10% approval gate. When approval is needed the
  /// item keeps its current price and is flagged `pendingApproval`; the
  /// request lands in the approvals inbox. Otherwise the price applies
  /// immediately.
  Future<void> setItemPrice(MenuItem item, int newPriceFcfa) async {
    final current = doc;
    if (current == null || !canEditPrices) return;
    if (newPriceFcfa < 0) return;
    // No published baseline (new item, or no snapshot yet) → no approval.
    final oldPrice = _publishedPrices[item.id];
    if (newPriceFcfa == item.priceFcfa && !item.pendingApproval) return;

    if (oldPrice != null && priceChangeNeedsApproval(oldPrice, newPriceFcfa)) {
      final approval = MenuApproval(
        id: _uuids.v4(),
        kind: MenuApproval.kindPriceChange,
        itemId: item.id,
        itemName: item.name,
        oldPriceFcfa: oldPrice,
        newPriceFcfa: newPriceFcfa,
        requestedBy: userId,
        requestedAt: DateTime.now(),
      );
      final flagged = item.copyWith(
        pendingApproval: true,
        approvalOldPrice: oldPrice,
        approvalNewPrice: newPriceFcfa,
        approvalRequestedBy: userId,
        approvalRequestedAt: DateTime.now(),
      );
      await _persist(current.copyWith(
        items: [
          for (final i in current.items) if (i.id == item.id) flagged else i,
        ],
        approvals: [...current.approvals, approval],
      ));
      notice =
          'Hausse de plus de 10 % : envoyée en approbation.';
    } else {
      final applied = item.copyWith(
        priceFcfa: newPriceFcfa,
        clearApproval: true,
      );
      // Drop any stale pending request for this item.
      final approvals = [
        for (final a in current.approvals)
          if (!(a.itemId == item.id &&
              a.kind == MenuApproval.kindPriceChange &&
              a.isPending))
            a
          else
            a.copyWith(status: MenuApproval.approvalRejected),
      ];
      await _persist(current.copyWith(
        items: [
          for (final i in current.items) if (i.id == item.id) applied else i,
        ],
        approvals: approvals,
      ));
    }
    notifyListeners();
  }

  Future<void> deleteItem(String itemId) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    await _persist(current.copyWith(
      items: [for (final i in current.items) if (i.id != itemId) i],
    ));
  }

  Future<void> setItemPhoto(MenuItem item, String photoUrl) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    await updateItem(item.copyWith(photoUrl: photoUrl));
  }

  // -- 86 toggle ------------------------------------------------------------
  Future<void> toggle86(String itemId, bool available) async {
    if (!canToggle86) return;
    await _broadcaster.setAvailability(
      tenantId: tenantId,
      itemId: itemId,
      available: available,
      requestedBy: userId,
    );
  }

  // -- Dayparts ---------------------------------------------------------------
  Future<void> updateDaypart(Daypart updated) async {
    final current = doc;
    if (current == null || !canEditItems) return;
    await _persist(current.copyWith(dayparts: [
      for (final d in current.dayparts) if (d.id == updated.id) updated else d,
    ]));
  }

  // -- Publish ------------------------------------------------------------------
  Future<bool> publish({String? actorLabel}) async {
    if (!canPublish) return false;
    final current = doc;
    if (current == null) return false;
    publishing = true;
    notifyListeners();
    try {
      final version = await _repository.publish(
        tenantId: tenantId,
        doc: current,
        actorUserId: userId,
        actorLabel: actorLabel,
      );
      _publishedPrices = await _repository.publishedPrices(tenantId);
      notice = 'Version $version publiée.';
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      publishing = false;
      notifyListeners();
    }
  }

  Future<List<MenuSnapshot>> versionHistory() =>
      _repository.versionHistory(tenantId);

  // -- Approvals ------------------------------------------------------------------
  Future<void> approvePrice(String approvalId) async {
    await _repository.approvePrice(
        tenantId: tenantId, approvalId: approvalId, actorUserId: userId);
    doc = await _repository.loadDraft(tenantId);
    notifyListeners();
  }

  Future<void> rejectPrice(String approvalId) async {
    await _repository.rejectPrice(
        tenantId: tenantId, approvalId: approvalId, actorUserId: userId);
    doc = await _repository.loadDraft(tenantId);
    notifyListeners();
  }

  Future<void> resolve86Request(String approvalId, bool approve) async {
    await _repository.resolve86Request(
      tenantId: tenantId,
      approvalId: approvalId,
      approve: approve,
      actorUserId: userId,
      applyAvailability: ({required String itemId, required bool available}) =>
          _broadcaster.setAvailability(
        tenantId: tenantId,
        itemId: itemId,
        available: available,
        requestedBy: userId,
      ),
    );
    doc = await _repository.loadDraft(tenantId);
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }
}
