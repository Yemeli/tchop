-- ============================================================================
-- TCHOP — staff invites: pending memberships claimed by phone on sign-in.
--
-- Flow:
--   1. An owner/manager enqueues `membership/invite` (outbox); the `sync`
--      Edge Function inserts a membership row with `user_id = NULL` and
--      `invited_phone` = the invitee's E.164 number.
--   2. On the invitee's first OTP sign-in the app calls
--      `claim_invited_memberships()`, which links every pending invite whose
--      phone matches `auth.users.phone` to the new user id.
-- ============================================================================

alter table public.memberships
  add column if not exists invited_phone text;

-- The invitee has no auth user yet when the invite row is created.
alter table public.memberships
  alter column user_id drop not null;

-- One pending invite per phone per tenant (claimed rows keep the original
-- unique(tenant_id, user_id) constraint; NULL user_ids never collide).
create unique index if not exists memberships_pending_invite_uidx
  on public.memberships (tenant_id, invited_phone)
  where user_id is null;

comment on column public.memberships.invited_phone is
  'E.164 phone of an invited staff member who has not signed in yet. '
  'Claimed (user_id set, invited_phone cleared) on first OTP sign-in via '
  'public.claim_invited_memberships().';

-- ----------------------------------------------------------------------------
-- Claim pending invites for the signed-in user (by phone).
-- SECURITY DEFINER: the caller cannot read other tenants' pending rows.
-- ----------------------------------------------------------------------------
create or replace function public.claim_invited_memberships()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_claimed integer := 0;
begin
  if auth.uid() is null then
    return 0;
  end if;

  select phone into v_phone from auth.users where id = auth.uid();
  if v_phone is null or v_phone = '' then
    return 0;
  end if;

  -- Link every pending invite for this phone, unless the user already
  -- belongs to that tenant (keeps unique(tenant_id, user_id) intact).
  update public.memberships m
     set user_id = auth.uid(),
         invited_phone = null
   where m.user_id is null
     and m.invited_phone = v_phone
     and not exists (
       select 1
         from public.memberships m2
        where m2.tenant_id = m.tenant_id
          and m2.user_id = auth.uid()
     );
  get diagnostics v_claimed = row_count;

  -- Clean up duplicate pending invites that could not be claimed because
  -- the user already belonged to the tenant through another invite.
  delete from public.memberships m
   where m.user_id is null
     and m.invited_phone = v_phone;

  return v_claimed;
end;
$$;

grant execute on function public.claim_invited_memberships() to authenticated;

comment on function public.claim_invited_memberships() is
  'Links pending staff invites (invited_phone) to the signed-in user by '
  'matching auth.users.phone. Called once after OTP sign-in.';

-- ----------------------------------------------------------------------------
-- Let an invited (not yet claimed) user see their own pending invite, so the
-- app can show "Vous avez été invité par X" before the claim runs. The phone
-- comes from the JWT claim, never from client input.
-- ----------------------------------------------------------------------------
create policy "users read own pending invites"
  on public.memberships for select
  using (
    user_id is null
    and invited_phone = (auth.jwt() ->> 'phone')
  );
