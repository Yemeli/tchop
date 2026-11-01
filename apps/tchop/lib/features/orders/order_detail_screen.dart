import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_typography.dart';
import 'order_models.dart';
import 'order_repository.dart';
import 'order_state_machine.dart';
import 'order_widgets.dart';
import '../payments/refund_screens.dart';

/// Order detail + live tracking.
///
/// - Status timeline with French labels (Reçue → Acceptée → En préparation
///   → Prête → En livraison → Livrée).
/// - Role-gated action buttons (from [OrderPermissions]):
///   secretary → Accepter / Annuler · kitchen → En préparation / Prête ·
///   driver → Récupérée / Livrée · owner/manager → everything.
/// - Every action goes through the outbox as
///   `order/transition {order_id, to}` (optimistic local flip first).
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.tenantId,
    required this.orderId,
  });

  final String tenantId;
  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _acting = false;

  OrderRepository _orders(BuildContext context) {
    final scope = ServicesScope.of(context);
    return scope.orderRepository ??
        OrderRepository(db: scope.db, syncEngine: scope.syncEngine);
  }

  String? _role(BuildContext context) =>
      SessionScope.maybeOf(context)?.role;

  Future<void> _transition(OrderCard card, OrderStatus to) async {
    if (_acting) return;
    if (to == OrderStatus.cancelled) {
      final confirmed = await confirmOrderAction(
        context,
        title: 'Annuler la commande ?',
        message:
            'La commande sera annulée. Cette action est définitive.',
        confirmLabel: 'Annuler la commande',
        danger: true,
      );
      if (!confirmed) return;
    }
    setState(() => _acting = true);
    try {
      await _orders(context).transitionOrder(
        tenantId: widget.tenantId,
        orderId: card.id,
        to: to,
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is IllegalOrderTransition
          ? 'Transition impossible : ${e.from.labelFr} → ${e.to.labelFr}.'
          : 'Échec : $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _role(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Commande')),
      body: StreamBuilder<List<OrderCard>>(
        stream: _orders(context).watchOrderCards(widget.tenantId),
        builder: (context, snapshot) {
          final cards = snapshot.data ?? const [];
          final card = cards.where((c) => c.id == widget.orderId).firstOrNull;
          if (snapshot.connectionState == ConnectionState.waiting &&
              card == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (card == null) {
            // The optimistic order was removed (e.g. a server 409
            // validation conflict deleted the never-created row).
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Commande introuvable sur cet appareil.\n'
                  'Elle a peut-être été rejetée par le serveur '
                  '(menu modifié entre-temps).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final actions =
              OrderPermissions.allowedFrom(role, card.status);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.customerName ?? 'Client',
                          style: TchopTypography.displayMedium,
                        ),
                        if (card.customerPhone != null)
                          Text(
                            card.customerPhone!,
                            style: TchopTypography.bodyMedium.copyWith(
                              color: TchopColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  OrderStatusChip(
                    status: card.status,
                    pendingSync: card.pendingSync,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(card.channelLabelFr)),
                  if (card.tableNumber != null)
                    Chip(
                      avatar: const Icon(Icons.qr_code_2, size: 16),
                      label: Text('Table ${card.tableNumber}'),
                    ),
                  if (card.paymentMethod != null)
                    Chip(
                        label: Text(OrderPaymentMethod.labelFr(
                            card.paymentMethod!))),
                ],
              ),
              if (card.address != null && card.address!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(card.address!)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Articles', style: TchopTypography.titleMedium),
              const SizedBox(height: 4),
              for (final line in card.lines)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${line.qty} × ${_itemLabel(line.itemId)}'),
                  trailing: Text(formatFcfa(line.lineTotal)),
                ),
              const Divider(),
              _AmountRow(
                  label: 'Sous-total',
                  value: formatFcfa(card.subtotal)),
              _AmountRow(
                label: 'Livraison',
                value: card.deliveryFee == 0
                    ? 'Gratuite'
                    : formatFcfa(card.deliveryFee),
              ),
              _AmountRow(
                label: 'Total',
                value: formatFcfa(card.total),
                bold: true,
              ),
              const SizedBox(height: 20),
              Text('Suivi', style: TchopTypography.titleMedium),
              const SizedBox(height: 12),
              OrderTimeline(status: card.status),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Actions', style: TchopTypography.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final to in actions)
                      _ActionButton(
                        label: OrderPermissions.actionLabelFr(to),
                        danger: to == OrderStatus.cancelled,
                        loading: _acting,
                        onPressed: () => _transition(card, to),
                      ),
                  ],
                ),
                if (role == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Connectez-vous avec un compte staff pour agir '
                      'sur cette commande.',
                      style: TextStyle(
                          color: TchopColors.textSecondary, fontSize: 12),
                    ),
                  ),
              ],
              // Feature 7 (Payments): refund entry point — owner/manager only,
              // electronic payments only (cash refunds are handed back at
              // the drawer, no provider flow involved).
              if ((role == 'owner' || role == 'manager') &&
                  card.paymentMethod != null &&
                  card.paymentMethod != OrderPaymentMethod.cash) ...[
                const SizedBox(height: 20),
                Text('Paiement', style: TchopTypography.titleMedium),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RefundButton(
                    orderId: widget.orderId,
                    amountFcfa: card.total,
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  String _itemLabel(String itemId) =>
      itemId.length > 8 ? 'Article ${itemId.substring(0, 8)}…' : itemId;
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? TchopTypography.titleMedium.copyWith(fontWeight: FontWeight.w800)
        : TchopTypography.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final style = danger
        ? FilledButton.styleFrom(backgroundColor: TchopColors.error)
        : null;
    return FilledButton.tonal(
      style: style,
      onPressed: loading ? null : onPressed,
      child: Text(label),
    );
  }
}

/// `firstOrNull` without pulling in `collection`.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
