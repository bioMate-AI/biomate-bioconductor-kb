# Billing / Pricing / Payment — Implementation Audit

**Date:** 2026-08-02
**Question (user):** check the pricing webpage; do we support both business models; is credit-card/payment implemented; is there a per-user billing page?
**Method:** code inspection + live dev API probes (`dev-public.biomate.ai`). Every claim below
cites a file/line or a live response.

---

## 2026-08-04 follow-up — "continue any left work, make sure everything works" (RESOLVED)

Re-audited all six surfaces (frontend / backend / S3 / pricing) with fresh live probes.
**Live internal metering is healthy** (`/api/billing/usage|quota|jobs/running` all return real
data). **The live pricing page was already correct** — Premium **$100/mo ($80 annual)**, Team/
Enterprise custom (byte-identical md5 to `webpage_design_v2/pricing.html`; matches the 20260727
decision doc + backend `DEFAULT_PLAN_LIMITS premium=$120`). The "$29/$49/$199 inconsistency" an
earlier sub-audit flagged was a misread of **stale, undeployed** repo files.

Fixed + committed (no deploy — pilot posture, routes stay disabled, Stripe unconfigured on dev):
- **Pricing drift** (`459aec42f`, `5cd63727d`): in-app `pricing.tsx` $49→$100 Premium, Team→custom
  /contact (was a broken self-serve `/checkout` for a sales-led tier); `PRICING_STRATEGY.md`
  superseded banner → canonical numbers.
- **Fake-money dev fallback** (`9eb2bd7b8`): `add-credits` no longer returns success-shaped
  `{url:null}` when Stripe is unconfigured — 503 unless `NODE_ENV!=production && BILLING_DEV_CREDITS=true`;
  `billing.tsx` never claims credits were added when they weren't. Dead `BillingWidget` removed.
- **Compute-billing accuracy** (`a30518549`): `job_completed` emit uses real vCPU/mem/instance from
  `run_meta` with fallback to 4/8192/optimal (unchanged for the common auto-optimal Batch case).
- **S3 storage metering** (`ab8e44642` IaC+runbook, `b03f795f7` handler fix): root cause of live
  `storage:$0` = S3 event notifications never wired (and only 1 of 2 billable buckets). Added a
  Terraform `billing_events` module + `docs/20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md` (not applied
  — needs an operator). Also fixed a real attribution bug: uploads tagged `bm_<uuid>` were split
  from the raw-`<uuid>` ledger → normalized in the handler.

**Still requires you (not code):** (1) go-live decision + prod `STRIPE_SECRET_KEY`/price-IDs to
un-disable `/billing /pricing /checkout` and add tier gating; (2) apply the Lambda wiring runbook
(AWS infra — deliberately not done out-of-band); (3) confirm the Makefile-vs-deploy-script
name/region mismatch (`us-east-1` vs `us-west-2`) before applying (2).

---

## TL;DR
| Component | State | Evidence |
|---|---|---|
| Pricing webpage | ✅ exists (static) | `webpage_design_v2/pricing.html` (+ `_new`/`_prototype`) |
| Usage/quota metering | ✅ **LIVE + working** | `GET /api/billing/usage` → real costs (LLM $0.081, compute $0.049, 2026-08) |
| Stripe credit-card payment | ⚠️ **coded but NOT configured on dev** | `configured:false`; checkout → "Stripe is not set up" |
| Per-user billing page | ⚠️ **built but route disabled** | `pages/billing.tsx` exists; `/billing` route commented in `App.tsx:613` |
| Two business models | ◑ defined; self-serve coded, enterprise = sales-led | `PRICING_STRATEGY.md` |
| Tier enforcement (gating) | ❌ not implemented | zero tier-gating in code (per tier-proposal analysis) |

---

## 1. Pricing webpage — ✅ exists
`webpage_design_v2/pricing.html` (the public site is the static HTML, not the React app).
Tiers per `frontend/PRICING_STRATEGY.md`: **Free $0 / Pro $20-mo / Team / Enterprise (custom)**,
hybrid model = base subscription **+ usage-based credits** (Replit-style).

