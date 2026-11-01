// ============================================================================
// TCHOP — `sync` Edge Function.
//
// Receives the offline outbox from the Flutter client and applies each
// mutation idempotently.
//
// Request:
//   POST /functions/v1/sync
//   Idempotency-Key: <outbox entry id, UUID v4>
//   Authorization: Bearer <user JWT>
//   {
//     "client_mutation_id": "uuid",   // business-level dedupe key
//     "tenant_id": "uuid",
//     "op": "create" | "update" | "delete" | "transition"
//         | "menu/draft_save" | "menu/publish" | "menu/set_availability"
//         | "menu/approve_price" | "menu/request_86"
//         | "order/create" | "order/transition" | "order/void"
//         | "delivery/assign" | "delivery/complete"
//         | "payments/credentials_save" | "payments/credentials_rotate"
//         | "payments/credentials_revoke" | "payments/cash_close"
//         | "payments/refund_request" | "payments/refund_approve"
//         | "payments/refund_reject"
//         | "inventory/set_count"
//         | "platform/suspend_tenant"
//     "entity": "order" | "item_availability" | "delivery" | "payment"
//             | "menu_draft" | "menu_snapshot" | "menu_approval"
//             | "payment_credential" | "cash_close" | "refund_request"
//             | "tenant" | "membership" | "branding"
//             | "platform" | "inventory",
//     "entity_id": "…",
//     "payload": { … }
//   }
//
// Payments ops (Feature 7):
// - payments/credentials_save   → owner/manager only. Plaintext credential
//     blob is encrypted server-side via Supabase Vault BEFORE insert; only
//     the Vault secret id + masked key_fingerprint are stored. Audit-logged.
// - payments/credentials_rotate → owner/manager only. New Vault secret, row
//     pointer swapped, old secret kept for audit (never reused).
// - payments/credentials_revoke → owner/manager only. is_active=false; row +
//     audit trail kept.
// - payments/verify             → NOT an outbox op; see the dedicated
//     `payments-verify` edge function (interactive, returns a verdict).
// - payments/cash_close         → secretary/owner/manager. Stores the day's
//     {expected, counted, variance}; server recomputes variance; one row per
//     tenant per business_date (unique constraint).
// - payments/refund_request     → owner/manager. Creates a pending
//     refund_requests row (four-eyes: requester cannot approve).
// - payments/refund_approve     → owner/manager ≠ requester. Marks the
//     payment refunded, orders.payment_status → 'refunded', audit-logged.
//     Does NOT move money (manual provider refund — see migration notes).
// - payments/refund_reject      → owner/manager ≠ requester.
//
// Orders (Feature 4):
// - order/create     → CANONICAL payload (snake_case, FCFA minor units):
//     { op:"order/create", menu_version, lines:[{item_id, qty, unit_price}],
//       subtotal, delivery_fee, total, channel, customer:{name, phone},
//       payment_method, client_mutation_id } (+ table_number for qr_table,
//       + discount_fcfa/discount_reason for staff/POS counter discounts).
//     Validated INSIDE one transaction by public.create_order_validated():
//       stale menu_version → 409 {conflicts:[{item_id:null,
//         reason:"stale_menu", current_menu_version}]};
//       unknown/86'd item → 409 {conflicts:[{item_id, reason:"unavailable"}]};
//       price mismatch   → 409 {conflicts:[{item_id, reason:"price_changed",
//         current_price}]};
//     Totals are RECOMPUTED server-side; client totals are IGNORED.
//     discount_fcfa is clamped to the subtotal server-side and audit-logged
//     (action "order.discount"); only staff channels may set it (zeroed for
//     app/qr_table). Returns {discount_fcfa} alongside the totals.
//     NOTE: this 409 is NOT a duplicate — it carries a `conflicts` array
//     (duplicates carry `duplicate:true`). The client tells them apart via
//     the body. Staff channels (phone/walkin/whatsapp) require a workspace
//     membership; app/qr_table are open to any authenticated user.
// - order/transition → payload {order_id, to}. Enforces the legal
//     transition map (placed→accepted→preparing→ready→picked_up→delivered,
//     cancel from placed/accepted/preparing only) + per-transition role
//     gates, and appends an `order.transition` row to audit_logs.
// - order/void       → secretary/manager/owner only. Payload {order_id,
//     reason?}. Cancels an order from ANY non-delivered state (unlike
//     order/transition, which only allows cancel early in the flow) and
//     appends an `order.void` row to audit_logs — this is what the
//     manager's void/discount alerts feed reads. Delivered orders can
//     never be voided (use a refund instead).
//
// Dispatch (Feature 6):
// - delivery/assign   → owner/manager/secretary only. Creates a
//     `deliveries` row {order_id, driver_id, dropoff_*} — the assignee must
//     be a membership with role='driver'. The order stays `ready` until the
//     driver marks it `picked_up` via `order/transition`.
// - delivery/complete → driver (own delivery) / owner / manager. Persists
//     the proof of delivery on the `deliveries` row (delivered_at,
//     pod_photo_url, pod_signature_url as a data: URI of the SVG,
//     pod_lat/lng) and reconciles the order milestones: an order still
//     `picked_up` moves to `delivered` (idempotent).
//
// Menu ops (Feature 3):
// - menu/draft_save      → upsert menu_drafts (debounced client writes).
// - menu/publish         → publish_menu_snapshot() RPC: per-tenant advisory
//                          lock + max(version)+1 INSIDE one transaction.
//                          The client-sent version is ADVISORY ONLY; the
//                          returned version is authoritative.
// - menu/set_availability→ upsert item_availability (86 fast path).
// - menu/approve_price    → owner/manager decision on a pending approval
//                          (applies the price server-side when approved).
// - menu/request_86       → kitchen staff file an 86 request; appended to
//                          the draft's approvals inbox, never flips
//                          availability directly.
//
// Realtime 86 fan-out (customer apps): the Flutter client ALSO broadcasts
//   channel `tenant:{tenant_id}:availability`, event `availability_changed`,
//   payload {tenant_id, item_id, available, at}
// directly from the device for ~1–2s propagation; the outbox op above is
// the durable source of truth.
//
// Session & provisioning ops (Feature 2 — auth + tenant onboarding):
// - tenant/create      → create tenant + owner membership + 30-day trial
//                        subscription. tenant_id/entity_id is the
//                        CLIENT-GENERATED UUID (the tenant does not exist
//                        yet, so the membership check is skipped for this
//                        op — the caller becomes owner). Payload: name,
//                        slug, primary_color?, secondary_color?, logo_url?.
// - membership/invite  → pending staff invite (user_id NULL, invited_phone
//                        set). Owner invites any role; manager any but
//                        owner. Payload: phone (E.164), role.
// - branding/update    → patch tenant brand columns (owner/manager only).
//                        Payload may contain: name, primary_color,
//                        secondary_color, logo_url.
//
// Feature 8 — dashboards & super-admin:
// - order/void            → secretary/manager/owner. Cancels from any
//     non-delivered state; appends `order.void` to audit_logs (manager
//     alerts feed). 422 for delivered orders (use a refund instead).
// - inventory/set_count   → PHASE 2 STUB. Any tenant member. No server
//     table yet: counts stay authoritative on-device; the op is ledgered +
//     audit-logged (`inventory.set_count`) so a future table can replay.
// - platform/suspend_tenant → PLATFORM ADMIN ONLY (verified against
//     `platform_admins` with the service-role client; the tenant-membership
//     gate is skipped for `entity: "platform"`). Payload {tenant_id,
//     suspend: bool} → flips the latest subscriptions.status
//     suspended↔active, audit-logged as platform.tenant_suspended/restored.
//     No new env vars: uses the existing SUPABASE_URL /
//     SUPABASE_SERVICE_ROLE_KEY.
//
// Response:
//   200  applied now (publish also returns {"version": n})
//   409  already applied (same client_mutation_id seen before) — the client
//        drops the outbox entry; safe by construction
//   400  malformed envelope / unsupported entity+op
//   401  no (valid) user session
//   403  caller is not a member of the tenant (or lacks the role for the op)
//   422  transition rejected (e.g. backward order status)
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type Envelope = {
  client_mutation_id: string;
  tenant_id: string;
  op: string;
  entity:
    | "order"
    | "item_availability"
    | "delivery"
    | "payment"
    | "menu_draft"
    | "menu_snapshot"
    | "menu_approval"
    | "payment_credential"
    | "cash_close"
    | "refund_request"
    | "tenant"
    | "membership"
    | "branding"
    | "platform"
    | "inventory";
  entity_id: string;
  payload: Record<string, unknown>;
};

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // --- auth: caller identity from their own JWT --------------------------------
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);
  const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
  } = await userClient.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  // --- envelope validation ------------------------------------------------------
  let env: Envelope;
  try {
    env = (await req.json()) as Envelope;
  } catch {
    return json({ error: "malformed_envelope" }, 400);
  }
  const { client_mutation_id, tenant_id, op, entity, entity_id, payload } = env;
  if (!client_mutation_id || !tenant_id || !op || !entity) {
    return json({ error: "malformed_envelope" }, 400);
  }

  // Privileged client; every statement below re-checks membership explicitly
  // so RLS bypass can never leak across tenants.
  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // `tenant/create` is the bootstrap op: the tenant does not exist yet, so
  // there is no membership to check — the caller becomes its owner below.
  // `order/create` is customer-facing: guests placing app/qr_table orders are
  // not workspace members (staff channels re-check membership inside the
  // handler). Every other op requires an existing membership.
  const isTenantCreate = entity === "tenant" && op === "create";
  const isOrderCreate = entity === "order" && op === "order/create";
  // Platform ops (super-admin console) are NOT tenant-membership-gated:
  // the caller is verified against `platform_admins` inside the handler
  // itself (STRICT — service-role query, never trusted from the client).
  const isPlatformOp = entity === "platform";

  const { data: membership } = isTenantCreate || isOrderCreate || isPlatformOp
    ? { data: null }
    : await db
        .from("memberships")
        .select("id, role")
        .eq("tenant_id", tenant_id)
        .eq("user_id", user.id)
        .maybeSingle();
  if (!membership && !isTenantCreate && !isOrderCreate && !isPlatformOp)
    return json({ error: "forbidden" }, 403);

  // Role gates for menu ops (mirror MenuPermissions in the Flutter app):
  // owner/manager = full menu control + publish; head_chef = item edits +
  // 86 toggle, no prices; kitchen staff may only *request* an 86.
  // Empty for `tenant/create` (no membership exists yet).
  const role = membership
    ? String((membership as { role?: string }).role ?? "")
    : "";
  const canManageMenu = role === "owner" || role === "manager";
  const canToggle86 =
    canManageMenu || role === "head_chef";
  const canEditDraft = canManageMenu || role === "head_chef";

  // --- idempotency gate ----------------------------------------------------------
  // A replayed mutation must not double-apply. Each entity table carries the
  // client's key (orders.client_mutation_id; others keyed via audit below).
  // We record every applied mutation in a sync ledger keyed on
  // client_mutation_id; a second delivery of the same key answers 409.
  const { data: seen } = await db
    .from("sync_ledger")
    .select("client_mutation_id")
    .eq("client_mutation_id", client_mutation_id)
    .maybeSingle();
  if (seen) return json({ applied: false, duplicate: true }, 409);

  const ledger = async () => {
    await db.from("sync_ledger").insert({
      client_mutation_id,
      tenant_id,
      op,
      entity,
      entity_id,
      idempotency_key: req.headers.get("Idempotency-Key"),
    });
  };

  // --- apply ---------------------------------------------------------------------
  // Feature 2 — workspace provisioning & staff invites.
  //
  // NOTE: the Flutter app creates workspaces through the atomic
  // `create_workspace` RPC (single transaction: tenant + owner membership
  // + 30-day trial), not through this op — workspace creation is
  // explicitly online-only because slug uniqueness is server-side. The
  // `tenant/create` handler below is kept as an equivalent offline-capable
  // path for future use; today nothing enqueues it.
  try {
    if (entity === "tenant" && op === "create") {
      const name = String(payload["name"] ?? "").trim();
      const slug = String(payload["slug"] ?? "").trim().toLowerCase();
      if (!name || !/^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(slug)) {
        return json({ error: "invalid_tenant" }, 400);
      }
      const trialEnd = new Date(
        Date.now() + 30 * 24 * 3600 * 1000,
      ).toISOString();
      const { error: tenantError } = await db.from("tenants").insert({
        id: entity_id, // client-generated UUID → natural idempotency key
        name,
        slug,
        primary_color: payload["primary_color"] ?? "#FF6B35",
        secondary_color: payload["secondary_color"] ?? null,
        logo_url: payload["logo_url"] ?? null,
      });
      if (tenantError) {
        if (tenantError.code === "23505") {
          // Either an idempotent replay of OUR tenant id, or a slug race
          // with another tenant.
          const { data: ours } = await db
            .from("tenants")
            .select("id")
            .eq("id", entity_id)
            .maybeSingle();
          if (ours) return json({ applied: false, duplicate: true }, 409);
          return json({ error: "slug_taken" }, 400);
        }
        throw tenantError;
      }
      const { error: memberError } = await db.from("memberships").insert({
        tenant_id: entity_id,
        user_id: user.id,
        role: "owner",
      });
      if (memberError) throw memberError;
      const { error: subError } = await db.from("subscriptions").insert({
        tenant_id: entity_id,
        plan: "trial",
        status: "trialing",
        trial_ends_at: trialEnd,
        current_period_end: trialEnd,
      });
      if (subError) throw subError;
      await ledger();
      return json({ applied: true, tenant_id: entity_id }, 200);
    }

    if (entity === "membership" && op === "invite") {
      const phone = String(payload["phone"] ?? "").trim();
      const targetRole = String(payload["role"] ?? "");
      if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
        return json({ error: "invalid_phone" }, 400);
      }
      const validRoles = [
        "owner",
        "manager",
        "head_chef",
        "secretary",
        "kitchen",
        "driver",
      ];
      if (!validRoles.includes(targetRole)) {
        return json({ error: "invalid_role" }, 400);
      }
      // Mirror canInviteRole() in the Flutter app: owner invites anyone,
      // manager invites anyone except owner.
      const mayInvite =
        role === "owner" || (role === "manager" && targetRole !== "owner");
      if (!mayInvite) return json({ error: "forbidden_role" }, 403);
      const { error } = await db.from("memberships").insert({
        id: entity_id,
        tenant_id,
        user_id: null, // claimed on the invitee's first OTP sign-in
        role: targetRole,
        invited_phone: phone,
      });
      if (error) {
        // Duplicate invite (same id, or same tenant+phone via the partial
        // unique index) → treat as already applied.
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "branding" && op === "update") {
      const mayBrand = role === "owner" || role === "manager";
      if (!mayBrand) return json({ error: "forbidden" }, 403);
      const patch: Record<string, unknown> = {};
      for (const key of [
        "name",
        "primary_color",
        "secondary_color",
        "logo_url",
      ]) {
        if (payload[key] !== undefined && payload[key] !== null) {
          patch[key] = payload[key];
        }
      }
      if (Object.keys(patch).length === 0) {
        await ledger();
        return json({ applied: true }, 200);
      }
      const { error } = await db
        .from("tenants")
        .update(patch)
        .eq("id", tenant_id);
      if (error) throw error;
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "order" && op === "order/create") {
      // --- Feature 4: validated order intake --------------------------------
      // The canonical payload is validated + inserted inside ONE transaction
      // by public.create_order_validated() (see
      // supabase/migrations/20260927_order_validation.sql). The Dart mirror
      // of the algorithm lives in
      // apps/tchop/lib/features/orders/order_validation.dart.
      const channel = String(payload["channel"] ?? "app");
      const validChannels = ["app", "whatsapp", "phone", "walkin", "qr_table"];
      if (!validChannels.includes(channel)) {
        return json({ error: "invalid_channel" }, 400);
      }
      // Staff channels (counter / phone / WhatsApp) require a workspace
      // membership; customer channels (app / qr_table) are open to any
      // authenticated user.
      const staffChannels = ["phone", "walkin", "whatsapp"];
      if (staffChannels.includes(channel) && !membership) {
        return json({ error: "forbidden" }, 403);
      }
      const { data: tenantRow } = await db
        .from("tenants")
        .select("id")
        .eq("id", tenant_id)
        .maybeSingle();
      if (!tenantRow) return json({ error: "unknown_tenant" }, 400);

      const lines = payload["lines"];
      if (!Array.isArray(lines) || lines.length === 0) {
        return json({ error: "empty_lines" }, 400);
      }
      for (const line of lines) {
        const l = line as Record<string, unknown>;
        if (
          typeof l["item_id"] !== "string" ||
          !Number.isInteger(l["qty"]) ||
          !Number.isInteger(l["unit_price"])
        ) {
          return json({ error: "invalid_line" }, 400);
        }
      }
      const paymentMethod = payload["payment_method"];
      const validPayments = [
        "mtn_momo",
        "orange_money",
        "wave",
        "cash",
        "card",
      ];
      if (paymentMethod != null && !validPayments.includes(String(paymentMethod))) {
        return json({ error: "invalid_payment_method" }, 400);
      }
      const customer = (payload["customer"] as Record<string, unknown>) ?? {};
      const tableNumber =
        payload["table_number"] == null
          ? null
          : Number(payload["table_number"]);

      // Counter discount (Feature 8 — POS). Only staff channels may set
      // it; app/qr_table payloads are zeroed here so a customer can never
      // self-discount. The RPC clamps to the subtotal and audit-logs
      // (action "order.discount").
      const rawDiscount = Number(payload["discount_fcfa"] ?? 0);
      const discountFcfa =
        staffChannels.includes(channel) &&
        Number.isInteger(rawDiscount) &&
        rawDiscount > 0
          ? rawDiscount
          : 0;
      const discountReason =
        discountFcfa > 0 && typeof payload["discount_reason"] === "string"
          ? String(payload["discount_reason"]).slice(0, 280)
          : null;

      const { data: result, error } = await db.rpc(
        "create_order_validated",
        {
          p_tenant_id: tenant_id,
          p_order_id: entity_id, // client-generated UUID → idempotent
          p_client_mutation_id: client_mutation_id,
          p_menu_version: Number(payload["menu_version"] ?? 0),
          p_lines: lines,
          p_customer: customer,
          p_channel: channel,
          p_payment_method:
            paymentMethod == null ? null : String(paymentMethod),
          p_created_by: user.id,
          p_table_number:
            tableNumber == null || !Number.isInteger(tableNumber)
              ? null
              : tableNumber,
          p_discount_fcfa: discountFcfa,
          p_discount_reason: discountReason,
        },
      );
      if (error) throw error;
      const r = result as {
        ok: boolean;
        duplicate?: boolean;
        order_id?: string;
        subtotal?: number;
        delivery_fee?: number;
        total?: number;
        menu_version?: number;
        conflicts?: unknown[];
      };
      if (!r.ok) {
        // Validation failure — NOT a duplicate. The client distinguishes
        // via the `conflicts` array (duplicates carry `duplicate: true`).
        return json(
          { applied: false, error: "order_conflict", conflicts: r.conflicts ?? [] },
          409,
        );
      }
      if (r.duplicate) {
        return json(
          { applied: false, duplicate: true, order_id: r.order_id },
          409,
        );
      }
      await ledger();
      return json(
        {
          applied: true,
          order_id: r.order_id,
          subtotal: r.subtotal,
          delivery_fee: r.delivery_fee,
          discount_fcfa: (r as { discount_fcfa?: number }).discount_fcfa ?? 0,
          total: r.total,
          menu_version: r.menu_version,
        },
        200,
      );
    }

    if (entity === "order" && op === "order/void") {
      // --- Feature 8: staff order void --------------------------------------
      // secretary/manager/owner only. Cancels from ANY non-delivered state
      // (order/transition only allows cancel early in the flow) and appends
      // an `order.void` row to audit_logs — this is what the manager's
      // void/discount alerts feed reads. Delivered orders can never be
      // voided: issue a refund (`payments/refund_request`) instead.
      const voidRoles = ["secretary", "manager", "owner"];
      if (!membership || !voidRoles.includes(role)) {
        return json({ error: "forbidden_role" }, 403);
      }
      const { data: current } = await db
        .from("orders")
        .select("id, status, total")
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!current) return json({ error: "not_found" }, 404);
      if (current.status === "cancelled") {
        // Idempotent replay.
        await ledger();
        return json({ applied: true, already: true }, 200);
      }
      if (current.status === "delivered") {
        return json({ error: "already_delivered" }, 422);
      }
      const reason =
        typeof payload["reason"] === "string"
          ? String(payload["reason"]).slice(0, 280)
          : null;
      const { error: voidError } = await db
        .from("orders")
        .update({ status: "cancelled" })
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id);
      if (voidError) throw voidError;
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action: "order.void",
        entity: "order",
        entity_id,
        before: { status: current.status, total: current.total },
        after: { status: "cancelled", reason },
      });
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "inventory" && op === "inventory/set_count") {
      // --- Feature 8: inventory-lite (PHASE 2 STUB) --------------------------
      // Stock counts are authoritative on-device for now (stored in the
      // app's local documents directory). We ledger the op and keep an
      // append-only audit trail so a future server-side `inventory` table
      // can replay history — but there is intentionally no server table
      // yet. The client labels this "Phase 2".
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action: "inventory.set_count",
        entity: "inventory",
        entity_id: String(entity_id),
        before: null,
        after: payload,
      });
      await ledger();
      return json({ applied: true, phase: "stub" }, 200);
    }

    if (entity === "platform" && op === "platform/suspend_tenant") {
      // --- Feature 8: super-admin suspend / restore -------------------------
      // STRICT GATE: the caller must be a row in `platform_admins`, verified
      // here with the service-role client (RLS is bypassed for `db`, so this
      // check can never be inherited from the tenant-membership path —
      // platform ops skip that gate entirely above). A non-admin gets 403
      // even if they are owner of the target tenant.
      const { data: adminRow } = await db
        .from("platform_admins")
        .select("user_id")
        .eq("user_id", user.id)
        .maybeSingle();
      if (!adminRow) {
        return json({ error: "forbidden_not_platform_admin" }, 403);
      }
      const targetTenant = String(
        payload["tenant_id"] ?? entity_id ?? "",
      ).trim();
      if (!targetTenant) return json({ error: "invalid_tenant" }, 400);
      const suspend = payload["suspend"] === true;
      const newStatus = suspend ? "suspended" : "active";
      const { data: sub } = await db
        .from("subscriptions")
        .select("id, status")
        .eq("tenant_id", targetTenant)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (sub) {
        const { error: subError } = await db
          .from("subscriptions")
          .update({ status: newStatus })
          .eq("id", (sub as { id: string }).id);
        if (subError) throw subError;
      } else {
        // Defensive: a tenant without a subscription row (should not
        // happen — onboarding creates one) gets a fresh row so the state
        // is explicit rather than null.
        const { error: subError } = await db.from("subscriptions").insert({
          tenant_id: targetTenant,
          plan: "trial",
          status: newStatus,
        });
        if (subError) throw subError;
      }
      await db.from("audit_logs").insert({
        tenant_id: targetTenant,
        user_id: user.id,
        action: suspend
          ? "platform.tenant_suspended"
          : "platform.tenant_restored",
        entity: "tenant",
        entity_id: targetTenant,
        before: { status: (sub as { status?: string } | null)?.status ?? null },
        after: { status: newStatus },
      });
      await ledger();
      return json(
        { applied: true, tenant_id: targetTenant, status: newStatus },
        200,
      );
    }

    if (entity === "order" && op === "order/transition") {
      // --- Feature 4: guarded status transitions -----------------------------
      // Legal-transition map. SOURCE OF TRUTH:
      //   apps/tchop/lib/features/orders/order_state_machine.dart
      // (Dart `OrderFlow.legalTransitions`). Keep in sync manually — any
      // change here must be mirrored there.
      const LEGAL_TRANSITIONS: Record<string, string[]> = {
        placed: ["accepted", "cancelled"],
        accepted: ["preparing", "cancelled"],
        preparing: ["ready", "cancelled"],
        ready: ["picked_up"],
        picked_up: ["delivered"],
        delivered: [],
        cancelled: [],
      };
      // Per-transition role gates. Mirrors `OrderPermissions.allowedFrom`
      // in the same Dart file: secretary accepts/cancels, kitchen advances
      // preparing/ready, driver picks up/delivers, owner/manager do all.
      const ROLE_GATES: Record<string, string[]> = {
        "placed>accepted": ["secretary", "manager", "owner"],
        "placed>cancelled": ["secretary", "manager", "owner"],
        "accepted>preparing": ["kitchen", "head_chef", "manager", "owner"],
        "accepted>cancelled": ["secretary", "manager", "owner"],
        "preparing>ready": ["kitchen", "head_chef", "manager", "owner"],
        "preparing>cancelled": ["secretary", "manager", "owner"],
        "ready>picked_up": ["driver", "manager", "owner"],
        "picked_up>delivered": ["driver", "manager", "owner"],
      };
      if (!membership) return json({ error: "forbidden" }, 403);
      // Canonical payload is {order_id, to}; accept the legacy {status}
      // shape during rollout.
      const to = String(payload["to"] ?? payload["status"] ?? "");
      const { data: current } = await db
        .from("orders")
        .select("id, status")
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!current) return json({ error: "not_found" }, 404);
      // Idempotent replay: the transition was already applied (e.g. the
      // ledger write raced a retry) — confirm instead of rejecting.
      if (current.status === to) {
        await ledger();
        return json({ applied: true }, 200);
      }
      const allowed = LEGAL_TRANSITIONS[current.status] ?? [];
      if (!allowed.includes(to)) {
        return json(
          { error: "invalid_transition", from: current.status, to },
          422,
        );
      }
      const gateKey = `${current.status}>${to}`;
      if (!(ROLE_GATES[gateKey] ?? []).includes(role)) {
        return json({ error: "forbidden_role", from: current.status, to }, 403);
      }
      const { error } = await db
        .from("orders")
        .update({ status: to })
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id);
      if (error) throw error;
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action: "order.transition",
        entity: "order",
        entity_id,
        before: { status: current.status },
        after: { status: to },
      });
      await ledger();
      return json({ applied: true, from: current.status, to }, 200);
    }

    if (entity === "item_availability" && (op === "update" || op === "create" || op === "menu/set_availability")) {
      if (!canToggle86) return json({ error: "forbidden" }, 403);
      const { error } = await db.from("item_availability").upsert(
        {
          tenant_id,
          item_id: entity_id,
          available: payload["available"] ?? true,
          updated_by: user.id,
        },
        { onConflict: "tenant_id,item_id" },
      );
      if (error) throw error;
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "delivery" && (op === "create" || op === "update")) {
      const { error } = await db.from("deliveries").upsert(
        {
          id: entity_id,
          tenant_id,
          order_id: payload["order_id"],
          driver_id: payload["driver_id"] ?? null,
          picked_up_at: payload["picked_up_at"] ?? null,
          delivered_at: payload["delivered_at"] ?? null,
          pod_photo_url: payload["pod_photo_url"] ?? null,
        },
        { onConflict: "id" },
      );
      if (error) throw error;
      await ledger();
      return json({ applied: true }, 200);
    }

    // --- Feature 6: dispatch -------------------------------------------------
    if (entity === "delivery" && op === "delivery/assign") {
      // Role gate: owner / manager / secretary assign drivers.
      if (role !== "owner" && role !== "manager" && role !== "secretary") {
        return json({ error: "forbidden" }, 403);
      }
      const orderId = String(payload["order_id"] ?? "");
      const driverId = String(payload["driver_id"] ?? "");
      if (!orderId || !driverId) {
        return json({ error: "bad_request" }, 400);
      }
      // The assignee must be a driver of this tenant.
      const { data: driverMember } = await db
        .from("memberships")
        .select("role")
        .eq("tenant_id", tenant_id)
        .eq("user_id", driverId)
        .maybeSingle();
      if (!driverMember || (driverMember as { role?: string }).role !== "driver") {
        return json({ error: "not_a_driver" }, 422);
      }
      // Only a `ready` order can be assigned; the status is NOT changed
      // here — it stays `ready` until the driver marks it `picked_up`
      // via `order/transition`.
      const { data: order } = await db
        .from("orders")
        .select("id, status")
        .eq("id", orderId)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!order) return json({ error: "not_found" }, 404);
      if ((order as { status: string }).status !== "ready") {
        return json({ error: "order_not_ready" }, 422);
      }
      const { error } = await db.from("deliveries").insert({
        id: entity_id,
        tenant_id,
        order_id: orderId,
        driver_id: driverId,
        dropoff_lat: payload["dropoff_lat"] ?? null,
        dropoff_lng: payload["dropoff_lng"] ?? null,
        dropoff_address: payload["dropoff_address"] ?? null,
      });
      if (error) {
        // Idempotent replay of the same assignment.
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action: "delivery.assign",
        entity: "delivery",
        entity_id,
        after: { order_id: orderId, driver_id: driverId },
      });
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "delivery" && op === "delivery/complete") {
      const deliveryId = String(payload["delivery_id"] ?? entity_id ?? "");
      const orderId = String(payload["order_id"] ?? "");
      if (!deliveryId || !orderId) {
        return json({ error: "bad_request" }, 400);
      }
      const { data: delivery } = await db
        .from("deliveries")
        .select("id, tenant_id, order_id, driver_id, delivered_at")
        .eq("id", deliveryId)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!delivery) return json({ error: "not_found" }, 404);
      const drv = delivery as {
        driver_id: string | null;
        delivered_at: string | null;
      };
      // Role gate: the assigned driver, or owner/manager.
      const isOwnDelivery = drv.driver_id != null && drv.driver_id === user.id;
      if (!isOwnDelivery && role !== "owner" && role !== "manager") {
        return json({ error: "forbidden" }, 403);
      }
      // Idempotent replay: PoD already recorded.
      if (drv.delivered_at) {
        await ledger();
        return json({ applied: false, duplicate: true }, 409);
      }
      const signatureSvg = String(payload["signature_svg"] ?? "");
      if (!signatureSvg) {
        return json({ error: "missing_signature" }, 422);
      }
      // NOTE: the signature SVG is stored inline in `pod_signature_url`
      // as a data: URI until a dedicated Storage bucket exists.
      const signatureUri = `data:image/svg+xml;utf8,${encodeURIComponent(signatureSvg)}`;
      const { error: updError } = await db
        .from("deliveries")
        .update({
          delivered_at: new Date().toISOString(),
          pod_photo_url: payload["pod_photo_url"] ?? null,
          pod_signature_url: signatureUri,
          pod_lat: payload["pod_lat"] ?? null,
          pod_lng: payload["pod_lng"] ?? null,
        })
        .eq("id", deliveryId)
        .eq("tenant_id", tenant_id);
      if (updError) throw updError;
      // Milestone reconciliation: an order still `picked_up` moves to
      // `delivered` (the client normally sends `order/transition` first;
      // this keeps the two in sync when it raced or was lost).
      const { data: order } = await db
        .from("orders")
        .select("id, status")
        .eq("id", orderId)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (order && (order as { status: string }).status === "picked_up") {
        await db
          .from("orders")
          .update({ status: "delivered" })
          .eq("id", orderId)
          .eq("tenant_id", tenant_id);
        await db.from("audit_logs").insert({
          tenant_id,
          user_id: user.id,
          action: "order.transition",
          entity: "order",
          entity_id: orderId,
          before: { status: "picked_up" },
          after: { status: "delivered" },
        });
      }
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action: "delivery.complete",
        entity: "delivery",
        entity_id: deliveryId,
        after: { order_id: orderId, has_photo: !!payload["pod_photo_url"] },
      });
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "payment" && op === "create") {
      const { error } = await db.from("payments").insert({
        id: entity_id,
        tenant_id,
        order_id: payload["order_id"],
        provider: payload["provider"],
        provider_ref: payload["provider_ref"] ?? null,
        amount: payload["amount"] ?? 0,
        currency: payload["currency"] ?? "XAF",
        status: payload["status"] ?? "pending",
      });
      if (error) {
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await ledger();
      return json({ applied: true }, 200);
    }

    // --- payment ops (Feature 7) -------------------------------------------
    // Threat model (mirrored in migration 20260927_payments_vault.sql):
    //   * TLS in transit: secrets arrive over HTTPS to this function only.
    //   * Vault at rest: plaintext is encrypted via Supabase Vault
    //     (vault_store_secret wrapper, SECURITY DEFINER, revoked from all
    //     client roles) BEFORE any insert; `credentials_encrypted` holds
    //     only the Vault secret UUID.
    //   * Masked display: clients read only `key_fingerprint`
    //     ("mtn••••9f2a") — plaintext is never selected, logged, or
    //     returned.
    //   * Rotation: a fresh Vault secret replaces the pointer; old secret
    //     rows are never reused.
    // Provider API calls are ALWAYS server-side (edge functions). The
    // Flutter client never calls MTN/Orange/Wave/CinetPay directly and
    // never persists plaintext on device.
    const canManagePayments = role === "owner" || role === "manager";
    const canCloseCash =
      canManagePayments || role === "secretary";

    const writeAudit = async (action: string, entityRow: string, after: unknown) => {
      await db.from("audit_logs").insert({
        tenant_id,
        user_id: user.id,
        action,
        entity: entityRow,
        entity_id: String(entity_id),
        after,
      });
    };

    // The secret arrives as a JSON blob of provider fields
    // ({"api_user": "…", "api_key": "…", …}) or a plain string. Fingerprint
    // the LONGEST field value — that's the actual key, not a username.
    const fingerprintFor = (providerId: string, secret: string): string => {
      let source = secret;
      try {
        const obj = JSON.parse(secret) as unknown;
        if (obj && typeof obj === "object") {
          const values = Object.values(obj).filter(
            (v): v is string => typeof v === "string",
          );
          if (values.length > 0) {
            source = values.reduce((a, b) => (b.length >= a.length ? b : a));
          }
        }
      } catch {
        // plain string secret — use as-is
      }
      return `${providerId.split("_")[0]}••••${source.slice(-4)}`;
    };

    if (entity === "payment_credential" && op === "payments/credentials_save") {
      if (!canManagePayments) return json({ error: "forbidden" }, 403);
      const provider = String(payload["provider"] ?? "");
      const validProviders = [
        "mtn_momo",
        "orange_money",
        "wave",
        "cinetpay",
        "flutterwave",
        "card",
      ];
      if (!validProviders.includes(provider)) {
        return json({ error: "invalid_provider" }, 400);
      }
      const label = String(payload["label"] ?? "").trim();
      const secret = String(payload["secret"] ?? "");
      if (!label || !secret) {
        return json({ error: "missing_label_or_secret" }, 400);
      }
      if (secret.length > 8000) {
        return json({ error: "secret_too_large" }, 400);
      }
      // Encrypt FIRST — if Vault is down we must not store anything.
      const { data: vaultId, error: vaultError } = await db.rpc(
        "vault_store_secret",
        {
          p_name: `tchop/${tenant_id}/${provider}/${entity_id}`,
          p_secret: secret,
        },
      );
      if (vaultError || !vaultId) {
        console.error("vault_store_secret failed", vaultError);
        return json({ error: "encryption_unavailable" }, 503);
      }
      const fingerprint = fingerprintFor(provider, secret);
      const { error } = await db.from("tenant_payment_credentials").insert({
        id: entity_id,
        tenant_id,
        provider,
        label,
        credentials_encrypted: vaultId,
        key_fingerprint: fingerprint,
        is_active: true,
        created_by: user.id,
      });
      if (error) {
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await writeAudit("payments.credentials_save", "payment_credential", {
        provider,
        label,
        key_fingerprint: fingerprint,
      });
      await ledger();
      return json({ applied: true, key_fingerprint: fingerprint }, 200);
    }

    if (entity === "payment_credential" && op === "payments/credentials_rotate") {
      if (!canManagePayments) return json({ error: "forbidden" }, 403);
      const secret = String(payload["secret"] ?? "");
      if (!secret) return json({ error: "missing_secret" }, 400);
      const { data: existing } = await db
        .from("tenant_payment_credentials")
        .select("id, provider")
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!existing) return json({ error: "not_found" }, 404);
      const { data: vaultId, error: vaultError } = await db.rpc(
        "vault_store_secret",
        {
          p_name: `tchop/${tenant_id}/${existing.provider}/${entity_id}/rotated`,
          p_secret: secret,
        },
      );
      if (vaultError || !vaultId) {
        return json({ error: "encryption_unavailable" }, 503);
      }
      const fingerprint = fingerprintFor(String(existing.provider), secret);
      const { error } = await db
        .from("tenant_payment_credentials")
        .update({
          credentials_encrypted: vaultId,
          key_fingerprint: fingerprint,
          is_active: true,
          updated_at: new Date().toISOString(),
        })
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id);
      if (error) throw error;
      await writeAudit("payments.credentials_rotate", "payment_credential", {
        key_fingerprint: fingerprint,
      });
      await ledger();
      return json({ applied: true, key_fingerprint: fingerprint }, 200);
    }

    if (entity === "payment_credential" && op === "payments/credentials_revoke") {
      if (!canManagePayments) return json({ error: "forbidden" }, 403);
      const { error } = await db
        .from("tenant_payment_credentials")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id);
      if (error) throw error;
      // Revocation keeps the row (and its audit trail) — money flows and
      // old webhook signatures stay attributable.
      await writeAudit("payments.credentials_revoke", "payment_credential", {
        is_active: false,
      });
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "cash_close" && op === "payments/cash_close") {
      if (!canCloseCash) return json({ error: "forbidden" }, 403);
      const businessDate = String(payload["business_date"] ?? "");
      const expected = Number(payload["expected"] ?? NaN);
      const counted = Number(payload["counted"] ?? NaN);
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(businessDate) ||
        !Number.isInteger(expected) ||
        !Number.isInteger(counted)
      ) {
        return json({ error: "invalid_cash_close" }, 400);
      }
      // Variance is recomputed server-side — never trusted from the client.
      const variance = counted - expected;
      const { error } = await db.from("cash_closes").insert({
        id: entity_id,
        tenant_id,
        business_date: businessDate,
        expected,
        counted,
        variance,
        closed_by: user.id,
        note: payload["note"] ? String(payload["note"]) : null,
        client_mutation_id,
      });
      if (error) {
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await writeAudit("payments.cash_close", "cash_close", {
        business_date: businessDate,
        expected,
        counted,
        variance,
      });
      await ledger();
      return json({ applied: true, variance }, 200);
    }

    if (entity === "refund_request" && op === "payments/refund_request") {
      if (!canManagePayments) return json({ error: "forbidden" }, 403);
      const paymentId = String(payload["payment_id"] ?? "");
      const reason = String(payload["reason"] ?? "").trim();
      if (!paymentId || !reason) {
        return json({ error: "invalid_refund_request" }, 400);
      }
      const { data: payment } = await db
        .from("payments")
        .select("id, order_id, amount, status, provider")
        .eq("id", paymentId)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!payment) return json({ error: "payment_not_found" }, 404);
      if (payment.status !== "succeeded") {
        return json({ error: "refund_not_allowed" }, 422);
      }
      const { error } = await db.from("refund_requests").insert({
        id: entity_id,
        tenant_id,
        payment_id: paymentId,
        order_id: payment.order_id,
        amount: payment.amount,
        reason,
        status: "pending",
        requested_by: user.id,
        client_mutation_id,
      });
      if (error) {
        if (error.code === "23505") {
          return json({ applied: false, duplicate: true }, 409);
        }
        throw error;
      }
      await writeAudit("payments.refund_request", "refund_request", {
        payment_id: paymentId,
        amount: payment.amount,
        reason,
      });
      await ledger();
      return json({ applied: true }, 200);
    }

    if (
      entity === "refund_request" &&
      (op === "payments/refund_approve" || op === "payments/refund_reject")
    ) {
      if (!canManagePayments) return json({ error: "forbidden" }, 403);
      const { data: request } = await db
        .from("refund_requests")
        .select("id, payment_id, order_id, requested_by, status")
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (!request) return json({ error: "not_found" }, 404);
      if (request.status !== "pending") {
        return json({ applied: false, duplicate: true }, 409);
      }
      // Four-eyes: the requester can never approve (or reject) their own
      // request. Enforced server-side — the client mirrors it in UI only.
      if (request.requested_by === user.id) {
        return json({ error: "self_approval_forbidden" }, 403);
      }
      const decision = op === "payments/refund_approve" ? "approved" : "rejected";
      const { error: decideError } = await db
        .from("refund_requests")
        .update({
          status: decision,
          decided_by: user.id,
          decided_at: new Date().toISOString(),
          decision_note: payload["note"] ? String(payload["note"]) : null,
        })
        .eq("id", entity_id)
        .eq("tenant_id", tenant_id)
        .eq("status", "pending");
      if (decideError) throw decideError;
      if (decision === "approved") {
        // Bookkeeping only — the money itself MUST be returned manually in
        // the provider's own app/portal (MoMo has no public refund API for
        // collections; the UI says so explicitly).
        const { error: payError } = await db
          .from("payments")
          .update({ status: "refunded" })
          .eq("id", request.payment_id)
          .eq("tenant_id", tenant_id);
        if (payError) throw payError;
        if (request.order_id) {
          const { error: orderError } = await db
            .from("orders")
            .update({ payment_status: "refunded" })
            .eq("id", request.order_id)
            .eq("tenant_id", tenant_id);
          if (orderError) throw orderError;
        }
      }
      await writeAudit(
        `payments.refund_${decision}`,
        "refund_request",
        { decision, payment_id: request.payment_id },
      );
      await ledger();
      return json({ applied: true, decision }, 200);
    }

    // --- menu studio ops (Feature 3) -------------------------------------
    // The draft doc shape is shared with the Flutter client
    // (MenuDraftDoc.toJson): {categories, items, dayparts, approvals}.
    const readDraftDoc = async () => {
      const { data, error } = await db
        .from("menu_drafts")
        .select("items")
        .eq("tenant_id", tenant_id)
        .maybeSingle();
      if (error) throw error;
      const doc = (data?.items as Record<string, unknown>) ?? {};
      return {
        categories: (doc["categories"] as unknown[]) ?? [],
        items: (doc["items"] as unknown[]) ?? [],
        dayparts: (doc["dayparts"] as unknown[]) ?? [],
        approvals: (doc["approvals"] as Record<string, unknown>[]) ?? [],
      };
    };
    const writeDraftDoc = async (doc: Record<string, unknown>) => {
      const { error } = await db.from("menu_drafts").upsert(
        {
          tenant_id,
          items: doc,
          updated_by: user.id,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "tenant_id" },
      );
      if (error) throw error;
    };

    if (entity === "menu_draft" && op === "menu/draft_save") {
      if (!canEditDraft) return json({ error: "forbidden" }, 403);
      await writeDraftDoc(
        (payload["doc"] as Record<string, unknown>) ?? {},
      );
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "menu_snapshot" && op === "menu/publish") {
      if (!canManageMenu) return json({ error: "forbidden" }, 403);
      // ATOMICITY: the RPC takes a per-tenant advisory lock and computes
      // max(version)+1 inside one transaction. The client-sent version is
      // advisory only — concurrent publishes can never collide on
      // (tenant_id, version). Returned version is authoritative.
      const { data: version, error } = await db.rpc("publish_menu_snapshot", {
        p_tenant_id: tenant_id,
        p_version: payload["version"] ?? 0,
        p_items: payload["items"] ?? {},
        p_published_by: user.id,
      });
      if (error) throw error;
      await ledger();
      return json({ applied: true, version }, 200);
    }

    if (entity === "menu_approval" && op === "menu/request_86") {
      // Any tenant member (kitchen staff) may file; it only lands in the
      // approvals inbox — it never flips availability directly.
      const doc = await readDraftDoc();
      const id = String(entity_id);
      if (!doc.approvals.some((a) => a["id"] === id)) {
        doc.approvals.push({
          id,
          kind: "request_86",
          item_id: payload["item_id"],
          item_name: payload["item_name"] ?? "",
          requested_by: payload["requested_by"] ?? user.id,
          requested_at: new Date().toISOString(),
          status: "pending",
        });
        await writeDraftDoc(doc as unknown as Record<string, unknown>);
      }
      await ledger();
      return json({ applied: true }, 200);
    }

    if (entity === "menu_approval" && op === "menu/approve_price") {
      if (!canManageMenu) return json({ error: "forbidden" }, 403);
      const doc = await readDraftDoc();
      const decision = String(payload["decision"] ?? "");
      const approval = doc.approvals.find((a) => a["id"] === String(entity_id));
      if (approval && approval["status"] === "pending") {
        approval["status"] = decision === "approved" ? "approved" : "rejected";
        if (approval["kind"] === "price_change") {
          const item = (doc.items as Record<string, unknown>[]).find(
            (i) => i["id"] === approval["item_id"],
          );
          if (item) {
            if (
              decision === "approved" &&
              typeof approval["new_price_fcfa"] === "number"
            ) {
              item["price_fcfa"] = approval["new_price_fcfa"];
            }
            item["pending_approval"] = false;
            item["approval_old_price"] = null;
            item["approval_new_price"] = null;
          }
        }
        // request_86 decisions resolved client-side via menu/set_availability;
        // the inbox entry here stays as the audit record.
        await writeDraftDoc(doc as unknown as Record<string, unknown>);
      }
      await ledger();
      return json({ applied: true }, 200);
    }

    return json({ error: "unsupported_entity_op" }, 400);
  } catch (e) {
    console.error("sync failed", e);
    return json({ error: "internal" }, 500);
  }
});
