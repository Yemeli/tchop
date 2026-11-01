import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/services_scope.dart';
import '../../design_system/tchop_typography.dart';
import 'order_detail_screen.dart';
import 'order_models.dart';
import 'order_repository.dart';
import 'order_widgets.dart';

/// Staff order queue: live list of order cards for the tenant (synced rows
/// + optimistic pending creates). Tapping a card opens [OrderDetailScreen].
///
/// NOTE: server pull / Realtime order fan-out is the kitchen/dispatch
/// feature's job — this list renders the on-device cache, which is exact
/// for orders taken on this device and converges as pulls land.
class OrdersListScreen extends StatelessWidget {
  const OrdersListScreen({super.key, required this.tenantId});

  final String tenantId;

  OrderRepository _orders(BuildContext context) {
    final scope = ServicesScope.of(context);
    return scope.orderRepository ??
        OrderRepository(db: scope.db, syncEngine: scope.syncEngine);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      body: StreamBuilder<List<OrderCard>>(
        stream: _orders(context).watchOrderCards(tenantId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final cards = snapshot.data ?? const [];
          if (cards.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune commande pour le moment.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _OrderCardTile(card: cards[i], tenantId: tenantId),
          );
        },
      ),
    );
  }
}

class _OrderCardTile extends StatelessWidget {
  const _OrderCardTile({required this.card, required this.tenantId});

  final OrderCard card;
  final String tenantId;

  @override
  Widget build(BuildContext context) {
    final lineSummary = card.lines
        .map((l) => '${l.qty}× ${_shortName(l.itemId)}')
        .join(', ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(
              tenantId: tenantId,
              orderId: card.id,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.customerName ?? 'Client',
                      style: TchopTypography.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatFcfa(card.total),
                    style: TchopTypography.price,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '#${card.id.substring(0, 8)} · ${card.channelLabelFr}'
                '${card.tableNumber != null ? ' · Table ${card.tableNumber}' : ''}',
                style: TchopTypography.bodySmall
                    .copyWith(color: TchopColors.textSecondary),
              ),
              if (lineSummary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    lineSummary,
                    style: TchopTypography.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),
              OrderStatusChip(
                status: card.status,
                pendingSync: card.pendingSync,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Line items only carry the item id locally; the name resolves once the
  /// server pull lands (kitchen/dispatch feature).
  String _shortName(String itemId) =>
      itemId.length > 8 ? '${itemId.substring(0, 8)}…' : itemId;
}
