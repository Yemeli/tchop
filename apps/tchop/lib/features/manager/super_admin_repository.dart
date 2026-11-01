import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/session/platform_admin.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';

/// One row of the super-admin tenant list.
class TenantSummary {
  const TenantSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    required this.plan,
    required this.subscriptionStatus,
  });

  final String id;
  final String name;
  final String slug;
  final DateTime createdAt;
  final String plan;
  final String subscriptionStatus;
}

/// Read-only tenant detail for the platform owner.
class TenantDetail {
  const TenantDetail({
    required this.summary,
    required this.monthlyOrderCount,
    required this.monthlySalesFcfa,
    required this.staffCount,
    required this.billingCycle,
    required this.trialEndsAt,
    required this.currentPeriodEnd,
  });

  final TenantSummary summary;
  final int monthlyOrderCount;
  final int monthlySalesFcfa;
  final int staffCount;
  final String billingCycle;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
}

/// Platform-level revenue rollup.
class PlatformRevenue {
  const PlatformRevenue({
    required this.planCounts,
    required this.trialToPaid,
    required this.churned,
    required this.activeTrials,
  });

  /// plan → number of tenants on their latest subscription.
  final Map<String, int> planCounts;

  /// Tenants whose latest subscription is a paid plan in good standing.
  final int trialToPaid;

  /// Tenants whose latest subscription is cancelled.
  final int churned;

  /// Tenants still trialing.
  final int activeTrials;
}

/// Super-admin reads for the platform owner (Feature 8).
///
/// READ-ONLY by design: every method selects aggregates — none of them
/// touches restaurant money. The single write ([setSuspended]) only flips
/// the platform subscription status via the strictly-gated
/// `platform/suspend_tenant` outbox op.
///
/// All entry points re-check [PlatformAdmin.isAdmin] and throw when the
/// caller is not a platform admin (defense in depth — the screens gate too,
/// and the Edge Function re-verifies with the service-role key).
class SuperAdminRepository {
  SuperAdminRepository({required SyncEngine syncEngine}) : _sync = syncEngine;

  final SyncEngine _sync;

  SupabaseClient? get _client => TchopSupabase.clientOrNull;

  Future<SupabaseClient> _requireAdmin() async {
    final client = _client;
    if (client == null) {
      throw StateError('Backend non configuré — console indisponible.');
    }
    if (!await PlatformAdmin.isAdmin()) {
      throw StateError('Accès réservé à l’administrateur de la plateforme.');
    }
    return client;
  }

  /// Latest subscription row per tenant (client-side rollup — the table is
  /// small at platform scale; revisit with an RPC past a few thousand).
  Future<Map<String, Map<String, dynamic>>> _latestSubscriptions(
      SupabaseClient client) async {
    final rows = await client
        .from('subscriptions')
        .select('tenant_id,plan,status,billing_cycle,trial_ends_at,'
            'current_period_end,created_at')
        .order('created_at', ascending: false);
    final latest = <String, Map<String, dynamic>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final tid = '${r['tenant_id']}';
      latest.putIfAbsent(tid, () => r);
    }
    return latest;
  }

  Future<List<TenantSummary>> tenants({String query = ''}) async {
    final client = await _requireAdmin();
    final rows = await client
        .from('tenants')
        .select('id,name,slug,created_at')
        .order('created_at', ascending: false)
        .limit(500);
    final subs = await _latestSubscriptions(client);
    final q = query.trim().toLowerCase();
    final list = <TenantSummary>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final name = '${r['name'] ?? ''}';
      final slug = '${r['slug'] ?? ''}';
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !slug.toLowerCase().contains(q)) {
        continue;
      }
      final sub = subs['${r['id']}'];
      list.add(TenantSummary(
        id: '${r['id']}',
        name: name,
        slug: slug,
        createdAt:
            DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        plan: '${sub?['plan'] ?? '—'}',
        subscriptionStatus: '${sub?['status'] ?? '—'}',
      ));
    }
    return list;
  }

  Future<TenantDetail> tenantDetail(String tenantId) async {
    final client = await _requireAdmin();
    final tenant = await client
        .from('tenants')
        .select('id,name,slug,created_at')
        .eq('id', tenantId)
        .single();
    final subs = await _latestSubscriptions(client);
    final sub = subs[tenantId];

    var orderCount = 0;
    var sales = 0;
    try {
      final since = DateTime.now().subtract(const Duration(days: 30));
      final orders = await client
          .from('orders')
          .select('total')
          .eq('tenant_id', tenantId)
          .neq('status', 'cancelled')
          .gte('created_at', since.toUtc().toIso8601String())
          .limit(5000);
      for (final o in (orders as List).cast<Map<String, dynamic>>()) {
        orderCount++;
        sales += (o['total'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    var staffCount = 0;
    try {
      final members = await client
          .from('memberships')
          .select('id')
          .eq('tenant_id', tenantId)
          .limit(500);
      staffCount = (members as List).length;
    } catch (_) {}

    return TenantDetail(
      summary: TenantSummary(
        id: '${tenant['id']}',
        name: '${tenant['name']}',
        slug: '${tenant['slug']}',
        createdAt: DateTime.tryParse('${tenant['created_at']}') ??
            DateTime.now(),
        plan: '${sub?['plan'] ?? '—'}',
        subscriptionStatus: '${sub?['status'] ?? '—'}',
      ),
      monthlyOrderCount: orderCount,
      monthlySalesFcfa: sales,
      staffCount: staffCount,
      billingCycle: '${sub?['billing_cycle'] ?? '—'}',
      trialEndsAt: sub?['trial_ends_at'] == null
          ? null
          : DateTime.tryParse('${sub!['trial_ends_at']}'),
      currentPeriodEnd: sub?['current_period_end'] == null
          ? null
          : DateTime.tryParse('${sub!['current_period_end']}'),
    );
  }

  Future<PlatformRevenue> platformRevenue() async {
    final client = await _requireAdmin();
    final subs = await _latestSubscriptions(client);
    final planCounts = <String, int>{};
    var trialToPaid = 0;
    var churned = 0;
    var activeTrials = 0;
    for (final sub in subs.values) {
      final plan = '${sub['plan']}';
      final status = '${sub['status']}';
      planCounts[plan] = (planCounts[plan] ?? 0) + 1;
      if (status == 'cancelled') {
        churned++;
      } else if (plan == 'trial' || plan == 'trialing') {
        activeTrials++;
      } else if (status == 'active') {
        trialToPaid++;
      }
    }
    return PlatformRevenue(
      planCounts: planCounts,
      trialToPaid: trialToPaid,
      churned: churned,
      activeTrials: activeTrials,
    );
  }

  /// Suspends or restores a tenant's platform subscription.
  ///
  /// Goes through the outbox (`platform/suspend_tenant`, entity `platform`)
  /// so it is durable + idempotent; the Edge Function re-verifies
  /// `platform_admins` membership with the service-role key before applying.
  /// This flips the SUBSCRIPTION status only — it never moves restaurant
  /// money.
  Future<void> setSuspended({
    required String tenantId,
    required bool suspend,
  }) async {
    await _requireAdmin();
    await _sync.enqueue(
      tenantId: tenantId,
      op: 'platform/suspend_tenant',
      entity: 'platform',
      entityId: tenantId,
      payload: {'tenant_id': tenantId, 'suspend': suspend},
    );
    await _sync.drain();
  }
}
