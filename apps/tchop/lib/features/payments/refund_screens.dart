import 'package:flutter/material.dart';

import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'payment_repository.dart';
import 'payment_security.dart';

/// "Rembourser" button for the order detail screen (owned by Feature 4).
///
/// Step 1 of the four-eyes workflow: an owner/manager files a refund
/// request (`payments/refund_request` via the outbox). Approval happens on
/// [RefundRequestsScreen] by a *different* owner/manager.
///
/// Wiring (Feature 4, one line in the order detail actions row):
/// ```dart
/// RefundButton(orderId: order.id, amountFcfa: order.total)
/// ```
///
/// Give [paymentId] directly when the caller already has the `payments` row;
/// otherwise the button resolves the order's latest succeeded payment
/// itself. Shows an explanatory message when there is nothing to refund.
class RefundButton extends StatefulWidget {
  const RefundButton({
    super.key,
    this.paymentId,
    this.orderId,
    required this.amountFcfa,
    this.repository,
  }) : assert(paymentId != null || orderId != null,
            'RefundButton needs paymentId or orderId');

  /// The `payments` row id for this order's succeeded payment.
  final String? paymentId;

  /// Fallback: the order id, used to resolve the succeeded payment row.
  final String? orderId;

  /// Amount in minor units (FCFA), shown for confirmation.
  final int amountFcfa;

  final PaymentRepository? repository;

  @override
  State<RefundButton> createState() => _RefundButtonState();
}

class _RefundButtonState extends State<RefundButton> {
  final _reasonController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final session = SessionScope.of(context, listen: false);
    if (!session.canManageStaff) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Seuls le propriétaire et le gérant peuvent demander un remboursement.'),
        ),
      );
      return;
    }
    final repo = widget.repository ??
        PaymentRepository(syncEngine: ServicesScope.of(context).syncEngine);
    setState(() => _sending = true);
    final paymentId = widget.paymentId ??
        (widget.orderId == null
            ? null
            : await repo.succeededPaymentIdForOrder(widget.orderId!));
    if (!mounted) return;
    setState(() => _sending = false);
    if (paymentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Aucun paiement encaissé à rembourser pour cette commande.'),
        ),
      );
      return;
    }
    _reasonController.clear();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Demander un remboursement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Montant : ${widget.amountFcfa} FCFA',
              style: TchopTypography.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'La demande devra être approuvée par un autre responsable '
              '(double validation). Le remboursement lui-même est manuel : '
              'l’argent doit être renvoyé depuis votre compte MTN MoMo / '
              'Orange Money / Wave — Tchop ne déplace pas les fonds.',
              style: TchopTypography.bodySmall
                  .copyWith(color: TchopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Motif',
                hintText: 'Ex. commande annulée après paiement',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final r = _reasonController.text.trim();
              if (r.isEmpty) return;
              Navigator.of(context).pop(r);
            },
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await repo.requestRefund(
        tenantId: session.tenantId ?? '',
        paymentId: paymentId,
        reason: reason,
      );
      await repo.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Demande de remboursement envoyée — en attente d’approbation.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _sending ? null : _open,
      icon: const Icon(Icons.undo_outlined, size: 18),
      label: const Text('Rembourser'),
    );
  }
}

/// Step 2 of the four-eyes workflow: pending refund requests awaiting
/// approval by a *different* owner/manager than the requester.
///
/// Approving marks the payment `refunded` in our books and writes an audit
/// entry. It does NOT move money: the screen states explicitly that the
/// money must be returned manually inside the provider's own app — MoMo
/// refunds are limited (MTN exposes no public refund API for collections).
class RefundRequestsScreen extends StatefulWidget {
  const RefundRequestsScreen({super.key, this.repository});

  final PaymentRepository? repository;

  @override
  State<RefundRequestsScreen> createState() => _RefundRequestsScreenState();
}

class _RefundRequestsScreenState extends State<RefundRequestsScreen> {
  List<RefundRequest>? _requests;
  String? _error;

  PaymentRepository _repo(BuildContext context) =>
      widget.repository ??
      PaymentRepository(syncEngine: ServicesScope.of(context).syncEngine);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requests == null && _error == null) _load();
  }

  Future<void> _load() async {
    final tenantId = SessionScope.of(context, listen: false).tenantId;
    if (tenantId == null) return;
    try {
      final reqs = await _repo(context).pendingRefunds(tenantId);
      if (mounted) setState(() => _requests = reqs);
    } catch (e) {
      if (mounted) setState(() => _error = 'Chargement impossible : $e');
    }
  }

  Future<void> _decide(RefundRequest req, bool approve) async {
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId ?? '';
    if (approve) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Approuver le remboursement ?'),
          content: Text(
            '« ${req.reason} » — ${req.amount} FCFA.\n\n'
            'Approuver marque le paiement « remboursé » dans Tchop. '
            'Rappel : le remboursement MANUEL reste à effectuer dans '
            'votre compte MTN MoMo / Orange Money / Wave — Tchop ne '
            'déplace pas les fonds.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Approuver'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    await _repo(context).decideRefund(
      tenantId: tenantId,
      refundId: req.id,
      approve: approve,
    );
    await _repo(context).syncNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve
              ? 'Remboursement approuvé — pensez au remboursement manuel '
                  'dans votre compte du fournisseur.'
              : 'Demande rejetée.'),
        ),
      );
      setState(() => _requests = null);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (!session.canManageStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Remboursements')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Seuls le propriétaire et le gérant peuvent traiter les '
              'remboursements.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final userId = session.userId ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Remboursements en attente')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _requests == null
              ? const Center(child: CircularProgressIndicator())
              : _requests!.isEmpty
                  ? const Center(
                      child: Text('Aucune demande en attente.'),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Double validation : vous ne pouvez pas approuver '
                          'une demande que vous avez vous-même créée.',
                          style: TchopTypography.bodySmall.copyWith(
                              color: TchopColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        for (final req in _requests!)
                          _RefundCard(
                            request: req,
                            canDecide: canApproveRefund(
                              requesterId: req.requestedBy ?? '',
                              approverId: userId,
                              approverRole: session.role ?? '',
                            ),
                            isOwn: req.requestedBy == userId,
                            onDecide: (approve) => _decide(req, approve),
                          ),
                      ],
                    ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({
    required this.request,
    required this.canDecide,
    required this.isOwn,
    required this.onDecide,
  });

  final RefundRequest request;
  final bool canDecide;
  final bool isOwn;
  final Future<void> Function(bool approve) onDecide;

  String _frDateTime(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${request.amount} FCFA',
                    style: TchopTypography.titleMedium),
                Text(
                  _frDateTime(request.requestedAt),
                  style: TchopTypography.bodySmall
                      .copyWith(color: TchopColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(request.reason, style: TchopTypography.bodyMedium),
            if (isOwn) ...[
              const SizedBox(height: 6),
              Text(
                'Vous avez créé cette demande : un autre responsable doit '
                'l’approuver.',
                style: TchopTypography.bodySmall.copyWith(
                  color: TchopColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: canDecide ? () => onDecide(false) : null,
                  child: const Text('Rejeter'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canDecide ? () => onDecide(true) : null,
                  child: const Text('Approuver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
