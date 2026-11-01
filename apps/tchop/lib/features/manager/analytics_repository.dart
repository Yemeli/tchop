import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../core/session/roles.dart';
import '../orders/order_models.dart';
import 'inventory_lite.dart';

/// Aggregated read models for the manager "Tableau de bord" (Feature 8).
class SalesSummary {
  const SalesSummary({
    required this.revenueFcfa,
    required this.orderCount,
    required this.offline,
  });

  final int revenueFcfa;
  final int orderCount;
  final bool offline;

  int get avgTicketFcfa => orderCount == 0 ? 0 : revenueFcfa ~/ orderCount;
}

class DailySales {
  const DailySales({
    required this.date,
    required this.totalFcfa,
    required this.orderCount,
  });

  final DateTime date;
  final int totalFcfa;
  final int orderCount;
}

class ChannelSlice {
  const ChannelSlice({
    required this.channel,
    required this.totalFcfa,
    required this.orderCount,
  });

  final String channel;
  final int totalFcfa;
  final int orderCount;

  /// Display labels for the analytics split (task spec):
  /// App / WhatsApp / Téléphone / Comptoir / QR.
  String get labelFr => switch (channel) {
        OrderChannel.app => 'App',
        OrderChannel.whatsapp => 'WhatsApp',
        OrderChannel.phone => 'Téléphone',
        OrderChannel.walkin => 'Comptoir',
        OrderChannel.qrTable => 'QR',
        _ => OrderChannel.labelFr(channel),
      };
}

class TopItem {
  const TopItem({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.revenueFcfa,
  });

  final String itemId;
  final String name;
  final int qty;
  final int revenueFcfa;
}

class StaffStat {
  const StaffStat({
    required this.userId,
    required this.role,
    required this.orderCount,
    required this.revenueFcfa,
  });

  final String userId;
  final String role;
  final int orderCount;
  final int revenueFcfa;

  /// No staff names in the DB — label by role + short id (honest).
  String get labelFr =>
      '${roleLabelFr(role)} · ${userId.length > 6 ? userId.substring(0, 6) : userId}';
}

/// One row of the alerts feed: void/discount (audit), failed payment, 86
/// request pending, low stock.
class ManagerAlert {
  const ManagerAlert({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.actorLabel,
    required this.at,
    required this.severity,
  });

  /// void | discount | payment_failed | eighty_six | stock_low
  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String? actorLabel;
  final DateTime at;
  final String severity; // danger | warning | info
}

/// Manager analytics reads (Feature 8).
///
/// Strategy: ONE PostgREST orders pull per refresh (bounded by `since`,
/// client-side aggregation) → [SalesSummary], [DailySales], [ChannelSlice],
/// [TopItem], [StaffStat]. When the backend is unreachable, the same
/// aggregates are computed from the local Drift `orders` cache (flagged
/// [SalesSummary.offline] = true); staff stats and audit alerts have no
/// local equivalent and come back empty offline.
class AnalyticsRepository {
  AnalyticsRepository({required TchopDatabase db}) : _db = db;

  final TchopDatabase _db;

  SupabaseClient? get _client => TchopSupabase.clientOrNull;

  // ------------------------------------------------------------------
  // Sales aggregates
  // ------------------------------------------------------------------

  /// Pulls the raw order facts once (server preferred, Drift fallback).
  Future<_OrderFacts> _facts(String tenantId, DateTime since) async {
    final client = _client;
    if (client != null) {
      try {
        final rows = await client
            .from('orders')
            .select('id,total,created_at,channel,created_by,lines')
            .eq('tenant_id', tenantId)
            .neq('status', 'cancelled')
            .gte('created_at', since.toUtc().toIso8601String())
            .order('created_at', ascending: false)
            .limit(2000);
        return _OrderFacts(
          offline: false,
          rows: [
            for (final r in (rows as List).cast<Map<String, dynamic>>())
              _FactRow(
                total: (r['total'] as num?)?.toInt() ?? 0,
                createdAt: DateTime.tryParse('${r['created_at']}') ??
                    DateTime.now(),
                channel: '${r['channel'] ?? 'app'}',
                createdBy: r['created_by'] as String?,
                lines: r['lines'],
              ),
          ],
        );
      } catch (_) {
        // fall through to the Drift cache
      }
    }
    final local = await _db.ordersForTenant(tenantId, limit: 2000);
    return _OrderFacts(
      offline: true,
      rows: [
        for (final o in local)
          if (o.createdAt.isAfter(since) && o.status != 'cancelled')
            _FactRow(
              total: o.totalCents,
              createdAt: o.createdAt,
              channel: o.channel ?? 'app',
              createdBy: null,
              lines: _decodeLines(o.linesJson),
            ),
      ],
    );
  }

