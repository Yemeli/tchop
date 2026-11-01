import 'package:flutter/material.dart';

import '../core/branding/tenant_brand.dart';
import 'tchop_colors.dart';
import 'tchop_typography.dart';

/// Builds the runtime [ThemeData] for a workspace brand.
///
/// The seed color comes from the tenant (`brand.primary`); everything else —
/// dark-premium surfaces, typography, functional colors — is fixed by the
/// design system. Rebuilds are cheap: this is called whenever the workspace
/// (or its brand JSON) changes.
///
/// When [reducedMotion] is true (accessibility setting), every page
/// transition is instant — no fades, slides, or shared-axis motion.
ThemeData buildTchopTheme(TenantBrand brand, {bool reducedMotion = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brand.primary,
    brightness: Brightness.dark,
    surface: TchopColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TchopColors.background,
    // Reduced-motion: every platform transition becomes an instant swap.
    pageTransitionsTheme: reducedMotion
        ? PageTransitionsTheme(
            builders: {
              for (final platform in TargetPlatform.values)
                platform: const _InstantPageTransitionsBuilder(),
            },
          )
        : null,
    appBarTheme: const AppBarTheme(
      backgroundColor: TchopColors.background,
      foregroundColor: TchopColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: TchopColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TchopColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: TchopColors.surfaceMuted,
      labelStyle: TchopTypography.bodySmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: TchopColors.border),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brand.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: TchopTypography.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TchopTypography.displayLarge,
      displayMedium: TchopTypography.displayMedium,
      titleLarge: TchopTypography.titleLarge,
      titleMedium: TchopTypography.titleMedium,
      bodyMedium: TchopTypography.bodyMedium,
      bodySmall: TchopTypography.bodySmall,
    ),
    dividerColor: TchopColors.border,
  );
}

/// Page transition that renders the new route immediately — no animation.
///
/// Used when the "Réduire les animations" accessibility setting is on.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
