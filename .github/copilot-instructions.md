Repository-specific Copilot instructions — ZenCards

Purpose
- Help an AI code agent be productive quickly in this repository: where the auth/billing gates live, how the login → checkout → app flow works, and the key files you should touch when changing access logic.

Quick architecture summary
- Frontend: static site pages in the repo root and `www/` (`index.html`, `app.html`, `landing.html`). Pages use Supabase JS (v2 via CDN) for auth and a small serverless Edge Function to create Stripe checkout sessions.
- Backend: Supabase DB + Edge Functions in `supabase/functions/` (notably `create-checkout-session` and `stripe-webhook`). The DB contains a `subscriptions` table used to gate access.
- Mobile: a Capacitor iOS project under `ios/App/` that bundles the web assets in `ios/App/App/public/`.

Key files & patterns to reference
- `app.html` — app UI, paywall and access gate. Important functions:
  - `enforceAccessGate()` (paywall logic; checks `supabase.auth.getUser()` and `subscriptions` table)
  - `getMySubscriptionStatus()` (reads `subscriptions` table and returns `active|trialing|none|unknown`)
  - `startTrialIfRequested()` (starts checkout when URL contains `startTrial=1`)
  - Paywall DOM ids: `#paywall`, `#paywallAuthFields`, `#paywallLoggedInActions`, `#paywallMsg`.

- `index.html` — landing page and login modal. Important bits:
  - `checkUserAccess(uid)` — performs the same `subscriptions` lookup used to decide whether to `window.location.href = 'app.html'`.
  - Login flow: modal uses `supabase.auth.signInWithPassword()` and then calls `checkUserAccess(uid)`; if access is present it redirects to `app.html`.
  - `startCheckoutFromLanding()` — creates checkout session and redirects to Stripe.

- `supabase/functions/` — serverless functions used to create Stripe checkout sessions and handle webhooks. Deploy with `npx supabase functions deploy <name>`.

- `supabase/config.toml` — local Supabase config (useful for test/deploy hints).

Auth/session conventions
- Supabase client is created in each page with `persistSession: true`, `autoRefreshToken: true`, `detectSessionInUrl: true`, and `storage: window.localStorage`.
- Sessions are persisted in `localStorage` under keys that end with `-auth-token`. The landing page checks for such keys to decide fast-path redirects.

Subscriptions & gating
- The app uses a `subscriptions` table. Rows are queried by `user_id` and the code treats `status === 'active'` or `'trialing'` as granted access.
- When changing gating logic, update both `index.html` (`checkUserAccess`) and `app.html` (`getMySubscriptionStatus` / `enforceAccessGate`).

Developer workflows & commands
- Deploy Supabase Edge Function (example):
  - `npx supabase functions deploy stripe-webhook`
  - `npx supabase functions deploy create-checkout-session`
- To test login→app flow locally: open `index.html` in a browser, use the login modal, and confirm console logs from `checkUserAccess` and `startCheckoutFromLanding`.
- Use the browser console to inspect `localStorage` for keys ending with `-auth-token` and to call helper functions exposed on `window` (e.g. `startFreeTrial()` in `index.html`).

When editing code — actionable tips
- Small changes to gating should be made in `app.html` only after checking `index.html` behavior. Both pages implement similar checks — keep them consistent.
- Prefer using the existing helper functions:
  - `checkUserAccess(uid)` in `index.html` for landing/login flows
  - `getMySubscriptionStatus()` and `enforceAccessGate()` in `app.html` for runtime gating
- If you change DB column names or the `subscriptions` table schema, update both read locations and keep the `.select(...)` clause compatible.
- When touching billing / Stripe logic, also check `supabase/functions/create-checkout-session` and `supabase/functions/stripe-webhook` to keep success/cancel redirect URLs and webhook expectations in sync.

Safety notes
- The repository currently contains the Supabase ANON key in the static pages — this is expected for a public client-side app. Do not commit secret keys (service_role) into the repo.

If anything is unclear
- Tell me which flow you want to modify (landing → login → app, or newsletter signup → app) and I will edit the specific functions and run a quick sanity check.

— end —
