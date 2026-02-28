// supabase/functions/verify-ios-subscription/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Body = {
  user_id: string;
  product_id: string;
  transaction_id?: string | null;

  // Option A: base64 receipt data (common)
  receipt_b64?: string;

  // Option B: StoreKit2 signed transaction JWS (best)
  signed_transaction_jws?: string;

  // TEMP: allow entitlement-only proof from the client
  active_product_ids?: string[] | null;
};

// ✅ IMPORTANT: Do NOT reference SUPABASE_ANON_KEY as a variable here.
// This helper must never throw, or OPTIONS preflight will fail with 500.
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
  try {
    if (req.method === "OPTIONS") return json(200, { ok: true });
    if (req.method !== "POST") return json(405, { error: "POST only" });

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

    if (!SUPABASE_URL) return json(500, { error: "Missing SUPABASE_URL env var" });
    if (!SERVICE_ROLE) return json(500, { error: "Missing SUPABASE_SERVICE_ROLE_KEY env var" });
    if (!ANON_KEY) return json(500, { error: "Missing SUPABASE_ANON_KEY env var" });

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
      active_product_ids,
      // accept old client field too
      receipt,
    } = body as Body & { receipt?: string };

    // ✅ DEBUG LOG
    console.log("verify-ios-subscription payload:", {
      user_id,
      product_id,
      transaction_id,
      hasReceiptFinal: !!(receipt_b64 ?? receipt),
      hasJws: !!signed_transaction_jws,
      active_product_ids,
    });

    // ✅ Guardrail: require a valid Supabase user JWT and make sure it matches user_id
    const authHeader = req.headers.get("authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return json(401, { error: "Missing bearer token" });
    }

    const authed = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await authed.auth.getUser();
    if (userErr || !userData?.user?.id) {
      console.log("auth.getUser error:", userErr);
      return json(401, { error: "Invalid token" });
    }

    if (userData.user.id !== user_id) {
      return json(403, { error: "user_id mismatch" });
    }

    if (!user_id || !product_id) {
      return json(400, { error: "Missing user_id or product_id" });
    }

    const receiptFinal = receipt_b64 ?? receipt ?? null;

    const activeIds = Array.isArray(active_product_ids) ? active_product_ids : [];
    const hasEntitlement = activeIds.includes(product_id);

    // TEMP rule: allow if we have receipt/JWS OR entitlement list says this product is active
    if (!receiptFinal && !signed_transaction_jws && !hasEntitlement) {
      return json(400, {
        error:
          "Provide receipt_b64 (or receipt) or signed_transaction_jws, or active_product_ids must include product_id",
      });
    }

    // ----------------------------
    // TEMP placeholder (do not ship):
    // Pretend verification succeeded and write a row.
    // ----------------------------
    const newStatus = hasEntitlement ? "active" : "trialing";

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

    if (upsertErr) {
      console.log("subscriptions upsert error:", upsertErr);
      return json(500, { error: upsertErr.message });
    }

    return json(200, { ok: true, status: newStatus });
  } catch (e) {
    // ✅ Catch-all so the function never hard-crashes without JSON
    console.log("verify-ios-subscription unhandled error:", e);
    return json(500, { error: e?.message || "Internal error" });
  }
});