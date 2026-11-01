#!/bin/sh
# ============================================================================
# TCHOP — aligne les rôles de service PostgreSQL sur POSTGRES_PASSWORD.
# (one-shot, APRÈS init du db)
#
# L'image supabase/postgres crée déjà tous les rôles (supabase_admin,
# supabase_auth_admin, supabase_storage_admin, authenticator, anon, …)
# mais avec des mots de passe inconnus, et les rôles de service ne sont
# PAS superuser. On se connecte en tant que supabase_admin (superuser
# pré-créé) pour aligner les mots de passe sur POSTGRES_PASSWORD et
# restaurer les flags superuser dont GoTrue/Storage/migrate ont besoin.
#
# Pourquoi pas /docker-entrypoint-initdb.d ? L'entrypoint custom exécute
# les scripts d'init AVANT de créer le rôle « postgres » ; un script qui
# s'y connecte échoue et — via set -e — annule toute l'initialisation
# (constaté le 2026-09-27).
#
# Note : mot de passe passé via format(... %L) dans un bloc DO, jamais via
# les variables :'var' de psql (substitution non fiable ici).
# Idempotent : peut être rejoué sans risque.
# ============================================================================
set -eu
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"
: "${PGPASSWORD:?PGPASSWORD must be set (same as POSTGRES_PASSWORD)}"

# Double les quotes pour une insertion sûre dans un littéral SQL.
pw_esc=$(printf '%s' "$POSTGRES_PASSWORD" | sed "s/'/''/g")

echo "[db-roles] alignement des roles de service (via supabase_admin)…"

psql -v ON_ERROR_STOP=1 -h "${PGHOST:-db}" -p "${PGPORT:-5432}" \
     -U supabase_admin -d postgres <<SQL
DO \$\$
DECLARE
  pw constant text := '$pw_esc';
BEGIN
  -- Superusers de service : mot de passe + flag superuser.
  EXECUTE format('ALTER ROLE supabase_admin WITH SUPERUSER LOGIN PASSWORD %L', pw);
  EXECUTE format('ALTER ROLE supabase_auth_admin WITH SUPERUSER LOGIN PASSWORD %L', pw);
  EXECUTE format('ALTER ROLE supabase_storage_admin WITH SUPERUSER LOGIN PASSWORD %L', pw);
  -- postgres : superuser (migrate y crée les extensions et le DDL).
  EXECUTE format('ALTER ROLE postgres WITH SUPERUSER LOGIN PASSWORD %L', pw);

  -- authenticator : rôle de connexion PostgREST (reste non-superuser).
  -- (rôle « réservé » : seul un superuser peut le modifier — c'est notre cas)
  EXECUTE format('ALTER ROLE authenticator WITH LOGIN PASSWORD %L', pw);

  -- pgbouncer : aligne aussi (inoffensif).
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgbouncer') THEN
    EXECUTE format('ALTER ROLE pgbouncer WITH LOGIN PASSWORD %L', pw);
  END IF;

  -- Garde-fous : anon / authenticated / service_role sans login.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;

  RAISE NOTICE '[db-roles] roles alignes sur POSTGRES_PASSWORD';
END
\$\$;
SQL

echo "[db-roles] OK — roles de service prets."
