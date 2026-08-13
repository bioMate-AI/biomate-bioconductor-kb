# Stripe Test-Mode Setup — to validate the payment half of billing

**Date:** 2026-08-04
**Why:** The Stripe payment path has **never been exercised end-to-end** — there is no key in
the repo or on dev (`/api/payments/subscription` → `configured:false`). This doc is the checklist
to stand up **Stripe test mode** (free, no real charges) so checkout → webhook → credit can finally
be validated. User is providing the Stripe credentials.

---

## 0. Current state (verified 2026-08-04)
- **No key anywhere.** Repo has only a commented placeholder (`.env.example:66-67`). No Secrets
  Manager / SSM wiring. Dev has `STRIPE_SECRET_KEY` unset → `stripeService.isConfigured()` false →
  every `/api/payments/*` returns 503 "Stripe is not set up".
- Code is otherwise complete: `frontend/server/stripe-service.ts` (checkout, portal, subscriptions,
  webhooks, credit top-ups), endpoints in `routes.ts` (~2864-3095), pages `checkout.tsx` /
  `billing.tsx` / `pricing.tsx` (routes currently disabled in `App.tsx` — pilot posture).

---

## 1. ⚠️ BLOCKER to fix BEFORE checkout will work (tier-vocabulary mismatch)

Even with valid keys, the Premium checkout **400s today**. The tier name flows through three
layers that disagree:

| Layer | Value | Evidence |
|---|---|---|
| Pricing page routes to | `/checkout/premium`, `/checkout` (Team→`/contact`) | `pricing.tsx` handleSelectPlan |
| Checkout page sends | `{ tier: "premium", interval }` | `checkout.tsx:66,128` |
| `getPricingTiers()` keys | `academic` / `professional` / `enterprise` | `stripe-service.ts:515-529` |
| Route lookup | `tiers["premium"]` → **undefined** → `400 "Unknown tier: premium"` | `routes.ts:~2878-2882` |
| Webhook sets `subscriptionTier` | `professional` (not `premium`) | `stripe-service.ts:196-211` |
| Quota plan limits use | `premium=$120` (no `professional` key) | `quota_enforcer.py DEFAULT_PLAN_LIMITS` |

**Fix required (do when wiring keys, then test):** align the vocabulary to the canonical tiers
(`Free / Premium / Team / Enterprise`). Minimal, correct version:
- `getPricingTiers()` → expose a **`premium`** key (mapped to the `PROFESSIONAL_*` env price IDs, or
  rename the env vars to `STRIPE_PRICE_PREMIUM_*`). Keep `academic` if an academic discount SKU is
  really wanted; drop/keep `professional` as a legacy alias only if needed.
- Webhook price→tier map (`stripe-service.ts:196-211`) → set `subscriptionTier = 'premium'` for the
  Premium price IDs, so it matches `DEFAULT_PLAN_LIMITS['premium']` ($120 cap).
- Only **Premium** needs a self-serve price ID. **Team** and **Enterprise** are sales-led → they
  route to `/contact` (no checkout). **Free** has no price.

Do NOT ship this rename without running the smoke in §4 — it touches the price↔quota join.

---

## 2. Create in the Stripe Dashboard (Test mode toggle ON)
1. **Test secret key** — Developers → API keys → `sk_test_…`.
2. **Webhook** — Developers → Webhooks → add endpoint
   `https://dev-public.biomate.ai/api/payments/webhook` (or local tunnel), events:
   `checkout.session.completed`, `customer.subscription.created|updated|deleted`,
   `invoice.payment_succeeded|payment_failed`. Copy the signing secret `whsec_…`.
3. **Products/Prices (recurring)** — create **Premium** with two prices:
   - Premium **monthly** = **$100/mo** → price id `price_…`
   - Premium **annual** = **$80/mo billed yearly ($960/yr)** → price id `price_…`
   - (Team/Enterprise: none — sales-led. Optional academic-discount SKU only if you want one.)

## 3. Env vars to set
Set on the **dev EC2 frontend container directly** (billing env is NOT synced by
`sync_to_dev.sh` — per CLAUDE.md), or in `frontend/.env` for a local test run:
```
STRIPE_SECRET_KEY=sk_test_…
STRIPE_WEBHOOK_SECRET=whsec_…
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_…   # = Premium monthly (until env renamed to _PREMIUM_)
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_…    # = Premium annual
# APP_URL defaults to https://dev-public.biomate.ai (stripe-service.ts:9)
```
Reference: consumed at `stripe-service.ts:7-18`. `isConfigured()` flips true once
`STRIPE_SECRET_KEY` is present.

## 4. Test procedure (once §1 fix + keys are in)
1. Re-enable `/pricing`, `/checkout`, `/billing` routes in `App.tsx` (temporarily, for the test).
2. `pricing.tsx` → Premium → **Get started** → `/checkout/premium`.
3. Stripe test checkout → pay with test card **`4242 4242 4242 4242`**, any future expiry/CVC/zip.
4. Confirm: redirect back with `?status=success`; the `checkout.session.completed` webhook fires;
   `/internal/billing/add-credits` bumps quota; `/api/payments/subscription` now returns the sub;
   `subscriptionTier` == `premium` and `/api/billing/quota` shows the $120 cap.
5. Portal: `/billing` → Manage plan → Stripe customer portal opens (`create-portal-session`).
6. Negative: decline card `4000 0000 0000 0002` → `invoice.payment_failed` path.
7. Then re-run `frontend/e2e/billing-smoke.e2e.ts` (currently only checks the internal ledger).

## 5. Guardrails
- **Test mode only** until go-live — test keys never move real money.
- The `BILLING_DEV_CREDITS` dev-fallback (fixed `9eb2bd7b8`) must stay **off in prod**; with real
  test keys you don't need it anyway.
- Do not commit any `sk_*` / `whsec_*` / `price_*` values to the repo — env/secret only.

---

**Related:** `docs/20260802_BILLING_PRICING_AUDIT.md` (full surface audit + 2026-08-04 resolution),
`docs/20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md` (S3/Batch metering infra).
