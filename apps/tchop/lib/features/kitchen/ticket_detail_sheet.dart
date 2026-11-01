import 'package:flutter/material.dart';

import '../../core/services_scope.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../menu/menu_permissions.dart';
import '../orders/order_models.dart';
import '../orders/order_state_machine.dart';
import 'kitchen_order_sync.dart';
import 'ticket_card.dart';

/// Opens the ticket detail bottom sheet: customer info, item lines with a
/// prominent per-line 86 button, and big one-tap transition buttons.
///
/// The 86 flow reuses Feature 3's contract:
/// - owner / manager / head_chef → direct 86 toggle
///   ([AvailabilityBroadcaster.setAvailability]);
/// - kitchen role → "Demander épuisement" → `menu/request_86` to the
///   manager's approvals inbox ([MenuRepository.request86]).
Future<void> showTicketDetailSheet({
  required BuildContext context,
  required KitchenTicket ticket,
  required Map<String, String> itemNames,
  required String tenantId,
  required String? role,
  required String? userId,
  required DateTime now,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: TchopColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TicketDetailSheet(
      ticket: ticket,
      itemNames: itemNames,
      tenantId: tenantId,
      role: role,
      userId: userId,
      now: now,
    ),
  );
}

class _TicketDetailSheet extends StatefulWidget {
  const _TicketDetailSheet({
    required this.ticket,
    required this.itemNames,
    required this.tenantId,
    required this.role,
    required this.userId,
    required this.now,
  });

  final KitchenTicket ticket;
  final Map<String, String> itemNames;
  final String tenantId;
  final String? role;
  final String? userId;
  final DateTime now;

  @override
  State<_TicketDetailSheet> createState() => _TicketDetailSheetState();
}

class _TicketDetailSheetState extends State<_TicketDetailSheet> {
  final Set<String> _busy86 = {};
  bool _advancing = false;

  KitchenTicket get ticket => widget.ticket;
  String _itemName(String itemId) => widget.itemNames[itemId] ?? itemId;

  @override
  Widget build(BuildContext context) {
    final elapsed = ticket.elapsed(now: widget.now);
    final actions = OrderPermissions.allowedFrom(widget.role, ticket.status)
        .where((to) =>
            to == OrderStatus.preparing ||
            to == OrderStatus.ready ||
            to == OrderStatus.cancelled)
        .toList();
    final canToggle86 = MenuPermissions.canToggle86(widget.role);
    final canRequest86 = MenuPermissions.canRequest86(widget.role);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: TchopColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(ticket.shortRef,
                    style: TchopTypography.displayMedium
                        .copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Text(ticket.channelBadgeFr,
                    style: TextStyle(
                        color: TchopColors.info,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Icon(Icons.timer_outlined,
                    size: 18, color: elapsedColor(elapsed)),
                const SizedBox(width: 4),
                Text(
                  formatElapsedFr(elapsed),
                  style: TchopTypography.titleMedium.copyWith(
                    color: elapsedColor(elapsed),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (ticket.pendingSync) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 16, color: TchopColors.warning),
                  SizedBox(width: 6),
                  Text('En attente de synchro',
                      style: TextStyle(
                          color: TchopColors.warning,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _sectionTitle('Note client'),
            if (ticket.customerSummary != null)
              Text(ticket.customerSummary!, style: TchopTypography.bodyMedium)
            else
              const Text('—', style: TchopTypography.bodyMedium),
            const SizedBox(height: 12),
            _sectionTitle('Articles (${ticket.totalQty})'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final line in ticket.lines)
                    _lineRow(context, line, canToggle86, canRequest86),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TchopTypography.titleMedium),
                Text(formatFcfa(ticket.totalCents),
                    style: TchopTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            // Big touch targets — kitchen hands are busy/wet.
            for (final to in actions) ...[
              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: _advancing ? null : () => _advance(context, to),
                  style: FilledButton.styleFrom(
                    backgroundColor: to == OrderStatus.cancelled
                        ? TchopColors.error
                        : null,
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  child: _advancing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(OrderPermissions.actionLabelFr(to)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 56,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          title,
          style: TchopTypography.bodySmall.copyWith(
            color: TchopColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _lineRow(BuildContext context, OrderLine line, bool canToggle86,
      bool canRequest86) {
    final name = _itemName(line.itemId);
    final busy = _busy86.contains(line.itemId);
    Widget? trailing;
    if (canToggle86 || canRequest86) {
      trailing = busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : OutlinedButton(
              onPressed: () => _on86(context, line, canToggle86),
              style: OutlinedButton.styleFrom(
                foregroundColor: TchopColors.error,
                side: const BorderSide(color: TchopColors.error, width: 1.5),
                minimumSize: const Size(72, 44),
              ),
              child: Text(canToggle86 ? '86' : '86 ?',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TchopColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${line.qty}×',
              style: TchopTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TchopTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(formatFcfa(line.lineTotal),
                    style: TchopTypography.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// Per-line 86: direct toggle for owner/manager/head_chef, approval
  /// request for the kitchen role (Feature 3's flow, reused here).
  Future<void> _on86(
      BuildContext context, OrderLine line, bool canToggle86) async {
    final services = ServicesScope.of(context);
    final name = _itemName(line.itemId);
    setState(() => _busy86.add(line.itemId));
    try {
      if (canToggle86) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Retirer du menu ?'),
            content: Text(
                '« $name » sera marqué épuisé pour tous les clients, immédiatement.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Non'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                    backgroundColor: TchopColors.error),
                child: const Text('Oui, épuiser'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await services.availabilityBroadcaster.setAvailability(
          tenantId: widget.tenantId,
          itemId: line.itemId,
          available: false,
          requestedBy: widget.userId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('« $name » marqué épuisé.'),
              backgroundColor: TchopColors.error));
        }
      } else {
        // Kitchen role: "Demander épuisement" → manager's approvals inbox.
        await services.menuRepository.request86(
          tenantId: widget.tenantId,
          itemId: line.itemId,
          itemName: name,
          requestedBy: widget.userId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Demande envoyée pour « $name » — en attente du manager.')));
        }
      }
    } finally {
      if (mounted) setState(() => _busy86.remove(line.itemId));
    }
  }

  /// One-tap transition: optimistic local flip + `order/transition` outbox
  /// op via the orders feature (Feature 4's contract).
  Future<void> _advance(BuildContext context, OrderStatus to) async {
    final services = ServicesScope.of(context);
    final repo = services.orderRepository;
    if (repo == null) return;
    setState(() => _advancing = true);
    try {
      await repo.transitionOrder(
        tenantId: widget.tenantId,
        orderId: ticket.id,
        to: to,
      );
      if (context.mounted) Navigator.of(context).pop();
    } on IllegalOrderTransition {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Transition impossible — le ticket a changé.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec — réessayez.')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }
}
