-- ============================================================================
-- TCHOP — menu ops: atomic publish + item photo storage.
--
-- 1. public.publish_menu_snapshot(...) — the ONLY sanctioned way to apply a
--    `menu/publish` outbox op. It takes a per-tenant advisory lock inside a
--    single transaction, recomputes max(version)+1 itself, and inserts.
--    The client-sent version is ADVISORY ONLY: two managers publishing at
--    the same second can never collide on the (tenant_id, version) unique
--    key, and the returned version is authoritative. The client's local
--    snapshot converges on the next draft pull.
-- 2. Storage bucket `menu` for item photos at {tenant_id}/{item_id}.jpg.
-- ============================================================================

create or replace function public.publish_menu_snapshot(
  p_tenant_id   uuid,
  p_version     int,      -- advisory; ignored for the insert
  p_items       jsonb,
  p_published_by uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version int;
begin
  -- Serialize concurrent publishes for this tenant for the duration of
  -- the transaction. hashtext() keeps the lock key in the 32-bit range.
  perform pg_advisory_xact_lock(hashtext(p_tenant_id::text));

  select coalesce(max(version), 0) + 1
    into v_version
    from public.menu_snapshots
   where tenant_id = p_tenant_id;

  insert into public.menu_snapshots (tenant_id, version, items, published_by)
  values (p_tenant_id, v_version, p_items, p_published_by);

  return v_version;
end;
$$;

comment on function public.publish_menu_snapshot(uuid, int, jsonb, uuid) is
  'Atomic menu publish: advisory-locked max(version)+1 insert. The sync Edge Function must route every menu/publish op through this RPC and treat the returned version as authoritative.';

-- ----------------------------------------------------------------------------
-- Item photos: public bucket `menu`, objects at {tenant_id}/{item_id}.jpg.
-- Reads are public (customer storefront); writes are limited to members of
-- the tenant that owns the folder (first path segment).
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('menu', 'menu', true)
on conflict (id) do nothing;

drop policy if exists "public read menu photos" on storage.objects;
create policy "public read menu photos"
  on storage.objects for select
  using (bucket_id = 'menu');

drop policy if exists "tenant members upload menu photos" on storage.objects;
create policy "tenant members upload menu photos"
  on storage.objects for insert
  with check (
    bucket_id = 'menu'
    and public.is_tenant_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "tenant members replace menu photos" on storage.objects;
create policy "tenant members replace menu photos"
  on storage.objects for update
  using (
    bucket_id = 'menu'
    and public.is_tenant_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'menu'
    and public.is_tenant_member(((storage.foldername(name))[1])::uuid)
  );
