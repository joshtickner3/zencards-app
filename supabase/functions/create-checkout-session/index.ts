// supabase/functions/create-checkout-session/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "npm:stripe@16.12.0";

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

    const success_url =
      typeof body?.success_url === "string"
        ? body.success_url
        : "https://zencardstudy.com/app.html?checkout=success";

    const cancel_url =
      typeof body?.cancel_url === "string"
        ? body.cancel_url
        : "https://zencardstudy.com/app.html?checkout=canceled";

    // ✅ Edge-safe Stripe client (prevents Deno.core.runMicrotasks issues)
    const stripe = new Stripe(STRIPE_SECRET_KEY, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    // -----------------------------
    // 1) Get / create Stripe customer
    // -----------------------------
    // Prefer mapping table if it exists (less error-prone than searching by email)
    let customerId: string | null = null;

    try {
      const { data: mapping } = await supabase
        .from("stripe_customers")
        .select("stripe_customer_id")
        .eq("user_id", userId)
        .maybeSingle();

      if (mapping?.stripe_customer_id) customerId = mapping.stripe_customer_id;
    } catch {
      // ignore; fallback to email lookup below
    }

    if (!customerId) {
      const existing = await stripe.customers.list({ email, limit: 1 });
      const customer =
        existing.data?.[0] ??
        (await stripe.customers.create({
          email,
          metadata: { supabase_user_id: userId },
        }));
      customerId = customer.id;
    }

    // -----------------------------------------
    // 2) Decide trial eligibility (NO DB INSERTS)
    // -----------------------------------------
    // We DO NOT upsert into public.users here because RLS blocks it.
    // Instead:
    // - If we can read users.trial_used, use it
    // - Always enforce with Stripe history:
    //    trial only if customer has NEVER had ANY subscription before
    let trialEligible = true;

    // DB hint (optional; if blocked by RLS or row missing, we just ignore)
    try {
      const { data: userRow } = await supabase
        .from("users")
        .select("trial_used")
        .eq("id", userId)
        .maybeSingle();

      if (userRow?.trial_used === true) trialEligible = false;
    } catch {
      // ignore; Stripe history below is still authoritative
    }

    // Stripe authoritative gate:
    // If customer has EVER had a subscription (trialing/active/canceled/etc), no trial.
    const subs = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      limit: 100,
    });

    const hasAnySubscriptionHistory = subs.data.length > 0;
    if (hasAnySubscriptionHistory) {
      trialEligible = false;
    }

    // -----------------------------------------
    // 3) Create Checkout Session
    // -----------------------------------------
    const sessionParams: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      customer: customerId,

      line_items: [{ price: STRIPE_PRICE_ID, quantity: 1 }],

      client_reference_id: userId,
      metadata: {
        supabase_user_id: userId,
        email,
        price_id: STRIPE_PRICE_ID,
      },

      // Always attach subscription metadata
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

    // Only include trial when eligible
    if (trialEligible) {
      sessionParams.subscription_data = {
        trial_period_days: 3,
        metadata: {
          supabase_user_id: userId,
          email,
          price_id: STRIPE_PRICE_ID,
        },
      };
    }

    const session = await stripe.checkout.sessions.create(sessionParams);

    return jsonResponse(origin, 200, {
      url: session.url,
      trial_eligible: trialEligible,
      has_any_subscription_history: hasAnySubscriptionHistory,
    });
  } catch (e) {
    console.error("create-checkout-session error:", e);
    return jsonResponse(origin, 500, {
      error: "Internal error",
      details: (e as any)?.message || String(e),
    });
  }
});
