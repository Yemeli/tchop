-- ============================================================================
-- TCHOP payments: server-side secret encryption (Supabase Vault), webhook
-- idempotency, refund requests and cash-close history.
--
-- Threat model for BYO payment credentials:
--   1. IN TRANSIT: secrets travel from the Flutter app to the edge function
--      over TLS (Supabase Edge Functions are HTTPS-only). They are kept in
--      device memory ONLY until the outbox op is acknowledged — never written
--      to the Drift database, never written to logs.
--   2. AT REST: the sync edge function stores the blob via Supabase Vault
--      (`vault.create_secret`, AES-256 at rest). The `credentials_encrypted`
--      column holds ONLY the Vault secret UUID — the ciphertext itself lives
--      in `vault.secrets`, never in our tables.
--   3. DISPLAY: clients only ever read `key_fingerprint` (e.g. "mtn••••9f2a",
--      provider prefix + last 4 chars). Plaintext is never returned by any
--      SELECT policy path.
--   4. ROTATION: `payments/credentials_rotate` writes a NEW Vault secret and
--      swaps the pointer (old secret is kept for audit, never reused).
--   5. REVOCATION: `is_active=false` keeps the row + audit trail so every
--      credential lifecycle event stays attributable.
--   6. LEAST PRIVILEGE: the `vault_*` wrapper functions are SECURITY DEFINER
--      and revoked from `anon`/`authenticated` — only the service-role edge
--      functions can store/read secrets. RLS on
--      `tenant_payment_credentials` keeps tenants isolated even if an edge
--      function had a bug.
--
-- Provider API calls ALWAYS happen server-side (edge functions). The client
-- never sees raw secrets and never calls MTN/Orange/Wave/CinetPay directly.
-- ============================================================================

-- Vault extension (available on Supabase-hosted projects; self-hosted needs
-- the `supabase_vault` extension installed).
create extension if not exists "supabase_vault" cascade;

-- --- SECURITY DEFINER wrappers ------------------------------------------------
-- PostgREST (used by the Deno edge functions) cannot call `vault.*`
-- functions directly, so we expose two narrow wrappers. Both are revoked
-- from every client role: only the service-role key (edge functions) can
-- call them, and RLS-independent tenant checks happen in the edge function.

create or replace function public.vault_store_secret(p_name text, p_secret text)
returns uuid
language sql
security definer
set search_path = vault, pg_temp
as $$
  select vault.create_secret(p_secret, p_name, 'tchop tenant payment credential');
$$;

create or replace function public.vault_read_secret(p_id uuid)
returns text
language sql
security definer
set search_path = vault, pg_temp
as $$
  select decrypted_secret from vault.decrypted_secrets where id = p_id;
$$;

revoke all on function public.vault_store_secret(text, text)
  from public, anon, authenticated;
revoke all on function public.vault_read_secret(uuid)
  from public, anon, authenticated;

-- --- Webhook idempotency -------------------------------------------------------
-- Aggregator webhooks (CinetPay, Flutterwave) are delivered at-least-once.
-- This UNIQUE constraint lets the webhook function dedupe retries on
-- (provider, provider_ref) instead of double-applying payment state.
alter table public.payments
  add constraint payments_provider_ref_unique
  unique (provider, provider_ref);

-- --- Refund requests -----------------------------------------------------------
-- Four-eyes workflow: a refund is REQUESTED by owner/manager #1 and must be
-- APPROVED by a *different* owner/manager #2. Approving flips
-- payments.status → 'refunded' but does NOT move money — MoMo/Orange refunds
-- are limited (MTN has no public refund API for collections), so the actual
-- money-back is a MANUAL step the restaurant performs inside its provider
-- account; the approval records that someone accepted responsibility.
create table public.refund_requests (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  payment_id      uuid not null references public.payments(id) on delete restrict,
  order_id        uuid references public.orders(id) on delete set null,
  amount          int  not null,                       -- minor units (FCFA)
  reason          text not null,
  status          text not null default 'pending' check (status in
                    ('pending','approved','rejected')),
  requested_by    uuid references auth.users(id),
  requested_at    timestamptz not null default now(),
  decided_by      uuid references auth.users(id),
  decided_at      timestamptz,
  decision_note   text,
  client_mutation_id uuid not null unique,             -- outbox idempotency
  created_at      timestamptz not null default now()
);
alter table public.refund_requests enable row level security;

-- All members may READ (the requester needs to see their own request's
-- state); writes go through the sync edge function with role checks, so the
-- RLS policy below intentionally allows no direct writes from clients.
create policy "tenant members read refund requests"
  on public.refund_requests for select
  using (public.is_tenant_member(tenant_id));

-- --- Cash closes ----------------------------------------------------------------
-- Secretary's end-of-day cash reconciliation. `expected` is computed from the
-- day's delivered cash orders; the secretary counts the drawer and records
-- `counted`; `variance = counted - expected` is computed server-side and
-- immutable afterwards. One close per tenant per business day.
create table public.cash_closes (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  business_date    date not null,                      -- Africa/Douala day
  expected         int  not null,                       -- minor units (FCFA)
  counted          int  not null,
  variance         int  not null,                       -- counted - expected
  closed_by        uuid references auth.users(id),
  note             text,
  client_mutation_id uuid not null unique,             -- outbox idempotency
  created_at       timestamptz not null default now(),
  unique (tenant_id, business_date)
);
alter table public.cash_closes enable row level security;

create policy "tenant members read cash closes"
  on public.cash_closes for select
  using (public.is_tenant_member(tenant_id));
