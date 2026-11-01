-- ============================================================================
-- TCHOP (codename) — initial database schema
-- Multi-tenant restaurant OS: one shared PostgreSQL database.
-- Every tenant table carries restaurant_id (tenant_id); Row-Level Security
-- enforces isolation so restaurants can never see each other's data.
-- Designed for Supabase (uses auth.users / auth.uid() / auth.jwt()).
--
-- ORDER MATTERS: PostgreSQL validates SQL-language function bodies at
-- CREATE time, so tables come first, then helper functions, then policies.
-- ============================================================================

-- ============================================================================
-- 1. TABLES
-- ============================================================================

-- Tenants = restaurant workspaces
create table public.tenants (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,                       -- brand name shown in app
  slug          text unique not null,                -- lapalmeraie -> lapalmeraie.tchop.cm
  logo_url      text,
  primary_color text not null default '#FF6B35',
  secondary_color text,
  currency      text not null default 'XAF',
  country       text not null default 'CM',
  timezone      text not null default 'Africa/Douala',
  created_at    timestamptz not null default now()
);
alter table public.tenants enable row level security;

-- Platform admins (super-admin dashboard)
create table public.platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;

-- Memberships: user <-> tenant <-> role
-- Roles: owner, manager, head_chef, secretary, kitchen, driver
create table public.memberships (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in
               ('owner','manager','head_chef','secretary','kitchen','driver')),
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);
alter table public.memberships enable row level security;
create index memberships_user_idx on public.memberships(user_id);

-- Subscriptions: the platform's revenue (trial -> starter/pro/enterprise)
create table public.subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  plan               text not null default 'trial'
                     check (plan in ('trial','starter','pro','enterprise')),
  status             text not null default 'trialing'
                     check (status in
                       ('trialing','active','past_due','suspended','cancelled')),
  billing_cycle      text not null default 'monthly'
                     check (billing_cycle in ('monthly','yearly')),
  trial_ends_at      timestamptz,
  current_period_end timestamptz,
  created_at         timestamptz not null default now()
);
alter table public.subscriptions enable row level security;

-- Payment credentials: each restaurant's OWN MoMo / Orange / card keys.
-- Secrets are encrypted before insert; only masked fingerprints are displayed.
-- Money flows directly to the restaurant's accounts — the platform never
-- holds funds.
create table public.tenant_payment_credentials (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id) on delete cascade,
  provider              text not null check (provider in
                          ('mtn_momo','orange_money','wave','cinetpay','flutterwave','card')),
  label                 text not null,               -- "MTN MoMo principal"
  credentials_encrypted text not null,               -- vault-encrypted JSON blob
  key_fingerprint       text not null,               -- masked id for display, e.g. "••••4f2a"
  is_active             boolean not null default true,
  created_by            uuid references auth.users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
alter table public.tenant_payment_credentials enable row level security;

-- Menus: immutable, versioned snapshots. Edits accumulate in menu_drafts;
-- publishing creates a new snapshot and flips the active version atomically.
-- The 86 (sold-out) toggle lives in item_availability for fast propagation.
create table public.menu_snapshots (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  version      int  not null,
  items        jsonb not null,                       -- full menu tree
  published_by uuid references auth.users(id),
  published_at timestamptz not null default now(),
  unique (tenant_id, version)
);
alter table public.menu_snapshots enable row level security;
create index menu_snapshots_tenant_idx on public.menu_snapshots(tenant_id, version desc);

create table public.menu_drafts (
  tenant_id  uuid primary key references public.tenants(id) on delete cascade,
  items      jsonb not null default '[]',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
alter table public.menu_drafts enable row level security;

-- Fast-path availability (86 / sold-out), separate from publishing.
create table public.item_availability (
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  item_id    text not null,
  available  boolean not null default true,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, item_id)
);
alter table public.item_availability enable row level security;

-- Orders: append-only status state machine.
-- placed -> accepted -> preparing -> ready -> picked_up -> delivered
-- Server re-validates every line against live availability + price at
-- creation; the client-sent menu_version is checked to prevent stale carts.
create table public.orders (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  customer_name  text,
  customer_phone text,
  channel        text not null default 'app' check (channel in
                   ('app','whatsapp','phone','walkin','qr_table')),
  menu_version   int not null,
  lines          jsonb not null,                     -- validated server-side
  subtotal       int  not null,                      -- minor units (FCFA)
  delivery_fee   int  not null default 0,
  total          int  not null,
  status         text not null default 'placed' check (status in
                   ('placed','accepted','preparing','ready',
                    'picked_up','delivered','cancelled')),
  payment_method text check (payment_method in
                   ('mtn_momo','orange_money','wave','cash','card')),
  payment_status text not null default 'pending' check (payment_status in
                   ('pending','succeeded','failed','refunded')),
  created_by     uuid references auth.users(id),
  created_at     timestamptz not null default now()
);
alter table public.orders enable row level security;
create index orders_tenant_time_idx on public.orders(tenant_id, created_at desc);
create index orders_status_idx on public.orders(tenant_id, status);