## 2. Two business models — self-serve is coded; enterprise is sales-led
- **(A) Self-serve SaaS** — Free/Pro/Team: subscription + monthly credits + pay-as-you-go
  overage. **Code-implemented** via Stripe (§3).
- **(B) Enterprise / pharma** — custom pricing, contracts, SSO/SAML, BAAs, on-prem
  (`PRICING_STRATEGY.md:92`). **Sales-led / negotiated, NOT a self-serve flow** (enterprise
  Stripe price-IDs exist as placeholders; no self-service enterprise checkout).
- **Caveat:** **no tier-gating in code** — features/compute are not enforced by plan, so today
  every user effectively has full access regardless of tier. The models are *billing-defined*,
  not *access-gated*.

## 3. Credit-card / payment — implemented in code, INACTIVE on dev
Code exists and is complete:
- `frontend/server/stripe-service.ts` — Stripe SDK: checkout sessions, customer portal,
  subscriptions, webhooks. Env-gated on `STRIPE_SECRET_KEY` + `STRIPE_PRICE_*`.
- `routes.ts`: `POST /api/payments/create-checkout-session`, `create-portal-session`,
  `GET /api/payments/subscription`.
- `pages/billing.tsx` has a buy-credits flow **with a "dev mode" fallback** that adds credits
  WITHOUT real payment (`billing.tsx:271`) — must be disabled in prod.

**Live dev probe (2026-08-02):**
- `GET /api/payments/subscription` → `{"success":true,"subscription":null,"configured":false}`
- `POST /api/payments/create-checkout-session` → `{"error":"Payment system not configured",
  "message":"Stripe is not set up. Contact support."}`

→ **Stripe is NOT configured on dev** (no keys). Whether it's live on **prod** depends on the
prod `STRIPE_SECRET_KEY`/price-IDs — verify separately (per CLAUDE.md, prod billing = Stripe).

## 4. Per-user billing page — built, but the route is disabled
`frontend/client/src/pages/billing.tsx` is complete (usage %, quota, usage history,
subscription, upgrade, buy-credits; reads `/api/billing/usage` + `/api/payments/subscription`).
BUT **the `/billing` route is commented out** in `App.tsx:613-617` — as are **`/dashboard`
(605-611) and `/checkout` (597-602)**. This is a **deliberate pilot posture**: self-serve
billing/payment intentionally hidden while pilot users are invited/comped. No "broken" reason
in git history — it was disabled during a refactor/pilot, not because it errors.

`/api/billing/usage` itself **works live** — so the page would render usage/quota correctly;
only Stripe-dependent actions degrade (graceful "not configured").

---

## Recommendations (by goal)
- **Keep pilot posture (invited/comped users):** leave routes disabled. Nothing to do; usage
  metering already tracks cost internally for reporting.
- **Turn on self-serve (GA / paid signups):**
  1. Set prod `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` + `STRIPE_PRICE_*` IDs.
  2. Re-enable `/billing` (usage view — low-risk, reads a working API) and, when payment is
     desired, `/checkout` + `/dashboard`.
  3. Ensure the `billing.tsx` **dev-mode credit fallback is gated off in prod**.
  4. Implement **tier gating** (currently absent) so plans actually limit features/compute —
     otherwise paid tiers grant nothing extra over Free.
  5. Run `frontend/e2e/billing-smoke.e2e.ts` against a Stripe-configured stack.
- **Enterprise/pharma:** this is sales-led/custom by design (no self-serve). What a pharma
  pilot deal needs (BAAs, SSO/SAML, dedicated resources, custom credits) is *listed* in
  strategy but **not implemented** — SSO/SAML and on-prem are build items, not config.

**Related:** `frontend/PRICING_STRATEGY.md`, CLAUDE.md "Billing System" (Stripe + internal
quota; Lago dropped), memory `project_billing_flat_tier` + `project_module_perf_tier`
(zero tier-gating), `project_fundability_thesis` (pharma-embedded model).
