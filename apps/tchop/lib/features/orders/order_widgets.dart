import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'order_models.dart';
import 'order_state_machine.dart';

/// Shared order UI bits: status chip, tracking timeline, payment form.
///
/// French-first. All money is formatted with [formatFcfa].

Color _statusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.placed:
      return TchopColors.warning;
    case OrderStatus.accepted:
      return TchopColors.info;
    case OrderStatus.preparing:
      return TchopColors.defaultPrimary;
    case OrderStatus.ready:
      return TchopColors.success;
    case OrderStatus.pickedUp:
      return TchopColors.defaultAccent;
    case OrderStatus.delivered:
      return TchopColors.success;
    case OrderStatus.cancelled:
      return TchopColors.textSecondary;
  }
}

/// Pill showing the order status (+ "En attente de synchro" when pending).
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({
    super.key,
    required this.status,
    this.pendingSync = false,
  });

  final OrderStatus status;
  final bool pendingSync;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 31),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 102)),
          ),
          child: Text(
            status.labelFr,
            style: TchopTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (pendingSync)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 14, color: TchopColors.textSecondary),
              SizedBox(width: 4),
              Text(
                'En attente de synchro',
                style: TextStyle(
                    fontSize: 12, color: TchopColors.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Vertical tracking timeline: Reçue → Acceptée → En préparation → Prête →
/// En livraison → Livrée. Cancelled orders show a single "Annulée" state.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled) {
      return _TimelineRow(
        done: true,
        last: true,
        color: TchopColors.textSecondary,
        label: 'Annulée',
        sub: 'La commande a été annulée.',
      );
    }
    final steps = OrderFlow.timeline;
    final currentIdx = steps.indexOf(status);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            done: i <= currentIdx,
            last: i == steps.length - 1,
            color: _statusColor(steps[i]),
            label: steps[i].labelFr,
            sub: _stepHint(steps[i]),
          ),
      ],
    );
  }

  static String? _stepHint(OrderStatus status) {
    switch (status) {
      case OrderStatus.placed:
        return 'Le restaurant a bien reçu votre commande.';
      case OrderStatus.accepted:
        return 'Le restaurant prépare votre commande.';
      case OrderStatus.preparing:
        return 'En cuisine, ça chauffe…';
      case OrderStatus.ready:
        return 'Prête ! Le livreur va la récupérer.';
      case OrderStatus.pickedUp:
        return 'Le livreur est en route.';
      case OrderStatus.delivered:
        return 'Bon appétit !';
      case OrderStatus.cancelled:
        return null;
    }
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.done,
    required this.last,
    required this.color,
    required this.label,
    this.sub,
  });

  final bool done;
  final bool last;
  final Color color;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? color : TchopColors.surfaceMuted,
                ),
                child: Icon(
                  done ? Icons.check : Icons.circle,
                  size: 14,
                  color: done ? Colors.white : TchopColors.textSecondary,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? color : TchopColors.surfaceMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TchopTypography.titleMedium.copyWith(
                      color: done ? null : TchopColors.textSecondary,
                    ),
                  ),
                  if (sub != null && done)
                    Text(sub!,
                        style: TchopTypography.bodySmall
                            .copyWith(color: TchopColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Customer details collected at checkout (name / phone / address +
/// payment method). Validates phone loosely (digits, ≥ 9).
class CheckoutForm extends StatefulWidget {
  const CheckoutForm({
    super.key,
    required this.onSubmit,
    this.initialName = '',
    this.initialPhone = '',
    this.showAddress = true,
    this.submitLabel = 'Commander',
  });

  final void Function({
    required String name,
    required String phone,
    required String address,
    required String paymentMethod,
  }) onSubmit;
  final String initialName;
  final String initialPhone;
  final bool showAddress;
  final String submitLabel;

  @override
  State<CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends State<CheckoutForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  String _paymentMethod = OrderPaymentMethod.mtnMomo;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _phone = TextEditingController(text: widget.initialPhone);
    _address = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Ex. Amina Nkomo',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Nom requis' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              hintText: 'Ex. 690 00 00 00',
              prefixText: '+237 ',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.length < 9 ? 'Numéro invalide' : null;
            },
          ),
          if (widget.showAddress) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Adresse de livraison',
                hintText: 'Quartier, rue, repère…',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Adresse requise' : null,
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Paiement',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final m in OrderPaymentMethod.all)
                DropdownMenuItem(
                  value: m,
                  child: Text(OrderPaymentMethod.labelFr(m)),
                ),
            ],
            onChanged: (v) => setState(() => _paymentMethod = v!),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
              widget.onSubmit(
                name: _name.text.trim(),
                phone: digits.startsWith('237') ? '+$digits' : '+237$digits',
                address: _address.text.trim(),
                paymentMethod: _paymentMethod,
              );
            },
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog for destructive transitions (cancel).
Future<bool> confirmOrderAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmer',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Retour'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: TchopColors.error)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
