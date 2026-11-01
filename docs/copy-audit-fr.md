# Audit copie française — Feature 9 (Polish)

Balayage de toutes les chaînes visibles par l'utilisateur dans `apps/tchop/lib/`
(251 occurrences de `Text('…')` passées en revue). La copie était déjà
francophone à ~99 % ; cet audit fige le glossaire canonique et corrige les
écarts restants.

## 1. Glossaire canonique

| Terme canonique      | À ne PAS utiliser                    | Notes |
|----------------------|--------------------------------------|-------|
| Commandes            | orders, commandes (anglicisme aucun) | — |
| Chiffre d'affaires   | CA seul, revenue                      | Toujours avec l'apostrophe typographique `'` |
| Ticket moyen         | panier moyen                          | `avgTicketFcfa` → « Ticket moyen » |
| En préparation       | en preparation (sans accent)          | Statut cuisine ; colonne KDS |
| Prêt / Prête         | pret                                  | « Prêt » (ticket), « Prête ! » (notification client), « Livraison terminée ✓ » |
| Livreur              | driver, chauffeur                      | Rôle `driver` → « Livreur » partout (`roles.dart`) |
| Clôture de caisse    | fermeture de caisse, cash close        | Écran `CashCloseScreen` : « Clôture de caisse » |
| Rupture (86)         | 86 seul (sans contexte), out of stock | Écran : « Disponibilités · 86 » ; alertes : « rupture (86) » |
| En ligne / Hors ligne| online / offline                      | Bannière : « Hors ligne — … » ; badge direct : « EN DIRECT » |
| Tableau de bord      | dashboard                             | Écran analytics (gérant/propriétaire) |
| Paiement             | checkout                              | Écran `PaymentConnectionsScreen` : « Paiement » / « Comptes de paiement » |
| Panier               | cart                                  | Icône + écrans client |

Règles de casse : phrases en casse normale (« Populaire aujourd’hui »),
titres d'écran en casse normale (« Tableau de bord », « Clôture de caisse »),
pas de TOUT-MAJUSCULES sauf les badges techniques (« SIMULATION »,
« EN DIRECT »).

## 2. Chaînes modifiées

| Fichier | Avant | Après | Motif |
|---------|-------|-------|-------|
| `features/customer/customer_home_screen.dart` | `Bon appétit 😋` | `Bon appétit` | Emoji décoratif retiré — la mascotte est désormais l'élément décoratif (fallback dessiné, sans emoji, voir `mascot.dart`) |
| `features/customer/customer_home_screen.dart` (commentaire) | `cart state + checkout sheet` | `cart state + panier/paiement sheet` | Anglicisme « checkout » → « Paiement » |
| `features/orders/order_widgets.dart` (doc) | `tracking timeline, checkout form` | `tracking timeline, payment form` | Anglicisme « checkout » |
| `features/manager/alerts_center_screen.dart` (état vide) | `Tout est calme.\nAucune annulation, remise, paiement échoué ou stock bas signalé.` | Titre `Tout est calme` + explication `Aucune annulation, remise, paiement échoué, rupture (86) ou stock bas signalé.` | Nouveau composant `EmptyView` ; « rupture (86) » ajouté au glossaire des alertes |
| `features/manager/analytics_screen.dart` (erreur) | `Chargement impossible : ${snap.error}` (texte brut) | `ErrorView` : `Les chiffres n’ont pas pu être chargés. Vérifiez votre connexion.` + bouton `Réessayer` | Les exceptions brutes ne sont plus affichées ; état d'erreur dessiné avec retry |
| `features/manager/alerts_center_screen.dart` (erreur) | `Chargement impossible : ${snap.error}` | `ErrorView` : `Les alertes n’ont pas pu être chargées. Vérifiez votre connexion.` + `Réessayer` | Idem |
| `features/manager/super_admin_screen.dart` (erreurs) | `Chargement impossible : ${snap.error}` (×2) | `ErrorView` : `Les revenus de la plateforme n’ont pas pu être chargés…` / `La liste des restaurants n’a pas pu être chargée…` + `Réessayer` | Idem |
| `features/manager/super_admin_screen.dart` (vide) | `Aucun restaurant trouvé.` | `EmptyView` : `Aucun restaurant inscrit` / `Aucun restaurant trouvé` + explication contextuelle (recherche vs liste vide) | État vide dessiné |
| `features/manager/inventory_screen.dart` (vide) | `Aucun menu publié. Publiez le menu pour suivre le stock de chaque article.` (texte centré) | `EmptyView` : titre `Aucun menu publié` + explication + CTA `Ouvrir le studio menu` | CTA exigé par le pattern d'état vide |
| `features/manager/inventory_screen.dart` (chargement) | `CircularProgressIndicator` nu | `LoadingView(label: 'Chargement du stock…')` | Label accessible |
| `features/manager/analytics_screen.dart` (vide) | — (aucun état vide) | `EmptyView` : `Aucune vente sur la période` + `Aucune commande aujourd’hui/… pour l’instant. Les chiffres apparaîtront ici dès la première vente.` | Nouvel état vide |
| `features/dispatch/customer_tracking_screen.dart` | — | Note placeholder : `Mode allégé — la carte est remplacée par la liste des étapes.` | Chaîne du mode allégé |

## 3. Vérifiés conformes (aucun changement)

- `En préparation`, `Prêt`, `Nouveau` — colonnes KDS (`kitchen_ticket_board_screen.dart`)
- `Livreur` — `roles.dart` (`'driver': 'Livreur'`), tracking (`customer_tracking_screen.dart`)
- `Clôture de caisse` / `Clôture de caisse du jour` — manager dashboard, cash close
- `Disponibilités · 86`, `Oui, épuiser`, `« … » marqué épuisé.` — eighty-six
- `Tableau de bord` — analytics + bouton manager (`Tableau de bord — ventes & équipe`)
- `Chiffre d'affaires` — analytics (`_StatCards`), super-admin (`Revenus de la plateforme`)
- `Ticket moyen` — analytics
- `Hors ligne` — bannières (cuisine, livreur, onboarding) désormais consolidées dans `OfflineBanner`
- `Paiement` — `payment_connections_screen.dart` (`Comptes de paiement`)
- Formats : `4 500 FCFA` (espaces insécables), dates `JJ/MM HH:MM`, `+237` indicatif

## 4. Points d'attention restants (non bloquants)

- `Gains du jour : — (bientôt : paie)` (driver) : formulation honnête, à revoir quand la paie MoMo arrivera.
- Les écrans d'authentification utilisent `Vérification…` / `Chargement…` — ellipse `…` (U+2026) utilisée partout, ne pas remplacer par `...`.
- Les pluriels dynamiques (`${items.length} plat${items.length > 1 ? 's' : ''}`) restent corrects.
- `CheckoutForm` / `_checkout` / `dashboard` n'existent que comme identifiants
  de code ou commentaires — aucune chaîne visible n'utilise « checkout » ou
  « dashboard » (les renommer serait du churn sans bénéfice utilisateur ;
  l'interface affiche « Finaliser la commande », « Panier », « Tableau de
  bord »).
