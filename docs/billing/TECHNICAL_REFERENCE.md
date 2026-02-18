# BioMate Billing System — Technical Reference

**Branch:** `billing_system`
**Audience:** Backend programmer deploying and operating the billing infrastructure
**See also:** [`README.md`](./README.md) (overview), [`MONITORING.md`](./MONITORING.md) (real-time monitoring setup)

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [API Endpoints — Full Reference](#2-api-endpoints--full-reference)
3. [Redis Key Schema](#3-redis-key-schema)
4. [Lago Billable Metrics](#4-lago-billable-metrics)
5. [Cost Pricing Tables](#5-cost-pricing-tables)
6. [Infrastructure Setup Checklist](#6-infrastructure-setup-checklist)
7. [End-to-End Mock Test Checklist](#7-end-to-end-mock-test-checklist)
8. [Environment Variables Reference](#8-environment-variables-reference)

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  User runs a workflow                                               │
│                                                                     │
│  ┌──────────────────┐   ┌──────────────────┐   ┌───────────────┐  │
│  │  LLM API calls   │   │  AWS Batch jobs  │   │  S3 uploads   │  │
│  │  (llm_client.py) │   │  (batch_billing  │   │  (s3_billing  │  │
│  │  tracks tokens   │   │   Lambda)        │   │   Lambda)     │  │
│  └────────┬─────────┘   └────────┬─────────┘   └──────┬────────┘  │
│           │                      │                     │           │
│           └──────────────────────┼─────────────────────┘          │
│                                  │                                  │
│                                  ▼                                  │
│              ┌────────────────────────────────┐                    │
│              │  billing_router.py (port 8081) │                    │
│              │  FastAPI — 11 endpoints        │                    │
│              └──────────┬─────────────────────┘                    │
│                         │                                           │
│           ┌─────────────┼──────────────┐                          │
│           ▼             ▼              ▼                           │
│    ┌─────────────┐ ┌─────────┐ ┌───────────────┐                 │
│    │cost_calcula-│ │  Redis  │ │  lago_client  │                  │
│    │tor.py       │ │ (live   │ │  (metered     │                  │
│    │(AWS pricing │ │  ledger)│ │   invoicing)  │                  │
│    │ tables)     │ └────┬────┘ └───────┬───────┘                 │
│    └─────────────┘      │              │                           │
│                          │              ▼                           │
│                          │        ┌──────────┐                     │
│                          │        │  Lago    │                     │
│                          │        │(invoices)│                     │
│                          │        └──────────┘                     │
│                          ▼                                          │
│                  ┌──────────────────┐                              │
│                  │ Node.js port 5000│                              │
│                  │ /internal/notify │                              │
│                  │ /quota           │                              │
│                  │ → quota emails   │                              │
│                  └──────────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Map

| Component | File | Language | Runs on |
|-----------|------|----------|---------|
| Billing API | `billing/api/billing_router.py` | Python/FastAPI | Galaxy EC2 (port 8081) |
| Cost Calculator | `billing/core/cost_calculator.py` | Python | In-process |
| Realtime Ledger | `billing/core/realtime_cost_service.py` | Python | In-process → Redis |
| Quota Enforcer | `billing/core/quota_enforcer.py` | Python | In-process |
| Lago Client | `billing/core/lago_client.py` | Python | In-process → Lago API |
| Batch Lambda | `billing/lambda/batch_event_handler.py` | Python | Lambda (us-west-2) |
| S3 Lambda | `billing/lambda/s3_billing.py` | Python | Lambda (us-east-1) |
| Billing Page | `frontend/client/src/pages/billing.tsx` | TypeScript/React | Browser |
| Registration | `frontend/client/src/pages/auth/register.tsx` | TypeScript/React | Browser |
| Email Service | `frontend/server/email-service.ts` | TypeScript/Node | Node.js (port 5000) |
| Stripe Service | `frontend/server/stripe-service.ts` | TypeScript/Node | Node.js (port 5000) |

---

## 2. API Endpoints — Full Reference

All endpoints on Galaxy backend (port 8081). The Node.js frontend proxies `/api/billing/*` to `http://localhost:8081`.

### 2.1 Public Endpoints (JWT Bearer auth)

All public endpoints require: `Authorization: Bearer <jwt_token>`

---

#### `GET /api/billing/usage`

Returns real-time cost breakdown for the current month. Reads from Redis → <5ms response.

**Query params:** `?month=2026-02` (optional, defaults to current month)

**Response:**
```json
{
  "user_id": "42",
  "month": "2026-02",
  "currency": "USD",
  "breakdown": {
    "llm": {
      "total_usd": 1.68,
      "input_usd": 1.23,
      "output_usd": 0.45,
      "input_tokens": 85000,
      "output_tokens": 12000,
      "calls": 47
    },
    "compute": {
      "total_usd": 4.56,
      "vcpu_usd": 2.10,
      "gpu_usd": 1.80,
      "memory_usd": 0.66,
      "total_seconds": 7200.0,
      "jobs": 5
    },
    "storage": {
      "total_usd": 0.23,
      "storage_usd": 0.15,
      "request_usd": 0.08,
      "transfer_usd": 0.00,
      "puts": 2,
      "gets": 14
    }
  },
  "running_jobs": [],
  "running_estimate_usd": 0.12,
  "committed_usd": 6.47,
  "total_usd": 6.59,
  "quota_usd": 30.0,
  "quota_pct": 21.97
}
```

---

#### `GET /api/billing/usage/history`

Returns usage totals for past N months.

**Query params:** `?months=6` (1–24, default 3)

**Response:**
```json
{
  "user_id": "42",
  "history": [
    { "month": "2026-02", "total_usd": 6.59, "llm_usd": 1.68, "compute_usd": 4.56, "storage_usd": 0.23 },
    { "month": "2026-01", "total_usd": 12.30, ... }
  ]
}
```

---

#### `GET /api/billing/quota`

Returns plan limits and current quota percentage.

**Response:**
```json
{
  "user_id": "42",
  "quota_usd": 30.0,
  "used_usd": 6.59,
  "quota_pct": 21.97,
  "over_quota": false
}
```

---

#### `GET /api/billing/jobs/running`

Returns in-flight Batch jobs with live cost estimates.

**Response:**
```json
{
  "user_id": "42",
  "running_jobs": [
    {
      "job_id": "abc123",
      "instance_type": "m6i.2xlarge",
      "elapsed_seconds": 1234,
      "estimated_usd": 0.12
    }
  ],
  "running_total_usd": 0.12
}
```

---

### 2.2 Internal Endpoints (X-Internal-Key auth)

All internal endpoints require: `X-Internal-Key: <BILLING_INTERNAL_KEY>`

These are **never exposed** to the public internet. Called by Lambda functions and Stripe webhooks only.

---

#### `POST /internal/billing/job_started`

Called by `batch_billing` Lambda when a Batch job transitions to RUNNING.

**Request body:**
```json
{
  "user_id": "42",
  "job_id": "abc123",
  "workflow_id": "wf-456",
  "instance_type": "m6i.2xlarge",
  "vcpus": 8,
  "memory_mb": 16384,
  "gpu_count": 0,
  "started_at_ms": 1708900000000,
  "is_spot": false
}
```

**Response:** `{"ok": true}`

**Effect:** Writes `cost:<user_id>:job:<job_id>:running` JSON string to Redis with start time and resource config (TTL 35 days). Used by `GET /api/billing/jobs/running` to estimate live cost.

---

#### `POST /internal/billing/job_completed`

Called by `batch_billing` Lambda when a job reaches SUCCEEDED or FAILED.

**Request body:**
```json
{
  "user_id": "42",
  "job_id": "abc123",
  "workflow_id": "wf-456",
  "status": "SUCCEEDED",
  "instance_type": "m6i.2xlarge",
  "vcpus": 8,
  "memory_mb": 16384,
  "gpu_count": 0,
  "duration_seconds": 3600.0,
  "is_spot": false
}
```

**Response:** `{"ok": true, "total_cost_usd": 0.384}`

**Effect:**
1. Calculates final compute cost using `CostCalculator.batch_job_cost()`
2. Writes to `cost:<user_id>:month:<YYYY-MM>:compute` hash in Redis
3. Updates `cost:<user_id>:month:<YYYY-MM>:total` in Redis
4. Deletes the running-job estimate key (`cost:<uid>:job:<job_id>:running`)
5. Emits `batch_vcpu_seconds`, `batch_memory_gb_sec`, `batch_gpu_seconds` events to Lago
6. Checks quota — triggers 80%/100% warning email if threshold crossed

---

#### `POST /internal/billing/s3_put`

Called by `s3_billing` Lambda on S3 object creation.

**Request body:**
```json
{
  "user_id": "42",
  "workflow_id": "wf-456",
  "bucket": "biomate-production-data-399683337364",
  "key": "results/wf-456/output.bam",
  "size_bytes": 1073741824
}
```

**Response:** `{"ok": true, "total_cost_usd": 0.023}`

**Effect:** Writes to `cost:<user_id>:month:<YYYY-MM>:storage` in Redis. Emits `s3_put_requests` and `s3_storage_gb_hours` events to Lago.

---

#### `POST /internal/billing/s3_delete`

Called by `s3_billing` Lambda on S3 object deletion. **Currently stubbed** — storage cost reversal not yet implemented (known gap, deferred to next sprint).

---

#### `POST /internal/billing/add-credits`

Called by Stripe webhook (`checkout.session.completed`) when user purchases a credit pack.

**Request body:**
```json
{
  "user_id": "42",
  "amount_usd": 25.00,
  "payment_id": "cs_live_..."
}
```

(`payment_id` is the Stripe PaymentIntent or CheckoutSession ID — used for audit logging only, can be empty string.)

**Response:** `{"ok": true, "new_quota_usd": 55.0}`

**Effect:** Increments `quota:<user_id>:month:<YYYY-MM>:limit` in Redis by `amount_usd`.

---

### 2.3 Admin Endpoints (X-Internal-Key auth)

---

#### `GET /internal/billing/admin/users`

Returns live cost data for **all** users this month, sorted by spend. Used by monitoring dashboards.

**Example:**
```bash
curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
     http://localhost:8081/internal/billing/admin/users
```

**Response:**
```json
{
  "month": "2026-02",
  "user_count": 12,
  "users": [
    {
      "user_id": "7",
      "total_usd": 45.23,
      "quota_usd": 50.00,
      "pct": 90.46,
      "llm_usd": 12.10,
      "compute_usd": 30.50,
      "storage_usd": 2.63
    },
    ...
  ]
}
```

---

#### `GET /internal/billing/admin/health`

System health check: Redis connectivity, active Batch jobs, Lambda liveness (via heartbeat key), Lago reachability.

**Example:**
```bash
curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
     http://localhost:8081/internal/billing/admin/health
```

**Response (healthy):**
```json
{
  "redis": "ok",
  "active_jobs": 3,
  "last_batch_event_age_sec": 142,
  "lago": "ok",
  "total_users_tracked": 12,
  "month": "2026-02"
}
```

**Response (Lambda stale or never fired):**
```json
{
  "redis": "ok",
  "active_jobs": 0,
  "last_batch_event_age_sec": null,
  "lago": "ok",
  "total_users_tracked": 0,
  "month": "2026-02"
}
```

`last_batch_event_age_sec` is `null` if the Lambda has never fired (no heartbeat key in Redis yet), or an integer number of seconds since the last event.

**Alarm thresholds:**
- `last_batch_event_age_sec > 3600` (or `null` in production) → Lambda may be down
- `redis != "ok"` → complete billing outage
- `lago != "ok"` → invoicing broken (costs still tracked in Redis)

---

### 2.4 Lago Webhook

#### `POST /webhooks/lago`

Receives Lago subscription and invoice lifecycle events. Signature verified using `HMAC-SHA256` with `LAGO_WEBHOOK_SECRET`.

**Events handled:**
- `customer.payment_failure` → triggers payment failed email via Node.js
- `invoice.payment_failure` → same
- `subscription.terminated` → logs event

---

## 3. Redis Key Schema

All keys use `:` as separator. TTL is 35 days (`35 * 24 * 3600` seconds) unless noted.

**Month format:** `YYYY-MM` computed as `datetime.now(timezone.utc).strftime("%Y-%m")` — always UTC. When calling any API endpoint with an optional `?month=` param, use this same format (e.g. `2026-02`).

| Key pattern | Type | Contents | Example |
|-------------|------|----------|---------|
| `cost:<uid>:month:<YYYY-MM>:llm` | Hash | `input_usd`, `output_usd`, `input_tokens`, `output_tokens`, `calls` | `cost:42:month:2026-02:llm` |
| `cost:<uid>:month:<YYYY-MM>:compute` | Hash | `vcpu_usd`, `gpu_usd`, `mem_usd`, `seconds`, `jobs` | `cost:42:month:2026-02:compute` |
| `cost:<uid>:month:<YYYY-MM>:storage` | Hash | `storage_usd`, `request_usd`, `transfer_usd`, `bytes_stored`, `puts`, `gets` | `cost:42:month:2026-02:storage` |
| `cost:<uid>:month:<YYYY-MM>:total` | String | Committed total USD (float as string) | `cost:42:month:2026-02:total` |
| `cost:<uid>:job:<job_id>:running` | String (JSON) | `instance_type`, `vcpus`, `gpu_count`, `started_ms`, `est_usd` — TTL 48h | `cost:42:job:abc123:running` |
| `quota:<uid>:month:<YYYY-MM>:limit` | String | Quota ceiling in USD | `quota:42:month:2026-02:limit` |
| `quota:<uid>:month:<YYYY-MM>:alert_sent` | String | `"1"` if 80% warning email sent this month | — |
| `quota:<uid>:month:<YYYY-MM>:exceeded_sent` | String | `"1"` if 100% hard-limit email sent this month | — |
| `billing:last_batch_event_ts` | String | Unix epoch of last `batch_billing` Lambda invocation | Written on every Batch state-change event |

### Quick Redis inspection

```bash
# Connect (from Galaxy EC2 or via SSH tunnel — see MONITORING.md)
redis-cli -u $REDIS_URL

# List all cost keys for user 42
KEYS cost:42:*

# Get all LLM costs for user 42 this month
HGETALL cost:42:month:2026-02:llm

# Check quota
GET quota:42:month:2026-02:limit

# Check Lambda heartbeat age
GET billing:last_batch_event_ts
```

---

## 4. Lago Billable Metrics

Lago must be configured with exactly these 9 billable metrics **before** going live.
The `code` values must match exactly — they are the strings sent by `lago_client.py`.

| # | Code (exact string) | Properties field name | Unit | Description |
|---|---------------------|-----------------------|------|-------------|
| 1 | `llm_input_tokens` | `tokens` | tokens | LLM prompt tokens consumed |
| 2 | `llm_output_tokens` | `tokens` | tokens | LLM completion tokens generated |
| 3 | `batch_vcpu_seconds` | `seconds` | vCPU-seconds | Batch job vCPU × duration |
| 4 | `batch_gpu_seconds` | `seconds` | GPU-seconds | Batch job GPU × duration |
| 5 | `batch_memory_gb_sec` | `gb_seconds` | GB-seconds | Batch job memory GB × duration |
| 6 | `s3_storage_gb_hours` | `gb_hours` | GB-hours | S3 object storage (30-day retention estimate) |
| 7 | `s3_put_requests` | `count` | requests | S3 PUT/COPY/POST/LIST operations |
| 8 | `s3_get_requests` | `count` | requests | S3 GET operations |
| 9 | `s3_data_transfer_gb` | `gb` | GB | S3 cross-region data transfer |

**The "Properties field name" column is the key inside the Lago `properties` object that holds the quantity.** Each event sends `"properties": {"<field_name>": <quantity>}`. This must match the **Aggregation field** configured in Lago for each metric.

### Creating metrics in Lago (self-hosted UI)

1. Go to **Lago UI → Billable Metrics → Add**
2. For each row in the table above:
   - **Name**: human-readable (e.g. "LLM Input Tokens")
   - **Code**: exactly as shown in the `Code` column (e.g. `llm_input_tokens`)
   - **Aggregation type**: `SUM`
   - **Field name / Aggregation field**: exactly as shown in the `Properties field name` column (e.g. `tokens` for LLM, `seconds` for Batch vCPU, `gb_hours` for S3 storage)
3. Create 3 plans: `academic_monthly`, `professional_monthly`, `enterprise_monthly`
4. Attach all 9 metrics to each plan

### Required Lago subscription plans

| Plan code (Lago) | Display name | Monthly price |
|------------------|-------------|---------------|
| `academic_monthly` | Academic | $30/mo included |
| `professional_monthly` | Professional | $100/mo included |
| `enterprise_monthly` | Enterprise | Custom |

### Default quota limits (quota_enforcer.py)

These are the hardcoded fallback limits used when Lago is not yet integrated or for pre-subscription users. Plan names here are internal (`free/basic/pro/enterprise`) — distinct from Lago plan codes above.

| Internal plan name | Monthly quota (USD) |
|--------------------|---------------------|
| `free` | $5.00 |
| `basic` | $50.00 |
| `pro` | $500.00 |
| `enterprise` | Unlimited |

> **Note:** Once Lago subscriptions are live, quota limits should come from Lago via subscription metadata, not these hardcoded defaults. Updating this is listed in the Known Gaps section of README.md.

---

## 5. Cost Pricing Tables

These tables are in `cost_calculator.py`. They are approximate; update periodically.

### AWS Batch (EC2 on-demand per hour)

**General purpose (m6i):**

| Instance type | vCPUs | RAM (GB) | GPU | $/hr |
|--------------|-------|----------|-----|------|
| `m6i.large` | 2 | 8 | 0 | 0.096 |
| `m6i.xlarge` | 4 | 16 | 0 | 0.192 |
| `m6i.2xlarge` | 8 | 32 | 0 | 0.384 |
| `m6i.4xlarge` | 16 | 64 | 0 | 0.768 |
| `m6i.8xlarge` | 32 | 128 | 0 | 1.536 |

**Compute optimized (c6i):**

| Instance type | vCPUs | RAM (GB) | GPU | $/hr |
|--------------|-------|----------|-----|------|
| `c6i.large` | 2 | 4 | 0 | 0.085 |
| `c6i.xlarge` | 4 | 8 | 0 | 0.170 |
| `c6i.2xlarge` | 8 | 16 | 0 | 0.340 |
| `c6i.4xlarge` | 16 | 32 | 0 | 0.680 |
| `c6i.8xlarge` | 32 | 64 | 0 | 1.360 |

**GPU — T4 (g4dn):**

| Instance type | vCPUs | RAM (GB) | GPU | $/hr |
|--------------|-------|----------|-----|------|
| `g4dn.xlarge` | 4 | 16 | 1×T4 | 0.526 |
| `g4dn.2xlarge` | 8 | 32 | 1×T4 | 0.752 |
| `g4dn.4xlarge` | 16 | 64 | 1×T4 | 1.204 |
| `g4dn.8xlarge` | 32 | 128 | 1×T4 | 2.264 |

**GPU — A10G (g5):**

| Instance type | vCPUs | RAM (GB) | GPU | $/hr |
|--------------|-------|----------|-----|------|
| `g5.xlarge` | 4 | 16 | 1×A10G | 1.006 |
| `g5.2xlarge` | 8 | 32 | 1×A10G | 1.212 |
| `g5.4xlarge` | 16 | 64 | 1×A10G | 1.624 |

**High-performance GPU:**

| Instance type | vCPUs | RAM (GB) | GPU | $/hr |
|--------------|-------|----------|-----|------|
| `p3.2xlarge` | 8 | 61 | 1×V100 | 3.06 |
| `p4d.24xlarge` | 96 | 1152 | 8×A100 | 32.77 |

**Fargate (fallback for unknown instance types):**
- vCPU: $0.04048/hr
- Memory: $0.004445/GB-hr

Spot pricing: multiply by 0.35 (65% discount — default in `cost_calculator.py`).

### LLM Model Pricing (per 1M tokens)

| Model | Input $/1M | Output $/1M |
|-------|-----------|------------|
| `claude-opus-4-6` | $15.00 | $75.00 |
| `claude-sonnet-4-5-20250929` | $3.00 | $15.00 |
| `claude-haiku-4-5-20251001` | $0.25 | $1.25 |
| `gpt-4o` | $5.00 | $15.00 |
| `gpt-4o-mini` | $0.15 | $0.60 |
| `gemini-1.5-pro` | $3.50 | $10.50 |
| `deepseek-chat` | $0.27 | $1.10 |
| `default` (unknown model) | $3.00 | $15.00 |

### S3 Pricing

| Resource | Rate |
|----------|------|
| STANDARD storage | $0.023/GB/month |
| STANDARD_IA storage | $0.0125/GB/month |
| GLACIER storage | $0.004/GB/month |
| PUT/COPY/POST/LIST requests | $0.005/1K requests |
| GET requests | $0.0004/1K requests |
| Data transfer out (cross-region) | $0.09/GB |
| Data transfer in | Free |

---

## 6. Infrastructure Setup Checklist

Complete these steps in order before the billing system goes live.

### 6.1 Galaxy Backend EC2

- [ ] SSH into `i-0a20417c5b630ab46` (35.89.57.94)
- [ ] Set environment variables (add to `/etc/environment` or systemd service):
  ```bash
  REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
  BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
  NOTIFY_URL=http://localhost:5000
  LAGO_API_KEY=<your_lago_api_key>
  LAGO_API_URL=https://api.getlago.com/api/v1    # or self-hosted URL
  LAGO_WEBHOOK_SECRET=<random_secret_min_32_chars>
  JWT_SECRET=<your_jwt_secret>
  ```
- [ ] Restart Galaxy (gunicorn)
- [ ] Verify: `curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" http://localhost:8081/internal/billing/admin/health`

### 6.2 AWS Lambda — batch_billing

- [ ] Create Lambda in **us-west-2** (must be same region as Batch)
- [ ] Upload `batch_event_handler.py` as Lambda function code
- [ ] Add Lambda layer with `redis` and `httpx` packages
- [ ] Set env vars on Lambda:
  ```
  BILLING_API_URL = http://172.31.8.116:8081
  BILLING_API_KEY = w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
  REDIS_URL       = redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
  ```
- [ ] Place Lambda in VPC: same VPC as Batch, assign `lambda-billing-sg` (sg-0f658dd4800b6ca30)
- [ ] Create EventBridge rule:
  - Source: `aws.batch`
  - Detail type: `Batch Job State Change`
  - Filter: `{"detail": {"status": ["RUNNING", "SUCCEEDED", "FAILED"]}}`
  - Target: this Lambda
- [ ] Test: trigger manually with a fake RUNNING event, verify `billing:last_batch_event_ts` written to Redis

### 6.3 AWS Lambda — s3_billing

- [ ] Create Lambda in **us-east-1** (S3 buckets are in us-east-1)
- [ ] Upload `s3_billing.py` as function code
- [ ] Set env vars:
  ```
  BILLING_API_URL = http://172.31.8.116:8081
  BILLING_API_KEY = w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
  ```
- [ ] Create SQS queue `biomate-s3-billing-events` in us-east-1
- [ ] Enable S3 Event Notifications → SQS on both buckets:
  - `biomate-nextflow-work` → event: `ObjectCreated:*`
  - `biomate-production-data-399683337364` → event: `ObjectCreated:*`
- [ ] Add SQS trigger to this Lambda

### 6.4 Lago Setup

- [ ] Deploy Lago (self-hosted Docker or Lago Cloud)
- [ ] Create API key, set `LAGO_API_KEY` env var
- [ ] Create 9 billable metrics (exact codes in Section 4)
- [ ] Create 3 subscription plans (codes in Section 4)
- [ ] Configure Lago webhook: `https://api.biomate.dev/webhooks/lago`
  - Events: `customer.payment_failure`, `invoice.payment_failure`, `subscription.terminated`
  - Set `LAGO_WEBHOOK_SECRET` (same value on Lago and Galaxy EC2)

### 6.5 Stripe Setup

- [ ] Create 5 products/prices in Stripe Dashboard:
  - Academic Monthly, Academic Yearly, Professional Monthly, Professional Yearly, Enterprise Monthly, Enterprise Yearly (6 total)
- [ ] Set `STRIPE_PRICE_*` env vars on Node.js server (see Section 8)
- [ ] Register webhook endpoint: `https://api.biomate.dev/api/stripe/webhook`
  - Events: `checkout.session.completed`, `customer.subscription.created`,
    `customer.subscription.updated`, `customer.subscription.deleted`,
    `invoice.payment_succeeded`, `invoice.payment_failed`, `payment_intent.succeeded`
- [ ] Set `STRIPE_WEBHOOK_SECRET` env var
- [ ] Enable Stripe Customer Portal (Settings → Billing → Customer portal)

### 6.6 Email (SMTP)

- [ ] Choose provider: SendGrid (recommended), AWS SES, or Postmark
- [ ] Verify sender domain in the provider
- [ ] Set `EMAIL_*` env vars on Node.js server (see Section 8)
- [ ] Test: `POST /internal/notify/quota` with `pct: 85` to trigger a 80% warning email

---

## 7. End-to-End Mock Test Checklist

**No real AWS jobs or Stripe payments required.** All data is injected via Redis and curl.

### Prerequisites

- Galaxy EC2 running with billing router registered (port 8081)
- Node.js server running (port 5000)
- Redis accessible (`$REDIS_URL` set)
- `BILLING_INTERNAL_KEY` set on EC2

### Step 1 — Verify billing router is loaded

```bash
curl -s http://localhost:8081/api/billing/usage \
  -H "Authorization: Bearer 1"
# Expected: JSON with llm/compute/storage breakdown (all zeros for new user)
# If 404: billing_router.py is not registered in app.py — check FastAPI router include
```

### Step 2 — Seed quota for test user (user_id=1)

```bash
MONTH=$(date +%Y-%m)
redis-cli -u $REDIS_URL SET "quota:1:month:${MONTH}:limit" 30.0
# Expected: OK
```

### Step 3 — Seed mock LLM usage

```bash
redis-cli -u $REDIS_URL HSET "cost:1:month:${MONTH}:llm" \
  input_usd 1.23 output_usd 0.45 \
  input_tokens 85000 output_tokens 12000 calls 47
# Expected: (integer) 5
# NOTE: Do NOT seed total_usd — the API computes it dynamically from input_usd + output_usd
```

### Step 4 — Seed mock compute usage

```bash
redis-cli -u $REDIS_URL HSET "cost:1:month:${MONTH}:compute" \
  vcpu_usd 2.10 gpu_usd 1.80 mem_usd 0.66 \
  seconds 7200 jobs 5
# NOTE: Do NOT seed total_usd — the API computes it dynamically from component fields
redis-cli -u $REDIS_URL SET "cost:1:month:${MONTH}:total" 6.24
# The :total key IS the committed total and IS read directly
```

### Step 5 — Verify frontend billing page reads correctly

```bash
curl -s http://localhost:8081/api/billing/usage \
  -H "Authorization: Bearer 1" | python3 -m json.tool
# Expected: total_usd≈6.24, quota_usd=30.0, quota_pct≈20.8
# Also check via browser: http://localhost:5000/billing (logged in as user 1)
```

### Step 6 — Simulate a Batch job arriving (job_started)

```bash
curl -s -X POST http://localhost:8081/internal/billing/job_started \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -d '{
    "user_id": "1",
    "job_id": "test-job-001",
    "workflow_id": "wf-mock-001",
    "instance_type": "m6i.2xlarge",
    "vcpus": 8,
    "memory_mb": 32768,
    "gpu_count": 0,
    "started_at_ms": '"$(date +%s000)"',
    "is_spot": false
  }'
# Expected: {"ok": true}

# Verify the running job appears
curl -s http://localhost:8081/api/billing/jobs/running \
  -H "Authorization: Bearer 1" | python3 -m json.tool
# Expected: running_jobs array with one entry containing:
#   "job_id": "test-job-001", "instance_type": "m6i.2xlarge",
#   "elapsed_seconds": <small number>, "estimated_usd": <small number>
# And "running_total_usd" at the top level
```

### Step 7 — Simulate job completion (job_completed)

```bash
# Wait 5+ seconds so duration > 0
sleep 5

curl -s -X POST http://localhost:8081/internal/billing/job_completed \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -d '{
    "user_id": "1",
    "job_id": "test-job-001",
    "workflow_id": "wf-mock-001",
    "status": "SUCCEEDED",
    "instance_type": "m6i.2xlarge",
    "vcpus": 8,
    "memory_mb": 32768,
    "gpu_count": 0,
    "duration_seconds": 3600.0,
    "is_spot": false
  }'
# Expected: {"ok": true, ...}

# Verify compute cost was recorded
redis-cli -u $REDIS_URL HGETALL "cost:1:month:${MONTH}:compute"
# Expected: should now include the new job's cost added to the existing 4.56
```

### Step 8 — Simulate S3 upload

```bash
curl -s -X POST http://localhost:8081/internal/billing/s3_put \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -d '{
    "user_id": "1",
    "workflow_id": "wf-mock-001",
    "bucket": "biomate-production-data-399683337364",
    "key": "results/wf-mock-001/output.bam",
    "size_bytes": 1073741824
  }'
# Expected: {"ok": true, "total_cost_usd": <small number>}

# Verify storage cost
redis-cli -u $REDIS_URL HGETALL "cost:1:month:${MONTH}:storage"
# Expected: storage_usd > 0, request_usd > 0, bytes_stored = 1073741824, puts = 1
```

### Step 9 — Trigger quota warning email (80% threshold)

Bump usage to 80%+ of the $30 quota to trigger a warning email:

```bash
# Set total to $25.00 (83% of $30 quota)
redis-cli -u $REDIS_URL SET "cost:1:month:${MONTH}:total" 25.0

# Remove any existing warn flag so the email fires again
redis-cli -u $REDIS_URL DEL "quota:1:month:${MONTH}:alert_sent"

# Trigger via the next billing write (job_completed also calls _check_quota)
curl -s -X POST http://localhost:8081/internal/billing/job_completed \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -d '{
    "user_id": "1", "job_id": "test-job-002",
    "workflow_id": "wf-mock-001", "status": "SUCCEEDED",
    "instance_type": "m6i.large", "vcpus": 2, "memory_mb": 8192,
    "gpu_count": 0, "duration_seconds": 60.0, "is_spot": false
  }'
# Expected: should trigger POST to http://localhost:5000/internal/notify/quota
# Check Node.js logs for email send attempt
```

### Step 10 — Admin health check

```bash
# Check health
curl -s http://localhost:8081/internal/billing/admin/health \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" | python3 -m json.tool
# Expected: redis="ok", warnings may include Lambda heartbeat warning (that's fine in mock mode)

# Check all users dashboard
curl -s http://localhost:8081/internal/billing/admin/users \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" | python3 -m json.tool
# Expected: user_count >= 1, user_id="1" in users list with correct spend
```

### Step 10b — Add credits via internal endpoint

```bash
# Simulate Stripe checkout completing (adds $25 to quota)
curl -s -X POST http://localhost:8081/internal/billing/add-credits \
  -H "Content-Type: application/json" \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -d '{
    "user_id": "1",
    "amount_usd": 25.0,
    "payment_id": "cs_test_mock_001"
  }'
# Expected: {"ok": true, ...}

# Verify quota increased from 30.0 to 55.0
redis-cli -u $REDIS_URL GET "quota:1:month:${MONTH}:limit"
# Expected: 55.0 (or 55)
```

### Mock Test Pass Criteria

```
[ ] Step 1:  /api/billing/usage returns JSON (not 404)
[ ] Step 2:  Redis SET succeeds
[ ] Step 3-4: Redis HSET succeeds
[ ] Step 5:  /api/billing/usage shows seeded data (total_usd ≈ 6.24)
[ ] Step 6:  job_started returns 200; /jobs/running shows the in-flight job
[ ] Step 7:  job_completed returns 200; compute hash updated in Redis
[ ] Step 8:  s3_put returns 200; storage hash updated in Redis
[ ] Step 9:  80% threshold triggers call to localhost:5000/internal/notify/quota (check Node.js logs)
[ ] Step 10: /admin/health returns redis="ok"; /admin/users shows user 1
[ ] Step 10b: /add-credits increases quota in Redis
```

---

## 8. Environment Variables Reference

### Node.js Server (`frontend/.env`)

```bash
# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_ACADEMIC_MONTHLY=price_...
STRIPE_PRICE_ACADEMIC_YEARLY=price_...
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_...
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_...
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_...
STRIPE_PRICE_ENTERPRISE_YEARLY=price_...

# Billing service
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

### Galaxy Backend EC2

```bash
REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
NOTIFY_URL=http://localhost:5000
LAGO_API_KEY=<your_lago_api_key>
LAGO_API_URL=https://api.getlago.com/api/v1
LAGO_WEBHOOK_SECRET=<random_secret_min_32_chars>
JWT_SECRET=<your_jwt_secret>
```

### AWS Lambda — batch_billing and s3_billing

```bash
BILLING_API_URL=http://172.31.8.116:8081   # Galaxy backend private IP
BILLING_API_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
# Note: Lambda code uses BILLING_API_KEY; billing_router.py accepts both
# BILLING_API_KEY and BILLING_INTERNAL_KEY with fallback. Use the same value.
```

**batch_billing only:**
```bash
REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
# Used to write billing:last_batch_event_ts heartbeat key for health monitoring
```

---

*Generated by Claude Code — last updated 2026-02-18*
