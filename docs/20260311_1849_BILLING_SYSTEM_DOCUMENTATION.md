# BioMate Billing System Documentation

*Last updated: 2026-03-11. Covers the Lambda fix, Redis key schema, and all API endpoints.*

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [What Changed — Lambda Fix](#2-what-changed--lambda-fix)
3. [Redis Key Schema (Canonical Store)](#3-redis-key-schema-canonical-store)
4. [How to Access Cost Records](#4-how-to-access-cost-records)
   - [4.1 Redis CLI (direct, lowest latency)](#41-redis-cli-direct-lowest-latency)
   - [4.2 REST API — User-Facing Endpoints](#42-rest-api--user-facing-endpoints)
   - [4.3 REST API — Internal / Admin Endpoints](#43-rest-api--internal--admin-endpoints)
5. [How Costs Are Written](#5-how-costs-are-written)
   - [5.1 LLM Costs (per chat message)](#51-llm-costs-per-chat-message)
   - [5.2 Compute Costs (per Batch task)](#52-compute-costs-per-batch-task)
   - [5.3 Storage Costs (S3)](#53-storage-costs-s3)
6. [Two Storage Systems Explained](#6-two-storage-systems-explained)
7. [Quota Enforcement](#7-quota-enforcement)
8. [Infrastructure Details](#8-infrastructure-details)
9. [Pricing Reference](#9-pricing-reference)
10. [Operating Playbook](#10-operating-playbook)

---

## 1. Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────┐
│                        BioMate Billing Stack                          │
│                                                                       │
│  ┌──────────────────┐    ┌──────────────────┐   ┌──────────────────┐ │
│  │  LLM API calls   │    │  AWS Batch jobs  │   │    S3 uploads    │ │
│  │  (per message)   │    │  (per workflow   │   │  (per output)    │ │
│  │                  │    │   task)          │   │                  │ │
│  └────────┬─────────┘    └────────┬─────────┘   └────────┬─────────┘ │
│           │                       │                       │           │
│           │ _emit_llm_billing()   │ EventBridge           │ SQS       │
│           │ in llm_client.py      │ Batch Job State       │ S3 Event  │
│           ▼                       ▼  Change               ▼           │
│  ┌─────────────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │  Galaxy backend     │  │   Lambda:    │  │   Lambda:            │ │
│  │  (port 8081)        │  │  biomate-    │  │   biomate-s3-billing │ │
│  │  record_llm_cost()  │  │  batch-      │  │   (us-east-1)        │ │
│  │                     │  │  billing     │  │                      │ │
│  └──────────┬──────────┘  │  (us-west-2) │  └──────────┬───────────┘ │
│             │              └──────┬───────┘             │             │
│             └──────────────────── ▼ ────────────────────┘             │
│                                                                       │
│                    ┌──────────────────────────────┐                   │
│                    │   Redis (ElastiCache)         │  ← CANONICAL     │
│                    │   biomate-billing-redis        │    BILLING       │
│                    │   us-west-2                    │    STORE         │
│                    └──────────────┬───────────────┘                   │
│                                   │                                   │
│                    ┌──────────────▼───────────────┐                   │
│                    │   Quota Enforcer              │                   │
│                    │   check_and_reserve()         │                   │
│                    │   blocks over-limit users     │                   │
│                    └──────────────┬───────────────┘                   │
│                                   │  (future)                         │
│                    ┌──────────────▼───────────────┐                   │
│                    │   Lago                        │                   │
│                    │   invoice generation          │                   │
│                    │   (not yet connected)         │                   │
│                    └───────────────────────────────┘                   │
└───────────────────────────────────────────────────────────────────────┘
```

**Separate from the above** — PostgreSQL `telemetry_events` tracks analytics events
(query counts, error rates, `cost.chat.estimated`). It is **not** authoritative for
billing; it's an observability/product-analytics layer. See [Section 6](#6-two-storage-systems-explained).

---

## 2. What Changed — Lambda Fix

### Problem

The `biomate-batch-billing` Lambda was timing out at 15,000ms (the configured limit)
on every invocation. Zero billing data was reaching Redis.

**Root cause**: Two blocking calls that hung indefinitely because the Lambda's VPC
subnets have no NAT gateway route:

1. `_notify_billing_api()` — called `http://172.31.8.116:8081/internal/billing/job_completed`
   (Galaxy backend on EC2). No NAT → TCP SYN goes nowhere → hangs until Lambda timeout.
2. `_describe_job()` — called `boto3 batch.describe_jobs(jobs=[job_id])`.
   AWS API endpoints are in the public internet; VPC without NAT → same hang.

### Fix

Rewrote `batch_event_handler.py` (deployed to Lambda as `lambda_function.py`) with
**zero external API calls**. All data needed is already in the EventBridge event itself:

| Data needed | Old approach | New approach |
|---|---|---|
| `user_id` | `describe_jobs()` → tags | EventBridge `detail.container.environment[BIOMATE_USER_ID]` |
| `run_id` | `describe_jobs()` → tags | EventBridge `detail.container.environment[BIOMATE_RUN_ID]` |
| vCPUs | `describe_jobs()` → container | EventBridge `detail.container.vcpus` |
| GPU count | `describe_jobs()` → resourceRequirements | EventBridge `detail.container.resourceRequirements` |
| Start/stop times | `describe_jobs()` → startedAt | EventBridge `detail.startedAt` / `detail.stoppedAt` |

### How `user_id` reaches the Lambda

The user ID travels from the frontend request all the way to the Batch container:

```
routes.ts                    → user_id in Nextflow execute POST body
nextflow_executor.py         → _generate_executor_config(user_id=..., run_id=...)
                             → writes to executor.config:
                                 process {
                                   environment = [
                                     BIOMATE_USER_ID: '<user_id>',
                                     BIOMATE_RUN_ID: '<run_id>',
                                   ]
                                 }
AWS Batch (spawned by NF)    → container starts with BIOMATE_USER_ID in env
EventBridge event            → detail.container.environment includes BIOMATE_USER_ID
Lambda handler               → reads it; writes to Redis with correct user_id
```

### Result

| Metric | Before | After |
|---|---|---|
| Lambda duration | 15,000ms (timeout) | **129ms** |
| Redis write | Never | **Confirmed** |
| User ID in record | `unknown` | Actual user ID |
| Cost computed | N/A | vCPUs × time × rate |

**Verification run (2026-03-11 18:49 UTC)**:
```
Batch job test-job-billing-verify-001 → SUCCEEDED
Recorded SUCCEEDED job=test-job-billing-verify-001 user=test-billing-real-e2e
  duration=180.0s cost=$0.009600
Lambda status: 200 OK  Duration: 129ms
```

### Key files changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py` | Complete rewrite — no API calls |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Added `user_id` to `NextflowExecuteRequest`; injects `BIOMATE_USER_ID`/`BIOMATE_RUN_ID` into Batch container env |
| `frontend/server/routes.ts` | Passes `user_id` in Nextflow execute request body |

---

## 3. Redis Key Schema (Canonical Store)

**Redis endpoint**: `redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379`

All keys use `:` as separator. `{YYYY-MM}` is e.g. `2026-03`.

### Per-user monthly aggregates

```
cost:{user_id}:month:{YYYY-MM}:total     STRING  — float USD; rolling monthly total
cost:{user_id}:month:{YYYY-MM}:llm       HSET    — {input_usd, output_usd, calls}
cost:{user_id}:month:{YYYY-MM}:compute   HSET    — {vcpu_usd, gpu_usd, mem_usd, seconds}
cost:{user_id}:month:{YYYY-MM}:storage   HSET    — {s3_usd, puts, gets}
cost:{user_id}:month:{YYYY-MM}:transfer  HSET    — {out_gb, usd}
```

TTL: 90 days on monthly keys.

### Per-job records (from Lambda)

```
billing:batch:job:{job_id}    HSET  — {user_id, run_id, instance_type, vcpus, gpu_count,
                                        started_at_ms, status, duration_seconds, cost_usd}
billing:run:{run_id}:compute_usd   STRING  — total compute cost for a Nextflow run
```

TTL: 30 days.

### In-flight job tracking

```
cost:{user_id}:job:{job_id}:running   HSET  — {vcpus, gpu, mem_gb, started_ms, est_usd, instance}
```

Updated every ~30s during job execution. Deleted on job completion.

### Quota

```
quota:{user_id}:month:{YYYY-MM}:limit   STRING  — float USD, monthly spend cap
```

### System health

```
billing:last_batch_event_ts   STRING  — Unix timestamp of last Lambda invocation (expires 1h)
```

---

## 4. How to Access Cost Records

### 4.1 Redis CLI (direct, lowest latency)

Access requires being on the VPC or SSH-tunnelling through the Galaxy EC2
(`35.89.57.94`). The ElastiCache cluster is on port 6379.

```bash
# Set REDIS_URL
export REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379

# ── Monthly totals for a user ──────────────────────────────────────────
redis-cli -u $REDIS_URL GET "cost:42:month:2026-03:total"
# → "0.019200"

# ── Breakdown by category ──────────────────────────────────────────────
redis-cli -u $REDIS_URL HGETALL "cost:42:month:2026-03:llm"
# → input_usd 0.012 output_usd 0.007 calls 15

redis-cli -u $REDIS_URL HGETALL "cost:42:month:2026-03:compute"
# → vcpu_usd 0.009600 gpu_usd 0 mem_usd 0

# ── Per-job Batch record ───────────────────────────────────────────────
redis-cli -u $REDIS_URL HGETALL "billing:batch:job:8f596342-0539-42ab-940c-1eb5336a1b2c"
# → user_id 42  run_id abc123  instance_type m5.xlarge
#   vcpus 4  started_at_ms 1773254000000  status SUCCEEDED
#   duration_seconds 180.0  cost_usd 0.009600

# ── All users active this month ────────────────────────────────────────
redis-cli -u $REDIS_URL KEYS "cost:*:month:2026-03:total"

# ── Lambda heartbeat (seconds since last Batch event) ─────────────────
redis-cli -u $REDIS_URL GET "billing:last_batch_event_ts"

# ── Quota for a user ───────────────────────────────────────────────────
redis-cli -u $REDIS_URL GET "quota:42:month:2026-03:limit"

# ── All in-flight jobs ────────────────────────────────────────────────
redis-cli -u $REDIS_URL KEYS "cost:*:job:*:running"
```

**Via SSH tunnel** from dev machine:
```bash
ssh -i ~/.ssh/biomate-prod.pem -L 6379:biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379 ubuntu@35.89.57.94 -N &
redis-cli -h localhost -p 6379 GET "billing:last_batch_event_ts"
```

---

### 4.2 REST API — User-Facing Endpoints

All user endpoints require a `Authorization: Bearer <JWT>` header.

Base URL (production): `https://app.biomate.ai` or `http://35.89.57.94:3000` (dev)

#### `GET /api/billing/usage`
Current month cost breakdown for the authenticated user.

```bash
curl -s -H "Authorization: Bearer $JWT" \
  https://app.biomate.ai/api/billing/usage | jq .
```

Response:
```json
{
  "month": "2026-03",
  "total_usd": 0.0192,
  "llm_usd": 0.0096,
  "compute_usd": 0.0096,
  "storage_usd": 0.0000,
  "quota_usd": 25.00,
  "quota_pct": 0.08,
  "running_estimate_usd": 0.0,
  "running_jobs": []
}
```

#### `GET /api/billing/usage?month=2026-02`
Cost breakdown for a specific past month.

#### `GET /api/billing/usage/history?months=3`
Past N months (max 24). Returns `{"user_id": ..., "history": [...]}`.

#### `GET /api/billing/quota`
Plan limit and current usage percentage.

```json
{
  "user_id": "42",
  "quota_usd": 25.00,
  "used_usd": 0.0192,
  "quota_pct": 0.08,
  "over_quota": false
}
```

#### `GET /api/billing/jobs/running`
In-flight Batch jobs with live cost estimates.

```json
{
  "user_id": "42",
  "running_jobs": [
    {
      "job_id": "8f596342-...",
      "instance_type": "m5.xlarge",
      "vcpus": 4,
      "elapsed_min": 3.2,
      "est_usd": 0.0021
    }
  ],
  "running_total_usd": 0.0021
}
```

#### `GET /api/billing/usage/cohort`
User's relative cost position in the cohort (privacy-preserving — no other user data).

```json
{
  "your_spend_usd": 0.0192,
  "cohort_avg_usd": 0.0850,
  "cohort_p75_usd": 0.1200,
  "cohort_p90_usd": 0.4500,
  "your_tier": "low",
  "active_users_this_month": 47
}
```

---

### 4.3 REST API — Internal / Admin Endpoints

Require `X-Internal-Key: w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE` header.
Only callable from within the VPC or from the Galaxy backend process.

#### `GET /internal/billing/admin/health`
System health: Redis connectivity, active jobs, Lago status, Lambda heartbeat.

```bash
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://35.89.57.94:8081/internal/billing/admin/health | jq .
```

Response:
```json
{
  "redis": "ok",
  "active_jobs": 3,
  "lago": "disabled (LAGO_API_KEY not set)",
  "total_users_tracked": 47,
  "month": "2026-03",
  "last_batch_event_age_sec": 142,
  "redis_connection_pool": {
    "max_connections": 50,
    "in_use_connections": 1,
    "utilization_percent": 2.0
  }
}
```

`last_batch_event_age_sec` — seconds since last Batch EventBridge event hit the Lambda.
If this exceeds 3600 and jobs are running, the Lambda may be broken.

#### `GET /internal/billing/admin/users`
All users sorted by spend this month.

```bash
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://35.89.57.94:8081/internal/billing/admin/users | jq .
```

Response:
```json
{
  "month": "2026-03",
  "user_count": 47,
  "users": [
    {
      "user_id": "12",
      "total_usd": 4.2100,
      "quota_usd": 25.00,
      "pct": 16.8,
      "llm_usd": 3.1200,
      "compute_usd": 1.0900,
      "storage_usd": 0.0000
    }
  ]
}
```

#### `GET /internal/billing/admin/cohort_cost?months=3`
Cohort-level cost dashboard: mean/median/percentile spend per active user.

```bash
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  "http://35.89.57.94:8081/internal/billing/admin/cohort_cost?months=3" | jq .
```

Response:
```json
{
  "months": [
    {
      "month": "2026-03",
      "total_active_users": 47,
      "total_spend_usd": 98.40,
      "cost_per_active_user_usd": 2.09,
      "percentiles": {
        "p50_usd": 0.85,
        "p75_usd": 2.40,
        "p90_usd": 6.10,
        "p99_usd": 18.20
      },
      "llm_fraction": 0.72,
      "compute_fraction": 0.26,
      "storage_fraction": 0.02
    }
  ]
}
```

#### Other internal endpoints (called automatically, not normally invoked manually)

```
POST /internal/billing/job_started      — registered running job
POST /internal/billing/job_completed    — finalise Batch job cost
POST /internal/billing/llm_cost         — record an LLM call cost
POST /internal/billing/s3_put           — record S3 upload cost
POST /internal/billing/s3_delete        — refund S3 storage cost
POST /internal/billing/set_quota        — set monthly quota for user
POST /internal/billing/add-credits      — add purchased credits
POST /internal/billing/register_user    — register user in Lago + Redis
```

---

## 5. How Costs Are Written

### 5.1 LLM Costs (per chat message)

Every successful LLM API call in `llm_client.py` calls `_emit_llm_billing()`.
This function (lines 18–73) does three things in sequence, each in a try/except:

```
1. Analytics tracking  → manual_track_call()        (PostgreSQL telemetry)
2. Redis billing       → get_cost_service()
                          .record_llm_cost()          (Redis ← CANONICAL)
3. Lago                → get_lago_client().emit_llm() (future invoicing)
```

**Precondition**: `user_id` must be non-empty. If `user_id` is empty/`"unknown"` the
function returns immediately and nothing is written. The `user_id` flows:

```
routes.ts (billingUserId = req.user.id)
  → galaxy-assistant.ts (generateWorkflow(billingUserId))
    → galaxy-api-proxy.ts (context.billing_user_id)
      → ai_assistant.py (constrained_generator.llm_client.user_id = ...)
        → llm_client.py _emit_llm_billing(user_id=..., ...)
          → record_llm_cost() → Redis cost:{user_id}:month:*:llm
```

**Pricing** (us-east-1 / us-west-2, 2026-Q1):

| Model | Input (per M tokens) | Output (per M tokens) |
|---|---|---|
| claude-sonnet-4-6 | $3.00 | $15.00 |
| claude-opus-4-6 | $15.00 | $75.00 |
| claude-haiku-4-5 | $0.80 | $4.00 |
| gpt-4o | $2.50 | $10.00 |
| gemini-2.0-flash | $0.10 | $0.40 |

### 5.2 Compute Costs (per Batch task)

Each Nextflow Batch task fires two EventBridge events: `RUNNING` and `SUCCEEDED`/`FAILED`.
The Lambda (`biomate-batch-billing`) handles both:

```
RUNNING event  → _record_started()   → Redis billing:batch:job:{job_id}  (status=RUNNING)
SUCCEEDED event → _record_completed() → Redis billing:batch:job:{job_id}  (status=SUCCEEDED)
                                      → Redis cost:{user_id}:month:*:total (INCRBYFLOAT)
                                      → Redis billing:run:{run_id}:compute_usd
```

Only `SUCCEEDED` jobs increment the user's monthly total. `FAILED` jobs are recorded
but not billed (recorded in `billing:batch:job:*` for debugging).

**Pricing** (on-demand, us-west-2, 2026-Q1):

| Instance | $/vCPU-hour | $/GPU-hour |
|---|---|---|
| m5.large | $0.048 | — |
| m5.xlarge | $0.048 | — |
| m5.2xlarge | $0.048 | — |
| m5.4xlarge | $0.048 | — |
| g4dn.xlarge | $0.1315 | — |
| p3.2xlarge | $0.3825 | — |

1-minute minimum billing per task (same as AWS Batch policy).

**Typical 24-step SPA cryo-EM run**: ~$0.10–0.40 at 4 vCPUs/task.

### 5.3 Storage Costs (S3)

The `biomate-s3-billing` Lambda (us-east-1) triggers on SQS events from
`arn:aws:sqs:us-east-1:399683337364:biomate-s3-billing-events`. It calls
`POST /internal/billing/s3_put` with `user_id`, `size_bytes`, and `key`.

S3 costs are currently tracked but small (~$0.023/GB/month standard storage).

---

## 6. Two Storage Systems Explained

### Why Both Exist

| | PostgreSQL `telemetry_events` | Redis `cost:*` keys |
|---|---|---|
| **Purpose** | Product analytics, observability | Quota enforcement, billing aggregation |
| **Latency** | Async, best-effort | <5ms, synchronous |
| **What's stored** | Every event: queries, errors, estimated costs | Committed costs only, per user/month |
| **Cost field** | `cost.chat.estimated` (token × price) | Actual model API cost in USD |
| **Quota enforcement** | No | Yes — blocks over-limit users |
| **Invoicing** | No | Yes — feeds Lago |
| **Retention** | Configurable (default 90 days) | 90 days |
| **Who reads it** | Dev dashboards, error rate monitoring | Quota enforcer, billing API, Lago |

### Why `cost.chat.estimated` in PostgreSQL ≠ Redis totals

PostgreSQL records are written from the Node.js `routes.ts` layer using a local
token estimator (Tiktoken-style approximation). Redis records are written by the
Python backend after the actual API response arrives with real token counts.
The two may differ by 5–20% due to estimation vs actuals, and because some code
paths write to PostgreSQL but not yet to Redis (test routes, unauthenticated requests).

**Redis is the authoritative source** for user quota enforcement and invoicing.
PostgreSQL telemetry is supplementary analytics.

---

## 7. Quota Enforcement

Before every AI assistant request and workflow execution, `check_and_reserve()` in
`quota_enforcer.py` runs:

```python
def check_and_reserve(user_id: str, estimated_cost_usd: float = 0.0) -> None:
    """
    Raises BillingQuotaExceededError if user is over their monthly limit.
    Atomically reserves the estimated cost to prevent race conditions.
    """
```

**Plan limits** (set in Redis on user registration):

| Plan | Monthly quota |
|---|---|
| free | $5.00 |
| trial (invited) | $25.00 (30-day) |
| professional | $25.00 |
| enterprise | Negotiated |

To manually set or inspect quota:

```bash
# Check current quota
redis-cli -u $REDIS_URL GET "quota:42:month:2026-03:limit"

# Set quota manually (admin)
curl -s -X POST -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "42", "quota_usd": 50.0}' \
  http://35.89.57.94:8081/internal/billing/set_quota

# Add purchased credits
curl -s -X POST -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "42", "amount_usd": 25.0, "payment_id": "pi_stripe_abc"}' \
  http://35.89.57.94:8081/internal/billing/add-credits
```

---

## 8. Infrastructure Details

### Redis (ElastiCache)

| Setting | Value |
|---|---|
| Endpoint | `biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379` |
| Instance | `cache.t4g.small` (us-west-2) |
| Security group | `sg-096a3c0fcd3e4504c` (biomate-redis-sg) |
| Access | Port 6379 from `biomate-sg` + `biomate-lambda-billing-sg` only |

### Lambda — `biomate-batch-billing`

| Setting | Value |
|---|---|
| Region | us-west-2 (same as Batch) |
| Runtime | Python 3.12 |
| Timeout | 15s (generous; actual execution <200ms) |
| Memory | 128MB |
| VPC | Yes — same VPC as Redis; **no NAT gateway** |
| Trigger | EventBridge rule `biomate-batch-job-state-change` |
| IAM role | `arn:aws:iam::399683337364:role/biomate-lambda-billing-role` |
| Entry point | `lambda_function.handler` |

**Important**: The Lambda has no NAT gateway route. It can only reach:
- Resources within the VPC (Redis via ElastiCache endpoint)
- Nothing else (no AWS APIs, no HTTP to internet, no Galaxy backend)

This is by design in the final implementation — all data comes from the EventBridge
event payload, so no external calls are needed.

### Lambda — `biomate-s3-billing`

| Setting | Value |
|---|---|
| Region | us-east-1 (S3 buckets are in us-east-1) |
| Trigger | SQS `biomate-s3-billing-events` |
| VPC | None (calls Galaxy backend HTTP) |

### Batch

| Setting | Value |
|---|---|
| Queue | `biomate-nextflow-queue` |
| Compute environment | `biomate-nextflow-cpu-v1` |
| Default container | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest` |
| S3 workdir | `s3://biomate-nextflow-work/nextflow/work` |
| Region | us-west-2 |

---

## 9. Pricing Reference

### LLM models (2026-Q1 list prices)

```python
# From cost_calculator.py
_LLM_PRICING = {
    "claude-sonnet-4-6":  {"input": 3.00,  "output": 15.00},   # per M tokens
    "claude-opus-4-6":    {"input": 15.00, "output": 75.00},
    "claude-haiku-4-5":   {"input": 0.80,  "output": 4.00},
    "gpt-4o":             {"input": 2.50,  "output": 10.00},
    "gpt-4o-mini":        {"input": 0.15,  "output": 0.60},
    "gemini-2.0-flash":   {"input": 0.10,  "output": 0.40},
}
```

### Compute (EC2 on-demand, us-west-2)

```python
# From batch_event_handler.py
_USD_PER_VCPU_HOUR = {
    "m5.large":    0.048,   # 0.096 / 2 vCPUs
    "m5.xlarge":   0.048,   # 0.192 / 4
    "m5.2xlarge":  0.048,   # 0.384 / 8
    "m5.4xlarge":  0.048,   # 0.768 / 16
    "g4dn.xlarge": 0.1315,  # 0.526 / 4 (GPU instance)
    "p3.2xlarge":  0.3825,  # 3.06  / 8 (V100)
}
```

### S3 (us-east-1, standard)

| Operation | Price |
|---|---|
| Storage | $0.023/GB/month |
| PUT | $0.005/1,000 requests |
| GET | $0.0004/1,000 requests |
| Data transfer out | $0.09/GB |

---

## 10. Operating Playbook

### Check if billing is working right now

```bash
# 1. Lambda heartbeat (should be < 300s if jobs are running)
redis-cli -u $REDIS_URL GET billing:last_batch_event_ts
# → "1773254000.123"   (Unix timestamp)

# 2. System health via API
curl -s -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://35.89.57.94:8081/internal/billing/admin/health

# 3. Run a test Lambda invocation
cat > /tmp/test_event.json << 'EOF'
{
  "source": "aws.batch",
  "detail-type": "Batch Job State Change",
  "detail": {
    "jobId": "test-health-check-001",
    "status": "SUCCEEDED",
    "startedAt": 1773254000000,
    "stoppedAt": 1773254060000,
    "container": {
      "vcpus": 2,
      "environment": [
        {"name": "BIOMATE_USER_ID", "value": "health-check"},
        {"name": "BIOMATE_RUN_ID",  "value": "health-check-run"}
      ],
      "resourceRequirements": []
    },
    "tags": {"instance_type": "m5.large"}
  }
}
EOF

aws lambda invoke \
  --function-name biomate-batch-billing \
  --payload file:///tmp/test_event.json \
  --cli-binary-format raw-in-base64-out \
  --region us-west-2 \
  --log-type Tail /tmp/resp.json 2>&1 | grep "Duration:"

# Expected: Duration: ~130ms (NOT 15000ms)
# If 15000ms: Lambda has timed out — check REDIS_URL env var on Lambda config
```

### Redeploy Lambda after code changes

```bash
cd /tmp && rm -rf lambda_deploy && mkdir lambda_deploy
cp /home/yzhang/biomate/backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py \
   lambda_deploy/lambda_function.py
pip install redis -t lambda_deploy/ -q
cd lambda_deploy && zip -r ../lambda_billing.zip . -q && cd /tmp

aws lambda update-function-code \
  --function-name biomate-batch-billing \
  --zip-file fileb:///tmp/lambda_billing.zip \
  --region us-west-2
```

### View billing for a specific user (by ID)

```bash
USER_ID=42
MONTH=2026-03

echo "=== Monthly total ==="
redis-cli -u $REDIS_URL GET "cost:${USER_ID}:month:${MONTH}:total"

echo "=== LLM breakdown ==="
redis-cli -u $REDIS_URL HGETALL "cost:${USER_ID}:month:${MONTH}:llm"

echo "=== Compute breakdown ==="
redis-cli -u $REDIS_URL HGETALL "cost:${USER_ID}:month:${MONTH}:compute"

echo "=== Quota ==="
redis-cli -u $REDIS_URL GET "quota:${USER_ID}:month:${MONTH}:limit"
```

### View billing for all Batch jobs in a Nextflow run

```bash
RUN_ID=billing-test-run-20260311

# Total compute cost for the run
redis-cli -u $REDIS_URL GET "billing:run:${RUN_ID}:compute_usd"

# List all job keys
redis-cli -u $REDIS_URL KEYS "billing:batch:job:*" | while read key; do
  status=$(redis-cli -u $REDIS_URL HGET "$key" status)
  user=$(redis-cli -u $REDIS_URL HGET "$key" user_id)
  cost=$(redis-cli -u $REDIS_URL HGET "$key" cost_usd)
  run=$(redis-cli -u $REDIS_URL HGET "$key" run_id)
  if [ "$run" = "$RUN_ID" ]; then
    echo "$key: status=$status user=$user cost=$cost"
  fi
done
```

### Find Lambda timeout root cause

```bash
# Get recent log streams
aws logs describe-log-streams \
  --log-group-name /aws/lambda/biomate-batch-billing \
  --order-by LastEventTime --descending \
  --max-items 5 --region us-west-2

# Read a specific stream
STREAM="2026/03/11/[\$LATEST]5c711253a7ac4923a15fc3456534ff39"
aws logs get-log-events \
  --log-group-name /aws/lambda/biomate-batch-billing \
  --log-stream-name "$STREAM" \
  --region us-west-2 | jq -r '.events[].message'

# If you see Duration: 15000.00 ms Status: timeout:
#   - Check REDIS_URL is set on the Lambda configuration
#   - Verify Lambda security group allows egress to port 6379
#   - Verify Lambda is in the correct VPC/subnet
aws lambda get-function-configuration \
  --function-name biomate-batch-billing \
  --region us-west-2 | jq '{VpcConfig, Environment}'
```

### Adjust a user's quota mid-month

```bash
# Extend quota for a specific user (e.g., heavy researcher)
curl -X POST -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "42", "quota_usd": 100.0}' \
  http://35.89.57.94:8081/internal/billing/set_quota
```

---

*Source files:*
- `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py` — Lambda handler
- `backend/lib/galaxy/ai/billing/api/billing_router.py` — REST API endpoints
- `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` — Redis read/write
- `backend/lib/galaxy/ai/billing/core/cost_calculator.py` — pricing formulas
- `backend/lib/galaxy/ai/billing/core/quota_enforcer.py` — quota gate
- `backend/lib/galaxy/ai/llm_client.py` — LLM cost emission
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — user_id injection
- `frontend/server/routes.ts` — user_id propagation + billing proxy routes
