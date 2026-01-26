// supabase/functions/create-checkout-session/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@16.12.0?target=deno";

const allowedOrigins = new Set([
  "https://zencardstudy.com",
  "https://www.zencardstudy.com",
]);

function getCorsHeaders(origin: string | null) {
  const o = origin && allowedOrigins.has(origin) ? origin : "https://zencardstudy.com";
  return {
    "Access-Control-Allow-Origin": o,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function jsonResponse(origin: string | null, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...getCorsHeaders(origin), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: getCorsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return jsonResponse(origin, 405, { error: "Method not allowed" });
  }

  try {
    const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
    const STRIPE_PRICE_ID = Deno.env.get("STRIPE_PRICE_ID");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

    if (!STRIPE_SECRET_KEY) return jsonResponse(origin, 500, { error: "Missing STRIPE_SECRET_KEY" });
    if (!STRIPE_PRICE_ID) return jsonResponse(origin, 500, { error: "Missing STRIPE_PRICE_ID" });
    if (!SUPABASE_URL) return jsonResponse(origin, 500, { error: "Missing SUPABASE_URL" });
    if (!SUPABASE_ANON_KEY) return jsonResponse(origin, 500, { error: "Missing SUPABASE_ANON_KEY" });

    // Require Bearer token
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : "";
    if (!token) return jsonResponse(origin, 401, { error: "Missing Bearer token" });

    // Use anon key + user's jwt to fetch the user
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse(origin, 401, { error: "Invalid or expired token", details: userErr?.message });
    }

    const user = userData.user;
    const userId = user.id;
    const email = user.email;
    if (!email) return jsonResponse(origin, 400, { error: "User has no email" });

    const body = await req.json().catch(() => ({} as Record<string, unknown>));

    // IMPORTANT: keep success on app.html so it can immediately re-check access
    const success_url =
      typeof body?.success_url === "string"
        ? body.success_url
        : "https://zencardstudy.com/app.html?checkout=success";

    const cancel_url =
      typeof body?.cancel_url === "string"
        ? body.cancel_url
        : "https://zencardstudy.com/app.html?checkout=canceled";

    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2023-10-16" });

    // 1) Trial eligibility (DB is your fast gate)
    // Make sure you added:
    // alter table public.users add column if not exists trial_used boolean not null default false;
    // 1) Trial eligibility (DB is your fast gate)
// IMPORTANT: brand-new users may not have a row in public.users yet.
// Use maybeSingle + create row if missing.
const { data: userRow, error: userRowErr } = await supabase
  .from("users")
  .select("trial_used")
  .eq("id", userId)
  .maybeSingle();

if (userRowErr) {
  return jsonResponse(origin, 500, {
    error: "Failed to load user trial status",
    details: userRowErr.message,
  });
}

// If no row exists yet, create it (trial_used defaults false)
if (!userRow) {
  const { error: insErr } = await supabase
    .from("users")
    .upsert({ id: userId }, { onConflict: "id" });

  if (insErr) {
    return jsonResponse(origin, 500, {
      error: "Failed to initialize public user row",
      details: insErr.message,
    });
  }
}

let trialEligible = !(userRow?.trial_used ?? false);


    // 2) Reuse/create customer (your existing logic)
    const existing = await stripe.customers.list({ email, limit: 1 });
    const customer =
      existing.data?.[0] ??
      (await stripe.customers.create({
        email,
        metadata: { supabase_user_id: userId },
      }));

    // 3) Stronger gate: if Stripe has ever seen a trial for this customer, block trial
    // (covers cases where DB flag wasn't set due to earlier iterations)
    if (trialEligible) {
      const subs = await stripe.subscriptions.list({
        customer: customer.id,
        status: "all",
        limit: 100,
      });

      const everHadTrial = subs.data.some((s) => !!s.trial_start);
      if (everHadTrial) trialEligible = false;
    }

    // 4) Build Checkout Session params; only include trial when eligible
    const sessionParams: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      customer: customer.id,

      // Your price
      line_items: [{ price: STRIPE_PRICE_ID, quantity: 1 }],

      // Put supabase_user_id in BOTH places so every webhook can map back to user
      client_reference_id: userId,
      metadata: {
        supabase_user_id: userId,
        email,
        price_id: STRIPE_PRICE_ID,
      },

      // Always attach subscription metadata (even if no trial)
      subscription_data: {
        metadata: {
          supabase_user_id: userId,
          email,
          price_id: STRIPE_PRICE_ID,
        },
      },

      success_url,
      cancel_url,
      allow_promotion_codes: true,
    };

    if (trialEligible) {
      sessionParams.subscription_data = {
        trial_period_days: 3, // <-- your trial length
        metadata: {
          supabase_user_id: userId,
          email,
          price_id: STRIPE_PRICE_ID,
        },
      };
    }

    const session = await stripe.checkout.sessions.create(sessionParams);

    // Return eligibility too (helps you debug in console)
    return jsonResponse(origin, 200, { url: session.url, trial_eligible: trialEligible });
  } catch (e) {
    console.error("create-checkout-session error:", e);
    return jsonResponse(origin, 500, { error: "Internal error", details: (e as any)?.message || String(e) });
  }
});
