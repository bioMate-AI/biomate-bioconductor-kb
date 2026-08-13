# Billing — Team Catch-up

**Date:** 2026-08-07 · **Owner:** billing left-work sweep · **Branch:** `billing/pr-clean-20260807`

One-page status for the team. Detailed docs linked at the bottom.

---

## TL;DR
Audited all six billing surfaces, fixed the real bugs, and validated the Stripe payment path
against **test mode** this session (keys live, Premium prices created, checkout + subscription
create OK). **Self-serve payment stays disabled by deliberate pilot posture** — turning it on is a
go-live decision that needs prod Stripe keys + tier gating. Internal usage metering is live and
healthy today.

## Status by surface
| Surface | State | Note |
|---|---|---|
| Internal metering (`/api/billing/usage|quota|jobs/running`) | ✅ **live** | real LLM/compute data; quota enforced at Batch submit; Lago gated off |
| Pricing webpage (`www.biomate.ai/pricing.html`) | ✅ **correct** | Premium $100/mo ($80 annual), Team/Enterprise custom — matches decision doc + backend quota |
| In-app React pricing + strategy doc | ✅ **fixed** | had drifted ($49/$20); realigned to $100 |
| Frontend payment (Stripe code, checkout/billing pages) | ✅ code complete | fake-money "dev credits" hazard closed; routes disabled (pilot) |
| S3 storage metering | ⚠️ **needs apply** | was `storage:$0` — event wiring never existed; IaC + runbook added, **not applied** |
| Stripe integration | ✅ **test-mode validated** | see smoke below; blocker fixed |

## Fixes landed (on the branch)
- **Pricing alignment** — in-app page $49→$100 Premium, Team→custom/contact; strategy doc superseded banner.
- **Fake-money gate** — `add-credits` no longer fakes credits when Stripe is unconfigured (now 503 unless an explicit dev flag); removed dead `BillingWidget`.
- **Compute-billing accuracy** — `job_completed` emit uses real vCPU/mem/instance (fallback preserved).
- **S3 metering** — Terraform `billing_events` module + wiring runbook; fixed a real attribution bug (uploads tagged `bm_<uuid>` were split from the raw-uuid ledger → under-counted).
- **Stripe tier-vocab blocker** — checkout sent `tier="premium"` but the price map only knew `academic/professional/enterprise` → **400 even with valid keys**. Now `premium` resolves and the webhook maps subscriptions to the canonical `premium` quota tier ($120).
- **Webhook body-parser bug (prod-breaking)** — a global `express.json()` parsed the webhook body before the route's `express.raw()`, so **every Stripe webhook 400'd** on signature verification. Fixed by excluding `/api/payments/webhook` from the global parser. (Found by the webhook→DB E2E below.)

## Stripe smoke (this session, TEST mode — no real money)
Ran against the real Stripe test API with the team's `sk_test_` key — **11/11 checks pass**:
- ✅ Key valid, `livemode=false`.
- ✅ Created **BioMate Premium** product + prices: **$100/mo** and **$960/yr**.
- ✅ Customer create; test card `pm_card_visa` attached + default.
- ✅ **Subscription `active`** on the Premium price (test card charged) — this is the `checkout.session.completed` end-state; its price id is what the webhook maps to the `premium` quota tier ($120).
- ✅ Subscription-mode **Checkout Session** create → real `checkout.stripe.com/c/pay/cs_test_…` URL, `mode=subscription`, `status=open`.
- ✅ Subscription retrievable (mirrors `/api/payments/subscription`).

**Webhook signature/routing smoke — 7/7 pass** (the security-critical gate in `handleWebhook`):
- ✅ Created a real webhook endpoint → genuine `whsec_`; signed events with `generateTestHeaderString` and verified with the same `constructEvent` call BioMate uses.
- ✅ Valid signature **accepted** (`checkout.session.completed` + `customer.subscription.created`); `userId` + Premium price id survive to the handlers; event routes to a handled `switch` case.
- ✅ **Negative gates hold:** tampered payload **rejected**; wrong signing secret **rejected**.

**Webhook → DB end-to-end (real running server + Postgres) — ✅ passed, and caught a prod bug:**
- Ran a second server instance (Stripe env set) against local Postgres; POSTed a **signed**
  `customer.subscription.created` to the real `/api/payments/webhook` → **HTTP 200 `{received:true}`**
  → server log "Updated subscription … active" → Postgres `users.subscription_tier=premium,
  subscription_status=active`. (Was `free` before.)
- 🐞 **Production bug found + fixed** (`fix(billing): exclude Stripe webhook path from global body
  parser`): `server/index.ts` mounted a global `express.json()` on all non-MCP paths, which parsed
  the webhook body **before** the route's `express.raw()` — so `constructEvent` threw "payload must
  be a string or Buffer" and **every** Stripe webhook returned 400. It would have failed silently in
  prod (sub lifecycle, credit grants, payment-failed all dead). Fixed by skipping the global parser
  for `/api/payments/webhook`; the E2E flipped 400 → 200 after the fix.
- ⏳ **Only remaining:** the *credit-grant* branch (checkout top-up → Galaxy `/internal/billing/
  add-credits` → Redis quota) needs Galaxy+Redis up (were down locally); and a full UI E2E with
  `/pricing`+`/checkout` re-enabled. Test keys/secret session-local only (never committed); all
  Stripe + DB test state cleaned up/restored.

## What needs the team / decisions
1. **Go-live vs stay pilot.** To enable `/pricing /checkout /billing`: provide **prod** `STRIPE_SECRET_KEY` + price IDs, and we add **tier gating** (currently none — all users get full access regardless of plan).
2. **Apply the S3/Batch Lambda wiring** (AWS infra, not done out-of-band). First resolve the flagged **`us-east-1` vs `us-west-2`** / function-name mismatch between the Makefile and deploy scripts.
3. **Merge:** open the PR below. ⚠️ The branch carries ~80 accumulated `integration/next-phase` commits from concurrent sessions (couldn't cut a clean billing-only branch — dirty shared tree + interleaved history + the new PR-only rule on `next-phase`). Review the billing commits specifically (see list in the audit doc).

---
## Links
- **Branch:** https://github.com/bioMate-AI/biomate/tree/billing/pr-clean-20260807
- **PR:** https://github.com/bioMate-AI/biomate/pull/115
- **Compare vs next-phase:** https://github.com/bioMate-AI/biomate/compare/integration/next-phase...billing/pr-clean-20260807
- **Detailed docs (on the branch):**
  - Full surface audit + resolution — `docs/20260802_BILLING_PRICING_AUDIT.md`
  - Stripe test-mode setup + tier blocker — `docs/20260804_STRIPE_TEST_MODE_SETUP.md`
  - S3/Batch Lambda wiring runbook — `docs/20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md`
