import 'package:flutter/material.dart';

import '../../core/flavor.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui/app_settings_scope.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';

/// "Paramètres" — device-level accessibility & performance settings.
///
/// Open to every authenticated role (no role-gating beyond the existing
/// screen guards): the toggles live on the device, not in the workspace.
/// Reached from the manager dashboard's gear icon.
///
/// - **Réduire les animations** → kitchen timers refresh as text every
///   30 s, new-ticket beep/flash off, page transitions instant, mascot
///   shows a static frame.
/// - **Mode allégé** → no gradients/shadows/blur, no mascot animation,
///   tracking uses the list-mode map placeholder, kitchen tick 30 s,
///   images stay thumbnails.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: controller,
        builder: (context, settings, _) => ListView(
          padding: const EdgeInsets.all(TchopSpacing.lg),
          children: [
            const _SectionTitle('Accessibilité'),
            SwitchListTile(
              title: const Text('Réduire les animations'),
              subtitle: const Text(
                'Minuteurs cuisine en texte toutes les 30 s, alertes '
                'sonores et visuelles désactivées, transitions instantanées.',
              ),
              value: settings.reducedMotion,
              onChanged: (v) => controller.update(
                settings.copyWith(reducedMotion: v),
              ),
            ),
            const SizedBox(height: TchopSpacing.lg),
            const _SectionTitle('Performances'),
            if (settings.liteSuggested && !settings.liteMode)
              Card(
                color: TchopColors.info.withValues(alpha: 31),
                child: Padding(
                  padding: const EdgeInsets.all(TchopSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed_outlined,
                              color: TchopColors.info, size: 20),
                          SizedBox(width: TchopSpacing.sm),
                          Expanded(
                            child: Text(
                              'Cet appareil semble lent au démarrage. '
                              'Le mode allégé peut fluidifier l’app.',
                              style: TchopTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TchopSpacing.sm),
                      FilledButton(
                        onPressed: () => controller.update(
                          settings.copyWith(liteMode: true),
                        ),
                        child: const Text('Activer le mode allégé'),
                      ),
                    ],
                  ),
                ),
              ),
            SwitchListTile(
              title: const Text('Mode allégé'),
              subtitle: const Text(
                'Désactive dégradés, ombres et animations ; la carte de '
                'suivi devient une liste ; images en miniatures uniquement. '
                'Recommandé sur les appareils modestes.',
              ),
              value: settings.liteMode,
              onChanged: (v) =>
                  controller.update(settings.copyWith(liteMode: v)),
            ),
            const SizedBox(height: TchopSpacing.lg),
            const _SectionTitle('À propos'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Tchop'),
              subtitle: Text(
                'Version 0.1.0+1 · saveur ${resolveFlavor().appLabel}',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: TchopSpacing.lg),
              child: Text(
                'Les réglages ci-dessus sont enregistrés sur cet appareil '
                'uniquement — ils suivent le téléphone, pas le restaurant.',
                style: TchopTypography.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: TchopSpacing.sm),
        child: Text(title, style: TchopTypography.displayMedium),
      );
}
