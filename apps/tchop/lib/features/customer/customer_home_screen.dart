import 'package:flutter/material.dart';

import '../../core/branding/tenant_branding_scope.dart';
import '../../core/branding/workspace_switcher.dart';
import '../../core/responsive.dart';
import '../../core/ui/app_settings_scope.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';

/// Customer storefront home — the branded face of one restaurant's workspace.
///
/// TODO (backend wiring):
///   - load active `menu_snapshots` for this `restaurantId` (Supabase Realtime),
///   - cart state + panier/paiement sheet (MoMo / Orange Money / cash),
///   - live order tracking view (MQTT driver positions on google_maps_flutter).
class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  static const _dishes = [
    ('Poulet DG', '4 500 FCFA', '🍗'),
    ('Ndolé + bâton de manioc', '3 000 FCFA', '🥘'),
    ('Poisson braisé', '5 000 FCFA', '🐟'),
    ('Eru + water fufu', '3 500 FCFA', '🍲'),
  ];

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    // Lite mode: no gradients — the hero becomes a flat brand-color card.
    final liteMode =
        AppSettingsScope.maybeOf(context)?.value.liteMode ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: BrandLogo(
            brandName: brand.name,
            logoUrl: brand.logoUrl,
            background: brand.primary,
            radius: 18,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(brand.name, style: TchopTypography.titleMedium),
            if (brand.tagline != null)
              Text(
                brand.tagline!,
                style: TchopTypography.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // Demo hook: proves runtime white-labeling — switch restaurant,
          // watch the whole app re-theme instantly.
          IconButton(
            tooltip: 'Changer de restaurant (démo)',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => showWorkspaceSwitcher(context),
          ),
          IconButton(
            tooltip: 'Panier',
            icon: const Icon(Icons.shopping_bag_outlined),
            // TODO: open cart sheet.
            onPressed: () {},
          ),
        ],
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          const OfflineBanner(),
          Text('Bon appétit', style: TchopTypography.displayLarge),
          const SizedBox(height: 4),
          Text(
            'Commandez, payez par Mobile Money, suivez votre livreur en direct.',
            style: TchopTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
          // TODO: replace with Rive hero animation (assets/rive/hero.riv).
          Container(
            height: context.responsiveValue(
              mobile: 140.0,
              tablet: 160.0,
              desktop: 180.0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TchopRadius.cardLarge),
              color: liteMode ? brand.primary : null,
              gradient: liteMode
                  ? null
                  : LinearGradient(
                      colors: [brand.primary, brand.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
            ),
            padding: const EdgeInsets.all(20),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Livraison en 30–45 min',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Paiement MTN MoMo · Orange Money · Espèces',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Populaire aujourd’hui', style: TchopTypography.displayMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: context.responsiveValue(
                mobile: 2,
                tablet: 3,
                desktop: 5,
              ),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: _dishes.length,
            itemBuilder: (context, i) {
              final (name, price, emoji) = _dishes[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TODO: 3D dish viewer / food photo (Filament, lazy-loaded).
                      Expanded(
                        child: Center(
                          child: Text(
                            emoji,
                            style: TextStyle(fontSize: 48),
                          ),
                        ),
                      ),
                      Text(name,
                          style: TchopTypography.titleMedium, maxLines: 1),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(price, style: TchopTypography.price),
                          IconButton.filled(
                            onPressed: () {
                              // TODO: add to cart (Drift outbox + optimistic UI).
                            },
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: brand.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          BrandButton(
            label: 'Voir tout le menu',
            icon: Icons.restaurant_menu,
            // TODO: navigate to full menu (daypart-aware).
            onPressed: () {},
          ),
          ],
        ),
      ),
    );
  }
}
