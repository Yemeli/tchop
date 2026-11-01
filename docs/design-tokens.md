# Design tokens — Tchop (« dark premium + warm appetite »)

Référence des tokens F1 + ajouts Feature 9. Règle d'or : **aucun hexadécimal
hors `lib/design_system/`** (vérifié par `grep -rn "Color(0x"
apps/tchop/lib --include="*.dart"`), **aucun `Colors.<material>`**
(`amber`/`grey`/`red`/…) hors du design system — tout passe par les tokens
ci-dessous.

## 1. Couleurs — `TchopColors` (`design_system/tchop_colors.dart`)

Surfaces sombres qui font ressortir la nourriture ; texte chaud sur fond
noir. Ces couleurs **ne changent jamais par tenant** — le tenant ne contrôle
que sa marque (`TenantBrand.primary/secondary/accent`), jamais les couleurs
fonctionnelles.

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `0xFF0D0D0D` | Fond d'écran (`scaffoldBackgroundColor`) |
| `surface` | `0xFF161616` | Cartes (`cardTheme.color`) |
| `surfaceMuted` | `0xFF1F1F1F` | Chips, placeholders, états vides |
| `border` | `0xFF2A2A2A` | Bordures cartes/chips/champs |
| `textPrimary` | `0xFFF5F1EA` | Texte principal (blanc chaud) |
| `textSecondary` | `0xFFA8A29A` | Texte secondaire — remplace tous les `Colors.grey` |
| `success` | `0xFF34C759` | Succès, « Prêt », livré, badges EN DIRECT |
| `warning` | `0xFFFFB340` | Alertes, « En préparation », bannières hors-ligne |
| `error` | `0xFFFF5A5A` | Erreurs, annulations, boutons danger — remplace `Colors.red` |
| `info` | `0xFF4DA3FF` | Info, statuts acceptés, bannière suggestion |
| `defaultPrimary` | `0xFFE8641B` | Orange « warm appetite » — graine de marque par défaut |
| `defaultAccent` | `0xFFD4AF37` | Doré — accent par défaut |

Transparences : toujours via `.withOpacity()` sur un token
(ex. `warning.withOpacity(0.15)` pour les bannières), jamais de hex
avec canal alpha codé en dur.

## 2. Rayons & espacements (nouveau — Feature 9)

### `TchopRadius`
| Token | Valeur | Usage |
|-------|--------|-------|
| `card` | 16 | Cartes (thème), états vides |
| `cardLarge` | 20 | Hero client, bottom sheets (`sheet` = 20 pour les modales) |
| `button` | 14 | Boutons (`elevatedButtonTheme`) |
| `sheet` | 20 | `BorderRadius.vertical(top: Radius.circular(20))` |
| `chip` | 999 | Chips, badges, pills |
| `small` | 8 | Conteneurs d'info, bannières inline |
| `tiny` | 4 | Micro-détails |

### `TchopSpacing`
`xs` 4 · `sm` 8 · `md` 12 · `lg` 16 · `xl` 20 · `xxl` 24 · `section` 32.
Les nouveaux écrans (Paramètres, onboarding, états) les utilisent ; la
migration des écrans existants se fait au fil des retouches.

## 3. Couleurs fournisseurs — `TchopProviderColors` (nouveau)

Identités propres aux fournisseurs de paiement affichés dans
`PaymentConnectionsScreen` (rail coloré) : `mtnMomo 0xFFFFCC00`,
`orangeMoney 0xFFFF7900`, `wave 0xFF1DC8FF`, `cinetpay 0xFF7C3AED`,
`flutterwave 0xFFF5A623`. `forProvider(id)` mappe l'id fournisseur →
couleur, repli sur `textSecondary`. Ce sont des marques tierces, pas du
thème tenant — d'où des tokens fixes dédiés plutôt que du hardcode local.

## 4. Typographie — `TchopTypography`

