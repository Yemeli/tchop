-- ============================================================================
-- TCHOP — Feature 8: POS discounts + order voids.
--
-- 1. `orders.discount_fcfa` / `orders.discount_reason` — counter discounts
--    taken at the POS (secretary). The server clamps the discount to the
--    subtotal and recomputes the total: total = subtotal + delivery_fee -
--    discount. Client-sent totals remain ignored (see 20260927_order_validation).
-- 2. `create_order_validated(...)` gains `p_discount_fcfa` /
--    `p_discount_reason` (both defaulted, so existing callers keep working).
--    A positive discount writes an append-only `audit_logs` row
--    (action = 'order.discount') — this is what the manager's void/discount
--    alerts feed reads.
-- 3. Order voids are handled by the `sync` Edge Function op `order/void`
--    (action = 'order.void' in audit_logs); no schema change needed there.
--
-- NOTE (Dart mirror): apps/tchop/lib/features/orders/order_validation.dart
-- validates lines only; totals (incl. discount) are recomputed here, and
-- the POS applies the same clamp client-side for the optimistic UI.
-- ============================================================================

alter table public.orders
  add column if not exists discount_fcfa integer not null default 0,
  add column if not exists discount_reason text;

comment on column public.orders.discount_fcfa is
  'Counter discount in FCFA (minor units), clamped server-side to the subtotal.';
comment on column public.orders.discount_reason is
  'Free-text reason for the discount (e.g. client fidele, geste commercial).';

-- Replace the 10-arg function with the 12-arg version (defaults keep the
-- old call shape working).
drop function if exists public.create_order_validated(
  uuid, uuid, uuid, integer, jsonb, jsonb, text, text, uuid, integer);

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
  p_table_number     integer,
  p_discount_fcfa    integer default 0,
  p_discount_reason  text    default null
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
  v_discount        integer := 0;
  v_total           integer;
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

  -- (e) counter discount, clamped to the subtotal (total can never go
  -- negative). Only staff channels set this; app/qr_table payloads must
  -- leave it at 0 (the Edge Function zeroes it for customer channels).
  v_discount := greatest(
    0,
    least(coalesce(p_discount_fcfa, 0), v_subtotal));
  v_total := v_subtotal + v_delivery_fee - v_discount;

  begin
    insert into public.orders (
      id, tenant_id, client_mutation_id, menu_version, lines,
      subtotal, delivery_fee, discount_fcfa, discount_reason, total,
      customer_name, customer_phone, channel, table_number,
      payment_method, status, created_by
    ) values (
      p_order_id, p_tenant_id, p_client_mutation_id, p_menu_version,
      v_clean_lines,
      v_subtotal, v_delivery_fee,
      v_discount,
      case when v_discount > 0 then nullif(trim(p_discount_reason), '') end,
      v_total,
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

  -- Append-only audit trail for the manager's discount alerts.
  if v_discount > 0 then
    insert into public.audit_logs (
      tenant_id, user_id, action, entity, entity_id, before, after
    ) values (
      p_tenant_id, p_created_by, 'order.discount', 'order', v_new_id::text,
      null,
      jsonb_build_object(
        'discount_fcfa', v_discount,
        'reason', nullif(trim(p_discount_reason), ''),
        'subtotal', v_subtotal,
        'total', v_total)
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'order_id', v_new_id,
    'subtotal', v_subtotal,
    'delivery_fee', v_delivery_fee,
    'discount_fcfa', v_discount,
    'total', v_total,
    'menu_version', v_current_version);
end;
$$;

comment on function public.create_order_validated(
  uuid, uuid, uuid, integer, jsonb, jsonb, text, text, uuid, integer,
  integer, text
) is
  'Feature 8: transactional order/create validation + counter discounts '
  '(clamped to subtotal, audit-logged as order.discount).';
