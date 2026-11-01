// ============================================================================
// TCHOP — `payment-webhook` Edge Function.
//
// Receives at-least-once payment notifications from aggregators and flips
// `payments.status` / `orders.payment_status` by provider_ref.
//
// Required env vars (Edge Function secrets — NEVER hardcoded, NEVER
// committed):
//   CINETPAY_WEBHOOK_SECRET      — HMAC secret configured in the CinetPay
//                                  merchant dashboard (notifications tab).
//   FLUTTERWAVE_WEBHOOK_SECRET   — the value Flutterwave sends in the
//                                  `verif-hash` header (your FLW secret hash).
//
// Signature verification:
//   * Flutterwave: `verif-hash` header must equal FLUTTERWAVE_WEBHOOK_SECRET.
//   * CinetPay: `signature` form field must equal HMAC-SHA256(raw body,
//     CINETPAY_WEBHOOK_SECRET), hex-encoded (constant-time compare).
//   Unverified requests are rejected with 401 BEFORE any state change.
//
// Payloads (provider docs change; both parsers are defensive):
//   * CinetPay posts form-urlencoded: cpm_trans_id, cpm_result
//     ("ACCEPTED"/"REFUSED"), cpm_trans_status, signature.
//   * Flutterwave posts JSON: { event, data: { tx_ref, status, amount } }.
//
// Idempotency: delivery retries are deduped on
// UNIQUE(provider, provider_ref) — a payment already in a final state
// (succeeded/failed/refunded) answers 200 {duplicate:true} without touching
// state. Every accepted delivery appends an audit_logs entry.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Constant-time string comparison (signature checks must not leak via
// timing, and `===` on secrets is not constant-time).
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacSha256Hex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data),
  );
  return [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

type ParsedEvent = {
  provider: "cinetpay" | "flutterwave";
  providerRef: string;
  status: "succeeded" | "failed";
};

async function parseEvent(
  req: Request,
  raw: string,
  params: URLSearchParams,
): Promise<ParsedEvent | { error: string; status: number }> {
  const hint = (params.get("provider") ?? "").toLowerCase();

  // --- Flutterwave (JSON, `verif-hash` header) ------------------------------
  const verifHash = req.headers.get("verif-hash");
  if (verifHash || hint === "flutterwave") {
    const secret = Deno.env.get("FLUTTERWAVE_WEBHOOK_SECRET");
    if (!secret || !verifHash || !timingSafeEqual(verifHash, secret)) {
      return { error: "invalid_signature", status: 401 };
    }
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return { error: "malformed_payload", status: 400 };
    }
    const data = (body["data"] as Record<string, unknown> | undefined) ?? {};
    const txRef = String(data["tx_ref"] ?? "");
    const flwStatus = String(data["status"] ?? "").toLowerCase();
    if (!txRef) return { error: "missing_tx_ref", status: 400 };
    return {
      provider: "flutterwave",
      providerRef: txRef,
      status: flwStatus === "successful" ? "succeeded" : "failed",
    };
  }

  // --- CinetPay (form-urlencoded, HMAC `signature` field) --------------------
  const fields = new URLSearchParams(raw);
  const sig = fields.get("signature") ?? "";
  const secret = Deno.env.get("CINETPAY_WEBHOOK_SECRET");
  if (!secret || !sig) {
    return { error: "invalid_signature", status: 401 };
  }
  const expected = await hmacSha256Hex(secret, raw);
  if (!timingSafeEqual(sig.toLowerCase(), expected)) {
    return { error: "invalid_signature", status: 401 };
  }
  const transId = fields.get("cpm_trans_id") ?? "";
  const result = (fields.get("cpm_result") ?? fields.get("cpm_trans_status") ?? "")
    .toUpperCase();
  if (!transId) return { error: "missing_trans_id", status: 400 };
  return {
    provider: "cinetpay",
    providerRef: transId,
    status: result === "ACCEPTED" ? "succeeded" : "failed",
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const url = new URL(req.url);
  const raw = await req.text();

  const parsed = await parseEvent(req, raw, url.searchParams);
  if ("error" in parsed) {
    return json({ error: parsed.error }, parsed.status);
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Idempotency: a payment already in a final state ignores redelivery.
  const { data: payment } = await db
    .from("payments")
    .select("id, tenant_id, order_id, status")
    .eq("provider", parsed.provider)
    .eq("provider_ref", parsed.providerRef)
    .maybeSingle();
  if (!payment) {
    return json({ error: "unknown_payment" }, 404);
  }
  if (payment.status !== "pending") {
    return json({ ok: true, duplicate: true }, 200);
  }

  const { error: payError } = await db
    .from("payments")
    .update({ status: parsed.status })
    .eq("id", payment.id);
  if (payError) throw payError;

  const { error: orderError } = await db
    .from("orders")
    .update({ payment_status: parsed.status })
    .eq("id", payment.order_id);
  if (orderError) throw orderError;

  await db.from("audit_logs").insert({
    tenant_id: payment.tenant_id,
    user_id: null, // system event from the provider, not a user action
    action: `payments.webhook_${parsed.status}`,
    entity: "payment",
    entity_id: payment.id,
    after: {
      provider: parsed.provider,
      provider_ref: parsed.providerRef,
      status: parsed.status,
    },
  });

  return json({ ok: true, status: parsed.status }, 200);
});
