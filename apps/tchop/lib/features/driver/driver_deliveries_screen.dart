import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding/tenant_brand.dart';
import '../../core/branding/tenant_branding_scope.dart';
import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/order_models.dart';
import '../orders/order_repository.dart';
import '../orders/order_state_machine.dart';
import '../dispatch/dispatch_repository.dart';
import '../dispatch/mqtt_dispatch_service.dart';
import '../dispatch/pod_sheet.dart';

/// Driver app home: this driver's assigned deliveries for the active
/// restaurant workspace.
///
/// Everything renders from the Drift cache (fully offline-capable).
/// Status changes go through the outbox:
/// - "Récupérée" → `order/transition` → `picked_up` (Feature 4 contract)
///   + local `deliveries.picked_up_at` milestone;
/// - "Livrée" → `order/transition` → `delivered`, then the proof-of-delivery
///   sheet (`delivery/complete`).
/// The "Disponible" toggle starts/stops GPS streaming over MQTT
/// (or the clearly-labeled SIMULATION stream when no broker is configured).
class DriverDeliveriesScreen extends StatefulWidget {
  const DriverDeliveriesScreen({super.key});

  @override
  State<DriverDeliveriesScreen> createState() => _DriverDeliveriesScreenState();
}

class _DriverDeliveriesScreenState extends State<DriverDeliveriesScreen> {
  DriverPositionStream? _stream;
  bool _streaming = false;

  @override
  void dispose() {
    _stream?.stop();
    _stream?.dispose();
    super.dispose();
  }

  DispatchRepository _repo(BuildContext context) {
    final services = ServicesScope.of(context);
    return DispatchRepository(
        db: services.db, syncEngine: services.syncEngine);
  }

  Future<void> _toggleStreaming() async {
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId;
    final driverId = session.userId;
    if (tenantId == null || driverId == null) {
      _snack('Session invalide — reconnectez-vous.');
      return;
    }
    if (_streaming) {
      await _stream?.stop();
      _stream?.dispose();
      _stream = null;
      setState(() => _streaming = false);
      return;
    }
    await ForegroundServiceHook.ensureRunning();
    final stream = DriverPositionSource.resolve(
      tenantId: tenantId,
      driverId: driverId,
    );
    try {
      if (stream is MqttDispatchService) {
        await stream.connect(tenantId: tenantId, driverId: driverId);
      } else {
        await stream.start();
      }
      setState(() {
        _stream = stream;
        _streaming = true;
      });
      _snack(stream.isSimulation
          ? 'Position partagée (SIMULATION — aucun courtier MQTT configuré).'
          : 'Position partagée en direct.');
    } catch (e) {
      stream.dispose();
      _snack('Streaming impossible : $e');
    }
  }

  Future<void> _markPickedUp(DeliveryCard card) async {
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId;
    if (tenantId == null) return;
    try {
      // Feature 4 contract: driver-gated order/transition.
      await session.enqueueMutation(
        tenantId: tenantId,
        op: OrderOps.transition,
        entity: 'order',
        entityId: card.orderId,
        payload: {'order_id': card.orderId, 'to': OrderStatus.pickedUp.wire},
      );
      await _repo(context).markPickedUpLocal(deliveryId: card.deliveryId);
    } catch (e) {
      if (mounted) _snack('Échec : $e');
    }
  }

  Future<void> _markDelivered(DeliveryCard card) async {
    final session = SessionScope.of(context, listen: false);
    final tenantId = session.tenantId;
    if (tenantId == null) return;
    try {
      await session.enqueueMutation(
        tenantId: tenantId,
        op: OrderOps.transition,
        entity: 'order',
        entityId: card.orderId,
        payload: {'order_id': card.orderId, 'to': OrderStatus.delivered.wire},
      );
      if (!mounted) return;
      // Proof of delivery AFTER the "Livrée" tap (Feature 6 flow).
      await showProofOfDeliverySheet(
        context: context,
        deliveryId: card.deliveryId,
        orderId: card.orderId,
      );
    } catch (e) {
      if (mounted) _snack('Échec : $e');
    }
  }

