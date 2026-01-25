// supabase/functions/delete-account/index.ts
// Cancels the caller's Stripe subscription (by stripe_subscription_id) and deletes their Supabase Auth user.
// IMPORTANT:
// - Set env vars in Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, STRIPE_SECRET_KEY
// - Ensure your "subscriptions" table has: user_id (uuid), stripe_subscription_id (text)
// - Client must call with Authorization: Bearer <access_token>

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const STRIPE_API = "https://api.stripe.com/v1";

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function stripeCancelSubscription(subscriptionId: string) {
  // DELETE /v1/subscriptions/{id} cancels immediately
  const resp = await fetch(`${STRIPE_API}/subscriptions/${encodeURIComponent(subscriptionId)}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
    },
  });

  const text = await resp.text();
  if (!resp.ok) throw new Error(`Stripe cancel failed ${resp.status}: ${text}`);

  // Stripe returns JSON
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });

  // Only allow POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return new Response(JSON.stringify({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }), {
        status: 500,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
      });
    }
    if (!STRIPE_SECRET_KEY) {
      return new Response(JSON.stringify({ error: "Missing STRIPE_SECRET_KEY" }), {
        status: 500,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
      });
    }

    // Service role client (admin)
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Verify caller identity from JWT (don't trust body)
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;

    if (!jwt) {
      return new Response(JSON.stringify({ error: "Missing Authorization Bearer token" }), {
        status: 401,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
      });
    }

    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Invalid auth token" }), {
        status: 401,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
      });
    }

    const user_id = userData.user.id;

    // 1) Lookup subscription id
    const { data: subRow, error: subErr } = await admin
      .from("subscriptions")
      .select("stripe_subscription_id")
      .eq("user_id", user_id)
      .maybeSingle();

    // 2) Cancel Stripe subscription if present (ignore "not found" row)
    let stripeResult: unknown = null;
    if (!subErr && subRow?.stripe_subscription_id) {
      stripeResult = await stripeCancelSubscription(subRow.stripe_subscription_id);
    }

    // 3) Delete user from Supabase Auth
    const { error: delErr } = await admin.auth.admin.deleteUser(user_id);
    if (delErr) {
      return new Response(JSON.stringify({ error: `Failed to delete user: ${delErr.message}` }), {
        status: 500,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
      });
    }

    // 4) Optional: delete their rows (recommended). Uncomment as needed.
    // await admin.from("subscriptions").delete().eq("user_id", user_id);
    // await admin.from("decks").delete().eq("user_id", user_id);
    // await admin.from("cards").delete().eq("user_id", user_id);

    return new Response(JSON.stringify({ success: true, stripeCanceled: !!stripeResult }), {
      status: 200,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as any)?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }
});
