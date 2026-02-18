# BioMate Billing System — Technical Documentation
**Date:** 2026-02-18
**Author:** Claude Code (audit + implementation)
**Branch:** `connection_formal`
**Status:** Code complete. Infrastructure + Stripe configuration pending.

---

## Table of Contents

1. [Cost Monitor Modules](#1-cost-monitor-modules)
2. [User Registration Modules](#2-user-registration-modules)
3. [Billing & Invoice Page](#3-billing--invoice-page)
4. [Work Remaining for Backend Programmer](#4-work-remaining-for-backend-programmer)

---

## 1. Cost Monitor Modules

The cost monitoring system is entirely written in Python and lives under:

```
backend/lib/galaxy/ai/billing/
├── core/
│   ├── realtime_cost_service.py   # Redis-backed live cost ledger
│   ├── cost_calculator.py         # Pure AWS pricing calculations
│   ├── quota_enforcer.py          # Pre-job quota gate
│   └── lago_client.py             # Lago billing platform client
├── api/
│   └── billing_router.py          # FastAPI endpoints
└── lambda/
    ├── batch_billing.py           # AWS Batch state-change handler
    └── s3_billing.py              # S3 upload event handler
```

---

### 1.1 `realtime_cost_service.py` — Live Cost Ledger

**Purpose:** Maintains a real-time cost ledger per user in Redis so the frontend can display current spend in sub-millisecond time without hitting the database.

**Singleton:** `get_cost_service()` returns the process-wide instance.

#### Redis Key Schema

| Key | Type | Content |
|-----|------|---------|
| `cost:{uid}:month:{YYYY-MM}:llm` | HSET | `input_usd`, `output_usd`, `input_tokens`, `output_tokens`, `calls` |
| `cost:{uid}:month:{YYYY-MM}:compute` | HSET | `vcpu_usd`, `gpu_usd`, `mem_usd`, `seconds`, `jobs` |
| `cost:{uid}:month:{YYYY-MM}:storage` | HSET | `storage_usd`, `request_usd`, `transfer_usd`, `bytes_stored`, `puts`, `gets` |
| `cost:{uid}:month:{YYYY-MM}:total` | STRING | running total USD (float) |
| `cost:{uid}:job:{job_id}:running` | STRING (JSON) | `instance_type`, `vcpus`, `gpu_count`, `started_at_ms`, `est_usd`, `elapsed_seconds` |
| `quota:{uid}:month:{YYYY-MM}:limit` | STRING | plan cap in USD |
| `quota:{uid}:month:{YYYY-MM}:alert_sent` | STRING | `"1"` if 80% email already sent this month |
| `quota:{uid}:month:{YYYY-MM}:exceeded_sent` | STRING | `"1"` if 100% email already sent this month |

**All keys expire after 35 days** (covers current + previous billing month).

#### Write Methods (called by event handlers)

```python
record_llm_cost(user_id, input_usd, output_usd, input_tokens, output_tokens)
record_batch_job_cost(user_id, job_id, vcpu_usd, gpu_usd, mem_usd, duration_seconds)
record_s3_put(user_id, size_bytes, storage_usd, request_usd)
record_s3_get(user_id, size_bytes, request_usd, transfer_usd)
```

#### Running Job Tracking

```python
register_running_job(user_id, job_id, instance_type, vcpus, memory_mb, gpu_count, started_at_ms, is_spot)
```

A background daemon thread (`_poll_running_jobs`) wakes every 10 seconds and updates the `est_usd` field in Redis for all tracked running jobs. This feeds the "Running jobs" section in the dashboard.

#### Quota Enforcement

```python
is_over_hard_limit(user_id) -> bool   # True = block new job submissions
set_quota(user_id, quota_usd)         # Set plan cap (called at login/plan change)
add_to_quota(user_id, amount_usd)     # Add credits (called by Stripe webhook)
```

#### Quota Email Notifications (`_check_quota`)

Called after every cost write. Fires once per threshold per month:

- **80%**: sets `alert_sent` key, calls `_notify_quota()`
- **100%**: sets `exceeded_sent` key, calls `_notify_quota()`

`_notify_quota()` makes a synchronous HTTP POST to:
```
POST $NOTIFY_URL/internal/notify/quota
X-Internal-Key: $BILLING_INTERNAL_KEY
Body: { user_id, pct, used_usd, quota_usd }
```

`NOTIFY_URL` defaults to `http://localhost:5000` (the Node.js frontend). The frontend endpoint looks up the user's email from the database and sends the email via nodemailer.

---

### 1.2 `cost_calculator.py` — AWS Pricing

**Purpose:** Pure-function cost calculator. Takes job parameters, returns a cost breakdown object. No I/O, fully deterministic.

#### AWS Pricing Tables (us-east-1, on-demand, as of 2026-02)

**EC2 Instance Pricing ($/hr):**
| Family | Examples | Notes |
|--------|----------|-------|
| General purpose | m6i.xlarge $0.192, m6i.4xlarge $0.768 | Default for CPU jobs |
| Compute optimized | c6i.xlarge $0.17, c6i.4xlarge $0.68 | |
| GPU small | g4dn.xlarge $0.526, g4dn.12xlarge $3.912 | T4 GPU |
| GPU medium | g5.xlarge $1.006, g5.12xlarge $5.672 | A10G GPU |
| GPU large | p3.2xlarge $3.06, p4d.24xlarge $32.77 | V100/A100 |

**Cost Attribution Per Instance:**
- GPU jobs: 50% vCPU share + 30% memory share + 20% GPU share
- CPU jobs: 60% vCPU share + 40% memory share
- Spot discount: multiply by `0.35` (35% of on-demand price)
- Unknown instance type: fallback to Fargate pricing ($0.04048/vCPU-hr, $0.004445/GB-hr)

**S3 Pricing:**
| Item | Rate |
|------|------|
| STANDARD storage | $0.023 / GB / month |
| PUT requests | $0.005 per 1,000 |
| GET requests | $0.0004 per 1,000 |
| Data transfer out | $0.09 / GB |

**LLM Pricing (per 1M tokens):**
| Model | Input | Output |
|-------|-------|--------|
| Claude Opus | $15 | $75 |
| Claude Sonnet | $3 | $15 |
| Claude Haiku | $0.25 | $1.25 |
| GPT-4o | $5 | $15 |
| GPT-4o-mini | $0.15 | $0.60 |

#### Key Methods

```python
batch_job_cost(job_id, user_id, workflow_id, instance_type, vcpus, memory_mb,
               gpu_count, duration_seconds, is_spot) -> CostResult

estimate_running_job_cost(instance_type, vcpus, memory_mb, gpu_count,
                          started_at_ms, now_ms, is_spot) -> float

llm_cost(model, input_tokens, output_tokens) -> CostResult
s3_put_cost(user_id, bucket, size_bytes) -> CostResult
s3_get_cost(user_id, bucket, size_bytes, cross_region) -> CostResult
```

---

### 1.3 `quota_enforcer.py` — Pre-Job Gate

**Purpose:** Checked **before** submitting a job to AWS Batch. Raises `QuotaExceededError` if the user is at or over their limit.

#### Plan Quotas (currently hardcoded)

| Plan | Monthly Cap |
|------|-------------|
| `free` | $5.00 |
| `basic` | $50.00 |
| `pro` | $500.00 |
| `enterprise` | unlimited |

#### Key Functions

```python
ensure_quota_set(user_id: str, plan: str) -> None
    # Called at login and on plan change. Writes quota cap to Redis.
    # Also called by Lago webhook (subscription.started/terminated).

check_and_reserve(user_id, workflow_id, instance_type, vcpus, memory_mb,
                  gpu_count, expected_duration_minutes, is_spot) -> float
    # Returns estimated cost in USD if quota allows.
    # Raises QuotaExceededError if over limit.
    # Raises QuotaSoftWarning at 80%.
```

---

### 1.4 `billing_router.py` — FastAPI Endpoints

**Mounted on:** Galaxy backend (port 8081)

#### Public Endpoints (require `Authorization: Bearer <JWT>`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/billing/usage` | Current month cost breakdown (reads Redis, <5ms) |
| GET | `/api/billing/usage/history?months=N` | Past N months (1-24), default 3 |
| GET | `/api/billing/quota` | Plan limit, used amount, quota % |
| GET | `/api/billing/jobs/running` | In-flight jobs with live cost estimates |

**Sample `/api/billing/usage` Response:**
```json
{
  "user_id": "42",
  "month": "2026-02",
  "currency": "USD",
  "breakdown": {
    "llm": { "total_usd": 1.23, "input_usd": 0.80, "output_usd": 0.43,
             "input_tokens": 85000, "output_tokens": 12000, "calls": 47 },
    "compute": { "total_usd": 4.56, "vcpu_usd": 2.10, "gpu_usd": 1.80,
                 "memory_usd": 0.66, "total_seconds": 7200, "jobs": 5 },
    "storage": { "total_usd": 0.18, "storage_usd": 0.11, "request_usd": 0.04,
                 "transfer_usd": 0.03, "puts": 120, "gets": 800 }
  },
  "running_jobs": [
    { "job_id": "abc-123", "instance_type": "g4dn.xlarge",
      "elapsed_seconds": 1820, "estimated_usd": 0.267 }
  ],
  "running_estimate_usd": 0.267,
  "committed_usd": 5.97,
  "total_usd": 6.24,
  "quota_usd": 30.00,
  "quota_pct": 20.8
}
```

#### Internal Endpoints (require `X-Internal-Key: $BILLING_INTERNAL_KEY`)

| Method | Path | Called by | Description |
|--------|------|-----------|-------------|
| POST | `/internal/billing/job_started` | Batch Lambda | Register running job in Redis |
| POST | `/internal/billing/job_completed` | Batch Lambda | Calculate + record final cost, emit to Lago |
| POST | `/internal/billing/s3_put` | S3 Lambda | Record S3 upload cost |
| POST | `/internal/billing/s3_delete` | S3 Lambda | Log deletion (cost reversal TODO) |
| POST | `/internal/billing/add-credits` | Stripe webhook (via Node.js) | Add purchased credits to Redis quota |

**`/internal/billing/add-credits` Request:**
```json
{ "user_id": "42", "amount_usd": 25.00, "payment_id": "cs_live_..." }
```

#### Lago Webhook

```
POST /webhooks/lago
X-Lago-Signature: <HMAC-SHA256>
```

Events handled: `subscription.started`, `subscription.terminated`, `subscription.updated`, `invoice.created`

On subscription events: calls `ensure_quota_set(user_id, plan_code)` to update Redis quota cap.

---

### 1.5 `lago_client.py` — Lago Billing Platform Client

**Purpose:** Emits usage events to Lago for invoice generation. Fire-and-forget (errors are logged, not re-raised).

#### Lago Event Codes (must exist in Lago UI before use)

| Code | Unit | Emitted by |
|------|------|------------|
| `llm_input_tokens` | tokens | `emit_llm()` |
| `llm_output_tokens` | tokens | `emit_llm()` |
| `batch_vcpu_seconds` | vCPU-seconds | `emit_batch_job()` |
| `batch_gpu_seconds` | GPU-seconds | `emit_batch_job()` (if gpu_count > 0) |
| `batch_memory_gb_sec` | GB-seconds | `emit_batch_job()` |
| `s3_storage_gb_hours` | GB-hours | `emit_s3_put()` (assumes 30-day retention) |
| `s3_put_requests` | requests | `emit_s3_put()` |
| `s3_get_requests` | requests | `emit_s3_get()` |
| `s3_data_transfer_gb` | GB | `emit_s3_get()` (cross-region only) |

**Required env vars:** `LAGO_API_KEY`, `LAGO_API_URL` (default `https://api.getlago.com/api/v1`)

---

### 1.6 Lambda Handlers

#### `lambda/batch_billing.py`
Triggered by EventBridge rule `biomate-batch-job-state-change` on AWS Batch job state changes.

- `RUNNING` → POST to `/internal/billing/job_started`
- `SUCCEEDED` or `FAILED` → POST to `/internal/billing/job_completed`

Required env vars: `BILLING_API_URL`, `BILLING_INTERNAL_KEY`, `REDIS_URL`

#### `lambda/s3_billing.py`
Triggered by SQS queue `biomate-s3-billing-events` which receives S3 event notifications.

- `ObjectCreated:*` → POST to `/internal/billing/s3_put`
- `ObjectRemoved:*` → POST to `/internal/billing/s3_delete`

Required env vars: same as batch_billing.

---

## 2. User Registration Modules

### 2.1 Two-Step Registration Flow

Registration is handled in two steps:

**Step 1: Account Creation**
- File: `frontend/client/src/pages/auth/register.tsx`
- Route: `POST /api/auth/register` (Node.js, `routes.ts`)
- No Stripe interaction here — only creates the user in the Postgres database

**Step 2: Trial Setup (Stripe)**
- File: same `register.tsx`, second screen
- Route: `POST /api/auth/start-trial` (Node.js, `routes.ts`)
- Creates a Stripe Checkout Session (subscription mode, 7-day trial)
- Redirects browser to Stripe-hosted checkout page
- User enters card; Stripe stores it but does **not** charge until trial ends

#### Step 1 — Account Creation Details

`POST /api/auth/register`
```json
Request:  { "fullName": "...", "email": "...", "password": "...", "termsAccepted": true }
Response: { "success": true, "user": {...}, "token": "<JWT>", "expiresIn": 604800 }
```

After success, the register page:
1. Stores `auth_token` and `user` in `localStorage`
2. Moves to Step 2 UI (does NOT navigate to `/dashboard` yet)

#### Step 2 — Start Trial Details

`POST /api/auth/start-trial` (requires `Authorization: Bearer <token>`)
```json
Request:  { "returnUrl": "https://app.biomate.dev/dashboard" }
Response: { "success": true, "sessionId": "cs_live_...", "url": "https://checkout.stripe.com/..." }
```

Behavior:
- If `STRIPE_SECRET_KEY` is not set (dev mode): returns `{ devMode: true, url: null }` → frontend goes directly to `/dashboard`
- If `STRIPE_PRICE_ACADEMIC_MONTHLY` is not set: returns 400 error
- Otherwise: creates Stripe Checkout session, returns URL, frontend does `window.location.href = url`

Stripe Checkout settings:
```
mode: 'subscription'
trial_period_days: 7
payment_method_collection: 'always'   ← card collected but not charged
```

After Stripe checkout completes, Stripe fires `customer.subscription.created` webhook which is handled by `stripe-service.ts → handleSubscriptionUpdate()`.

#### User can also skip

The Step 2 UI offers "Skip for now — explore the free tier" which goes straight to `/dashboard`. The user can start the trial later from the Billing page.

---

### 2.2 Auth Service (`frontend/server/auth-service.ts`)

The `register()` function creates a user with:
```
subscriptionStatus: 'trialing'
subscriptionTier:   'free'
trialEndsAt:        now + 7 days
trialUsed:          false
```

After Stripe processes the trial checkout, `handleSubscriptionUpdate()` updates:
```
subscriptionStatus: 'trialing' (then 'active' when trial converts)
subscriptionId:     <stripe_subscription_id>
stripeCustomerId:   <stripe_customer_id>
currentPeriodEnd:   <timestamp>
trialUsed:          true
```

---

### 2.3 Post-Registration Email

`sendWelcomeEmail(email, userName)` is sent after email verification (already implemented in `auth-service.ts`). The email mentions the 7-day trial and links to the dashboard.

---

### 2.4 Quota Initialization at Login

When a user logs in (`POST /api/auth/login`), the backend calls `register_user()` in the Python billing system which calls `_sync_quota_to_billing()`. This writes the user's plan quota into Redis using `ensure_quota_set(user_id, plan)` so quota checks work immediately.

---

## 3. Billing & Invoice Page

### 3.1 Location

`frontend/client/src/pages/billing.tsx`

Route: `/billing` (in `App.tsx`, wrapped in `AuthenticatedPageLayout`)

Sidebar navigation: "Billing & Invoices" button in `app-sidebar.tsx` (uses `setLocation('/billing')`)

---

### 3.2 Page Layout

The page has three main sections plus a warning banner:

```
┌─────────────────────────────────────────────────┐
│  Billing & Invoices           [Add Credits] [Payment method] [Manage plan]  │
├─────────────────────────────────────────────────┤
│  [QuotaWarningBanner — shown only when ≥80%]    │
├─────────────────────────────────────────────────┤
│  Section 1: Included Usage                      │
│  Table: AI Workflows | tokens used | %          │
│         ↳ Input tokens                          │
│         ↳ Output tokens                         │
│         Compute (vCPU hrs) | hours | %          │
│         Storage | GB | %                        │
│  Quota progress bar                             │
├─────────────────────────────────────────────────┤
│  Section 2: On-Demand Usage (current cycle)     │
│  Total: $X.XX  [Refresh icon]                   │
│  Table: Input tokens  | tokens | $X.XX          │
│         Output tokens | tokens | $X.XX          │
│         vCPU hours    | hrs    | $X.XX          │
│         GPU hours     | hrs    | $X.XX          │
│         Storage       | GB     | $X.XX          │
│  [Running jobs notice if any]                   │
├─────────────────────────────────────────────────┤
│  Section 3: Invoices                            │
│  [Month filter dropdown]                        │
│  Table: Date | Description | Status | Amount | View │
│  View → opens Stripe Customer Portal            │
└─────────────────────────────────────────────────┘
```

---

### 3.3 Data Sources

| Data | Source | Endpoint |
|------|--------|----------|
| Current month usage | Python billing API → Redis | `GET /api/billing/usage` |
| Usage history (6 months) | Python billing API → Redis | `GET /api/billing/usage/history?months=6` |
| Subscription info | Node.js → Postgres | `GET /api/payments/subscription` |
| Portal redirect | Node.js → Stripe API | `POST /api/payments/create-portal-session` |
| Add credits | Node.js → Stripe API | `POST /api/payments/add-credits` |

The `/api/billing/*` routes are proxied from Node.js (port 5000) to Galaxy backend (port 8081).

---

### 3.4 Header Action Buttons

| Button | Action |
|--------|--------|
| **Add Credits** | Opens `AddCreditsDialog` |
| **Payment method** | `POST /api/payments/create-portal-session` → redirects to Stripe portal |
| **Manage plan** | Same as Payment method — Stripe portal handles plan changes too |

---

### 3.5 `AddCreditsDialog` Component

Three preset credit packs:

| Pack | Amount | Description |
|------|--------|-------------|
| $10 | 1000 cents | ~500K tokens or 2 hrs CPU |
| $25 | 2500 cents | ~1.3M tokens or 5 hrs CPU (Popular) |
| $50 | 5000 cents | ~2.6M tokens or 1 hr GPU |

Flow:
1. User selects pack and clicks "Pay $N"
2. Frontend calls `POST /api/payments/add-credits` with `{ amountCents, returnUrl }`
3. Node.js calls `stripeService.createCreditTopupSession()` → returns Stripe Checkout URL
4. Browser redirects to Stripe
5. After payment, Stripe fires `checkout.session.completed` webhook
6. Node.js stripe webhook handler calls `POST /internal/billing/add-credits` on Galaxy backend
7. Galaxy backend calls `svc.add_to_quota(user_id, amount_usd)` → writes new limit to Redis
8. Stripe redirects back to `/billing?topup=success&amount=2500`

---

### 3.6 `QuotaWarningBanner` Component

Shown when `quota_pct >= 80`. Color: amber at 80–99%, red at 100%.

Contains:
- Usage summary text
- **Add Credits** button → opens `AddCreditsDialog`
- **Upgrade Plan** button → opens Stripe portal
- **Auto-charge toggle**: when enabled, automatically purchases selected pack when threshold is hit
  - Preference stored in `localStorage` key `biomate_auto_charge`
  - Guard via `sessionStorage` prevents repeat charges in the same browser session within a month

---

### 3.7 Email Notifications

Two billing-related email templates in `frontend/server/email-service.ts`:

#### `sendPaymentFailedEmail(email, userName, amountDue, nextAttemptDate, updateUrl)`
- Triggered by: `invoice.payment_failed` Stripe webhook → `handlePaymentFailed()` in `stripe-service.ts`
- Subject: "Action Required: BioMate Payment Failed"
- Content: amount due, next retry date, "Update Payment Method" button

#### `sendQuotaWarningEmail(email, userName, pct, usedUsd, quotaUsd, addCreditsUrl)`
- Triggered by: Python `_notify_quota()` → `POST /internal/notify/quota` → Node.js route
- Subject: dynamic — `"BioMate: you've used 80% of your monthly quota"` or `"Your BioMate quota is exhausted — jobs paused"`
- Content: visual usage meter bar, "Add Credits Now" button

Both use the nodemailer `EmailService`. SMTP must be configured (see Section 4).

---

### 3.8 Mock Data Testing

To test the billing page with mock data, set `REDIS_URL` to point to the dev Redis instance and seed it:

```bash
# Seed mock usage data for user_id=1
redis-cli -u $REDIS_URL HSET "cost:1:month:2026-02:llm" \
  input_usd 1.23 output_usd 0.45 input_tokens 85000 output_tokens 12000 calls 47

redis-cli -u $REDIS_URL HSET "cost:1:month:2026-02:compute" \
  vcpu_usd 2.10 gpu_usd 1.80 mem_usd 0.66 seconds 7200 jobs 5

redis-cli -u $REDIS_URL HSET "cost:1:month:2026-02:storage" \
  storage_usd 0.11 request_usd 0.04 transfer_usd 0.03 bytes_stored 500000000 puts 120 gets 800

redis-cli -u $REDIS_URL SET "cost:1:month:2026-02:total" 6.39

# Set quota (e.g., $30/month)
redis-cli -u $REDIS_URL SET "quota:1:month:2026-02:limit" 30.0

# Simulate a running job
redis-cli -u $REDIS_URL SET "cost:1:job:test-job-001:running" \
  '{"user_id":"1","instance_type":"g4dn.xlarge","vcpus":4,"memory_mb":16384,"gpu_count":1,"started_at_ms":1708200000000,"is_spot":false,"est_usd":0.526,"elapsed_seconds":3600}'
```

The billing page will then display populated data with a running job.

---

## 4. Work Remaining for Backend Programmer

This section lists everything that must be done before the billing system is production-ready. Grouped by area.

---

### 4.1 Infrastructure

#### AWS Batch
- [ ] **EventBridge rule deployed:** Rule `biomate-batch-job-state-change` must target the `batch-billing` Lambda. Rule pattern:
  ```json
  { "source": ["aws.batch"],
    "detail-type": ["Batch Job State Change"],
    "detail": { "status": ["RUNNING", "SUCCEEDED", "FAILED"] } }
  ```
- [ ] **Lambda deployed:** `batch-billing` Lambda in `us-west-2`, in VPC with access to Redis SG `sg-096a3c0fcd3e4504c`. IAM role: `biomate-lambda-billing-role`.
- [ ] **Lambda env vars set:**
  ```
  BILLING_API_URL=http://172.31.8.116:8081   (Galaxy backend private IP)
  BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
  REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
  ```

#### S3 Event Pipeline
- [ ] **S3 → SQS notifications configured** on both buckets:
  - `biomate-nextflow-work` (us-east-1)
  - `biomate-production-data-399683337364` (us-east-1)
  - Target SQS: `arn:aws:sqs:us-east-1:399683337364:biomate-s3-billing-events`
  - Events: `s3:ObjectCreated:*`, `s3:ObjectRemoved:*`
- [ ] **`s3-billing` Lambda deployed:** in `us-east-1` (matches bucket region), no VPC needed
- [ ] **Lambda env vars set** (same three as batch-billing)
- [ ] **SQS trigger configured** on Lambda from the SQS queue above

#### Galaxy Backend EC2
- [ ] **Set `REDIS_URL`** in the Galaxy EC2 systemd environment or `.env`:
  ```
  REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
  ```
- [ ] **Set `BILLING_INTERNAL_KEY`**:
  ```
  BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
  ```
- [ ] **Set `NOTIFY_URL`** (so Python can call Node.js for quota emails):
  ```
  NOTIFY_URL=http://localhost:5000
  ```
  (or the actual public URL if Galaxy backend is not co-located with Node.js)
- [ ] **Restart Galaxy backend** after setting env vars

#### Node.js Frontend EC2 (same instance or separate)
- [ ] **Set `BILLING_INTERNAL_KEY`** (same value as Python side, used to authenticate `/internal/notify/quota` calls)
- [ ] **Set `BILLING_API_URL`**:
  ```
  BILLING_API_URL=http://localhost:8081
  ```
  (or private IP if on separate instance)

---

### 4.2 Monitoring Software (Lago) Configuration

Lago is the metered billing/invoicing platform. It must be configured before usage events can be tracked.

#### Initial Setup
- [ ] **Deploy Lago** (self-hosted Docker or use Lago Cloud at `https://app.getlago.com`)
- [ ] **Create organization** and obtain API key
- [ ] **Set env vars** on Galaxy backend:
  ```
  LAGO_API_KEY=<your_lago_api_key>
  LAGO_API_URL=https://api.getlago.com/api/v1   (or self-hosted URL)
  LAGO_WEBHOOK_SECRET=<random_secret>
  ```

#### Billable Metric Setup (in Lago UI)

Create each metric under **Billable Metrics → New Metric**:

| Code | Name | Aggregation | Field |
|------|------|-------------|-------|
| `llm_input_tokens` | LLM Input Tokens | SUM | `value` |
| `llm_output_tokens` | LLM Output Tokens | SUM | `value` |
| `batch_vcpu_seconds` | Batch vCPU-Seconds | SUM | `value` |
| `batch_gpu_seconds` | Batch GPU-Seconds | SUM | `value` |
| `batch_memory_gb_sec` | Batch Memory GB-Sec | SUM | `value` |
| `s3_storage_gb_hours` | S3 Storage GB-Hours | SUM | `value` |
| `s3_put_requests` | S3 PUT Requests | SUM | `value` |
| `s3_get_requests` | S3 GET Requests | SUM | `value` |
| `s3_data_transfer_gb` | S3 Data Transfer GB | SUM | `value` |

#### Plan Setup (in Lago UI)

Create one plan per subscription tier. Example for Academic plan:

| Plan Code | Name | Interval | Charges |
|-----------|------|----------|---------|
| `academic_monthly` | Academic | monthly | $29/mo flat + per-metric overages |
| `professional_monthly` | Professional | monthly | $99/mo flat + per-metric overages |
| `enterprise_monthly` | Enterprise | monthly | custom |

For each plan, add charges for each billable metric (or bundle into a flat fee for simplicity in v1).

#### Webhook Setup (in Lago UI)
- [ ] Create webhook endpoint pointing to: `https://api.biomate.dev/webhooks/lago` (or your backend URL)
- [ ] Copy the signing secret into `LAGO_WEBHOOK_SECRET` env var
- [ ] Subscribe to events: `subscription.started`, `subscription.terminated`, `subscription.updated`, `invoice.created`

---

### 4.3 Stripe Configuration

Stripe handles subscription billing and payment method collection.

#### Keys
- [ ] **Set on Node.js server:**
  ```
  STRIPE_SECRET_KEY=sk_live_...
  STRIPE_WEBHOOK_SECRET=whsec_...
  ```

#### Product & Price IDs

Create these in the Stripe Dashboard under **Products**:

| Product | Price | Env Var |
|---------|-------|---------|
| Academic Plan (monthly) | $29/mo | `STRIPE_PRICE_ACADEMIC_MONTHLY` |
| Academic Plan (yearly) | $290/yr | `STRIPE_PRICE_ACADEMIC_YEARLY` |
| Professional Plan (monthly) | $99/mo | `STRIPE_PRICE_PROFESSIONAL_MONTHLY` |
| Professional Plan (yearly) | $990/yr | `STRIPE_PRICE_PROFESSIONAL_YEARLY` |
| Enterprise Plan (monthly) | custom | `STRIPE_PRICE_ENTERPRISE_MONTHLY` |

**Most critical for launch:** `STRIPE_PRICE_ACADEMIC_MONTHLY` — this is what the trial registration flow uses.

- [ ] **Create products and prices in Stripe dashboard**
- [ ] **Set price ID env vars** on the Node.js server (`.env` file)

#### Webhook Setup

- [ ] Go to Stripe Dashboard → **Developers → Webhooks → Add endpoint**
- [ ] URL: `https://app.biomate.dev/api/payments/webhook` (Node.js handles this)
- [ ] Events to subscribe:
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`
  - `checkout.session.completed`
- [ ] Copy the **Signing secret** (`whsec_...`) into `STRIPE_WEBHOOK_SECRET` env var

#### Customer Portal Setup
- [ ] Go to Stripe Dashboard → **Settings → Billing → Customer portal**
- [ ] Enable: Update payment method, Cancel subscription, View invoices, Download invoices
- [ ] Set **Return URL**: `https://app.biomate.dev/billing`

---

### 4.4 Email (SMTP) Configuration

Required for payment failure and quota warning emails.

- [ ] **Set on Node.js server:**
  ```
  SMTP_HOST=smtp.sendgrid.net     (or SES, Postmark, etc.)
  SMTP_PORT=587
  SMTP_SECURE=false
  SMTP_USER=apikey
  SMTP_PASS=SG.xxx...             (SendGrid API key)
  SMTP_FROM=noreply@biomate.dev
  APP_URL=https://app.biomate.dev
  ```

If using AWS SES:
- [ ] Verify domain `biomate.dev` in SES
- [ ] Request production access (exit sandbox) via AWS support ticket
- [ ] Create SMTP credentials under SES → SMTP Settings
- [ ] Set `SMTP_HOST=email-smtp.us-east-1.amazonaws.com`

---

### 4.5 End-to-End Mock Test Checklist

Once all env vars are set, the backend programmer can run this sequence to verify the full flow:

```bash
# 1. Verify Redis is reachable from Galaxy backend
redis-cli -u $REDIS_URL PING   # → PONG

# 2. Seed quota for test user (user_id=1)
redis-cli -u $REDIS_URL SET "quota:1:month:2026-02:limit" 30.0

# 3. POST to billing job_started
curl -X POST http://localhost:8081/internal/billing/job_started \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"1","job_id":"mock-001","workflow_id":"wf-001",
       "instance_type":"g4dn.xlarge","vcpus":4,"memory_mb":16384,
       "gpu_count":1,"started_at_ms":1708200000000,"is_spot":false}'

# 4. Check running job appears in usage API
curl http://localhost:8081/api/billing/jobs/running \
  -H "Authorization: Bearer <test_jwt>"   # → should show mock-001

# 5. Complete the job
curl -X POST http://localhost:8081/internal/billing/job_completed \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"1","job_id":"mock-001","workflow_id":"wf-001","status":"SUCCEEDED",
       "instance_type":"g4dn.xlarge","vcpus":4,"memory_mb":16384,
       "gpu_count":1,"duration_seconds":3600,"is_spot":false}'

# 6. Verify cost recorded
curl http://localhost:8081/api/billing/usage \
  -H "Authorization: Bearer <test_jwt>"   # → should show GPU cost ~$0.527

# 7. Trigger quota warning (seed high usage)
redis-cli -u $REDIS_URL SET "cost:1:month:2026-02:total" 25.0   # 83% of $30 quota

# 8. Record a tiny LLM cost to trigger _check_quota
curl -X POST http://localhost:8081/internal/billing/job_completed \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"1","job_id":"mock-002","workflow_id":"wf-001","status":"SUCCEEDED",
       "instance_type":"m6i.xlarge","vcpus":4,"memory_mb":16384,
       "gpu_count":0,"duration_seconds":60,"is_spot":false}'
# → Should trigger quota 80% notification email if SMTP is configured

# 9. Test add-credits
curl -X POST http://localhost:8081/internal/billing/add-credits \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"1","amount_usd":25.0,"payment_id":"test-payment-001"}'
# → Response: {"ok":true,"new_quota_usd":55.0}

# 10. Visit billing page in browser (dev mode, no Stripe required)
# http://localhost:5000/billing  (logged in as test user)
# Should show usage data, quota bar, and all three sections
```

---

### 4.6 Known Limitations / Future Work

| Item | Priority | Notes |
|------|----------|-------|
| S3 delete cost reversal | High | `s3_delete` endpoint is stubbed — should subtract unused storage cost |
| Lago event retry logic | High | Currently fire-and-forget; failed events are lost |
| Spot price accuracy | Medium | Hardcoded at 35% of on-demand; should use Spot price history API |
| Plan limits in database | Medium | Currently hardcoded in `quota_enforcer.py`; should come from user's Lago subscription |
| S3 retention period | Medium | Lago emission hardcodes 30 days; should be configurable |
| JWT required in prod | High | Must set `JWT_SECRET` — dev fallback accepts raw user_id strings (security risk) |
| Quota block enforcement | High | `is_over_hard_limit()` is implemented but not yet wired into job submission path |
| Lago customer creation | Medium | `upsert_customer()` must be called when user registers; currently only on Lago webhook events |

---

*Document end. Questions: contact the engineering team.*
