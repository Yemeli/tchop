import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../orders/order_state_machine.dart';

/// One pin listed on the [MapPlaceholder].
class MapPin {
  const MapPin({
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
}

/// Graceful fallback when no Google Maps API key is configured
/// (`--dart-define=MAPS_API_KEY` absent).
///
/// A stylized static card listing the route pins plus the same
/// [OrderStatusTimeline] the live map shows — the screen is never broken.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({
    super.key,
    required this.pins,
    required this.currentStatus,
    this.note,
  });

  final List<MapPin> pins;
  final OrderStatus currentStatus;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Carte indisponible — clé API manquante'),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: TchopColors.textSecondary)),
            ],
            const Divider(height: 24),
            for (final pin in pins) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: pin.color.withValues(alpha: 38),
                    child: Icon(pin.icon, color: pin.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pin.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(pin.detail,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: TchopColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            const Divider(height: 24),
            OrderStatusTimeline(current: currentStatus),
          ],
        ),
      ),
    );
  }
}

/// Vertical order-status timeline (Reçue → Livrée), shared by the live map
/// and the [MapPlaceholder].
class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({super.key, required this.current});

  final OrderStatus current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = OrderFlow.timeline;
    final currentIdx = steps.indexOf(current);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= currentIdx
                          ? theme.colorScheme.primary
                          : theme.disabledColor.withValues(alpha: 51),
                    ),
                    child: Icon(
                      i < currentIdx
                          ? Icons.check
                          : i == currentIdx
                              ? Icons.circle
                              : Icons.circle_outlined,
                      size: 16,
                      color: i <= currentIdx
                          ? Colors.white
                          : theme.disabledColor,
                    ),
                  ),
                  if (i < steps.length - 1)
                    Container(
                      width: 2,
                      height: 20,
                      color: i < currentIdx
                          ? theme.colorScheme.primary
                          : theme.disabledColor.withValues(alpha: 51),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  steps[i].labelFr,
                  style: TextStyle(
                    fontWeight: i == currentIdx
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i <= currentIdx ? null : TchopColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
