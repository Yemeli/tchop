import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'kitchen_order_sync.dart';

/// Formats an elapsed duration as MM:SS (minutes can exceed 99).
String formatElapsedFr(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}'
      ':${seconds.toString().padLeft(2, '0')}';
}

/// Color of the prep timer: neutral → orange after 10 min → red after 20.
Color elapsedColor(Duration d) {
  if (d >= const Duration(minutes: 20)) return TchopColors.error;
  if (d >= const Duration(minutes: 10)) return TchopColors.warning;
  return TchopColors.textSecondary;
}

/// One ticket on the board. Compact enough for a column, big touch targets
/// only where they matter (tap → detail sheet, advance button).
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.itemNames,
    required this.now,
    required this.onTap,
    this.advanceLabel,
    this.onAdvance,
    this.nightMode = false,
    this.highlight = false,
  });

  final KitchenTicket ticket;
  final Map<String, String> itemNames;
  final DateTime now;
  final VoidCallback onTap;

  /// Label + handler of the one-tap transition button (null when the
  /// active role may not advance this ticket).
  final String? advanceLabel;
  final VoidCallback? onAdvance;
  final bool nightMode;

  /// Briefly true after the ticket arrives — the card flashes its border.
  final bool highlight;

  String _itemName(String itemId) {
    final known = itemNames[itemId];
    if (known != null) return known;
    final hex = itemId.replaceAll('-', '');
    return hex.length >= 4 ? hex.substring(0, 4).toUpperCase() : itemId;
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = ticket.elapsed(now: now);
    final bg = nightMode ? Colors.black : TchopColors.surface;
    final borderColor = nightMode ? Colors.white24 : TchopColors.border;
    final frameColor = highlight
        ? TchopColors.success
        : ticket.pendingSync
            ? TchopColors.warning.withValues(alpha: 153)
            : borderColor;
    return Card(
      color: bg,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: frameColor,
          width: (highlight || ticket.pendingSync) ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    ticket.shortRef,
                    style: TchopTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: nightMode ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChannelBadge(label: ticket.channelBadgeFr),
                  const Spacer(),
                  Icon(Icons.timer_outlined,
                      size: 16, color: elapsedColor(elapsed)),
                  const SizedBox(width: 4),
                  Text(
                    formatElapsedFr(elapsed),
                    style: TchopTypography.bodyMedium.copyWith(
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
                        size: 14, color: TchopColors.warning),
                    SizedBox(width: 4),
                    Text(
                      'En attente de synchro',
                      style: TextStyle(
                        color: TchopColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              for (final line in ticket.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${line.qty}× ${_itemName(line.itemId)}',
                    style: (nightMode
                            ? TchopTypography.bodyMedium
                                .copyWith(color: Colors.white)
                            : TchopTypography.bodyMedium)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              if (ticket.customerSummary != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: TchopColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ticket.customerSummary!,
                        style: TchopTypography.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (advanceLabel != null && onAdvance != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: onAdvance,
                    child: Text(
                      advanceLabel!,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TchopColors.info.withValues(alpha: 46),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: TchopColors.info,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
