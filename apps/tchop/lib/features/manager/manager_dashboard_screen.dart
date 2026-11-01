import 'package:flutter/material.dart';

import '../../core/adaptive_scaffold.dart';
import '../../core/branding/tenant_branding_scope.dart';
import '../../core/services_scope.dart';
import '../../core/session/platform_admin.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/pos_intake_screen.dart';
import '../payments/cash_close_screen.dart';
import '../payments/payment_connections_screen.dart';
import '../payments/refund_screens.dart';
import '../menu/menu_studio_screen.dart';
import '../dispatch/dispatch_board_screen.dart';
import 'alerts_center_screen.dart';
import 'analytics_repository.dart';
import 'analytics_screen.dart';
import 'inventory_lite.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import 'super_admin_screen.dart';

/// Workspace control room (Feature 8 hub).
///
/// Strictly role-gated:
/// - `secretary` → POS workstation + daily cash-up ONLY (no numbers, no
///   menu, no super-admin);
/// - `owner` / `manager` → full hub: analytics ("Tableau de bord"),
///   alerts center (badge), POS, stock, menu, dispatch, refunds, cash
///   close — plus the "Super-admin" section when (and only when)
///   [PlatformAdmin.isAdmin] (the platform owner).
class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final tenantId = session.tenantId;
    if (tenantId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pilotage')),
        body: const Center(
            child: Text('Aucun restaurant sélectionné.')),
      );
    }
    final role = session.role ?? '';
    if (role == 'secretary') return _SecretaryHome(tenantId: tenantId);
    return _ManagerHome(tenantId: tenantId);
  }
}

/// Secretary home: the till and nothing else — one tap away via tabs.
class _SecretaryHome extends StatelessWidget {
  const _SecretaryHome({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: [
        AdaptiveDestination(
          icon: Icons.point_of_sale_outlined,
          label: 'Caisse',
          body: PosIntakeScreen(tenantId: tenantId),
        ),
        const AdaptiveDestination(
          icon: Icons.calculate_outlined,
          label: 'Clôture',
          body: CashCloseScreen(),
        ),
      ],
    );
  }
}

/// Owner / manager home: tab shell — hub + one-tap access to the till,
/// the menu studio and dispatch.
class _ManagerHome extends StatelessWidget {
  const _ManagerHome({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: [
        AdaptiveDestination(
          icon: Icons.dashboard_outlined,
          label: 'Pilotage',
          body: _HubBody(tenantId: tenantId),
        ),
        AdaptiveDestination(
          icon: Icons.point_of_sale_outlined,
          label: 'Caisse',
          body: PosIntakeScreen(tenantId: tenantId),
        ),
        const AdaptiveDestination(
          icon: Icons.restaurant_menu_outlined,
          label: 'Menu',
          body: MenuStudioScreen(),
        ),
        const AdaptiveDestination(
          icon: Icons.delivery_dining_outlined,
          label: 'Expéditions',
          body: DispatchBoardScreen(),
        ),
      ],
    );
  }
}

/// The hub content with its own Scaffold + AppBar (alert bell, payments,
/// settings): kept as an [AdaptiveDestination] body so the shell's
/// navigation chrome wraps it on every screen size.
class _HubBody extends StatelessWidget {
  const _HubBody({required this.tenantId});

  final String tenantId;

  void _go(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: BrandLogo(
            brandName: brand.name,
            logoUrl: brand.logoUrl,
            background: brand.primary,
            radius: 18,
          ),
        ),
        title: Text('Pilotage · ${brand.name}',
            style: TchopTypography.titleMedium),
        actions: [
          _AlertBell(tenantId: tenantId),
          IconButton(
            tooltip: 'Paiements du restaurant',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () =>
                _go(context, const PaymentConnectionsScreen()),
          ),
          IconButton(
            tooltip: 'Paramètres',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _go(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pilotage', style: TchopTypography.displayMedium),
          const SizedBox(height: 12),
          BrandButton(
            label: 'Tableau de bord — ventes & équipe',
            icon: Icons.insights_outlined,
            onPressed: () => _go(context, const AnalyticsScreen()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: const Text('Caisse (POS)'),
                  onPressed: () => _go(
                      context, PosIntakeScreen(tenantId: tenantId)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Stock'),
                  onPressed: () =>
                      _go(context, const InventoryScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Opérations', style: TchopTypography.displayMedium),
          const SizedBox(height: 12),
          BrandButton(
            label: 'Gérer le menu',
            icon: Icons.restaurant_menu,
            onPressed: () => _go(context, const MenuStudioScreen()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon:
                      const Icon(Icons.delivery_dining_outlined, size: 18),
                  label: const Text('Expéditions'),
                  onPressed: () =>
                      _go(context, const DispatchBoardScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.undo_outlined, size: 18),
                  label: const Text('Remboursements'),
                  onPressed: () =>
                      _go(context, const RefundRequestsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('Clôture de caisse'),
            onPressed: () => _go(context, const CashCloseScreen()),
          ),
          const SizedBox(height: 20),
          _SuperAdminSection(tenantId: tenantId),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// App-bar bell with today's alert count badge → alerts center.
class _AlertBell extends StatelessWidget {
  const _AlertBell({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context) {
    final repo = AnalyticsRepository(db: ServicesScope.of(context).db);
    final inventory = InventoryLiteRepository(
        syncEngine: ServicesScope.of(context).syncEngine);
    return FutureBuilder<int>(
      future: repo.todayAlertCount(tenantId, inventory: inventory),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Alertes',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AlertsCenterScreen()),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: TchopColors.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Super-admin" section — rendered ONLY for the platform owner.
class _SuperAdminSection extends StatelessWidget {
  const _SuperAdminSection({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PlatformAdmin.isAdmin(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Plateforme', style: TchopTypography.displayMedium),
            const SizedBox(height: 12),
            Card(
              color: TchopColors.surfaceMuted,
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined,
                    color: TchopColors.warning),
                title: const Text('Console Super-admin'),
                subtitle: const Text(
                    'Restaurants, abonnements, revenus plateforme — lecture seule.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SuperAdminScreen()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
