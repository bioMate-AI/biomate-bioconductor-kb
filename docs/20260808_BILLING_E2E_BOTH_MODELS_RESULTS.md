# Billing E2E — both models, longitudinal, on the real stack

**Date:** 2026-08-08 · Ran the full billing lifecycle through the **real** stack — Node (Stripe
test keys) + the **real** `billing_router` on local Redis + Postgres — exercising subscription AND
pay-as-you-go from the checkout/webhook layer, then tracking the ledger over many rounds until
quota enforcement fired. Found + fixed **2 real bugs** and implemented the **trial-abuse rule**.

## How it was run (faithful, isolated)
- **Node** `:5055` with the team's `sk_test_`/`whsec_` + Premium price IDs, `BILLING_API_URL→:8081`.
- **billing_router** (unchanged prod code) mounted on `uvicorn :8081` against **local** Redis
  (NOT prod ElastiCache — no pollution), Lago/Java disabled.
- **Postgres** local `biomate` DB.
- The one non-real step: a human typing the card into Stripe's *hosted* page — replaced by the
  **identical signed webhook** Stripe sends post-payment (checkout/subscription session creation is
  separately proven 11/11 against the Stripe test API).

## Results
### A. Premium 14-day trial eligibility (new rule) — ✅ 3/3
Checked against DB records at checkout (`isTrialEligible`: `trialUsed` + account age ≤ 14d):
| user state | `trial_granted` | outcome |
|---|---|---|
| new (age 0d, unused) | `true` | gets 14-day trial ✅ |
| existing (age 30d, free window passed) | `false` | pays immediately, no repeat trial ✅ |
| already used a trial | `false` | no second free trial ✅ |

### B. Subscribe → enforced quota — ✅ (bug fixed)
`$5 (free) → subscribe Premium (real webhook) → $120`. **Before the fix it stayed $5** — the
subscription webhook wrote only Postgres `subscriptionTier`; the enforced Redis quota kept the
signup cap, so a paying Premium user was capped at Free.

### C. Pay-as-you-go credit top-up → ✅
`$120 → +$25 credit top-up (real checkout.session.completed webhook) → $145`.

### D. Longitudinal ledger (round = 1 chat + 1 workflow run) — ✅
Usage accrues ~$8.79/round via the **real `CostCalculator`**; a mid-run PAYG **+$50** raises the
cap $120→$170 (pct drops 51%→41%); tracked cleanly round-by-round.

### E. Enforcement gate — ✅
Pushed usage to **$175.90 > $170** → `over_quota=true` → the real
`quota_enforcer.check_and_reserve` (the gate at AWS Batch submit) raises **`QuotaExceededError`** and
blocks the next job. Under-cap it returns ALLOWED.

## Bugs found + fixed (this pass)
1. **Webhook body-parser** (`957ae8f07`, earlier) — global `express.json()` broke signature
   verification → every webhook 400'd. (E2E flipped 400→200.)
2. **Subscription never reached the enforced quota** (`388ec5a7b`) — added
   `/internal/billing/set_plan` + call it from the subscription webhook
   (`_syncPlanToBilling`; active/trialing→tier, canceled→free). Verified $5→$120→(cancel)→$5.

## Feature implemented
- **Premium trial-abuse gate** (`388ec5a7b`) — `isTrialEligible` grants the 14-day trial only to
  users who haven't used/passed their free trial; repeat/expired users are charged immediately.

## Still not exercised locally
- Real card entry on Stripe's hosted page (browser) and the Galaxy/Redis prod deployment — both
  validated by-proxy here (identical webhook; same `billing_router` code). Prod verification needs
  the deploy + prod Stripe keys.
