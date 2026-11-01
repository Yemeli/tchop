import 'package:flutter/material.dart';

import '../../core/adaptive_scaffold.dart';
import '../../core/session/session_context.dart';
import '../orders/customer_menu_screen.dart';
import 'customer_home_screen.dart';

/// Customer flavor shell: storefront home + full menu.
///
/// Navigation adapts to the screen size: bottom bar on phones,
/// icon rail on tablets, extended rail on desktop.
class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key});

  @override
  Widget build(BuildContext context) {
    // maybeOf: the shell must also build in widget tests without bootstrap's
    // scope. Mirrors the kitchen board's fallback: demo data when no session.
    final tenantId =
        SessionScope.maybeOf(context)?.tenantId ?? 'demo-tenant';
    return AdaptiveScaffold(
      destinations: [
        const AdaptiveDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Accueil',
          body: CustomerHomeScreen(),
        ),
        AdaptiveDestination(
          icon: Icons.restaurant_menu_outlined,
          selectedIcon: Icons.restaurant_menu,
          label: 'Menu',
          body: CustomerMenuScreen(tenantId: tenantId),
        ),
      ],
    );
  }
}
