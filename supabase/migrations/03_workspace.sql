-- ============================================================================
-- TCHOP — workspace provisioning: slug check, atomic creation, brand assets.
--
-- Creating a workspace REQUIRES connectivity (slug uniqueness is
-- server-side). The app calls `create_workspace()` directly so a partial
-- failure rolls back atomically; the client surfaces the French error.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Live slug availability check (callable before the user is a member —
-- the tenants SELECT policy would otherwise hide the answer).
-- ----------------------------------------------------------------------------
create or replace function public.slug_available(p_slug text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select not exists (
    select 1 from public.tenants where slug = p_slug
  );
$$;

grant execute on function public.slug_available(text) to authenticated;

comment on function public.slug_available(text) is
  'True when no tenant uses this slug. Used for the live availability '
  'indicator on the create-workspace screen.';

-- ----------------------------------------------------------------------------
-- Atomic workspace creation: tenant + owner membership + 30-day trial
-- subscription in ONE transaction. Either everything exists or nothing
-- does — the client never has to roll back manually.
--
-- Errors (surfaced in French by the app):
--   slug_taken        — another tenant already uses the slug
--   invalid_slug      — fails the ^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$ shape
--   not_authenticated — no session
-- ----------------------------------------------------------------------------
create or replace function public.create_workspace(
  p_name text,
  p_slug text,
  p_primary_color text default '#FF6B35',
  p_secondary_color text default null,
  p_logo_url text default null
)
returns public.tenants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant public.tenants%rowtype;
  v_trial_end timestamptz := now() + interval '30 days';
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_slug !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' then
    raise exception 'invalid_slug';
  end if;

  if exists (select 1 from public.tenants where slug = p_slug) then
    raise exception 'slug_taken';
  end if;

  insert into public.tenants
    (name, slug, primary_color, secondary_color, logo_url)
  values
    (nullif(trim(p_name), ''), p_slug,
     coalesce(nullif(p_primary_color, ''), '#FF6B35'),
     nullif(p_secondary_color, ''), nullif(p_logo_url, ''))
  returning * into v_tenant;

  insert into public.memberships (tenant_id, user_id, role)
  values (v_tenant.id, auth.uid(), 'owner');

  insert into public.subscriptions
    (tenant_id, plan, status, trial_ends_at, current_period_end)
  values
    (v_tenant.id, 'trial', 'trialing', v_trial_end, v_trial_end);

  return v_tenant;
exception
  when unique_violation then
    -- Backstop for a slug race between the pre-check and the insert.
    raise exception 'slug_taken';
end;
$$;

grant execute on function
  public.create_workspace(text, text, text, text, text) to authenticated;

comment on function
  public.create_workspace(text, text, text, text, text) is
  'Creates a restaurant workspace atomically: tenant + owner membership + '
  '30-day trial subscription.';

-- ----------------------------------------------------------------------------
-- Brand asset storage: public `brand` bucket, objects at
-- `{tenant_id}/logo.png`. Members of the tenant can upload/replace;
-- everyone can read (logos render in the customer storefront).
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('brand', 'brand', true)
on conflict (id) do nothing;

create policy "tenant members upload brand assets"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'brand'
    and (storage.foldername(name))[1] in (
      select tenant_id::text
        from public.memberships
       where user_id = auth.uid()
    )
  );

create policy "tenant members replace brand assets"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'brand'
    and (storage.foldername(name))[1] in (
      select tenant_id::text
        from public.memberships
       where user_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'brand'
    and (storage.foldername(name))[1] in (
      select tenant_id::text
        from public.memberships
       where user_id = auth.uid()
    )
  );

create policy "tenant members delete brand assets"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'brand'
    and (storage.foldername(name))[1] in (
      select tenant_id::text
        from public.memberships
       where user_id = auth.uid()
    )
  );

-- Public read (applies to anon + authenticated): logos are brand assets.
create policy "public read brand assets"
  on storage.objects for select
  using (bucket_id = 'brand');
