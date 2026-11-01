import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Responsive breakpoints (logical pixels of [MediaQuery] width).
///
/// - **mobile** `< 600` — phones, portrait handsets.
/// - **tablet** `600 – 1100` — large phones landscape, small tablets, iPads.
/// - **desktop** `≥ 1100` — laptops, desktops, landscape tablets, web.
const double kMobileBreakpoint = 600.0;
const double kDesktopBreakpoint = 1100.0;

/// Coarse screen-size bucket used across the app.
enum ScreenSize { mobile, tablet, desktop }

/// Responsive helpers on [BuildContext].
///
/// Usage:
/// ```dart
/// if (context.isDesktop) { ... }
/// final columns = context.responsiveValue(mobile: 2, tablet: 3, desktop: 5);
/// ```
extension ResponsiveContext on BuildContext {
  /// Current bucket from the [MediaQuery] width.
  ScreenSize get screenSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < kMobileBreakpoint) return ScreenSize.mobile;
    if (width < kDesktopBreakpoint) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Picks the value for the current bucket.
  ///
  /// [tablet] defaults to [mobile] (never to [desktop]): a 700 px-wide
  /// window must not receive a layout designed for 1400 px.
  T responsiveValue<T>({required T mobile, T? tablet, required T desktop}) {
    switch (screenSize) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop;
    }
  }

  /// Max content width for centered reading layouts (forms, dashboards).
  /// Phones use the full width; wider screens cap the line length.
  double get contentMaxWidth => responsiveValue(
        mobile: double.infinity,
        tablet: 860,
        desktop: 1200,
      );
}

/// Picks a whole widget subtree per bucket.
///
/// ```dart
/// ResponsiveLayout(
///   mobile: const PhoneBoard(),
///   tablet: const TabletBoard(),
///   desktop: const DesktopBoard(),
/// )
/// ```
/// [tablet] falls back to [mobile] when omitted.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  @override
  Widget build(BuildContext context) {
    switch (context.screenSize) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop;
    }
  }
}

/// Centers [child] and caps its width on tablet/desktop so dashboards,
/// forms and menus don't stretch across ultrawide monitors.
/// Phones render [child] full-bleed.
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: maxWidth ?? context.contentMaxWidth),
        child: child,
      ),
    );
  }
}

/// Dialog wrapper that closes on the Escape key (desktop/web keyboards).
///
/// Flutter's [showDialog] does not bind Escape by default; this helper adds
/// it without changing the dialog's look or barrier behavior.
Future<T?> showResponsiveDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    builder: (dialogContext) => _EscapeCloser(
      child: Builder(builder: builder),
    ),
  );
}

/// Binds the Escape key to [Navigator.maybePop] for its subtree.
///
/// Placed inside the dialog route (not the page), so Escape never pops the
/// underlying screen by accident.
class _EscapeCloser extends StatelessWidget {
  const _EscapeCloser({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      // Autofocus only matters when nothing else in the dialog takes
      // focus; text fields still grab focus normally and Escape keeps
      // working because they are descendants of this subtree.
      child: Focus(autofocus: true, child: child),
    );
  }
}
