import 'package:flutter/material.dart';

import '../../core/adaptive_scaffold.dart';
import '../menu/eighty_six_screen.dart';
import 'kitchen_ticket_board_screen.dart';

/// Kitchen shell: ticket board + 86 availability board behind the
/// [AdaptiveScaffold] navigation chrome (bottom bar on mobile, rail on
/// tablet/desktop). Each destination keeps its own AppBar; the shell only
/// adds the navigation around them.
class KitchenShell extends StatelessWidget {
  const KitchenShell({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: [
        AdaptiveDestination(
          icon: Icons.receipt_long_outlined,
          label: 'Tickets',
          body: KitchenTicketBoardScreen(),
        ),
        AdaptiveDestination(
          icon: Icons.block_outlined,
          label: '86',
          tooltip: 'Plats épuisés',
          body: EightySixScreen(),
        ),
      ],
    );
  }
}