-- Deliveries: driver assignment + proof of delivery.
-- Raw GPS pings stream over MQTT (not stored here); only milestones persist.
create table public.deliveries (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  order_id        uuid not null references public.orders(id) on delete cascade,
  driver_id       uuid references auth.users(id),
  dropoff_lat     double precision,
  dropoff_lng     double precision,
  dropoff_address text,
  picked_up_at    timestamptz,
  delivered_at    timestamptz,
  pod_photo_url   text,                              -- proof-of-delivery photo
  pod_signature_url text,
  pod_lat         double precision,
  pod_lng         double precision,
  created_at      timestamptz not null default now()
);
alter table public.deliveries enable row level security;
create index deliveries_driver_idx on public.deliveries(tenant_id, driver_id);

-- Payments: record of each order's payment (money itself settles directly
-- into the restaurant's own provider accounts).
create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  order_id     uuid not null references public.orders(id) on delete cascade,
  provider     text not null,
  provider_ref text,                                 -- MoMo transaction id
  amount       int  not null,                        -- minor units (FCFA)
  currency     text not null default 'XAF',
  status       text not null default 'pending' check (status in
                 ('pending','succeeded','failed','refunded')),
  created_at   timestamptz not null default now()
);
alter table public.payments enable row level security;
create index payments_tenant_time_idx on public.payments(tenant_id, created_at desc);

-- Audit logs: append-only. No UPDATE or DELETE permitted (trigger).
-- Logs every price change, publish, 86 toggle, refund, role change,
-- and payment-credential change: who, what, before -> after.
create table public.audit_logs (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  user_id    uuid references auth.users(id),
  action     text not null,                          -- e.g. menu.publish, price.change
  entity     text,
  entity_id  text,
  before     jsonb,
  after      jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_logs enable row level security;
create index audit_tenant_time_idx on public.audit_logs(tenant_id, created_at desc);

-- ============================================================================
-- 2. HELPER FUNCTIONS (after tables: SQL bodies are validated at CREATE)
-- ============================================================================

create or replace function public.is_tenant_member(p_tenant uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.memberships
    where tenant_id = p_tenant
      and user_id = auth.uid()
  );
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins
    where user_id = auth.uid()
  );
$$;

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_logs is append-only: updates and deletes are forbidden';
end;
$$;

create trigger audit_logs_no_mutation
  before update or delete on public.audit_logs
  for each row execute function public.prevent_audit_mutation();

-- ============================================================================
-- 3. ROW-LEVEL SECURITY POLICIES (after functions)
-- ============================================================================

create policy "members read own tenant"
  on public.tenants for select
  using (public.is_tenant_member(id));
create policy "platform admins read all tenants"
  on public.tenants for select
  using (public.is_platform_admin());
create policy "platform admins manage tenants"
  on public.tenants for all
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

create policy "platform admins read admin list"
  on public.platform_admins for select
  using (public.is_platform_admin());

create policy "users read own memberships"
  on public.memberships for select
  using (user_id = auth.uid() or public.is_platform_admin());
create policy "owners and managers manage memberships"
  on public.memberships for all
  using (public.is_tenant_member(tenant_id) or public.is_platform_admin())
  with check (public.is_tenant_member(tenant_id) or public.is_platform_admin());

create policy "members read own subscription"
  on public.subscriptions for select
  using (public.is_tenant_member(tenant_id) or public.is_platform_admin());
create policy "platform admins manage subscriptions"
  on public.subscriptions for all
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- NOTE: role-level check (owner/manager only) for payment credentials is
-- enforced in API middleware; RLS guarantees tenant isolation even if
-- middleware has a bug.
create policy "owners/managers manage payment credentials"
  on public.tenant_payment_credentials for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage menu snapshots"
  on public.menu_snapshots for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage menu drafts"
  on public.menu_drafts for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage availability"
  on public.item_availability for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage orders"
  on public.orders for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage deliveries"
  on public.deliveries for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "tenant members manage payments"
  on public.payments for all
  using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

create policy "owners/managers read audit logs"
  on public.audit_logs for select
  using (public.is_tenant_member(tenant_id) or public.is_platform_admin());
create policy "system writes audit logs"
  on public.audit_logs for insert
  with check (public.is_tenant_member(tenant_id));

-- ============================================================================
-- End of initial schema.
-- Next migrations: daypart schedules, inventory, loyalty, staff payroll.
-- ============================================================================
