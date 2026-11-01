#!/bin/sh
# ============================================================================
# TCHOP — conteneur `migrate` (éphémère).
# Applique, dans l'ordre : extensions, les 9 migrations (00_*.sql → 08_*.sql),
# les grants, puis le seed démo (si SEED_DEMO=true).
# Il attend que GoTrue ait créé le schéma `auth` et que storage-api ait créé
# le schéma `storage`, car les migrations y font référence (FK auth.users,
# buckets storage). C'est POURQUOI les migrations ne sont pas dans
# /docker-entrypoint-initdb.d : à l'init de postgres, ces schémas n'existent
# pas encore (ils sont créés par les services, après).
# ============================================================================
set -e
export PGPASSWORD="$POSTGRES_PASSWORD"

PSQL="psql -h ${PGHOST:-db} -p ${PGPORT:-5432} -U ${PGUSER:-postgres} -d ${PGDATABASE:-postgres}"

echo "[migrate] attente du schéma auth (GoTrue)…"
until $PSQL -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='auth'" 2>/dev/null | grep -q 1; do
  sleep 3
done

echo "[migrate] attente du schéma storage (storage-api)…"
until $PSQL -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='storage' AND table_name='buckets'" 2>/dev/null | grep -q 1; do
  sleep 3
done

echo "[migrate] extensions…"
$PSQL -v ON_ERROR_STOP=1 -f /pre.sql

echo "[migrate] migrations (ordre alphabétique = ordre de dépendances)…"
for f in $(ls /migrations/*.sql | sort); do
  echo "  -> $(basename "$f")"
  $PSQL -v ON_ERROR_STOP=1 -f "$f"
done

echo "[migrate] grants + publication realtime…"
$PSQL -v ON_ERROR_STOP=1 -f /grants.sql

if [ "${SEED_DEMO:-true}" = "true" ]; then
  echo "[migrate] seed démo…"
  $PSQL -v ON_ERROR_STOP=1 -f /seed.sql
else
  echo "[migrate] seed démo ignoré (SEED_DEMO=false)."
fi

echo "[migrate] OK — backend prêt."