`Fraunces` (display serif) + `Plus Jakarta Sans` (body). Échelle :
`displayLarge` 32 / `displayMedium` 24 / `titleMedium` 16 / `bodyMedium` 14 /
`bodySmall` 12 / `price` 15 (chiffres tabulaires — colonnes de prix alignées).
Les fichiers de fontes ne sont pas encore embarqués (voir le commentaire
dans `tchop_typography.dart`) ; les `fontFamily` compilent en l'état.

## 5. Patterns d'écran (thème + `lib/core/ui/`)

Le `ThemeData` (`buildTchopTheme`) fige : `AppBar` (fond `background`,
titre non centré, élévation 0), cartes (fond `surface`, rayon 16, bordure
`border`), chips, boutons surélevés (couleur primaire du tenant, rayon 14).
Patterns réutilisables créés quand un motif se répète ≥ 3 fois :

| Widget | Fichier | Usage |
|--------|---------|-------|
| `OfflineBanner` | `core/ui/state_views.dart` | Bannière hors-ligne canonique (consolide cuisine, livreur, onboarding) ; message surchargeable |
| `EmptyView` | `core/ui/state_views.dart` | Titre + explication + CTA obligatoire ; mascotte ou icône |
| `ErrorView` | `core/ui/state_views.dart` | Titre + message (jamais d'exception brute) + `Réessayer` |
| `LoadingView` | `core/ui/state_views.dart` | Progression centrée + label accessible |
| `SectionHeader` | `core/ui/state_views.dart` | Titre de section + action optionnelle |
| `BrandButton` | `design_system/brand_widgets.dart` | CTA primaire pleine largeur (F1) |
| `BrandLogo` | `design_system/brand_widgets.dart` | Logo tenant + repli initiale (F1) |
| `MascotWidget` | `core/ui/mascot.dart` | Mascotte Rive/dessinée (slots : splash, order-success, empty-cart, delivery-arrived) |

Boutons secondaires : `OutlinedButton.icon` directement (pattern assez stable
pour ne pas exiger un wrapper).

## 6. Exceptions documentées (hex hors design system)

`lib/core/branding/tenant_brand.dart` conserve ses `Color(0x…)` : ce sont
les **valeurs par défaut de la graine de marque** parsées depuis le JSON
(couche données), pas du style d'UI. Les importer depuis le design system
créerait un cycle (`tchop_theme.dart` importe déjà `tenant_brand.dart`).
Si un jour les défauts doivent être partagés, extraire un mini-module
sans dépendance plutôt que d'inverser le layering.

## 7. Préférences d'affichage (Feature 9)

Stockées dans `AppSettings` (table `app_settings`, même pattern KV que
`KdsSettings`) : `reducedMotion`, `liteMode`, `customerOnboardingSeen`,
`liteSuggested`. Exposées via `AppSettingsScope` ; `bootstrap.dart`
reconstruit l'arbre à chaque bascule.

| Réglage | Effets |
|---------|--------|
| Réduire les animations | Timers cuisine en texte / 30 s, bip/flash nouveau ticket coupés (`TicketAlertBeep.quiet`), transitions de pages instantanées (`buildTchopTheme(reducedMotion:)`), mascotte en image fixe |
| Mode allégé | Tout le dessus + pas de dégradés/ombres/flou, carte de suivi → liste (`MapPlaceholder`), images en miniatures uniquement |

**Heuristique de démarrage** (`StartupJankMeter`) : mesure l'intervalle
médian des 13 premières frames ; si > 50 ms (moins de ~20 i/s soutenus) ou
démarrage > 4 s, un drapeau `liteSuggested` est persisté et l'écran
Paramètres affiche **une suggestion unique** avec bouton d'activation. Le
mode allégé n'est **jamais activé automatiquement** — l'utilisateur décide
toujours. L'heuristique est approximative par nature (documentée comme telle
dans l'écran) ; le basculeur manuel reste la voie principale.
