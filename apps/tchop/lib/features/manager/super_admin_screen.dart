import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/platform_admin.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/order_models.dart';
import 'platform_config_screen.dart';
import 'super_admin_repository.dart';

/// Super-admin console — the PLATFORM OWNER's read-only dashboard
/// (Feature 8).
///
/// Gated strictly: [PlatformAdmin.isAdmin] (fail-closed) before anything
/// renders. Everything here is read-only aggregates (GMV, staff counts,
/// subscription status) EXCEPT suspend/restore, which only flips the
/// platform subscription status — it never touches restaurant money.
///
/// The banner says it plainly: « Lecture seule — vous ne touchez pas à
/// l’argent des restaurants. »
class SuperAdminScreen extends StatelessWidget {
  const SuperAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PlatformAdmin.isAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Super-admin')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Super-admin')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Accès réservé à l’administrateur de la plateforme.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return const _Console();
      },
    );
  }
}

class _Console extends StatefulWidget {
  const _Console();

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final _search = TextEditingController();
  int _reloadToken = 0;

  SuperAdminRepository _repo(BuildContext context) =>
      SuperAdminRepository(syncEngine: ServicesScope.of(context).syncEngine);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Super-admin')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _reloadToken++),
        child: CenteredContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
          children: [
            const OfflineBanner(),
            // --- the honest banner ---------------------------------------
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TchopColors.warning.withValues(alpha: 31),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: TchopColors.warning.withValues(alpha: 128)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.visibility_outlined,
                      color: TchopColors.warning, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lecture seule — vous ne touchez pas à l’argent '
                      'des restaurants.',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Configuration de la plateforme'),
                subtitle: const Text(
                  'Clés API (Supabase, Google Maps, MQTT) — collées ici, '
                  'actives sans rebuild.',
                  style: TextStyle(
                      color: TchopColors.textSecondary, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PlatformConfigScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Revenus de la plateforme',
                style: TchopTypography.displayMedium),
            const SizedBox(height: 8),
            _RevenueCard(
              key: ValueKey('rev-$_reloadToken'),
              repo: _repo(context),
              onRetry: () => setState(() => _reloadToken++),
            ),
            const SizedBox(height: 16),
            Text('Restaurants', style: TchopTypography.displayMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Rechercher un restaurant',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _TenantList(
              key: ValueKey('tenants-$_reloadToken-${_search.text}'),
              repo: _repo(context),
              query: _search.text,
              onRetry: () => setState(() => _reloadToken++),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({super.key, required this.repo, required this.onRetry});

  final SuperAdminRepository repo;
  final VoidCallback onRetry;

  static const _planLabels = {
    'trial': 'Essai',
    'starter': 'Starter',
    'pro': 'Pro',
    'enterprise': 'Enterprise',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlatformRevenue>(
      future: repo.platformRevenue(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError || snap.data == null) {
          return ErrorView(
            message: 'Les revenus de la plateforme n’ont pas pu être '
                'chargés. Vérifiez votre connexion.',
            onRetry: onRetry,
          );
        }
        final rev = snap.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in rev.planCounts.entries)
                      Chip(
                        label: Text(
                            '${_planLabels[e.key] ?? e.key} : ${e.value}'),
                      ),
                    if (rev.planCounts.isEmpty)
                      const Text('Aucun abonnement.'),
                  ],
                ),
                const SizedBox(height: 12),
                _kv('Essai → payant', '${rev.trialToPaid}'),
                _kv('En essai', '${rev.activeTrials}'),
                _kv('Résiliés (churn)', '${rev.churned}'),
                const Divider(),
                const Text(
                  'MRR : tarifs des formules non configurés — ajoutez-les '
                  'pour calculer le revenu mensuel récurrent.',
                  style: TextStyle(
                      fontSize: 12, color: TchopColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child:
                    Text(label, style: TchopTypography.bodyMedium)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  style: TchopTypography.price,
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}

class _TenantList extends StatelessWidget {
  const _TenantList(
      {super.key,
      required this.repo,
      required this.query,
      required this.onRetry});

  final SuperAdminRepository repo;
  final String query;
  final VoidCallback onRetry;

  Color _statusColor(String status) => switch (status) {
        'active' => TchopColors.success,
        'trialing' => TchopColors.info,
        'past_due' => TchopColors.warning,
        'suspended' => TchopColors.error,
        'cancelled' => TchopColors.textSecondary,
        _ => TchopColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TenantSummary>>(
      future: repo.tenants(query: query),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return ErrorView(
            message: 'La liste des restaurants n’a pas pu être chargée. '
                'Vérifiez votre connexion.',
            onRetry: onRetry,
          );
        }
        final tenants = snap.data ?? const <TenantSummary>[];
        if (tenants.isEmpty) {
          return EmptyView(
            icon: Icons.storefront_outlined,
            title: query.isEmpty
                ? 'Aucun restaurant inscrit'
                : 'Aucun restaurant trouvé',
            explanation: query.isEmpty
                ? 'Les restaurants créés sur la plateforme apparaîtront ici.'
                : 'Aucun restaurant ne correspond à « $query ».',
          );
        }
        return Card(
          child: Column(
            children: [
              for (var i = 0; i < tenants.length; i++) ...[
                ListTile(
                  title: Text(tenants[i].name),
                  // Mobile hides the less-critical slug column.
                  subtitle: Text('Inscrit le ${_frDate(tenants[i].createdAt)}'
                      '${context.isMobile ? '' : ' · ${tenants[i].slug}'}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tenants[i].plan,
                          style: TchopTypography.price
                              .copyWith(fontSize: 13)),
                      Text(
                        tenants[i].subscriptionStatus,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              _statusColor(tenants[i].subscriptionStatus),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _TenantDetailScreen(
                        repo: repo,
                        tenantId: tenants[i].id,
                      ),
                    ),
                  ),
                ),
                if (i < tenants.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  String _frDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _TenantDetailScreen extends StatefulWidget {
  const _TenantDetailScreen({required this.repo, required this.tenantId});

  final SuperAdminRepository repo;
  final String tenantId;

  @override
  State<_TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends State<_TenantDetailScreen> {
  bool _working = false;

  Future<void> _toggleSuspend(TenantDetail detail) async {
    final suspend = detail.summary.subscriptionStatus != 'suspended';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspendre ce restaurant ?' : 'Réactiver ce restaurant ?'),
        content: Text(
          suspend
              ? '« ${detail.summary.name} » passera en statut « suspended ». '
                'L’abonnement est gelé ; vous ne touchez à aucun fonds — '
                'cette action ne fait que changer le statut plateforme.'
              : '« ${detail.summary.name} » repassera en statut « active ».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: suspend
                ? FilledButton.styleFrom(
                    backgroundColor: TchopColors.error)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(suspend ? 'Suspendre' : 'Réactiver'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.repo.setSuspended(
          tenantId: widget.tenantId, suspend: suspend);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(suspend
              ? 'Restaurant suspendu (file de synchro).'
              : 'Restaurant réactivé (file de synchro).'),
        ),
      );
      setState(() => _working = false);
      // Refresh the detail (re-push a fresh screen state).
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail restaurant')),
      body: FutureBuilder<TenantDetail>(
        future: widget.repo.tenantDetail(widget.tenantId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Chargement impossible : ${snap.error}'),
            ));
          }
          final d = snap.data!;
          final suspended =
              d.summary.subscriptionStatus == 'suspended';
          return CenteredContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
            children: [
              Text(d.summary.name,
                  style: TchopTypography.displayMedium),
              Text(d.summary.slug,
                  style: TchopTypography.bodySmall),
              const SizedBox(height: 12),
              _kv('Formule', d.summary.plan),
              _kv('Statut abonnement', d.summary.subscriptionStatus),
              _kv('Cycle de facturation', d.billingCycle),
              const Divider(),
              Text('Activité — 30 derniers jours',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              _kv('Volume de commandes', '${d.monthlyOrderCount}'),
              _kv('Ventes totales (GMV)',
                  formatFcfa(d.monthlySalesFcfa)),
              _kv('Équipe (membres)', '${d.staffCount}'),
              const Divider(),
              const Text(
                'Lecture seule : ces chiffres sont des agrégats. '
                'Vous ne touchez pas à l’argent du restaurant.',
                style: TextStyle(
                    fontSize: 12, color: TchopColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(suspended
                        ? Icons.play_arrow_outlined
                        : Icons.pause_outlined),
                style: suspended
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: TchopColors.error),
                label: Text(_working
                    ? 'Envoi…'
                    : suspended
                        ? 'Réactiver le restaurant'
                        : 'Suspendre le restaurant'),
                onPressed: _working ? null : () => _toggleSuspend(d),
              ),
            ],
          ),
        );
        },
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child:
                    Text(label, style: TchopTypography.bodyMedium)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  style: TchopTypography.price,
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}
