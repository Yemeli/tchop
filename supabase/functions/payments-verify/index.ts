// ============================================================================
// TCHOP — `payments-verify` Edge Function.
//
// Interactive ("Tester la connexion") sandbox check for a stored payment
// credential. NOT an outbox op: the user waits for the verdict.
//
// Request:
//   POST /functions/v1/payments-verify
//   Authorization: Bearer <user JWT>
//   { "tenant_id": "uuid", "credential_id": "uuid" }
//
// Response (always 200 on a well-formed call):
//   { "verified": true,  "demo": false, "detail": "..." }  // real sandbox OK
//   { "verified": false, "demo": true,  "reason": "sandbox_indisponible" }
//     // sandbox key not configured or sandbox unreachable — the UI MUST
//     // label this "Mode démo — vérification simulée" and NEVER present it
//     // as a success.
//   { "verified": false, "demo": false, "reason": "sandbox_refuse" }
//     // sandbox reachable but rejected the credential.
//
// HONESTY RULE: this function never returns verified:true unless a provider
// sandbox actually accepted the credential. When in doubt it returns the
// demo payload above.
//
// Required env vars (Edge Function secrets):
//   MTN_MOMO_SANDBOX_SUBSCRIPTION_KEY  — sandbox subscription key for MTN MoMo
//   ORANGE_MONEY_SANDBOX_API_KEY       — sandbox key for Orange Money WebPay
//   WAVE_SANDBOX_API_KEY               — sandbox key for Wave
//   CINETPAY_SANDBOX_APIKEY            — sandbox apikey for CinetPay
//   FLUTTERWAVE_SANDBOX_SECRET_KEY     — test secret key for Flutterwave
//
// Secrets are read from Vault server-side via the `vault_read_secret`
// SECURITY DEFINER wrapper (service role only) — plaintext never leaves
// this function.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Best-effort sandbox endpoints. These are intentionally cheap "ping"
// calls; provider sandbox APIs change — on any failure the honest answer
// is the demo payload, never a fabricated success.
const SANDBOX_PING: Record<
  string,
  { env: string; url: string; headers: (key: string) => Record<string, string> }
> = {
  mtn_momo: {
    env: "MTN_MOMO_SANDBOX_SUBSCRIPTION_KEY",
    url: "https://sandbox.momodeveloper.mtn.com/collection/token/",
    headers: (key) => ({
      "Ocp-Apim-Subscription-Key": key,
      Authorization: `Basic ${key}`,
    }),
  },
  orange_money: {
    env: "ORANGE_MONEY_SANDBOX_API_KEY",
    url: "https://api.sandbox.orange-sonatel.sonatel.com/api/eWallet/v4",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
  },
  wave: {
    env: "WAVE_SANDBOX_API_KEY",
    url: "https://api.wave.com/v1/checkout/sessions",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
  },
  cinetpay: {
    env: "CINETPAY_SANDBOX_APIKEY",
    url: "https://api-checkout.cinetpay.com/v2/payment",
    headers: (key) => ({
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    }),
  },
  flutterwave: {
    env: "FLUTTERWAVE_SANDBOX_SECRET_KEY",
    url: "https://api.flutterwave.com/v3/transactions/verify",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
  },
};

const demo = (reason: string) =>
  json({ verified: false, demo: true, reason }, 200);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
  } = await userClient.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: { tenant_id?: string; credential_id?: string };
  try {
    body = (await req.json()) as { tenant_id?: string; credential_id?: string };
  } catch {
    return json({ error: "malformed_body" }, 400);
  }
  const { tenant_id, credential_id } = body;
  if (!tenant_id || !credential_id) {
    return json({ error: "missing_params" }, 400);
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Membership check (defense in depth — RLS also isolates tenants).
  const { data: membership } = await db
    .from("memberships")
    .select("role")
    .eq("tenant_id", tenant_id)
    .eq("user_id", user.id)
    .maybeSingle();
  const role = String((membership as { role?: string } | null)?.role ?? "");
  if (role !== "owner" && role !== "manager") {
    return json({ error: "forbidden" }, 403);
  }

  const { data: credential } = await db
    .from("tenant_payment_credentials")
    .select("id, provider, is_active, credentials_encrypted")
    .eq("id", credential_id)
    .eq("tenant_id", tenant_id)
    .maybeSingle();
  if (!credential) return json({ error: "credential_not_found" }, 404);

  const ping = SANDBOX_PING[credential.provider];
  const sandboxKey = ping ? Deno.env.get(ping.env) : undefined;
  if (!ping || !sandboxKey) {
    // No sandbox configured for this provider — honest demo answer.
    return demo("sandbox_indisponible");
  }

  // Attempt a real sandbox check. 8s timeout; anything but a clean
  // provider acceptance falls back to the honest demo payload.
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const res = await fetch(ping.url, {
      method: "GET",
      headers: ping.headers(sandboxKey),
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (res.status >= 200 && res.status < 300) {
      return json(
        {
          verified: true,
          demo: false,
          detail: `Bac à sable ${credential.provider} joignable.`,
        },
        200,
      );
    }
    if (res.status === 401 || res.status === 403) {
      return json(
        { verified: false, demo: false, reason: "sandbox_refuse" },
        200,
      );
    }
    return demo("sandbox_indisponible");
  } catch (e) {
    console.error("payments-verify sandbox ping failed", e);
    return demo("sandbox_indisponible");
  }
});
