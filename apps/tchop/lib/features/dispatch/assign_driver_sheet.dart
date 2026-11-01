import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_typography.dart';
import 'dispatch_models.dart';
import 'dispatch_repository.dart';

/// "Assigner un livreur" bottom sheet (owner / manager / secretary).
///
/// Lists the tenant's drivers with the auto-suggested one highlighted
/// ([suggestDriver]: fewest active deliveries, then longest idle).
/// Confirming enqueues the `delivery/assign` outbox op through
/// [DispatchRepository.assignDriver] — the order stays `ready` until the
/// driver marks it `picked_up`.
Future<void> showAssignDriverSheet({
  required BuildContext context,
  required String orderId,
  double? dropoffLat,
  double? dropoffLng,
  String? dropoffAddress,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssignDriverSheet(
      orderId: orderId,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      dropoffAddress: dropoffAddress,
    ),
  );
}

class _AssignDriverSheet extends StatefulWidget {
  const _AssignDriverSheet({
    required this.orderId,
    this.dropoffLat,
    this.dropoffLng,
    this.dropoffAddress,
  });

  final String orderId;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? dropoffAddress;

  @override
  State<_AssignDriverSheet> createState() => _AssignDriverSheetState();
}

class _AssignDriverSheetState extends State<_AssignDriverSheet> {
  late final Future<List<DriverCandidate>> _candidates;
  bool _assigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = ServicesScope.of(context);
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId;
    _candidates = tenantId == null
        ? Future.value(const <DriverCandidate>[])
        : DispatchRepository(db: services.db, syncEngine: services.syncEngine)
            .driverCandidates(tenantId);
  }

  bool get _canAssign {
    final role = SessionScope.of(context, listen: false).role;
    return role == 'owner' || role == 'manager' || role == 'secretary';
  }

  Future<void> _assign(DriverCandidate candidate) async {
    if (_assigning) return;
    setState(() {
      _assigning = true;
      _error = null;
    });
    try {
      final services = ServicesScope.of(context);
      final session = SessionScope.of(context, listen: false);
      final tenantId = session.tenantId;
      if (tenantId == null) throw StateError('Aucun restaurant actif.');
      await DispatchRepository(
        db: services.db,
        syncEngine: services.syncEngine,
      ).assignDriver(
        tenantId: tenantId,
        orderId: widget.orderId,
        driverId: candidate.driverId,
        dropoffLat: widget.dropoffLat,
        dropoffLng: widget.dropoffLng,
        dropoffAddress: widget.dropoffAddress,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Livreur assigné : ${candidate.labelFr()} — la commande reste « Prête » jusqu’à la récupération.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _assigning = false;
          _error = 'Échec de l’assignation : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assigner un livreur', style: TchopTypography.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Le livreur récupère la commande quand elle est prête.',
              style: TextStyle(color: TchopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (!_canAssign)
              const Text(
                'Seuls le propriétaire, le gérant et le secrétariat peuvent assigner un livreur.',
                style: TextStyle(color: TchopColors.error),
              )
            else
              FutureBuilder<List<DriverCandidate>>(
                future: _candidates,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final candidates = snap.data ?? const [];
                  if (candidates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aucun livreur connu pour ce restaurant.\n'
                        'Invitez un livreur (rôle « Livreur ») depuis la gestion du personnel.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final suggested = suggestDriver(candidates);
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = candidates[i];
                        final isSuggested = c.driverId ==
                            suggested?.driverId;
                        return Card(
                          color: isSuggested
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                              : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(c.labelFr().characters.first),
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(c.labelFr())),
                                if (isSuggested)
                                  const Chip(
                                    label: Text('Suggéré',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              c.activeDeliveries == 0
                                  ? 'Disponible'
                                  : '${c.activeDeliveries} livraison(s) en cours',
                            ),
                            trailing: _assigning
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _assigning ? null : () => _assign(c),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: TchopColors.error)),
            ],
          ],
        ),
      ),
    );
  }
}
