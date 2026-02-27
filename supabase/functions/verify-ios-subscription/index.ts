// supabase/functions/verify-ios-subscription/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Body = {
  user_id: string;
  product_id: string;
  transaction_id?: string | null;

  // You will send ONE of these depending on what your plugin can provide:
  // Option A: base64 receipt data (common)
  receipt_b64?: string;

  // Option B: StoreKit2 signed transaction JWS (best)
  signed_transaction_jws?: string;
};

function json(status: number, data: unknown) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
      "access-control-allow-methods": "POST, OPTIONS",
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return json(200, { ok: true });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON" });
  }

const {
  user_id,
  product_id,
  transaction_id,
  receipt_b64,
  signed_transaction_jws,
  // accept the old client field name too:
  receipt,
} = body as Body & { receipt?: string };

// ✅ Guardrail: require a valid Supabase user JWT and make sure it matches user_id
const authHeader = req.headers.get("authorization") || "";
if (!authHeader.startsWith("Bearer ")) {
  return json(401, { error: "Missing bearer token" });
}

const anon = Deno.env.get("SUPABASE_ANON_KEY");
if (!anon) return json(500, { error: "Missing SUPABASE_ANON_KEY env var" });
const authed = createClient(SUPABASE_URL, anon, {
  global: { headers: { Authorization: authHeader } },
});

const { data: userData, error: userErr } = await authed.auth.getUser();
if (userErr || !userData?.user?.id) {
  return json(401, { error: "Invalid token" });
}

if (userData.user.id !== user_id) {
  return json(403, { error: "user_id mismatch" });
}

  if (!user_id || !product_id) {
    return json(400, { error: "Missing user_id or product_id" });
  }

const receiptFinal = receipt_b64 ?? receipt ?? null;

if (!receiptFinal && !signed_transaction_jws) {
  return json(400, { error: "Provide receipt_b64 (or receipt) or signed_transaction_jws" });
}

  // ----------------------------
  // TEMP placeholder (do not ship):
  // Pretend verification succeeded and mark trialing.
  // ----------------------------
  const newStatus = "trialing";

  const { error: upsertErr } = await sb
    .from("subscriptions")
    .upsert(
      {
        user_id,
        status: newStatus,
        platform: "ios",
        product_id,
        transaction_id: transaction_id ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" }
    );

  if (upsertErr) return json(500, { error: upsertErr.message });

  return json(200, { ok: true, status: newStatus });
});