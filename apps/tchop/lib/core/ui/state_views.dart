import 'package:flutter/material.dart';

import '../../core/services_scope.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'mascot.dart';

/// Canonical state views: every screen gets a designed offline banner,
/// empty state (title + explanation + CTA) and error state with retry.
///
/// French-first copy throughout. All views consume the F1 design tokens —
/// no hardcoded hex, no light-mode leftovers.

/// Full-width connectivity banner. Shows only while the sync engine
/// reports offline; hidden otherwise (returns a zero-size box).
///
/// Consolidates the ad-hoc banners previously scattered across screens
/// (kitchen board, driver deliveries, workspace onboarding).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.message =
        'Hors ligne — vos actions sont enregistrées et seront synchronisées.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.maybeOf(context);
    final stream = services?.syncEngine.online;
    // Screens constructed in tests without a ServicesScope still render
    // the banner — honest default when connectivity is unknown.
    if (stream == null) return _banner();
    return StreamBuilder<bool>(
      stream: stream,
      initialData: true,
      builder: (context, snapshot) =>
          snapshot.data == true ? const SizedBox.shrink() : _banner(),
    );
  }

  Widget _banner() => Container(
        width: double.infinity,
        color: TchopColors.warning.withValues(alpha: 38),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off,
                size: 16, color: TchopColors.warning),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: TchopColors.warning,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Centered loading state with an accessible label.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Chargement…'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: TchopSpacing.sm),
            Text(label, style: TchopTypography.bodyMedium),
          ],
        ),
      );
}

/// Designed empty state: mascot (or icon) + title + explanation + CTA.
///
/// The mascot plays its Rive animation when brand artwork is registered;
/// otherwise it falls back to a drawn illustration, and in reduced-motion
/// / lite mode it always renders the static frame.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.explanation,
    this.icon,
    this.mascotSlot,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final String explanation;
  final IconData? icon;
  final MascotSlot? mascotSlot;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TchopSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mascotSlot != null)
              MascotWidget(slot: mascotSlot!, size: 96)
            else if (icon != null)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: TchopColors.surfaceMuted,
                  borderRadius:
                      BorderRadius.circular(TchopRadius.card),
                ),
                child: Icon(icon,
                    size: 36, color: TchopColors.textSecondary),
              ),
            const SizedBox(height: TchopSpacing.lg),
            Text(
              title,
              style: TchopTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TchopSpacing.sm),
            Text(
              explanation,
              style: TchopTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: TchopSpacing.lg),
              FilledButton(
                onPressed: onCta,
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Designed error state with a retry button.
///
/// [message] should already be user-facing French; raw exceptions are
/// never shown verbatim — callers map them first.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Réessayer',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TchopSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: TchopColors.error.withValues(alpha: 31),
                borderRadius:
                    BorderRadius.circular(TchopRadius.card),
              ),
              child: const Icon(Icons.error_outline,
                  size: 36, color: TchopColors.error),
            ),
            const SizedBox(height: TchopSpacing.lg),
            const Text(
              'Quelque chose s’est mal passé',
              style: TchopTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TchopSpacing.sm),
            Text(
              message,
              style: TchopTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TchopSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header pattern: title on the left, optional action on the right.
///
/// Used everywhere a screen previously hand-rolled
/// `Text(style: displayMedium)` + spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TchopTypography.displayMedium),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}
