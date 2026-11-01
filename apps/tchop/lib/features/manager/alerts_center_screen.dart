import 'package:flutter/material.dart';

import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'analytics_repository.dart';
import 'inventory_lite.dart';

/// Alerts center (Feature 8) — manager / owner only.
///
/// Merged feed, newest first: order voids + discounts (red, from
/// audit_logs), failed payments, pending 86 requests, low-stock warnings.
/// Each row carries its timestamp and actor. The dashboard badge count
/// comes from [AnalyticsRepository.todayAlertCount].
class AlertsCenterScreen extends StatefulWidget {
  const AlertsCenterScreen({super.key});

  @override
  State<AlertsCenterScreen> createState() => _AlertsCenterScreenState();
}

class _AlertsCenterScreenState extends State<AlertsCenterScreen> {
  int _reloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final tenantId = session.tenantId;
    final role = session.role ?? '';
    if (tenantId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alertes')),
        body: const Center(child: Text('Aucun restaurant sélectionné.')),
      );
    }
    if (role != 'owner' && role != 'manager') {
      return Scaffold(
        appBar: AppBar(title: const Text('Alertes')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Le centre d’alertes est réservé au gérant et au propriétaire.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final repo = AnalyticsRepository(db: ServicesScope.of(context).db);
    final inventory = InventoryLiteRepository(
        syncEngine: ServicesScope.of(context).syncEngine);
    return Scaffold(
      appBar: AppBar(title: const Text('Alertes')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => setState(() => _reloadToken++),
              child: FutureBuilder<List<ManagerAlert>>(
                key: ValueKey(_reloadToken),
                future: repo.recentAlerts(tenantId, inventory: inventory),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ErrorView(
                      message: 'Les alertes n’ont pas pu être chargées. '
                          'Vérifiez votre connexion.',
                      onRetry: () => setState(() => _reloadToken++),
                    );
                  }
                  final alerts = snap.data ?? const <ManagerAlert>[];
                  if (alerts.isEmpty) {
                    return EmptyView(
                      icon: Icons.check_circle_outline,
                      title: 'Tout est calme',
                      explanation:
                          'Aucune annulation, remise, paiement échoué, '
                          'rupture (86) ou stock bas signalé.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _AlertCard(alert: alerts[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final ManagerAlert alert;

  (IconData, Color) get _visual => switch (alert.kind) {
        'void' => (Icons.cancel_outlined, TchopColors.error),
        'discount' => (Icons.percent_outlined, TchopColors.error),
        'payment_failed' =>
          (Icons.money_off_outlined, TchopColors.warning),
        'eighty_six' =>
          (Icons.restaurant_menu_outlined, TchopColors.warning),
        'stock_low' =>
          (Icons.inventory_2_outlined, TchopColors.warning),
        _ => (Icons.info_outline, TchopColors.info),
      };

  String get _kindLabel => switch (alert.kind) {
        'void' => 'Annulation',
        'discount' => 'Remise',
        'payment_failed' => 'Paiement',
        'eighty_six' => 'Cuisine',
        'stock_low' => 'Stock',
        _ => 'Info',
      };

  String _frDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visual;
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 31),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(alert.title,
            style: TchopTypography.titleMedium.copyWith(fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert.subtitle != null) Text(alert.subtitle!),
            const SizedBox(height: 2),
            Text(
              [
                _kindLabel,
                if (alert.actorLabel != null) 'par ${alert.actorLabel}',
                '· ${_frDateTime(alert.at)}',
              ].join(' '),
              style: TchopTypography.bodySmall,
            ),
          ],
        ),
        isThreeLine: alert.subtitle != null,
      ),
    );
  }
}
