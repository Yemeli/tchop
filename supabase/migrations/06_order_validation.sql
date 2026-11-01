-- ============================================================================
-- TCHOP — order intake validation (Feature 4).
--
-- 1. `tenants.delivery_fee_fcfa` — the restaurant's configured delivery fee.
--    The server recomputes order totals from this column; client-sent totals
--    are IGNORED (they exist only for the optimistic UI).
-- 2. `orders.table_number` — for `qr_table` channel orders.
-- 3. `public.create_order_validated(...)` — the whole `order/create`
--    validation + insert in ONE transaction (called by the `sync` Edge
--    Function). Mirrors the pure-Dart algorithm in
--    `apps/tchop/lib/features/orders/order_validation.dart` — keep them in
--    sync.
--
-- Validation rules (in order):
--   a. menu_version must equal the current published snapshot version,
--      else a single {item_id: null, reason: 'stale_menu'} conflict;
--   b. every line: item exists in the snapshot AND item_availability
--      (default true) — else {reason: 'unavailable'};
--   c. unit_price must equal the snapshot price — else
--      {reason: 'price_changed', current_price};
--   d. totals recomputed server-side (subtotal from snapshot prices +
--      tenants.delivery_fee_fcfa); client totals ignored.
-- Returns: {ok, order_id?, subtotal?, delivery_fee?, total?,
--           menu_version?, conflicts?} / {ok: true, duplicate: true, …}
--          on client_mutation_id replay (idempotent).
-- ============================================================================

alter table public.tenants
  add column if not exists delivery_fee_fcfa integer not null default 0;

alter table public.orders
  add column if not exists table_number integer;

comment on column public.tenants.delivery_fee_fcfa is
  'Flat delivery fee in FCFA (minor units). Server recomputes order totals from this.';
comment on column public.orders.table_number is
  'Physical table number for qr_table channel orders.';

create or replace function public.create_order_validated(
  p_tenant_id        uuid,
  p_order_id         uuid,
  p_client_mutation_id uuid,
  p_menu_version     integer,
  p_lines            jsonb,   -- [{item_id, qty, unit_price}]
  p_customer         jsonb,   -- {name, phone, address?}
  p_channel          text,
  p_payment_method   text,
  p_created_by       uuid,
  p_table_number     integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_version integer;
  v_snapshot_items  jsonb;
  v_price_map       jsonb;
  v_avail_map       jsonb := '{}'::jsonb;
  v_conflicts       jsonb := '[]'::jsonb;
  v_clean_lines     jsonb := '[]'::jsonb;
  v_subtotal        integer := 0;
  v_delivery_fee    integer := 0;
  v_line            jsonb;
  v_item_id         text;
  v_qty             integer;
  v_price           integer;
  v_avail           boolean;
  v_new_id          uuid;
begin
  -- (a) stale-menu check against the current published snapshot.
  select max(version) into v_current_version
    from public.menu_snapshots
   where tenant_id = p_tenant_id;

  if v_current_version is null then
    return jsonb_build_object(
      'ok', false,
      'conflicts', jsonb_build_array(
        jsonb_build_object('item_id', null,
                           'reason', 'no_menu_published')));
  end if;

  if v_current_version is distinct from p_menu_version then
    return jsonb_build_object(
      'ok', false,
      'conflicts', jsonb_build_array(
        jsonb_build_object('item_id', null,
                           'reason', 'stale_menu',
                           'current_menu_version', v_current_version)));
  end if;

  -- Snapshot doc shape: MenuDraftDoc.toJson → {items: [{id, price_fcfa…}]}.
  -- Tolerate a bare items array for older snapshots.
  select items into v_snapshot_items
    from public.menu_snapshots
   where tenant_id = p_tenant_id
     and version = v_current_version;

  select jsonb_object_agg(i ->> 'id', (i ->> 'price_fcfa')::int)
    into v_price_map
    from jsonb_array_elements(
           coalesce(v_snapshot_items -> 'items', v_snapshot_items)) as i;

  select jsonb_object_agg(item_id, available)
    into v_avail_map
    from public.item_availability
   where tenant_id = p_tenant_id;
  v_avail_map := coalesce(v_avail_map, '{}'::jsonb);

  -- (b)+(c) per-line checks; rebuild lines with server-side prices.
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_item_id := v_line ->> 'item_id';
    v_qty     := coalesce((v_line ->> 'qty')::int, 0);

    if v_qty <= 0 then
      v_conflicts := v_conflicts || jsonb_build_object(
        'item_id', v_item_id, 'reason', 'invalid_qty');
      continue;
    end if;

    v_price := (v_price_map ->> v_item_id)::int;
    if v_price is null then
      v_conflicts := v_conflicts || jsonb_build_object(
        'item_id', v_item_id, 'reason', 'unavailable');
      continue;
    end if;

    v_avail := coalesce((v_avail_map ->> v_item_id)::boolean, true);
    if not v_avail then
      v_conflicts := v_conflicts || jsonb_build_object(
        'item_id', v_item_id, 'reason', 'unavailable');
      continue;
    end if;

    if (v_line ->> 'unit_price')::int is distinct from v_price then
      v_conflicts := v_conflicts || jsonb_build_object(
        'item_id', v_item_id, 'reason', 'price_changed',
        'current_price', v_price);
      continue;
    end if;

    v_subtotal    := v_subtotal + v_qty * v_price;
    v_clean_lines := v_clean_lines || jsonb_build_object(
      'item_id', v_item_id, 'qty', v_qty, 'unit_price', v_price);
  end loop;

  if jsonb_array_length(v_conflicts) > 0 then
    return jsonb_build_object('ok', false, 'conflicts', v_conflicts);
  end if;

  -- (d) server-side totals; client totals are ignored.
  select delivery_fee_fcfa into v_delivery_fee
    from public.tenants
   where id = p_tenant_id;
  v_delivery_fee := coalesce(v_delivery_fee, 0);

  begin
    insert into public.orders (
      id, tenant_id, client_mutation_id, menu_version, lines,
      subtotal, delivery_fee, total,
      customer_name, customer_phone, channel, table_number,
      payment_method, status, created_by
    ) values (
      p_order_id, p_tenant_id, p_client_mutation_id, p_menu_version,
      v_clean_lines,
      v_subtotal, v_delivery_fee, v_subtotal + v_delivery_fee,
      p_customer ->> 'name', p_customer ->> 'phone', p_channel,
      p_table_number, p_payment_method, 'placed', p_created_by
    )
    returning id into v_new_id;
  exception when unique_violation then
    -- Idempotent replay of the same client_mutation_id: report the
    -- existing order instead of failing.
    select id into v_new_id
      from public.orders
     where client_mutation_id = p_client_mutation_id;
    return jsonb_build_object(
      'ok', true, 'duplicate', true, 'order_id', v_new_id);
  end;

  return jsonb_build_object(
    'ok', true,
    'order_id', v_new_id,
    'subtotal', v_subtotal,
    'delivery_fee', v_delivery_fee,
    'total', v_subtotal + v_delivery_fee,
    'menu_version', v_current_version);
end;
$$;

comment on function public.create_order_validated(
  uuid, uuid, uuid, integer, jsonb, jsonb, text, text, uuid, integer
) is
  'Feature 4: transactional order/create validation — stale-menu, availability '
  'and price checks, server-side totals, idempotent on client_mutation_id.';
