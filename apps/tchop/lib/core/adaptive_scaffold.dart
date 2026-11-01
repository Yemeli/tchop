import 'package:flutter/material.dart';

import 'responsive.dart';

/// One tab of an [AdaptiveScaffold].
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.label,
    required this.body,
    this.selectedIcon,
    this.tooltip,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final String? tooltip;

  /// The screen content. May be a full [Scaffold] (own AppBar included) —
  /// the shell only adds the navigation chrome around it.
  final Widget body;
}

/// App shell shared by every flavor's home screen.
///
/// - **mobile** → [NavigationBar] (bottom tabs).
/// - **tablet** → [NavigationRail] (icons + labels).
/// - **desktop** → extended [NavigationRail] (icons + full labels).
///
/// Each [AdaptiveDestination.body] is kept alive in an [IndexedStack], so
/// switching tabs never loses scroll position or form state. With a single
/// destination the shell renders the body with no navigation chrome.
///
/// Bodies keep their own AppBar/Scaffold: the shell only wraps them, so
/// existing screens migrate by moving their content into a destination.
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    this.initialIndex = 0,
    this.onDestinationSelected,
    this.extendRailOnDesktop = true,
  }) : assert(destinations.length > 0,
            'AdaptiveScaffold needs at least one destination');

  final List<AdaptiveDestination> destinations;
  final int initialIndex;
  final ValueChanged<int>? onDestinationSelected;

  /// When false, the desktop rail stays compact (icons + labels).
  final bool extendRailOnDesktop;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.destinations.length - 1);
  }

  void _select(int i) {
    if (i == _index || i >= widget.destinations.length) return;
    setState(() => _index = i);
    widget.onDestinationSelected?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    // Single destination: no chrome at all — just the screen.
    if (widget.destinations.length == 1) {
      return widget.destinations.first.body;
    }
    return ResponsiveLayout(
      mobile: Scaffold(
        body: _bodies,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final d in widget.destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon:
                    d.selectedIcon == null ? null : Icon(d.selectedIcon),
                label: d.label,
                tooltip: d.tooltip ?? d.label,
              ),
          ],
        ),
      ),
      tablet: _railShell(extended: false),
      desktop: _railShell(extended: widget.extendRailOnDesktop),
    );
  }

  Widget get _bodies => IndexedStack(
        index: _index,
        children: [for (final d in widget.destinations) d.body],
      );

  Widget _railShell({required bool extended}) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelType:
                extended ? null : NavigationRailLabelType.selected,
            leading: extended ? const SizedBox(height: 12) : null,
            destinations: [
              for (final d in widget.destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: d.selectedIcon == null
                      ? null
                      : Icon(d.selectedIcon),
                  label: Text(d.label),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _bodies),
        ],
      ),
    );
  }
}
