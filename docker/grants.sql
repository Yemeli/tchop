-- ============================================================================
-- TCHOP — grants post-migrations (dev local).
-- La sécurité entre restaurants reste assurée par le RLS (policies des
-- migrations) ; ici on donne simplement aux rôles API l'accès physique
-- dont PostgREST a besoin.
-- ============================================================================

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;

grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all tables in schema storage to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;

-- Publication lue par Realtime (canal cuisine / suivi / dispo 86).
drop publication if exists supabase_realtime;
create publication supabase_realtime for all tables;

-- Charge utile complète (lignes avant/après) pour les UPDATE/DELETE.
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I replica identity full', r.tablename);
  end loop;
end $$;
