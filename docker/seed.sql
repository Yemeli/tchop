-- ============================================================================
-- TCHOP — SEED DE DONNÉES DE **DÉMO** (dev local uniquement).
-- Inséré automatiquement au premier `docker compose up` (SEED_DEMO=true).
-- Pour une base vide : SEED_DEMO=false dans docker/.env puis
-- `docker compose down -v && docker compose up -d`.
--
-- Contenu : un restaurant de démo « La Palmeraie » + abonnement d'essai +
-- un menu version 1 (4 plats) + disponibilités.
-- Les COMPTES (auth.users) et MEMBERSHIPS se créent via l'app :
--   1. dans l'app, créez un compte par OTP (mode dev, voir docs/docker.md) ;
--   2. exécutez ensuite le snippet en bas de ce fichier en remplaçant
--      <USER_ID> par l'id retourné par GoTrue, pour devenir `owner` du
--      restaurant démo.
-- ============================================================================

-- Restaurant démo -------------------------------------------------------------
insert into public.tenants (id, name, slug, primary_color, secondary_color,
                            currency, country, timezone)
values ('11111111-1111-1111-1111-111111111111',
        'La Palmeraie — Démo',
        'demo-palmeraie',
        '#FF6B35', '#1A1A2E',
        'XAF', 'CM', 'Africa/Douala')
on conflict (id) do nothing;

-- Abonnement d'essai (30 jours) ------------------------------------------------
insert into public.subscriptions (tenant_id, plan, status, billing_cycle,
                                  trial_ends_at, current_period_end)
values ('11111111-1111-1111-1111-111111111111',
        'trial', 'trialing', 'monthly',
        now() + interval '30 days', now() + interval '30 days')
on conflict do nothing;

-- Menu version 1 (snapshot publié) --------------------------------------------
insert into public.menu_snapshots (tenant_id, version, items)
values ('11111111-1111-1111-1111-111111111111', 1,
  '[
    {"id":"demo_poulet_dg","name":"Poulet DG","price_fcfa":3500,
     "category":"Plats","description":"Poulet, plantain, légumes — le classique."},
    {"id":"demo_ndole","name":"Ndolé","price_fcfa":2500,
     "category":"Plats","description":"Ndolé aux crevettes, bâton de manioc."},
    {"id":"demo_eru","name":"Eru","price_fcfa":2000,
     "category":"Plats","description":"Eru au waterleaf, peau de bœuf."},
    {"id":"demo_jus_gingembre","name":"Jus de gingembre","price_fcfa":1000,
     "category":"Boissons","description":"Jus de gingembre frais maison."}
  ]'::jsonb)
on conflict (tenant_id, version) do nothing;

-- Brouillon initial (copie du snapshot) ---------------------------------------
insert into public.menu_drafts (tenant_id, items)
values ('11111111-1111-1111-1111-111111111111',
  (select items from public.menu_snapshots
    where tenant_id = '11111111-1111-1111-1111-111111111111' and version = 1))
on conflict (tenant_id) do nothing;

-- Disponibilités (tout disponible) --------------------------------------------
insert into public.item_availability (tenant_id, item_id, available)
values ('11111111-1111-1111-1111-111111111111','demo_poulet_dg', true),
       ('11111111-1111-1111-1111-111111111111','demo_ndole', true),
       ('11111111-1111-1111-1111-111111111111','demo_eru', true),
       ('11111111-1111-1111-1111-111111111111','demo_jus_gingembre', true)
on conflict (tenant_id, item_id) do nothing;

-- ============================================================================
-- SNIPPET — devenir `owner` du restaurant démo après création du compte.
-- Remplacez <USER_ID> par l'id de l'utilisateur (visible dans les logs auth
-- ou via : select id, phone from auth.users;).
-- ============================================================================
-- insert into public.platform_admins (user_id) values ('<USER_ID>')
--   on conflict do nothing;  -- décommentez pour faire de ce compte un
--                             -- super-admin plateforme (Gayellen).
--
-- insert into public.memberships (tenant_id, user_id, role)
-- values ('11111111-1111-1111-1111-111111111111', '<USER_ID>', 'owner')
-- on conflict (tenant_id, user_id) do nothing;
