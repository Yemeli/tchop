import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/branding/tenant_branding_scope.dart';
import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/order_models.dart';
import '../orders/order_repository.dart';
import '../orders/order_state_machine.dart';
import 'assign_driver_sheet.dart';
import 'dispatch_repository.dart';

/// Dispatch board (owner / manager / secretary): ready orders awaiting a
/// driver, each with an "Assigner un livreur" action.
///
/// Reads real orders from the Drift cache via [OrderRepository]; the
/// assignment itself goes through the `delivery/assign` outbox op
/// ([DispatchRepository.assignDriver]). The order stays `ready` until the
/// driver marks it `picked_up`.
class DispatchBoardScreen extends StatelessWidget {
  const DispatchBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    final session = SessionScope.of(context);
    final services = ServicesScope.of(context);
    final tenantId = session.tenantId;
    final orderRepo = services.orderRepository ??
        OrderRepository(db: services.db, syncEngine: services.syncEngine);

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
        title:
            Text('Expéditions · ${brand.name}', style: TchopTypography.titleMedium),
      ),
      body: tenantId == null
          ? const Center(child: Text('Aucun restaurant actif.'))
          : StreamBuilder<List<OrderCard>>(
              stream: orderRepo.watchOrderCards(tenantId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ready = (snap.data ?? const [])
                    .where((o) => o.status == OrderStatus.ready)
                    .toList();
                if (ready.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucune commande prête.\nLes commandes « Prête » apparaîtront ici pour assignation.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return CenteredContent(
                  child: _readyList(context, ready),
                );
              },
            ),
    );
  }

  /// Ready-order list: single column on mobile/tablet, two-column card
  /// grid on desktop. Tiles are chunked into [Row]s so each tile keeps
  /// its natural height — no aspect-ratio overflow.
  Widget _readyList(BuildContext context, List<OrderCard> ready) {
    final columns = context.responsiveValue(mobile: 1, tablet: 1, desktop: 2);
    if (columns == 1) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: ready.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _ReadyOrderTile(order: ready[i]),
      );
    }
    final children = <Widget>[];
    for (var i = 0; i < ready.length; i += columns) {
      final rowChildren = <Widget>[];
      for (var k = 0; k < columns; k++) {
        if (k > 0) rowChildren.add(const SizedBox(width: 12));
        final order = i + k < ready.length ? ready[i + k] : null;
        rowChildren.add(
          Expanded(
            child: order == null
                ? const SizedBox.shrink()
                : _ReadyOrderTile(order: order),
          ),
        );
      }
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowChildren,
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

class _ReadyOrderTile extends StatefulWidget {
  const _ReadyOrderTile({required this.order});

  final OrderCard order;

  @override
  State<_ReadyOrderTile> createState() => _ReadyOrderTileState();
}

class _ReadyOrderTileState extends State<_ReadyOrderTile> {
  bool _loadingDriver = true;
  String? _driverLabel;

  @override
  void initState() {
    super.initState();
    _loadDriver();
  }

  Future<void> _loadDriver() async {
    final session = SessionScope.of(context, listen: false);
    final services = ServicesScope.of(context);
    final tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() => _loadingDriver = false);
      return;
    }
    final delivery = await DispatchRepository(
      db: services.db,
      syncEngine: services.syncEngine,
    ).deliveryForOrder(tenantId, widget.order.id);
    if (!mounted) return;
    setState(() {
      _loadingDriver = false;
      final driverId = delivery?.driverId;
      _driverLabel = (driverId == null || driverId.isEmpty)
          ? null
          : 'Assignée à ${driverId.length <= 8 ? driverId : driverId.substring(0, 8)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('#${order.id.substring(0, 8).toUpperCase()}',
                    style: TchopTypography.titleMedium),
                const SizedBox(width: 8),
                const Chip(
                  label: Text('Prête',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                if (order.pendingSync) ...[
                  const SizedBox(width: 8),
                  const Chip(label: Text('En attente de synchro',
                      style: TextStyle(fontSize: 11))),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              order.address ?? order.customerName ?? 'Sans adresse',
              style: TchopTypography.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${order.lines.length} article(s) · ${formatFcfa(order.total)}',
              style: TchopTypography.bodySmall,
            ),
            if (_driverLabel != null) ...[
              const SizedBox(height: 4),
              Text(_driverLabel!,
                  style: TextStyle(
                      color: TchopColors.success, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.delivery_dining),
              label: Text(_driverLabel == null
                  ? 'Assigner un livreur'
                  : 'Réassigner un livreur'),
              onPressed: _loadingDriver
                  ? null
                  : () async {
                      await showAssignDriverSheet(
                        context: context,
                        orderId: order.id,
                        dropoffAddress: order.address,
                      );
                      if (mounted) {
                        setState(() => _loadingDriver = true);
                        _loadDriver();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
