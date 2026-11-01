#!/bin/sh
# ============================================================================
# TCHOP — génère les secrets du backend Docker local.
# Écrit UNIQUEMENT `.env` à la racine : ce fichier sert à la fois à
# l'interpolation des variables dans docker-compose.yml ET aux conteneurs
# via `env_file`. Un seul fichier = impossible de désynchroniser le mot de
# passe entre la base initialisée et les services.
# Les clés ANON/SERVICE_ROLE sont des JWT HS256 forgés à la main
# (openssl + base64url), sans dépendance externe.
# NE COMMITEZ JAMAIS ce fichier.
# ============================================================================
set -eu
cd "$(dirname "$0")/.."

command -v openssl >/dev/null 2>&1 || { echo "openssl requis." >&2; exit 1; }

b64url() { openssl base64 -A 2>/dev/null | tr -- '+/' '-_' | tr -d '=' | tr -d '\n'; }
randhex() { openssl rand -hex "$1"; }

JWT_SECRET=$(randhex 32)
POSTGRES_PASSWORD=$(randhex 24)
SECRET_KEY_BASE=$(randhex 64)
REALTIME_DB_ENC_KEY=$(randhex 16)

mkjwt() { # $1 = role (anon | service_role)
  h=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '{"role":"%s","iss":"tchop-local","iat":%s,"exp":4102444800}' \
      "$1" "$(date +%s)" | b64url)
  s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$s"
}

ANON_KEY=$(mkjwt anon)
SERVICE_ROLE_KEY=$(mkjwt service_role)

ENV_CONTENT="# Généré par docker/genkeys.sh — NE PAS COMMITTER.
# Régénérez avec ./docker/genkeys.sh (invalide les anciens tokens).
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
REALTIME_DB_ENC_KEY=${REALTIME_DB_ENC_KEY}
JWT_EXPIRY=3600
SEED_DEMO=true
"

printf '%s' "$ENV_CONTENT" > .env
chmod 600 .env 2>/dev/null || true

echo "OK — .env généré à la racine (droits 600). Fichier unique : ne le dupliquez pas."
echo "ANON_KEY (à coller dans l'écran Configuration de l'app) :"
printf '%s\n' "$ANON_KEY"
