import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/order_models.dart';
import '../orders/order_repository.dart';
import 'alerts_center_screen.dart';
import 'analytics_repository.dart';
import 'inventory_lite.dart';

/// Manager / owner "Tableau de bord" (Feature 8).
///
/// Period selector (Aujourd'hui / 7 jours / 30 jours), sales cards in FCFA,
/// hand-rolled 14-day bar chart (CustomPainter — no chart dependency),
/// channel split, top items, staff performance. Pull-to-refresh.
///
/// Data: PostgREST aggregates via [AnalyticsRepository], with a Drift-cache
/// fallback when offline (flagged in the UI). Role-gated: owner/manager
/// only — secretaries get the POS, not the numbers.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _Period { day, week, month }

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _Period _period = _Period.day;
  int _reloadToken = 0;

  DateTime get _since {
    final now = DateTime.now();
    switch (_period) {
      case _Period.day:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case _Period.month:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
    }
  }

  String get _periodLabel => switch (_period) {
        _Period.day => 'aujourd’hui',
        _Period.week => '7 derniers jours',
        _Period.month => '30 derniers jours',
      };

  AnalyticsRepository _repo(BuildContext context) =>
      AnalyticsRepository(db: ServicesScope.of(context).db);

  InventoryLiteRepository _inventory(BuildContext context) =>
      InventoryLiteRepository(
          syncEngine: ServicesScope.of(context).syncEngine);

  Future<Map<String, String>> _itemNames(BuildContext context) async {
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    try {
      final repo = ServicesScope.of(context).orderRepository ??
          OrderRepository(
            db: ServicesScope.of(context).db,
            syncEngine: ServicesScope.of(context).syncEngine,
          );
      final menu = await repo.loadPublishedMenu(tenantId);
      if (menu == null) return {};
      return {for (final i in menu.items) i.id: i.name};
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final tenantId = session.tenantId;
    final role = session.role ?? '';
    if (tenantId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tableau de bord')),
        body: const Center(child: Text('Aucun restaurant sélectionné.')),
      );
    }
    if (role != 'owner' && role != 'manager') {
      return Scaffold(
        appBar: AppBar(title: const Text('Tableau de bord')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Le tableau de bord est réservé au gérant et au propriétaire.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            tooltip: 'Centre d’alertes',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AlertsCenterScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _reloadToken++),
        child: CenteredContent(
          child: _AnalyticsBody(
            key: ValueKey('$_period-$_reloadToken'),
            tenantId: tenantId,
            since: _since,
            period: _period,
            periodLabel: _periodLabel,
            onPeriod: (p) => setState(() => _period = p),
            onRetry: () => setState(() => _reloadToken++),
            repo: _repo(context),
            inventory: _inventory(context),
            itemNames: () => _itemNames(context),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({
    super.key,
    required this.tenantId,
    required this.since,
    required this.period,
    required this.periodLabel,
    required this.onPeriod,
    required this.onRetry,
    required this.repo,
    required this.inventory,
    required this.itemNames,
  });

  final String tenantId;
  final DateTime since;
  final _Period period;
  final String periodLabel;
  final ValueChanged<_Period> onPeriod;
  final VoidCallback onRetry;
  final AnalyticsRepository repo;
  final InventoryLiteRepository inventory;
  final Future<Map<String, String>> Function() itemNames;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const OfflineBanner(),
            SegmentedButton<_Period>(
              segments: const [
                ButtonSegment(
                    value: _Period.day, label: Text('Jour')),
                ButtonSegment(
                    value: _Period.week, label: Text('7 jours')),
                ButtonSegment(
                    value: _Period.month, label: Text('30 jours')),
              ],
              selected: {period},
              onSelectionChanged: (s) => onPeriod(s.first),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState == ConnectionState.waiting &&
                data == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError)
              ErrorView(
                // Never leak raw exceptions: the repository throws
                // French-mapped errors; anything else gets a generic line.
                message: 'Les chiffres n’ont pas pu être chargés. '
                    'Vérifiez votre connexion.',
                onRetry: onRetry,
              )
            else if (data != null) ...[
              if (data.summary.offline)
                const Card(
                  color: TchopColors.surfaceMuted,
                  child: ListTile(
                    leading: Icon(Icons.cloud_off_outlined,
                        color: TchopColors.warning),
                    title: Text('Hors-ligne — chiffres du cache local'),
                    subtitle: Text(
                        'Reconnectez-vous pour les chiffres du serveur.'),
                  ),
                ),
              if (data.summary.orderCount == 0)
                EmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: 'Aucune vente sur la période',
                  explanation:
                      'Aucune commande $periodLabel pour l’instant. '
                      'Les chiffres apparaîtront ici dès la première vente.',
                )
              else ...[
              _StatCards(summary: data.summary, periodLabel: periodLabel),
              const SizedBox(height: 16),
              Text('Ventes — 14 derniers jours',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: SizedBox(
                    height: context.responsiveValue(
                        mobile: 180.0, tablet: 220.0, desktop: 260.0),
                    child: _SalesBarChart(days: data.daily),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Canaux de vente — $periodLabel',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              _ChannelSplit(slices: data.channels),
              const SizedBox(height: 16),
              Text('Articles les plus vendus',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              _TopItems(items: data.topItems),
              const SizedBox(height: 16),
              Text('Équipe — $periodLabel',
                  style: TchopTypography.titleMedium),
              const SizedBox(height: 8),
              _StaffList(stats: data.staff, offline: data.summary.offline),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.notifications_outlined, size: 18),
                label: const Text('Centre d’alertes'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AlertsCenterScreen()),
                ),
              ),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<_DashboardData> _load() async {
    final names = await itemNames();
    final results = await Future.wait([
      repo.salesSummary(tenantId, since),
      repo.dailySales(tenantId),
      repo.channelSplit(tenantId, since),
      repo.topItems(tenantId, since, itemNames: names),
      repo.staffPerformance(tenantId, since),
    ]);
    return _DashboardData(
      summary: results[0] as SalesSummary,
      daily: results[1] as List<DailySales>,
      channels: results[2] as List<ChannelSlice>,
      topItems: results[3] as List<TopItem>,
      staff: results[4] as List<StaffStat>,
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.summary,
    required this.daily,
    required this.channels,
    required this.topItems,
    required this.staff,
  });

  final SalesSummary summary;
  final List<DailySales> daily;
  final List<ChannelSlice> channels;
  final List<TopItem> topItems;
  final List<StaffStat> staff;
}

class _StatCards extends StatelessWidget {
  const _StatCards({required this.summary, required this.periodLabel});

  final SalesSummary summary;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'Chiffre d’affaires',
        formatFcfa(summary.revenueFcfa),
        Icons.payments_outlined,
        TchopColors.success,
      ),
      (
        'Commandes',
        '${summary.orderCount}',
        Icons.receipt_long_outlined,
        TchopColors.info,
      ),
      (
        'Ticket moyen',
        formatFcfa(summary.avgTicketFcfa),
        Icons.trending_up_outlined,
        TchopColors.warning,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chiffres — $periodLabel',
            style: TchopTypography.displayMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, icon, color) in cards)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 20),
                        const SizedBox(height: 6),
                        Text(value,
                            style: TchopTypography.price
                                .copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(label,
                            style: TchopTypography.bodySmall,
                            maxLines: 2),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Hand-rolled 14-day sales bar chart (CustomPainter — no dependency).
class _SalesBarChart extends StatelessWidget {
  const _SalesBarChart({required this.days});

  final List<DailySales> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(
        values: [for (final d in days) d.totalFcfa.toDouble()],
        labels: [for (final d in days) '${d.date.day}/${d.date.month}'],
        barColor: TchopColors.defaultAccent,
        gridColor: TchopColors.border,
        labelColor: TchopColors.textSecondary,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.labels,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartH = size.height - bottomPad - topPad;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final n = values.length;
    if (n == 0) return;
    final slot = size.width / n;
    final barW = (slot * 0.55).clamp(4.0, 28.0);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = topPad + chartH * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final bar = Paint()..color = barColor;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final h = maxV <= 0 ? 0.0 : chartH * v / maxV;
      final x = slot * i + (slot - barW) / 2;
      final y = topPad + chartH - h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h.clamp(0.0, chartH)),
          const Radius.circular(3),
        ),
        bar,
      );
      tp.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: labelColor, fontSize: 9),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(slot * i + (slot - tp.width) / 2, size.height - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values || old.labels != labels;
}

class _ChannelSplit extends StatelessWidget {
  const _ChannelSplit({required this.slices});

  final List<ChannelSlice> slices;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucune vente sur la période.'),
        ),
      );
    }
    final maxTotal =
        slices.fold<int>(0, (m, s) => s.totalFcfa > m ? s.totalFcfa : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final s in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(s.labelFr,
                          style: TchopTypography.bodyMedium),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxTotal == 0
                              ? 0
                              : s.totalFcfa / maxTotal,
                          minHeight: 10,
                          backgroundColor: TchopColors.surfaceMuted,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  TchopColors.defaultPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: Text(
                        formatFcfa(s.totalFcfa),
                        style: TchopTypography.price
                            .copyWith(fontSize: 13),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopItems extends StatelessWidget {
  const _TopItems({required this.items});

  final List<TopItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucune vente sur la période.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: TchopColors.surfaceMuted,
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              title: Text(items[i].name),
              subtitle: Text('${items[i].qty} vendus'),
              trailing: Text(formatFcfa(items[i].revenueFcfa),
                  style: TchopTypography.price.copyWith(fontSize: 13)),
            ),
            if (i < items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _StaffList extends StatelessWidget {
  const _StaffList({required this.stats, required this.offline});

  final List<StaffStat> stats;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    if (offline) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Statistiques d’équipe indisponibles hors-ligne (nécessite le serveur).'),
        ),
      );
    }
    if (stats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucune commande attribuée sur la période.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline),
              title: Text(stats[i].labelFr),
              subtitle:
                  Text('${stats[i].orderCount} commandes traitées'),
              trailing: Text(formatFcfa(stats[i].revenueFcfa),
                  style: TchopTypography.price.copyWith(fontSize: 13)),
            ),
            if (i < stats.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
