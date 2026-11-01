-- ============================================================================
-- TCHOP — sync support: idempotency key on orders.
--
-- The client's SyncEngine replays every outbox entry with a UUID
-- `client_mutation_id`. The server upserts on it
-- (INSERT … ON CONFLICT (client_mutation_id) DO NOTHING) so retried
-- deliveries never create duplicate orders; a duplicate replay answers 409.
-- ============================================================================

alter table public.orders
  add column if not exists client_mutation_id uuid;

create unique index if not exists orders_client_mutation_id_uidx
  on public.orders (client_mutation_id);

comment on column public.orders.client_mutation_id is
  'Client-generated UUID for idempotent order replay from the offline outbox.';

-- ----------------------------------------------------------------------------
-- Sync ledger: idempotency record for the /sync Edge Function.
-- Every applied mutation is recorded here keyed on client_mutation_id;
-- a replayed envelope with an already-seen key answers 409 instead of
-- double-applying.
-- ----------------------------------------------------------------------------
create table if not exists public.sync_ledger (
  client_mutation_id uuid primary key,
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  op                 text not null,
  entity             text not null,
  entity_id          text,
  idempotency_key    text,
  created_at         timestamptz not null default now()
);
alter table public.sync_ledger enable row level security;

-- Only the service-role Edge Function writes here; tenant members get no
-- direct access (no policies = no access for anon/authenticated).
comment on table public.sync_ledger is
  'Idempotency ledger for the /sync Edge Function. Written by service role only.';