  Future<void> _navigate(DeliveryCard card) async {
    Uri uri;
    if (card.dropoffLat != null && card.dropoffLng != null) {
      uri = Uri.parse(
          'geo:${card.dropoffLat},${card.dropoffLng}?q=${card.dropoffLat},${card.dropoffLng}');
    } else if ((card.dropoffAddress ?? '').isNotEmpty) {
      uri = Uri.parse(
          'geo:0,0?q=${Uri.encodeComponent(card.dropoffAddress!)}');
    } else {
      _snack('Adresse de livraison inconnue.');
      return;
    }
    if (!await launchUrl(uri)) {
      if (mounted) _snack('Aucune application de navigation trouvée.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    final session = SessionScope.of(context);
    final tenantId = session.tenantId;
    final driverId = session.userId;
    final services = ServicesScope.of(context);

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
        title: Text('Livraisons · ${brand.name}',
            style: TchopTypography.titleMedium),
        actions: [
          if (_streaming)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(
                  _stream?.isSimulation == true ? 'SIMULATION' : 'EN DIRECT',
                  style: TextStyle(fontSize: 11),
                ),
                backgroundColor: _stream?.isSimulation == true
                    ? TchopColors.warning.withValues(alpha: 64)
                    : TchopColors.success.withValues(alpha: 64),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner: pending outbox ops = unsynced work.
          StreamBuilder<int>(
            stream: services.syncEngine.pendingCount,
            initialData: 0,
            builder: (context, snap) {
              final n = snap.data ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: TchopColors.warning.withValues(alpha: 38),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_outlined,
                        size: 16, color: TchopColors.warning),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Hors ligne — $n modification(s) en attente de synchronisation.',
                        style: TextStyle(
                            color: TchopColors.warning,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: CenteredContent(
              child: tenantId == null || driverId == null
                  ? const Center(
                      child:
                          Text('Connectez-vous pour voir vos livraisons.'))
                  : StreamBuilder<List<DeliveryCard>>(
                    stream: _repo(context)
                        .watchDriverDeliveries(tenantId, driverId),
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final cards = snap.data ?? const [];
                      final pending = cards
                          .where((c) => !c.isDelivered)
                          .toList();
                      if (pending.isEmpty) {
                        return const Center(
                          child: Text(
                            'Aucune livraison assignée.\nActivez « Disponible » pour recevoir des courses.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final waiting = pending
                          .where((c) => !c.isPickedUp)
                          .toList();
                      final ongoing = pending
                          .where((c) => c.isPickedUp)
                          .toList();
                      return _deliveriesView(
                          context, brand, waiting, ongoing);
                    },
                  ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
                        _streaming ? TchopColors.surfaceMuted : brand.primary,
        foregroundColor: Colors.white,
        icon: Icon(_streaming ? Icons.pause : Icons.my_location),
        label: Text(_streaming ? 'En pause' : 'Disponible'),
        onPressed: _toggleStreaming,
      ),
    );
  }

  /// Delivery list: single column on mobile/tablet, two-column card
  /// grid on desktop. Cards are chunked into [Row]s (rather than a
  /// [GridView]) so each card keeps its natural height — no aspect-ratio
  /// overflow with long addresses.
  Widget _deliveriesView(
    BuildContext context,
    TenantBrand brand,
    List<DeliveryCard> waiting,
    List<DeliveryCard> ongoing,
  ) {
    final columns = context.responsiveValue(mobile: 1, tablet: 1, desktop: 2);

    List<Widget> section(String label, List<DeliveryCard> cards) {
      final tiles = <Widget>[_sectionTitle(label, cards.length)];
      if (columns == 1) {
        tiles.addAll(
            [for (final c in cards) _deliveryTile(context, brand, c)]);
        return tiles;
      }
      for (var i = 0; i < cards.length; i += columns) {
        final rowChildren = <Widget>[];
        for (var k = 0; k < columns; k++) {
          if (k > 0) rowChildren.add(const SizedBox(width: 12));
          final card = i + k < cards.length ? cards[i + k] : null;
          rowChildren.add(
            Expanded(
              child: card == null
                  ? const SizedBox.shrink()
                  : _deliveryTile(context, brand, card),
            ),
          );
        }
        tiles.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ),
        );
      }
      return tiles;
    }

    return ListView(
      // Extra bottom padding clears the "Disponible" FAB.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (waiting.isNotEmpty) ...section('En attente', waiting),
        if (ongoing.isNotEmpty) ...section('En cours', ongoing),
      ],
    );
  }

  Widget _sectionTitle(String label, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text('$label · $count',
            style: TchopTypography.titleMedium),
      );

  Widget _deliveryTile(
      BuildContext context, TenantBrand brand, DeliveryCard card) {
    final enCours = card.isPickedUp;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('#${card.orderId.substring(0, 8).toUpperCase()}',
                    style: TchopTypography.titleMedium),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    card.sectionLabelFr,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: enCours
                      ? brand.primary.withValues(alpha: 51)
                      : TchopColors.surfaceMuted,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Naviguer',
                  icon: const Icon(Icons.navigation),
                  onPressed: () => _navigate(card),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(card.dropoffAddress ?? 'Adresse à confirmer',
                style: TchopTypography.bodyMedium),
            const SizedBox(height: 4),
            Text('Frais de course : ${formatFcfa(card.orderTotal)}',
                style: TchopTypography.price),
            const SizedBox(height: 12),
            if (!enCours)
              FilledButton(
                onPressed: () => _markPickedUp(card),
                child: Text(OrderPermissions.actionLabelFr(
                    OrderStatus.pickedUp)), // "Récupérée"
              )
            else
              FilledButton(
                onPressed: () => _markDelivered(card),
                child: Text(OrderPermissions.actionLabelFr(
                    OrderStatus.delivered)), // "Livrée"
              ),
          ],
        ),
      ),
    );
  }
}
