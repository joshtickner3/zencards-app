// supabase/functions/stripe-webhook/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "npm:stripe@16.12.0";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!STRIPE_WEBHOOK_SECRET || !STRIPE_SECRET_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return json(500, {
      error:
        "Missing env vars (need STRIPE_WEBHOOK_SECRET, STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)",
    });
  }

  const sigHeader = req.headers.get("stripe-signature");
  if (!sigHeader) return json(400, { error: "Missing stripe-signature header" });

  // ✅ raw body exactly once
  const rawBody = await req.text();

 const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

  let event: Stripe.Event;
  try {
    // ✅ Use Stripe's official signature verification
    event = await stripe.webhooks.constructEventAsync(rawBody, sigHeader, STRIPE_WEBHOOK_SECRET);
  } catch (e) {
    console.error("[stripe-webhook] signature verification failed:", e);
    return json(400, { error: "Signature verification failed", details: String(e) });
  }

  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---- Helpers ----

  async function ensurePublicUserRow(userId: string) {
    // Minimal insert to satisfy FK constraints.
    // Your public.users table does NOT have an 'email' column (per logs),
    // so we ONLY upsert the primary key.
    const { error } = await supabaseAdmin.from("users").upsert({ id: userId }, { onConflict: "id" });

    if (error) {
      console.warn("[stripe-webhook] ensurePublicUserRow failed:", error);
      throw error;
    }
  }

  async function markTrialUsed(userId: string) {
    // Requires columns:
    // alter table public.users add column if not exists trial_used boolean not null default false;
    // alter table public.users add column if not exists trial_used_at timestamptz null;
    const { error } = await supabaseAdmin
      .from("users")
      .update({ trial_used: true, trial_used_at: new Date().toISOString() })
      .eq("id", userId);

    if (error) {
      console.warn("[stripe-webhook] markTrialUsed failed:", error);
      throw error;
    }
  }

  async function upsertStripeCustomerMapping(userId: string, stripeCustomerId: string) {
    const { error } = await supabaseAdmin.from("stripe_customers").upsert(
      {
        user_id: userId,
        stripe_customer_id: stripeCustomerId,
        created_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );
    if (error) throw error;
  }

  async function upsertSubscriptionRow(opts: {
    userId: string;
    subscriptionId: string;
    status: string | null;
    priceId: string | null;
    currentPeriodEnd: string | null;
    trialEnd: string | null;
    cancelAtPeriodEnd: boolean;
  }) {
    const { userId, subscriptionId, status, priceId, currentPeriodEnd, trialEnd, cancelAtPeriodEnd } = opts;

    const { error } = await supabaseAdmin.from("subscriptions").upsert(
      {
        user_id: userId,
        stripe_subscription_id: subscriptionId,
        status,
        price_id: priceId,
        current_period_end: currentPeriodEnd,
        trial_end: trialEnd, // remove if your column doesn't exist
        cancel_at_period_end: cancelAtPeriodEnd,
        updated_at: new Date().toISOString(),
      } as any,
      { onConflict: "user_id" },
    );

    if (error) throw error;
  }

  async function resolveUserIdFromSubscriptionId(subscriptionId: string): Promise<string | null> {
    const { data, error } = await supabaseAdmin
      .from("subscriptions")
      .select("user_id")
      .eq("stripe_subscription_id", subscriptionId)
      .maybeSingle();

    if (error) {
      console.warn("[stripe-webhook] resolveUserIdFromSubscriptionId failed:", error.message);
      return null;
    }
    return data?.user_id ?? null;
  }

  // ---- Main handler ----

  try {
    const type = event.type;

    // 1) checkout.session.completed
    if (type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;

      const userId =
        (typeof session.client_reference_id === "string" ? session.client_reference_id : null) ||
        (session.metadata?.supabase_user_id ?? null);

      const subscriptionId = typeof session.subscription === "string" ? session.subscription : null;

      const stripeCustomerId =
        typeof session.customer === "string" ? session.customer : (session.customer as any)?.id ?? null;

      // const email = session.customer_details?.email || session.metadata?.email || null; // not used

      if (userId) {
        // ✅ Prevent FK failures
        await ensurePublicUserRow(userId);
      }

      if (userId && stripeCustomerId) {
        await upsertStripeCustomerMapping(userId, stripeCustomerId);
      }

      if (userId && subscriptionId) {
        // Fetch subscription immediately so status becomes trialing right away
        const sub = await stripe.subscriptions.retrieve(subscriptionId);

        // ✅ If trial started, mark it used
       // ✅ Permanently mark trial as used once the user has a real subscription start
// (trialing or active). This covers both:
// - first-time trial
// - paid signup with no trial
// and prevents ever getting a trial again later.
if (sub.status === "trialing" || sub.status === "active") {
  await markTrialUsed(userId);
}


        const priceId = sub.items.data?.[0]?.price?.id ?? null;
        const currentPeriodEnd = sub.current_period_end
          ? new Date(sub.current_period_end * 1000).toISOString()
          : null;
        const trialEnd = sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null;
        const cancelAtPeriodEnd = Boolean(sub.cancel_at_period_end);

        await upsertSubscriptionRow({
          userId,
          subscriptionId,
          status: sub.status ?? "trialing",
          priceId,
          currentPeriodEnd,
          trialEnd,
          cancelAtPeriodEnd,
        });
      }

      return json(200, { ok: true, handled: type });
    }

    // 2) customer.subscription.created / updated
    if (type === "customer.subscription.created" || type === "customer.subscription.updated") {
      const sub = event.data.object as Stripe.Subscription;
      const subscriptionId = sub.id;

      let userId = (sub.metadata?.supabase_user_id as string | undefined) ?? null;
      if (!userId) userId = await resolveUserIdFromSubscriptionId(subscriptionId);

      if (!userId) {
        // Don’t 500 — Stripe will retry forever for an unmappable event.
        return json(200, {
          ok: true,
          handled: type,
          warning:
            "No supabase_user_id found. Ensure create-checkout-session sets subscription_data.metadata.supabase_user_id and/or client_reference_id.",
        });
      }

      await ensurePublicUserRow(userId);

      /// ✅ Permanently mark trial as used once the user has a real subscription start
// (trialing or active). This covers both:
// - first-time trial
// - paid signup with no trial
// and prevents ever getting a trial again later.
if (sub.status === "trialing" || sub.status === "active") {
  await markTrialUsed(userId);
}

      const priceId = sub.items.data?.[0]?.price?.id ?? null;
      const currentPeriodEnd = sub.current_period_end
        ? new Date(sub.current_period_end * 1000).toISOString()
        : null;
      const trialEnd = sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null;
      const cancelAtPeriodEnd = Boolean(sub.cancel_at_period_end);

      await upsertSubscriptionRow({
        userId,
        subscriptionId,
        status: sub.status ?? null,
        priceId,
        currentPeriodEnd,
        trialEnd,
        cancelAtPeriodEnd,
      });

      return json(200, { ok: true, handled: type });
    }

    // 3) customer.subscription.deleted
    if (type === "customer.subscription.deleted") {
      const sub = event.data.object as Stripe.Subscription;
      const subscriptionId = sub.id;

      let userId = (sub.metadata?.supabase_user_id as string | undefined) ?? null;
      if (!userId) userId = await resolveUserIdFromSubscriptionId(subscriptionId);

      if (!userId) {
        return json(200, { ok: true, handled: type, warning: "No userId; ignoring." });
      }

      await ensurePublicUserRow(userId);

      await upsertSubscriptionRow({
        userId,
        subscriptionId,
        status: "canceled",
        priceId: sub.items.data?.[0]?.price?.id ?? null,
        currentPeriodEnd: sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
        trialEnd: sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null,
        cancelAtPeriodEnd: true,
      });

      return json(200, { ok: true, handled: type });
    }

    // ignore others
    return json(200, { ok: true, handled: type, ignored: true });
  } catch (e) {
    console.error("[stripe-webhook] handler failed:", e);

    return json(500, {
      error: "Webhook handler failed",
      details:
        e instanceof Error ? { name: e.name, message: e.message, stack: e.stack } : e,
    });
  }
});
