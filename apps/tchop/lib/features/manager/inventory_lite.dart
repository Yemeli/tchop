import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/sync/sync_engine.dart';

/// Manual stock count for one menu item.
class StockCount {
  const StockCount({
    required this.itemId,
    required this.itemName,
    required this.count,
    required this.lowThreshold,
    required this.updatedAt,
  });

  final String itemId;
  final String itemName;
  final int count;
  final int lowThreshold;
  final DateTime updatedAt;

  bool get isLow => count <= lowThreshold;

  Map<String, Object?> toJson() => {
        'item_id': itemId,
        'item_name': itemName,
        'count': count,
        'low_threshold': lowThreshold,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StockCount.fromJson(Map<String, dynamic> json) => StockCount(
        itemId: '${json['item_id']}',
        itemName: '${json['item_name'] ?? 'Article'}',
        count: (json['count'] as num?)?.toInt() ?? 0,
        lowThreshold: (json['low_threshold'] as num?)?.toInt() ?? 5,
        updatedAt: DateTime.tryParse('${json['updated_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Inventory-lite (Feature 8) — manual stock counts, PHASE 2 honesty.
///
/// Storage is purely local (one JSON file per tenant in the app documents
/// directory — no new Drift table, so no codegen needed). Every count also
/// enqueues the `inventory/set_count` outbox op: the server currently only
/// ledgers + audit-logs it (see `supabase/functions/sync/index.ts`) — there
/// is intentionally no server inventory table yet. The UI labels this
/// "Phase 2".
class InventoryLiteRepository {
  InventoryLiteRepository({required SyncEngine syncEngine})
      : _sync = syncEngine;

  final SyncEngine _sync;

  Future<File> _file(String tenantId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/inventory_$tenantId.json');
  }

  Future<Map<String, StockCount>> load(String tenantId) async {
    try {
      final file = await _file(tenantId);
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is Map<String, dynamic>)
            '${e.key}': StockCount.fromJson(
                (e.value as Map).cast<String, dynamic>()),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(
      String tenantId, Map<String, StockCount> counts) async {
    final file = await _file(tenantId);
    await file.writeAsString(
        jsonEncode({for (final e in counts.entries) e.key: e.value.toJson()}));
  }

  /// Records a manual count (local write) and enqueues `inventory/set_count`
  /// for the future server table (phase-2 stub — see class docs).
  Future<void> setCount({
    required String tenantId,
    required String itemId,
    required String itemName,
    required int count,
    int lowThreshold = 5,
  }) async {
    final counts = await load(tenantId);
    counts[itemId] = StockCount(
      itemId: itemId,
      itemName: itemName,
      count: count,
      lowThreshold: lowThreshold,
      updatedAt: DateTime.now(),
    );
    await _save(tenantId, counts);
    await _sync.enqueue(
      tenantId: tenantId,
      op: 'inventory/set_count',
      entity: 'inventory',
      entityId: itemId,
      payload: {
        'item_id': itemId,
        'item_name': itemName,
        'count': count,
        'low_threshold': lowThreshold,
        'counted_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Items at or below their alert threshold, most urgent first.
  Future<List<StockCount>> lowStock(String tenantId) async {
    final counts = await load(tenantId);
    final low = counts.values.where((s) => s.isLow).toList()
      ..sort((a, b) => a.count.compareTo(b.count));
    return low;
  }
}
