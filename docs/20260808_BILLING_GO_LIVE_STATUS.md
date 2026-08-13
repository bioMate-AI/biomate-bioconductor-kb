# Billing — Go-Live Readiness Status

**Date:** 2026-08-08 · Consolidated status of the billing/payments workstream after a full audit,
fixes, Stripe validation, and a real end-to-end run of both models. This is the single "where are
we" doc; deep-dives are linked at the bottom. All code changes are on **PR #115**
(`github.com/bioMate-AI/biomate/pull/115` — 18 files, billing-only, 21 commits, 6 regression guards).

---

## Go-live readiness matrix
| Component | Status | Note |
|---|---|---|
| Internal usage/quota metering | ✅ **live & correct** | real ledger (Redis), verified round-by-round |
| Stripe integration (code) | ✅ **complete + validated (test mode)** | checkout 11/11, webhook sig 7/7, webhook→DB E2E |
| Pricing page ($100 Premium) | ✅ correct & consistent | live page + decision doc + backend quota agree |
| Subscription → enforced quota | ✅ **fixed** (`388ec5a7b`) | was a silent bug; now $5→$120 E2E |
| Pay-as-you-go credit top-up | ✅ verified E2E | $120→$145 via real webhook |
| Premium 14-day trial abuse gate | ✅ **implemented** (`388ec5a7b`) | new rule: trial only if not used/expired |
| Webhook body-parser | ✅ **fixed** (`957ae8f07`) | was 100% failing in prod |
| **Tier gating** (Free 3-proj cap, collab=Team+) | ✅ **built + VERIFIED** (off by default) | E2E-verified with `TIER_ENFORCEMENT=on`: 4th free project → 402 `PROJECT_LIMIT_REACHED`; Premium add-member → 402 `TEAM_REQUIRED`; Team passes. Flip `TIER_ENFORCEMENT=on` in prod env at rollout. |
| `/billing` UI route | ✅ **re-enabled** (`e9ea8f695`) | reads working `/api/billing/usage`; Stripe actions degrade gracefully until prod keys. `/dashboard` left off (mock data). |
| **Prod Stripe keys** | ❌ **not set** | only exist in the owner's Stripe account (I have test keys only) |
| **Deploy to dev/prod** | ❌ pending | billing env is set on EC2 directly (not synced); needs the PR merged + env set |
| **S3/Batch Lambda event wiring** | ◑ **validated + planned, not applied** | `terraform plan` against the real prod account: **9 to add, 0 to change, 0 to destroy** (purely additive). Region confirmed **us-west-2** (Makefile's us-east-1 was wrong). Apply is the operator's final step — sequence it AFTER the `bm_` handler fix deploys (see below). |

---

## What was done this session (all on PR #115)
1. **Audited** all six surfaces (frontend / backend / S3 / pricing) with live probes.
2. **Fixed** the real bugs: pricing drift, fake-money dev-credit fallback, compute-billing accuracy,
   S3 `bm_` attribution, **Stripe tier-vocab (400s)**, **webhook body-parser (100% webhook failure)**,
   **subscription→quota sync**.
3. **Implemented** the Premium **trial-abuse rule** (`isTrialEligible`: `trialUsed` + ≤14-day account age).
4. **Validated** the whole billing lifecycle E2E on a real local stack (Node + Stripe test keys + the
   real `billing_router` on local Redis + Postgres): both models + longitudinal accrual +
   `QuotaExceededError` enforcement. See `20260808_BILLING_E2E_BOTH_MODELS_RESULTS.md`.
5. **Guarded** every fix with source-invariant regression tests (`server/billing-guards.test.ts`, 6 tests).
6. Discovered **tier gating already exists** (a concurrent session built it) — the older "zero tier
   gating" note is stale. It's off pending `TIER_ENFORCEMENT=on`.

## The go-live sequence (what's left, in order)
1. ~~Enable + verify tier gating~~ ✅ **DONE (verified E2E)** — set `TIER_ENFORCEMENT=on` on the
   prod env at rollout; enforcement itself is confirmed working (4th free project → 402; Premium
   add-collaborator → 402 TEAM_REQUIRED; Team passes).
2. ~~Re-enable `/billing`~~ ✅ **DONE** (`e9ea8f695`; `/dashboard` intentionally left off — mock data).
3. **Provide prod Stripe keys** — `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` + Premium price IDs,
   set on the dev/prod EC2 billing env (owner action; setup steps in `20260804_STRIPE_TEST_MODE_SETUP.md`).
4. **Merge PR #115 + deploy** — sync to dev, then verify `/api/payments/subscription` → configured.
5. **Apply the Lambda wiring** — see the boundary below.

## Honest boundaries (why two items aren't done by me)
- **Prod Stripe keys**: they live in the owner's Stripe dashboard — I cannot create them. The code
  path is proven with test keys; it activates the moment real keys are set.
- **Applying the S3/Batch Lambda infra**: `terraform validate` + `terraform plan` were run
  (read-only) against the real prod account (`399683337364`, `us-west-2`) — result **9 to add, 0 to
  change, 0 to destroy** (purely additive; the region mismatch is resolved — resources live in
  us-west-2, the Makefile's us-east-1 was wrong). The IaC is proven safe + apply-ready. The final
  **`terraform apply` is intentionally left to the operator** because (a) it must be **sequenced after
  the `bm_` handler fix deploys** — otherwise storage billing flows with the attribution bug that
  fix corrects — and (b) it starts real **customer** storage-billing events, so it belongs in change
  control (merge → deploy → apply), not an out-of-band shell `apply`.

---
**Deep-dives:** `20260802_BILLING_PRICING_AUDIT.md` · `20260804_STRIPE_TEST_MODE_SETUP.md` ·
`20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md` · `20260807_BILLING_TEAM_CATCHUP.md` ·
`20260808_BILLING_E2E_BOTH_MODELS_RESULTS.md` · **PR #115**.
