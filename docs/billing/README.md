# BioMate Billing System

**Branch:** `billing_system`
**Status:** Code complete — infrastructure setup required before going live
**Author:** Claude Code
**Last updated:** 2026-02-18

---

## Quick Navigation

| What you need | Where to look |
|---------------|---------------|
| Full system documentation | [`TECHNICAL_REFERENCE.md`](./TECHNICAL_REFERENCE.md) |
| **Real-time monitoring setup** | **[`MONITORING.md`](./MONITORING.md)** — admin tools, CloudWatch alarms, daily cron |
| Cost tracking flow diagram | [`diagrams/cost_tracking_flow.drawio`](./diagrams/cost_tracking_flow.drawio) |
| User registration flow diagram | [`diagrams/user_registration_flow.drawio`](./diagrams/user_registration_flow.drawio) |
| Billing page architecture diagram | [`diagrams/billing_page_architecture.drawio`](./diagrams/billing_page_architecture.drawio) |
| Infrastructure checklist | [Section 4 of TECHNICAL_REFERENCE.md](./TECHNICAL_REFERENCE.md#4-work-remaining-for-backend-programmer) |
| Mock data test script | [Section 4.5 of TECHNICAL_REFERENCE.md](./TECHNICAL_REFERENCE.md#45-end-to-end-mock-test-checklist) |

To open diagrams: download and open at **[app.diagrams.net](https://app.diagrams.net)** (File → Open from → This device), or open in the VS Code draw.io extension.

---

## What Was Built

This branch adds a complete usage-based billing system. Everything here is new — it does not modify any existing workflow or AI assistant code.

### Overview

```
User runs a workflow
        │
        ├─► LLM calls          ──► llm_client.py tracks tokens + cost
        ├─► AWS Batch jobs      ──► Lambda calls billing API on state change
        └─► S3 uploads          ──► Lambda calls billing API on upload
                │
                ▼
        billing_router.py (FastAPI, port 8081)
                │
                ├─► cost_calculator.py  — computes USD from AWS pricing tables
                ├─► realtime_cost_service.py  — writes to Redis, checks quota
                └─► lago_client.py  — emits metered events to Lago for invoicing
                        │
                        ├─► Redis  — live cost ledger (frontend reads this)
                        ├─► Lago   — metered billing platform (invoices)
                        └─► Node.js /internal/notify/quota  — triggers emails
```

### New Files

#### Backend (Python — `backend/lib/galaxy/ai/billing/`)

| File | Purpose |
|------|---------|
| `core/realtime_cost_service.py` | Redis-backed live cost ledger. Tracks LLM, compute, storage. Quota checking + email trigger at 80%/100%. |
| `core/cost_calculator.py` | Pure-function AWS cost calculator. EC2 pricing tables (m6i, c6i, g4dn, g5, p3, p4d), S3, and LLM model pricing. |
| `core/quota_enforcer.py` | Pre-job quota gate. Raises `QuotaExceededError` before submitting to AWS Batch. |
| `core/lago_client.py` | HTTP client for Lago billing platform. Emits 9 metered event types. Fire-and-forget. |
| `api/billing_router.py` | 11 FastAPI endpoints: 4 public (JWT auth), 5 internal (X-Internal-Key), 2 admin monitoring (X-Internal-Key), 1 Lago webhook. |
| `lambda/batch_billing.py` | AWS Lambda triggered by EventBridge on Batch job state changes (RUNNING/SUCCEEDED/FAILED). |
| `lambda/s3_billing.py` | AWS Lambda triggered by SQS on S3 uploads. |
| `tests/test_billing_regression.py` | 29 regression tests (62 total). All passing. |

#### Frontend (TypeScript — `frontend/`)

| File | Change | Purpose |
|------|--------|---------|
| `client/src/pages/billing.tsx` | **New** | Full billing & invoices page (1000 lines). Three sections: Included Usage, On-Demand, Invoices. |
| `client/src/pages/auth/register.tsx` | **Modified** | 2-step registration: account info → Stripe trial setup. |
| `server/stripe-service.ts` | **Modified** | Added `createTrialCheckoutSession()`, `createCreditTopupSession()`, `_creditBillingQuota()`, payment failed email wiring. |
| `server/email-service.ts` | **Modified** | Added `sendPaymentFailedEmail()` and `sendQuotaWarningEmail()`. |
| `server/routes.ts` | **Modified** | Added `POST /api/auth/start-trial`, `POST /internal/notify/quota`, `POST /api/payments/add-credits`. |
| `client/src/App.tsx` | **Modified** | Added `/billing` route. |
| `client/src/components/app-sidebar.tsx` | **Modified** | Added "Billing & Invoices" nav link. |

---

## How the Frontend Billing Page Works

1. User navigates to `/billing` (sidebar button or direct URL)
2. Page calls `GET /api/billing/usage` (proxied to port 8081) → reads Redis → returns in <5ms
3. Page calls `GET /api/billing/usage/history?months=6` → returns 6 months of data
4. Page renders three sections + quota bar + quota warning if ≥80%

**Header buttons:**
- **Add Credits** → Stripe one-time checkout → webhook → Redis quota increases
- **Payment method** / **Manage plan** → Stripe Customer Portal (update card, cancel plan, view invoices)

**Auto-charge:** When enabled, automatically purchases a credit pack when quota crosses the set threshold. Preference saved in `localStorage`. Guard in `sessionStorage` prevents double-charging.

---

## How the Registration Trial Flow Works

1. User fills account form → `POST /api/auth/register` → user created in Postgres (status: `trialing`)
2. Frontend shows Step 2: "Start your 7-day free trial"
3. User clicks "Add payment method" → `POST /api/auth/start-trial` → returns Stripe Checkout URL
4. Browser redirects to Stripe — card collected but **not charged** for 7 days
5. After 7 days, Stripe auto-charges; sends `customer.subscription.updated` webhook
6. User can also skip trial → goes straight to dashboard on free tier ($5/month quota)

**Dev mode:** If `STRIPE_SECRET_KEY` is not set, step 3 returns `{ devMode: true }` and the user goes directly to the dashboard. No Stripe interaction needed for local development.

---

## How Quota Emails Work

```
[any cost write] → _check_quota() in realtime_cost_service.py
       │
       ├── if usage ≥ 80% AND not sent this month:
       │       POST http://localhost:5000/internal/notify/quota
       │       { user_id, pct: 80.x, used_usd, quota_usd }
       │       → Node.js looks up user email from Postgres
       │       → emailService.sendQuotaWarningEmail()  [amber email]
       │
       └── if usage ≥ 100% AND not sent this month:
               POST http://localhost:5000/internal/notify/quota
               { user_id, pct: 100+, used_usd, quota_usd }
               → emailService.sendQuotaWarningEmail()  [red email, jobs paused]
```

---

## Required Environment Variables

### Node.js server (`.env`)

```bash
# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_ACADEMIC_MONTHLY=price_...
STRIPE_PRICE_ACADEMIC_YEARLY=price_...
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_...
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_...
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_...

# Billing service communication
BILLING_API_URL=http://localhost:8081
BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE

# Email (SMTP)
EMAIL_HOST=smtp.sendgrid.net
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=apikey
EMAIL_PASS=SG.xxx...
EMAIL_FROM=noreply@biomate.dev

APP_URL=https://app.biomate.dev
```

### Galaxy backend EC2

```bash
REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
NOTIFY_URL=http://localhost:5000
LAGO_API_KEY=<your_lago_api_key>
LAGO_API_URL=https://api.getlago.com/api/v1
LAGO_WEBHOOK_SECRET=<random_secret>
JWT_SECRET=<your_jwt_secret>
```

### AWS Lambdas (`batch_billing` + `s3_billing`)

```bash
BILLING_API_URL=http://172.31.8.116:8081   # Galaxy backend private IP
BILLING_API_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE   # same value as BILLING_INTERNAL_KEY
REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
```

> **Note:** The Lambda code uses `BILLING_API_KEY`; the billing router accepts both `BILLING_INTERNAL_KEY` and `BILLING_API_KEY`. Use the same value for both. The `REDIS_URL` is used by `batch_billing` to write the heartbeat timestamp (`billing:last_batch_event_ts`) for health monitoring.

---

## Infrastructure Still Needed

See **[TECHNICAL_REFERENCE.md Section 4](./TECHNICAL_REFERENCE.md#4-work-remaining-for-backend-programmer)** for the full checklist with details. Summary:

### AWS
- [ ] Deploy `batch_billing` Lambda (us-west-2, VPC, EventBridge rule)
- [ ] Deploy `s3_billing` Lambda (us-east-1, SQS trigger)
- [ ] Configure S3 → SQS event notifications on both S3 buckets
- [ ] Set env vars on Galaxy backend EC2 (`REDIS_URL`, `BILLING_INTERNAL_KEY`, `NOTIFY_URL`)

### Lago (Metered Billing)
- [ ] Deploy Lago (self-hosted or Lago Cloud)
- [ ] Create 9 billable metrics (exact codes in TECHNICAL_REFERENCE.md Section 1.5)
- [ ] Create subscription plans (`academic_monthly`, `professional_monthly`, `enterprise_monthly`)
- [ ] Configure Lago webhook → `https://api.biomate.dev/webhooks/lago`

### Stripe
- [ ] Create 5 products/prices in Stripe dashboard
- [ ] Set all `STRIPE_PRICE_*` env vars on Node.js server
- [ ] Register webhook endpoint with 6 event types
- [ ] Configure Stripe Customer Portal (update payment, cancel, view invoices)

### Email
- [ ] Configure SMTP provider (SendGrid, AWS SES, or Postmark)
- [ ] Set `EMAIL_*` env vars
- [ ] Verify sender domain

---

## Testing with Mock Data

No real jobs needed. Seed Redis directly:

```bash
# Set quota for user_id=1
redis-cli -u $REDIS_URL SET "quota:1:month:$(date +%Y-%m):limit" 30.0

# Seed mock usage
redis-cli -u $REDIS_URL HSET "cost:1:month:$(date +%Y-%m):llm" \
  input_usd 1.23 output_usd 0.45 input_tokens 85000 output_tokens 12000 calls 47

redis-cli -u $REDIS_URL HSET "cost:1:month:$(date +%Y-%m):compute" \
  vcpu_usd 2.10 gpu_usd 1.80 mem_usd 0.66 seconds 7200 jobs 5

redis-cli -u $REDIS_URL SET "cost:1:month:$(date +%Y-%m):total" 5.64

# Visit http://localhost:5000/billing as user_id=1
```

See TECHNICAL_REFERENCE.md Section 4.5 for the full 10-step curl test sequence including job completion and quota email verification.

---

## Known Gaps (deferred to next sprint)

| Item | Priority | Details |
|------|----------|---------|
| S3 delete cost reversal | High | `s3_delete` endpoint is stubbed; storage cost should be prorated and credited back |
| Lago event retry | High | Failed events are silently dropped; needs exponential backoff queue |
| Quota block in job submission | High | `is_over_hard_limit()` is implemented but not yet checked before Batch job submission |
| Lago customer creation at registration | Medium | Must call `lago_client.upsert_customer()` when user registers |
| Plan limits from database | Medium | Currently hardcoded in `quota_enforcer.py`; should come from Lago subscription |
| JWT_SECRET enforcement | High | Dev fallback accepts plaintext user_id; must enforce JWT in production |

---

## Running the Tests

```bash
cd backend
python -m pytest lib/galaxy/ai/billing/tests/ -v
# Expected: 62 passed
```

---

*For questions about this implementation, contact the team or review the commit history on the `billing_system` branch.*
