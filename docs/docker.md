# TCHOP — Backend local en une commande (Docker)

> **But :** `docker compose up -d` lance tout le backend (base de données,
> authentification, API, temps réel, stockage) avec les 9 migrations
> appliquées et un restaurant de démo. L'app Flutter s'y connecte via son
> écran **Configuration** (super-admin).

> ⚠️ **Non testé en conditions réelles :** Docker n'est pas installé sur la
> machine de build — cette stack est assemblée d'après le pattern officiel
> d'auto-hébergement Supabase (versions épinglées), mais le premier
> démarrage réel reste à valider. Signalez tout écart.

## 1. Prérequis

- **Docker Engine** ≥ 24 + plugin **Compose v2** (`docker compose version`)
- ~2 Go de RAM libres, ports **8000, 3000, 9999, 4000, 5001, 5432** libres
- `openssl` (pour générer les secrets)

## 2. Démarrage — la commande

```bash
cd ~/workspace/tchop

./docker/genkeys.sh      # 1ʳᵉ fois seulement : génère le fichier .env (600)
docker compose up -d     # LA commande : tout démarre
docker compose logs -f migrate   # suivre l'application des migrations
```

Premier démarrage : ~1–2 min (téléchargement des images + migrations).
Vérification :

```bash
curl -s http://localhost:8000/auth/v1/health   # GoTrue via la passerelle
curl -s http://localhost:8000/rest/v1/          # PostgREST (401 attendu = OK)
```

## 3. Services & ports

| Service (conteneur) | Image épinglée | Port | Rôle |
|---|---|---|---|
| `db` (tchop-db) | `supabase/postgres:17.6.1.136` | 5432 | PostgreSQL + extensions (vault, pgcrypto). Volume persistant `tchop-db-data` |
| `auth` (tchop-auth) | `supabase/gotrue:v2.196.0` | 9999 | Login OTP téléphone/email (dev : auto-confirmé, aucun SMS réel) |
| `rest` (tchop-rest) | `postgrest/postgrest:v14.17` | 3000 | API REST auto-générée sur le schéma |
| `realtime` (realtime-dev…) | `supabase/realtime:v2.134.10` | 4000 | WebSocket : cuisine, dispo 86, suivi livreur |
| `storage` (tchop-storage) | `supabase/storage-api:v1.74.0` | 5001 (hôte) | Fichiers : logos, photos de plats, preuves de livraison |
| `gateway` (tchop-gateway) | `kong:2.8.1` | **8000** | **URL unique pour l'app** → `/auth/v1`, `/rest/v1`, `/realtime/v1`, `/storage/v1` |
| `migrate` (tchop-migrate) | `postgres:17-alpine` | — | Éphémère : applique les 9 migrations + seed, puis s'arrête |

> **Pourquoi ces images ?** `supabase/postgres` (et non `postgres:15-alpine`)
> fournit l'extension `supabase_vault` (exigée par `07_payments_vault.sql`)
> et les rôles `authenticator` / `supabase_auth_admin` / `supabase_storage_admin`.
> Kong remplace l'Envoy officiel : même résultat (une URL), config bien plus
> simple en déclaratif.

## 4. Connecter l'app Flutter

1. Dans l'app : **Super-admin → Configuration de la plateforme**.
2. Collez :
   - **URL Supabase** : `http://<IP_DE_VOTRE_MACHINE>:8000`
   - **Clé anon** : la valeur `ANON_KEY` du fichier `.env` (racine du projet)
3. « Tester la connexion », puis enregistrer — l'app se reconnecte en direct,
   sans rebuild.

**Quelle IP ?**

| Cas | URL à utiliser |
|---|---|
| App sur le même PC (émulateur/desktop/web) | `http://localhost:8000` |
| Téléphone physique sur le même Wi-Fi | `http://192.168.x.x:8000` (IP LAN du PC) |
| Émulateur Android | `http://10.0.2.2:8000` (alias vers le PC hôte) |
| Simulateur iOS | `http://localhost:8000` |

## 5. Données de démo

Si `SEED_DEMO=true` (défaut), le premier démarrage crée :

- Restaurant **« La Palmeraie — Démo »** (`demo-palmeraie`), abonnement d'essai 30 j
- Menu version 1 : Poulet DG, Ndolé, Eru, Jus de gingembre (+ disponibilités)

