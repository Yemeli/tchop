import 'package:flutter/material.dart';

import '../../core/branding/tenant_branding_scope.dart';
import '../../core/ui/app_settings_scope.dart';
import '../../core/ui/mascot.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';

/// First-run onboarding for the customer flavor — shown exactly once
/// (persisted flag `customer_onboarding_seen` in [AppSettings]).
///
/// Three pages: **Commander / Suivre / Payer**. Copy is honest about what
/// the demo backend does today: live tracking and in-app payment are
/// labeled « bientôt » rather than faked.
class FirstRunOnboardingScreen extends StatefulWidget {
  const FirstRunOnboardingScreen({super.key});

  @override
  State<FirstRunOnboardingScreen> createState() =>
      _FirstRunOnboardingScreenState();
}

class _FirstRunOnboardingScreenState extends State<FirstRunOnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _slides =
      <({MascotSlot slot, String title, String body, String? note})>[
    (
      slot: MascotSlot.emptyCart,
      title: 'Commander',
      body: 'Parcourez le menu du restaurant, composez votre '
          'commande et choisissez le retrait ou la livraison.',
      note: null,
    ),
    (
      slot: MascotSlot.deliveryArrived,
      title: 'Suivre',
      body: 'Voyez votre livreur arriver en direct, du restaurant '
          'jusqu’à votre porte.',
      note: 'Bientôt : suivi en direct — la démo utilise des '
          'positions simulées.',
    ),
    (
      slot: MascotSlot.orderSuccess,
      title: 'Payer',
      body: 'MTN Mobile Money, Orange Money ou espèces à la livraison.',
      note: 'Bientôt : paiement intégré dans l’app — la démo '
          'n’encaisse pas encore.',
    ),
  ];

  Future<void> _finish() async {
    final settings = AppSettingsScope.maybeOf(context);
    await settings?.markCustomerOnboardingSeen();
    // The SessionGate rebuilds on the settings notification and swaps
    // in the storefront; nothing to pop — this screen IS the gate.
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    final last = _index == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Passer'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final slide = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.all(TchopSpacing.xxl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MascotWidget(
                          slot: slide.slot,
                          size: 140,
                          brandColor: brand.primary,
                        ),
                        const SizedBox(height: TchopSpacing.xl),
                        Text(slide.title,
                            style: TchopTypography.displayLarge),
                        const SizedBox(height: TchopSpacing.sm),
                        Text(
                          slide.body,
                          style: TchopTypography.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        if (slide.note != null) ...[
                          const SizedBox(height: TchopSpacing.lg),
                          Container(
                            padding: const EdgeInsets.all(TchopSpacing.md),
                            decoration: BoxDecoration(
                              color: TchopColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(
                                  TchopRadius.small),
                              border: Border.all(
                                  color: TchopColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 18,
                                    color: TchopColors.info),
                                const SizedBox(width: TchopSpacing.sm),
                                Expanded(
                                  child: Text(
                                    slide.note!,
                                    style: TchopTypography.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? brand.primary
                          : TchopColors.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: TchopSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: TchopSpacing.xxl),
              child: last
                  ? BrandButton(
                      label: 'Commencer',
                      icon: Icons.arrow_forward,
                      onPressed: _finish,
                    )
                  : FilledButton(
                      onPressed: () => _pages.nextPage(
                        duration:
                            const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Suivant'),
                    ),
            ),
            const SizedBox(height: TchopSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
