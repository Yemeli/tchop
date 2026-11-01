# TCHOP — Guide de configuration (checklist des clés)

> **Règle d'or :** aucune vraie clé n'est jamais écrite en dur dans le code
> ni committée. Deux couches existent pour chaque clé plateforme :
>
> 1. **À chaud (recommandé)** — écran super-admin **Configuration**
>    (console super-admin → *Configuration de la plateforme*). Valeurs
>    masquées (`••••9f2a`), stockées chiffrées sur l'appareil
>    (Keychain / Keystore), **aucun rebuild requis**, bouton
>    *Tester la connexion* par section.
> 2. **Au build (plan B)** — `--dart-define=CLE=valeur` (voir
>    [.env.example](../.env.example)). Sert de valeur par défaut quand
>    rien n'a été collé dans l'app.

Sans aucune clé, l'app démarre quand même en **mode démo hors-ligne**
(base Drift locale, badges « en attente de synchro »).

## Clés plateforme (super-admin uniquement)

| Clé | À quoi ça sert | Où l'obtenir (portail exact) | Où la coller | Sans elle (mode dégradé) |
|---|---|---|---|---|
| `SUPABASE_URL` | URL du backend (Postgres, Auth, Realtime, Storage) | Supabase Dashboard → votre projet → **Project Settings → API** → *Project URL* | Configuration → Backend Supabase, ou `--dart-define=SUPABASE_URL=…` | Mode démo hors-ligne : tout fonctionne en local, rien ne se synchronise |
| `SUPABASE_ANON_KEY` | Clé publique d'accès API (les politiques RLS protègent les données) | Supabase Dashboard → **Project Settings → API** → clé *anon* / *publishable* | Configuration → Backend Supabase, ou `--dart-define=SUPABASE_ANON_KEY=…` | Idem ci-dessus (les deux sont requises ensemble) |
| `MAPS_API_KEY` | Carte de suivi livreur en temps réel | Google Cloud Console → **APIs & Services → Credentials** → créer une clé API ; activer **Maps SDK for Android** et **Maps SDK for iOS** | Configuration → Google Maps, ou `--dart-define=MAPS_API_KEY=…` | Écran de suivi en mode liste (épingles Restaurant / Livreur / Vous) au lieu de la carte |
| `MQTT_BROKER_URL` | Streaming GPS des livreurs (toutes les 8 s) | Un broker MQTT, ex. **EMQX Cloud** → Deployment → Overview (adresse `wss://…` + port), ou HiveMQ Cloud | Configuration → Broker MQTT, ou `--dart-define=MQTT_BROKER_URL=…` | **Mode SIMULATION** : positions de démonstration avec badge « SIMULATION » |

### ⚠️ Cas particulier — Google Maps (lisez-moi)

La **carte native** (le widget carte dans l'app) lit la clé dans le
manifeste de la plateforme **au moment du build** :

- Android : `android/app/src/main/AndroidManifest.xml` →
  `<meta-data android:name="com.google.android.geo.API_KEY" android:value="…"/>`
- iOS : `ios/Runner/AppDelegate.swift` (ou Info.plist selon la version du plugin)

Une clé collée à chaud dans **Configuration** est conservée en sécurité et
fonctionne **immédiatement** pour les appels Maps en HTTP (geocodage,
Static Maps…), mais la carte native intégrée ne s'active qu'**après rebuild**
avec la clé au build. Le bouton *Vérifier* de la section Maps l'explique
dans l'app (pas de test réseau possible pour ce cas).

### Cas particulier — Supabase

Après un changement d'URL/clé, **reconnectez-vous** : le nouveau client
backend ne porte aucune session. Le bouton *Tester la connexion* envoie une
vraie requête légère ; toute réponse HTTP (même 401/403) = backend
joignable, seuls les échecs réseau purs = échec.

### Cas particulier — MQTT

Le bouton *Tester la connexion* tente une vraie poignée de main MQTT
(timeout 10 s). URL vide ou par défaut = SIMULATION (aucun réseau tenté).
Format attendu : `wss://hôte:port/mqtt` (TLS) ou `mqtt://hôte:1883`.

## Clés de paiement par restaurant (chaque restaurant, isolé)

> Ces clés ne passent **jamais** par l'écran Configuration ci-dessus.
> Chaque restaurant connecte **ses propres** comptes : l'argent va
> directement chez lui, jamais via la plateforme.

| Clé / credential | À quoi ça sert | Où l'obtenir | Où la coller |
|---|---|---|---|
| MTN MoMo — *API User / API Key / Subscription Key* | Encaisser via MTN Mobile Money | **MTN MoMo Developer Portal** (developer.mtn.com) → créer une app, générer API User + API Key, souscrire au produit *Collection* | App restaurant → **Paiements → Connexions** → MTN MoMo |
| Orange Money — *Client ID / Client Secret* | Encaisser via Orange Money | **Orange Developer** (developer.orange.com) → *My Apps* → API *Orange Money* (Cameroun) | Paiements → Connexions → Orange Money |
| Wave — clé API | Encaisser via Wave (Sénégal / Côte d'Ivoire…) | **Wave** → espace développeur / commercial | Paiements → Connexions → Wave |
| CinetPay — *API Key / Site ID / Secret* | Agrégateur (MoMo + cartes), webhooks | **CinetPay** dashboard → API keys | Paiements → Connexions → CinetPay |
| Flutterwave — *Public / Secret Key* | Cartes + mobile money, webhooks | **Flutterwave** dashboard → Settings → API Keys | Paiements → Connexions → Flutterwave |

Détails (chiffrement Vault, clés masquées, bouton *vérifier en mode test*,
rotation/révocation, rapprochement d'espèces, remboursements à quatre yeux) :
voir l'écran **Paiements → Connexions** dans l'app.

## Autres services (phase pilote)

| Service | Statut | Action requise |
|---|---|---|
| Push (FCM) | Non configuré | Projet **Firebase Console** → ajouter les apps Android/iOS → `google-services.json` / `GoogleService-Info.plist` |
| Notifications SMS/WhatsApp | Non configuré | Compte **Twilio** (ou agrégateur local) → clé API dans les Edge Functions |
| Nom de marque final | En attente | Gayellen choisit le nom → renommer le codename « tchop » (bundle id, titres, assets) |