**Devenir owner du restaurant démo :**

1. Créez un compte dans l'app (OTP téléphone — en dev, aucun vrai SMS
   n'est envoyé ; si l'app exige un code, cherchez-le dans
   `docker compose logs auth`).
2. Récupérez l'id : `docker compose exec db psql -U postgres -c "select id, phone from auth.users;"`
3. Décommentez et exécutez le snippet en bas de `docker/seed.sql`
   (remplacez `<USER_ID>`) — ou via psql directement.

Pour une base **vide** : `SEED_DEMO=false` dans `.env`, puis
`docker compose down -v && docker compose up -d`.

## 6. Opérations courantes

```bash
docker compose ps                 # état des services
docker compose logs -f <service>  # logs (db, auth, rest, realtime, migrate…)
docker compose down               # stoppe (les données sont conservées)
docker compose down -v            # RESET COMPLET (supprime volumes = données)

# psql direct
docker compose exec db psql -U postgres

# Ré-appliquer les migrations à la main (ex. après modification)
docker compose run --rm migrate
```

## 7. Edge Functions (Deno) — hors scope local v1

`supabase/functions/` (`sync`, `payments-verify`, `payment-webhook`) se
déploient sur **Supabase hébergé** via `supabase functions deploy`
(elles lisent `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`SUPABASE_ANON_KEY` + secrets webhooks CinetPay/Flutterwave).

**Sans elles, en local :**
- ✅ L'app reste utilisable : le **mode dégradé** du moteur de sync
  (`lib/data/sync/sync_engine.dart`) accumule les mutations localement
  (file d'attente + pastilles « en attente de synchro ») au lieu d'échouer.
- ⚠️ Pas de validation serveur des commandes, pas de webhooks de paiement :
  à tester contre Supabase hébergé avant le pilote.

## 8. Dépannage

| Symptôme | Piste |
|---|---|
| `migrate` tourne en boucle sur « attente du schéma auth » | `docker compose logs auth` — GoTrue n'a pas démarré (mot de passe DB ?). |
| Port déjà utilisé (`Bind for 0.0.0.0:5000 failed: port is already allocated`) | Un autre programme occupe le port. Le plus simple : dans `docker-compose.yml`, sous `storage:` → `ports:`, changez `"5000:5000"` en `"5001:5000"` (seul le chiffre AVANT `:` change ; l'app passe par la passerelle `:8000`, rien d'autre n'est impacté). Alternative : trouvez le coupable avec `netstat -ano | findstr :5000` (Windows) puis arrêtez-le. |
| `tchop-auth` reste `unhealthy` au premier démarrage | GoTrue applique ses migrations SQL au premier boot — lent sur les disques lents. Attendez 2–3 min puis `docker compose up -d` à nouveau. Si les logs (`docker compose logs auth --tail 60`) montrent `password authentication failed for user "supabase_auth_admin"` : les rôles de service n'existent pas dans la base. Le service one-shot `db-roles` les crée automatiquement après le démarrage du db (`docker/docker/db-roles.sh`, idempotent). Vérifiez qu'il a réussi : `docker compose logs db-roles`. En cas de doute sur l'état du volume : `docker compose down -v && docker compose up -d` (reset complet, données démo uniquement). |
| `rest` renvoie 500 / schéma vide | Les migrations n'ont pas tourné : `docker compose logs migrate`. |
| L'app n'atteint pas `http://localhost:8000` depuis un téléphone | Utilisez l'IP LAN du PC, pas `localhost` (cf. §4). |
| Realtime silencieux | Vérifiez la publication : `select * from pg_publication_tables where pubname='supabase_realtime';` |
| Tout casser et repartir | `docker compose down -v && docker compose up -d` (régénérez les secrets si besoin). |

## 9. Production — avertissements

- Cette stack est pour le **développement local**. En production :
  utilisez Supabase hébergé (ou durcissez : secrets en vault, TLS,
  sauvegardes du volume `tchop-db-data`, fournisseur SMS réel —
  `GOTRUE_SMS_TWILIO_*` — au lieu de l'auto-confirmation).
- `.env` (racine) est git-ignoré : ne le commitez jamais. Ne le dupliquez pas non plus — un seul fichier de secrets.
