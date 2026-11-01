import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'payment_repository.dart';
import 'payment_security.dart';

/// Cash reconciliation — "Clôture de caisse" (secretary flavor).
///
/// Expected cash = sum of today's delivered orders with payment_method=cash.
/// The cashier counts the drawer, enters the amount, sees the variance
/// ("Écart : +500 FCFA"), then closes the day. The close goes through the
/// outbox (`payments/cash_close`) so it works offline; the server recomputes
/// variance and keeps one close per tenant per business day.
class CashCloseScreen extends StatefulWidget {
  const CashCloseScreen({super.key, this.repository});

  final PaymentRepository? repository;

  @override
  State<CashCloseScreen> createState() => _CashCloseScreenState();
}

class _CashCloseScreenState extends State<CashCloseScreen> {
  int? _expected;
  List<CashClose>? _history;
  final _countedController = TextEditingController();
  bool _closing = false;

  PaymentRepository _repo(BuildContext context) =>
      widget.repository ??
      PaymentRepository(syncEngine: ServicesScope.of(context).syncEngine);

  int get _counted => int.tryParse(
          _countedController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_expected == null) _load();
  }

  @override
  void dispose() {
    _countedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tenantId = SessionScope.of(context, listen: false).tenantId;
    if (tenantId == null) return;
    final repo = _repo(context);
    final expected = await repo.expectedCashToday(tenantId);
    final history = await repo.cashCloseHistory(tenantId);
    if (mounted) {
      setState(() {
        _expected = expected;
        _history = history;
      });
    }
  }

  Future<void> _close() async {
    final tenantId = SessionScope.of(context, listen: false).tenantId;
    if (tenantId == null) return;
    setState(() => _closing = true);
    try {
      await _repo(context).closeCashDay(
        tenantId: tenantId,
        businessDate: DateTime.now(),
        expected: _expected ?? 0,
        counted: _counted,
      );
      await _repo(context).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caisse clôturée.')),
        );
        _countedController.clear();
        setState(() {
          _expected = null;
          _history = null;
        });
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la clôture : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  String _frDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final allowed = session.role == 'owner' ||
        session.role == 'manager' ||
        session.role == 'secretary';
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Clôture de caisse')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'La clôture de caisse est réservée à la secrétaire, au gérant '
              'et au propriétaire.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final expected = _expected;
    final variance =
        expected == null ? 0 : cashVariance(expected: expected, counted: _counted);

    return Scaffold(
      appBar: AppBar(title: const Text('Clôture de caisse')),
      body: expected == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _AmountTile(
                  label: 'Espèces attendues (commandes livrées, payées cash)',
                  amount: expected,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _countedController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Montant compté en caisse (FCFA)',
                    hintText: 'Ex. 86500',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _AmountTile(
                  label: formatVarianceFr(variance),
                  amount: null,
                  accent: variance == 0
                      ? TchopColors.success
                      : variance > 0
                          ? TchopColors.success
                          : TchopColors.error,
                ),
                const SizedBox(height: 8),
                Text(
                  variance == 0
                      ? 'La caisse est juste.'
                      : variance > 0
                          ? 'Surplus en caisse — à justifier si récurrent.'
                          : 'Manquant en caisse — à justifier.',
                  style: TchopTypography.bodySmall
                      .copyWith(color: TchopColors.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _closing ? null : _close,
                  child: _closing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Clôturer la journée'),
                ),
                const SizedBox(height: 32),
                Text('Historique', style: TchopTypography.titleMedium),
                const SizedBox(height: 8),
                if (_history == null)
                  const Center(child: CircularProgressIndicator())
                else if (_history!.isEmpty)
                  Text(
                    'Aucune clôture enregistrée pour le moment.',
                    style: TchopTypography.bodySmall
                        .copyWith(color: TchopColors.textSecondary),
                  )
                else
                  for (final close in _history!)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(_frDate(close.businessDate.toLocal())),
                        subtitle: Text(
                          'Attendu : ${close.expected} FCFA · '
                          'Compté : ${close.counted} FCFA',
                          style: TchopTypography.bodySmall,
                        ),
                        trailing: Text(
                          formatVarianceFr(close.variance),
                          style: TchopTypography.bodyMedium.copyWith(
                            color: close.variance == 0
                                ? TchopColors.success
                                : close.variance > 0
                                    ? TchopColors.success
                                    : TchopColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.label,
    required this.amount,
    this.accent,
  });

  final String label;
  final int? amount;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TchopColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: TchopTypography.bodyMedium)),
          if (amount != null)
            Text('$amount FCFA',
                style: TchopTypography.titleMedium
                    .copyWith(color: accent)),
        ],
      ),
    );
  }
}