  static List<dynamic> _decodeLines(String json) {
    try {
      final d = jsonDecode(json);
      return d is List ? d : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<SalesSummary> salesSummary(String tenantId, DateTime since) async {
    final facts = await _facts(tenantId, since);
    final revenue = facts.rows.fold(0, (n, r) => n + r.total);
    return SalesSummary(
      revenueFcfa: revenue,
      orderCount: facts.rows.length,
      offline: facts.offline,
    );
  }

  /// Sales per day for the last [days] days (oldest → newest), for the bar
  /// chart. Days are bucketed in device-local time.
  Future<List<DailySales>> dailySales(String tenantId,
      {int days = 14}) async {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final facts = await _facts(tenantId, since);
    final buckets = <String, List<_FactRow>>{};
    for (final r in facts.rows) {
      final d = r.createdAt;
      final key = '${d.year}-${d.month}-${d.day}';
      (buckets[key] ??= []).add(r);
    }
    return [
      for (var i = 0; i < days; i++)
        () {
          final d = since.add(Duration(days: i));
          final key = '${d.year}-${d.month}-${d.day}';
          final rows = buckets[key] ?? const <_FactRow>[];
          return DailySales(
            date: d,
            totalFcfa: rows.fold(0, (n, r) => n + r.total),
            orderCount: rows.length,
          );
        }(),
    ];
  }

  Future<List<ChannelSlice>> channelSplit(
      String tenantId, DateTime since) async {
    final facts = await _facts(tenantId, since);
    final byChannel = <String, List<_FactRow>>{};
    for (final r in facts.rows) {
      (byChannel[r.channel] ??= []).add(r);
    }
    final slices = [
      for (final e in byChannel.entries)
        ChannelSlice(
          channel: e.key,
          totalFcfa: e.value.fold(0, (n, r) => n + r.total),
          orderCount: e.value.length,
        ),
    ]..sort((a, b) => b.totalFcfa.compareTo(a.totalFcfa));
    return slices;
  }

  /// Best-selling items by quantity. [itemNames] maps item_id → display
  /// name (built from the published snapshot); unknown ids show a short id.
  Future<List<TopItem>> topItems(
    String tenantId,
    DateTime since, {
    int limit = 10,
    Map<String, String> itemNames = const {},
  }) async {
    final facts = await _facts(tenantId, since);
    final agg = <String, ({int qty, int revenue})>{};
    for (final r in facts.rows) {
      final lines = r.lines;
      if (lines is! List) continue;
      for (final l in lines) {
        if (l is! Map) continue;
        final id = '${l['item_id'] ?? ''}';
        if (id.isEmpty) continue;
        final qty = (l['qty'] as num?)?.toInt() ?? 0;
        final price = (l['unit_price'] as num?)?.toInt() ?? 0;
        final cur = agg[id] ?? (qty: 0, revenue: 0);
        agg[id] = (qty: cur.qty + qty, revenue: cur.revenue + qty * price);
      }
    }
    final items = [
      for (final e in agg.entries)
        TopItem(
          itemId: e.key,
          name: itemNames[e.key] ??
              (e.key.length > 8 ? '${e.key.substring(0, 8)}…' : e.key),
          qty: e.value.qty,
          revenueFcfa: e.value.revenue,
        ),
    ]..sort((a, b) => b.qty.compareTo(a.qty));
    return items.take(limit).toList();
  }

  /// Orders handled per staff member (from `orders.created_by`).
  /// Offline: no `created_by` locally → empty list (honest, not guessed).
  Future<List<StaffStat>> staffPerformance(
      String tenantId, DateTime since) async {
    final facts = await _facts(tenantId, since);
    if (facts.offline) return const [];
    final byUser = <String, List<_FactRow>>{};
    for (final r in facts.rows) {
      final u = r.createdBy;
      if (u == null || u.isEmpty) continue;
      (byUser[u] ??= []).add(r);
    }
    if (byUser.isEmpty) return const [];
    final roles = await _memberRoles(tenantId);
    final stats = [
      for (final e in byUser.entries)
        StaffStat(
          userId: e.key,
          role: roles[e.key] ?? '—',
          orderCount: e.value.length,
          revenueFcfa: e.value.fold(0, (n, r) => n + r.total),
        ),
    ]..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return stats;
  }

  Future<Map<String, String>> _memberRoles(String tenantId) async {
    final client = _client;
    if (client == null) return const {};
    try {
      final rows = await client
          .from('memberships')
          .select('user_id,role')
          .eq('tenant_id', tenantId);
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          '${r['user_id']}': '${r['role']}',
      };
    } catch (_) {
      return const {};
    }
  }

  // ------------------------------------------------------------------
  // Alerts
  // ------------------------------------------------------------------

  /// Merged alerts feed, newest first:
  /// audit `order.void` / `order.discount` (red) → failed payments →
  /// pending 86 requests → low-stock warnings.
  Future<List<ManagerAlert>> recentAlerts(
    String tenantId, {
    int limit = 40,
    InventoryLiteRepository? inventory,
  }) async {
    final client = _client;
    if (client == null) {
      // Offline: only local low-stock is knowable.
      return _lowStockAlerts(tenantId, inventory);
    }
    final alerts = <ManagerAlert>[];
    final roles = await _memberRoles(tenantId);
    String actorOf(String? userId) {
      if (userId == null || userId.isEmpty) return 'Système';
      final role = roles[userId];
      final short =
          userId.length > 6 ? userId.substring(0, 6) : userId;
      return role == null ? short : '${roleLabelFr(role)} · $short';
    }

    try {
      final rows = await client
          .from('audit_logs')
          .select('id,action,entity_id,before,after,created_at,user_id')
          .eq('tenant_id', tenantId)
          .inFilter('action', ['order.void', 'order.discount'])
          .order('created_at', ascending: false)
          .limit(50);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final after = (r['after'] as Map?)?.cast<String, dynamic>() ?? {};
        final at = DateTime.tryParse('${r['created_at']}') ?? DateTime.now();
        if (r['action'] == 'order.void') {
          final total = (after['total'] as num?)?.toInt();
          final reason = after['reason'] as String?;
          alerts.add(ManagerAlert(
            id: 'audit-${r['id']}',
            kind: 'void',
            title:
                'Commande annulée${total != null ? ' — ${formatFcfa(total)}' : ''}',
            subtitle: reason != null && reason.isNotEmpty
                ? 'Motif : $reason'
                : 'Sans motif renseigné',
            actorLabel: actorOf(r['user_id'] as String?),
            at: at,
            severity: 'danger',
          ));
        } else {
          final amount = (after['discount_fcfa'] as num?)?.toInt() ?? 0;
          final reason = after['reason'] as String?;
          alerts.add(ManagerAlert(
            id: 'audit-${r['id']}',
            kind: 'discount',
            title: 'Remise de ${formatFcfa(amount)}',
            subtitle: reason != null && reason.isNotEmpty
                ? 'Motif : $reason'
                : null,
            actorLabel: actorOf(r['user_id'] as String?),
            at: at,
            severity: 'danger',
          ));
        }
      }
    } catch (_) {
      // audit read failed — other sources still render
    }

    try {
      final rows = await client
          .from('payments')
          .select('id,amount,created_at,provider,order_id')
          .eq('tenant_id', tenantId)
          .eq('status', 'failed')
          .order('created_at', ascending: false)
          .limit(20);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        alerts.add(ManagerAlert(
          id: 'pay-${r['id']}',
          kind: 'payment_failed',
          title:
              'Paiement échoué — ${formatFcfa((r['amount'] as num?)?.toInt() ?? 0)}',
          subtitle: 'Via ${r['provider'] ?? '—'}',
          at: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
          severity: 'warning',
        ));
      }
    } catch (_) {}

