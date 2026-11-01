-- ============================================================================
-- TCHOP — tighten membership management RBAC.
--
-- The init migration's "owners and managers manage memberships" policy used
-- `is_tenant_member(tenant_id)` in its USING/WITH CHECK clauses, which is
-- true for ANY role — so a driver or kitchen staffer could promote
-- themselves to owner through direct PostgREST access. The app's invite
-- flow already enforces owner/manager-only in the `sync` Edge Function;
-- this closes the same hole at the database layer.
--
-- Pending invites (user_id IS NULL) are still written by the service-role
-- Edge Function and claimed by the SECURITY DEFINER
-- `claim_invited_memberships()` function — neither goes through this policy.
-- ============================================================================

create or replace function public.is_tenant_owner_or_manager(p_tenant uuid)
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
      and role in ('owner', 'manager')
  );
$$;

comment on function public.is_tenant_owner_or_manager(uuid) is
  'True when the caller is an owner or manager of the tenant. Used by the '
  'membership management policy so kitchen/driver/secretary roles cannot '
  'invite staff or change roles.';

drop policy if exists "owners and managers manage memberships"
  on public.memberships;

create policy "owners and managers manage memberships"
  on public.memberships for all
  using (
    public.is_tenant_owner_or_manager(tenant_id)
    or public.is_platform_admin()
  )
  with check (
    public.is_tenant_owner_or_manager(tenant_id)
    or public.is_platform_admin()
  );
