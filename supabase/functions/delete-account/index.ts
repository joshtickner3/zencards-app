// Supabase Edge Function: delete-account
// Cancels user's Stripe subscription (if any) and deletes their Supabase account.
// Expects: { user_id: string, email: string }
// Requires: STRIPE_SECRET_KEY env var set in Supabase project


import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
const STRIPE_API = "https://api.stripe.com/v1";

async function getStripeCustomerId(supabase, user_id) {
  // Assumes you store Stripe customer id in a 'stripe_customer_id' column in 'users' or 'subscriptions' table
  // Adjust query as needed for your schema
  const { data, error } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id')
    .eq('user_id', user_id)
    .maybeSingle();
  if (error || !data) return null;
  return data.stripe_customer_id;
}

async function cancelStripeSubscription(stripeCustomerId) {
  // Find active subscription for this customer
  const resp = await fetch(`${STRIPE_API}/subscriptions?customer=${stripeCustomerId}&status=all&limit=1`, {
    headers: { "Authorization": `Bearer ${STRIPE_SECRET_KEY}` }
  });
  const json = await resp.json();
  if (!json.data || !json.data.length) return null;
  const sub = json.data.find((s) => s.status === "active" || s.status === "trialing");
  if (!sub) return null;
  // Cancel immediately
  await fetch(`${STRIPE_API}/subscriptions/${sub.id}`, {
    method: "DELETE",
    headers: { "Authorization": `Bearer ${STRIPE_SECRET_KEY}` }
  });
  return sub.id;
}

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      }
    });
  }

  const supabase = createClient();
  const { user_id, email } = await req.json();
  if (!user_id || !email) {
    return new Response(JSON.stringify({ error: "Missing user_id or email" }), {
      status: 400,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      }
    });
  }

  // 1. Cancel Stripe subscription if exists
  let stripeCustomerId = await getStripeCustomerId(supabase, user_id);
  if (stripeCustomerId) {
    await cancelStripeSubscription(stripeCustomerId);
  }

  // 2. Delete user from Supabase Auth
  const { error: deleteError } = await supabase.auth.admin.deleteUser(user_id);
  if (deleteError) {
    return new Response(JSON.stringify({ error: "Failed to delete user from Supabase" }), {
      status: 500,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      }
    });
  }

  // 3. Optionally, delete user data from other tables here

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    }
    const supabase = createClient(supabaseUrl, supabaseKey);
});