    alerts.addAll(await _pending86Alerts(tenantId));
    alerts.addAll(await _lowStockAlerts(tenantId, inventory));
    alerts.sort((a, b) => b.at.compareTo(a.at));
    return alerts.take(limit).toList();
  }

  /// Pending 86 requests from the menu draft's approvals inbox.
  Future<List<ManagerAlert>> _pending86Alerts(String tenantId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final row = await client
          .from('menu_drafts')
          .select('doc')
          .eq('tenant_id', tenantId)
          .maybeSingle();
      final doc = row?['doc'];
      final approvals = doc is Map ? doc['approvals'] : null;
      if (approvals is! List) return const [];
      return [
        for (final a in approvals)
          if (a is Map &&
              a['kind'] == 'request_86' &&
              a['status'] == 'pending')
            ManagerAlert(
              id: '86-${a['id'] ?? a['item_id']}',
              kind: 'eighty_six',
              title: 'Demande 86 en attente : ${a['item_name'] ?? 'article'}',
              subtitle: 'Demandée par la cuisine — à valider',
              at: DateTime.tryParse('${a['requested_at']}') ?? DateTime.now(),
              severity: 'warning',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<ManagerAlert>> _lowStockAlerts(
      String tenantId, InventoryLiteRepository? inventory) async {
    if (inventory == null) return const [];
    try {
      final low = await inventory.lowStock(tenantId);
      return [
        for (final s in low)
          ManagerAlert(
            id: 'stock-${s.itemId}',
            kind: 'stock_low',
            title: 'Stock bas : ${s.itemName} (${s.count} restants)',
            subtitle: 'Seuil d’alerte : ${s.lowThreshold}',
            at: s.updatedAt,
            severity: 'warning',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Badge count: alerts from the last 24h (voids/discounts/failed
  /// payments/86 requests) + current low-stock warnings.
  Future<int> todayAlertCount(
    String tenantId, {
    InventoryLiteRepository? inventory,
  }) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final alerts =
        await recentAlerts(tenantId, limit: 100, inventory: inventory);
    return alerts.where((a) => a.at.isAfter(cutoff)).length;
  }
}

class _OrderFacts {
  const _OrderFacts({required this.offline, required this.rows});

  final bool offline;
  final List<_FactRow> rows;
}

class _FactRow {
  const _FactRow({
    required this.total,
    required this.createdAt,
    required this.channel,
    required this.createdBy,
    required this.lines,
  });

  final int total;
  final DateTime createdAt;
  final String channel;
  final String? createdBy;
  final dynamic lines;
}
