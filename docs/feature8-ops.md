# Feature 8 — New outbox ops & Edge Function notes

## New outbox ops (client → `sync` Edge Function)

| op | entity | payload | roles | server behavior |
|---|---|---|---|---|
| `order/void` | `order` | `{order_id, reason?}` | secretary / manager / owner | Sets `orders.status='cancelled'` from **any** non-delivered state (unlike `order/transition`, which only allows cancel early). 422 for delivered orders (use a refund). Appends `audit_logs` row `action='order.void'`, `before={status,total}`, `after={status:'cancelled',reason}` — this is what the manager alerts feed reads. Idempotent: replay on already-cancelled → 200. |
| `inventory/set_count` | `inventory` | `{item_id, item_name, count, low_threshold, counted_at}` | any tenant member | **PHASE 2 STUB (honest):** no server table yet. The op is ledgered (idempotent) and audit-logged (`action='inventory.set_count'`) so a future `inventory` table can replay history. Counts stay authoritative on-device (JSON file per tenant). |
| `platform/suspend_tenant` | `platform` | `{tenant_id, suspend: bool}` | **platform admin only** | Flips the tenant's latest `subscriptions.status` `suspended` ↔ `active` (inserts a `trial` row defensively if none exists). Audit-logged as `platform.tenant_suspended` / `platform.tenant_restored` on the **target** tenant. **Never moves restaurant money** — subscription status only. |

### `order/create` payload extension (POS discounts)

- New optional fields: `discount_fcfa` (int ≥ 0), `discount_reason` (string ≤ 280 chars).
- **Server rules** (`sync/index.ts` + `create_order_validated` RPC):
  - Only staff channels (`phone`, `walkin`, `whatsapp`) may set it — zeroed for `app`/`qr_table` so customers can never self-discount.
  - Clamped to the subtotal (`total = subtotal + delivery_fee − discount`, never negative).
  - Positive discounts write an append-only `audit_logs` row `action='order.discount'`, `after={discount_fcfa, reason, subtotal, total}` (manager void/discount alerts).
  - RPC signature is backwards-compatible (new params defaulted); response now includes `discount_fcfa`.
- Schema: `supabase/migrations/20260927_feature8_discount_void.sql` adds `orders.discount_fcfa` / `orders.discount_reason` and replaces the RPC.

## Strict gating for `platform/suspend_tenant`

1. **Membership gate bypass is explicit:** `entity === "platform"` skips the tenant-membership check (`isPlatformOp`), because platform admins are not members of the tenants they oversee.
2. **STRICT verification inside the handler:** the caller (`auth.uid()` from their own JWT) is looked up in `platform_admins` **with the service-role client** — RLS is bypassed for `db`, so this check cannot be inherited from any tenant path. Non-admin → `403 forbidden_not_platform_admin`, even if they own the target tenant.
3. Client-side defense in depth: `SuperAdminScreen` renders only when `PlatformAdmin.isAdmin()` (fail-closed, 5-min cache), and `SuperAdminRepository` re-checks before every call.

## Edge Function environment requirements

**No new env vars.** `platform/suspend_tenant`, `order/void`, and `inventory/set_count` reuse the existing `SUPABASE_URL`, `SUPABASE_ANON_KEY` (caller JWT verification), and `SUPABASE_SERVICE_ROLE_KEY` (privileged writes + the strict `platform_admins` lookup).

## Deploy checklist (for the parent agent / Gayellen)

- [ ] `supabase db push` — applies `20260927_feature8_discount_void.sql` (RPC replace is `CREATE OR REPLACE` + a `DROP` of the old 10-arg signature).
- [ ] `supabase functions deploy sync` — new op handlers.
- [ ] Insert Gayellen's user id into `platform_admins` (one row; service-level RLS policy already exists) to unlock the Super-admin console.
- [ ] Still not run (no Flutter SDK): `flutter analyze`, `flutter test`, `build_runner` codegen.
