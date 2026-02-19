# BioMate Real-Time Per-User Cost Tracking — Implementation Plan

**Date**: 2026-02-17
**Status**: Draft for backend engineers
**Infrastructure**: EC2 (Docker/ECR) + AWS Batch (CPU/GPU) + S3 + Lago

---

## Architecture Overview

```
 User Browser
     │
     │ JWT auth
     ▼
 EC2 — BioMate App (Docker, ECR)
     │ FastAPI /api/billing/usage   ─── Redis (ElastiCache) ◄──┐
     │                                                          │
     │ submits job                                              │ live estimate
     ▼                                                          │ every 10s
 AWS Batch Queue                                                │
     │                                                          │
     │ RUNNING / SUCCEEDED / FAILED                             │
     ▼                                                          │
 EventBridge ──► Lambda (batch_event_handler)                  │
                    │ POST /internal/billing/job_started  ──────┘
                    │ POST /internal/billing/job_completed ──► Redis + Lago
                    │
 S3 Results Bucket
     │ ObjectCreated / ObjectRemoved
     ▼
 SQS Queue ──► Lambda (s3_event_handler)
                    │ POST /internal/billing/s3_put ──────────► Redis + Lago
                    │
 Lago (self-hosted Docker)
     │ webhooks: subscription.started → quota set in Redis
     │           invoice.created       → user notified
     └─► Stripe (payment collection)
```

---

## Level 1: System Components

| # | Component | Responsibility |
|---|-----------|----------------|
| 1 | **Cost Event Collector** | Captures raw AWS usage signals (Batch, S3, LLM) |
| 2 | **Cost Calculator** | Converts raw signals to USD using pricing tables |
| 3 | **Redis Ledger** | Stores per-user running totals; powers real-time API |
| 4 | **Lago Client** | Forwards metered events to Lago for invoicing |
| 5 | **Quota Enforcer** | Blocks job submission when user exceeds plan |
| 6 | **Billing API** | REST endpoints for frontend and internal services |
| 7 | **Infrastructure** | EventBridge, SQS, Lambda, ElastiCache provisioning |

---

## Level 2: Sub-Components

### 1. Cost Event Collector

| # | Sub-Component | Description |
|---|---------------|-------------|
| 1.1 | Batch EventBridge Consumer | Lambda triggered on every RUNNING/SUCCEEDED/FAILED Batch event |
| 1.2 | S3 Event Consumer | Lambda triggered by SQS ← S3 notifications for PUT/DELETE |
| 1.3 | LLM Call Interceptor | Python middleware in the BioMate app; wraps all Anthropic calls |
| 1.4 | Job Tag Convention | All Batch jobs and S3 objects tagged with user_id, workflow_id |

### 2. Cost Calculator

| # | Sub-Component | Description |
|---|---------------|-------------|
| 2.1 | Batch Pricing Engine | EC2 instance table + per-vCPU/GPU/memory proportional split |
| 2.2 | S3 Pricing Engine | Storage ($0.023/GB-month) + requests + data transfer |
| 2.3 | LLM Pricing Engine | Per-model token pricing (Claude, future models) |
| 2.4 | Running Job Estimator | estimate_running_job_cost() called every 10s by background thread |

### 3. Redis Ledger

| # | Sub-Component | Description |
|---|---------------|-------------|
| 3.1 | Monthly Cost Hashes | HSET per cost category (llm, compute, storage) per user per month |
| 3.2 | Running Job Keys | SETEX for in-flight job metadata + latest cost estimate |
| 3.3 | Quota Keys | SETEX for plan limit per user per month |
| 3.4 | Alert State Keys | SETEX to track whether 80% alert was already sent |

### 4. Lago Client

| # | Sub-Component | Description |
|---|---------------|-------------|
| 4.1 | Event Emitter | POST /api/v1/events — fire-and-forget, never blocks user requests |
| 4.2 | Batch Event Emitter | POST /api/v1/events/batch — up to 100 events per call |
| 4.3 | Customer Sync | Upsert Lago customer on first login or plan change |
| 4.4 | Subscription Manager | Lago plan ↔ BioMate plan code mapping |
| 4.5 | Webhook Receiver | Handle Lago→BioMate events (subscription.started, invoice.created) |

### 5. Quota Enforcer

| # | Sub-Component | Description |
|---|---------------|-------------|
| 5.1 | Pre-Job Check | check_and_reserve() called in BioMate job submission handler |
| 5.2 | Hard Limit | Raises QuotaExceededError → returns HTTP 402 to user |
| 5.3 | Soft Limit | 80% warning → stored in Redis, surfaced in /api/billing/quota |
| 5.4 | Plan Limit Sync | ensure_quota_set() called on login + Lago subscription webhook |

### 6. Billing API

| # | Sub-Component | Description |
|---|---------------|-------------|
| 6.1 | GET /api/billing/usage | Real-time breakdown: LLM + compute + storage + running estimate |
| 6.2 | GET /api/billing/usage/history | Past N months, from Redis (TTL=35 days) |
| 6.3 | GET /api/billing/quota | Plan limit, current %, over-quota flag |
| 6.4 | GET /api/billing/jobs/running | In-flight jobs with live cost estimates |
| 6.5 | POST /internal/billing/job_started | Called by Batch Lambda → registers running job |
| 6.6 | POST /internal/billing/job_completed | Called by Batch Lambda → finalises job cost |
| 6.7 | POST /internal/billing/s3_put | Called by S3 Lambda → records storage cost |
| 6.8 | POST /webhooks/lago | Receives Lago subscription/invoice events |

### 7. Infrastructure

| # | Sub-Component | Description |
|---|---------------|-------------|
| 7.1 | EventBridge Rule | Pattern: source=aws.batch, status=RUNNING/SUCCEEDED/FAILED |
| 7.2 | Lambda: batch_event_handler | 128MB, timeout 30s, Python 3.12, VPC-attached |
| 7.3 | SQS Queue | biomate-s3-billing-events; DLQ with 3 retries |
| 7.4 | Lambda: s3_event_handler | Triggered by SQS; 128MB, timeout 30s |
| 7.5 | ElastiCache Redis | cache.t4g.small; Multi-AZ; same VPC as EC2 |
| 7.6 | Lago (Docker on EC2) | lago:latest; PostgreSQL backend; expose port 3000 internally |
| 7.7 | IAM Roles | Least-privilege roles for each Lambda and the app EC2 |

---

## Level 3: Implementation Tasks

### 1.1 Batch EventBridge Consumer

| # | Task | Owner | Done |
|---|------|-------|------|
| 1.1.1 | Create EventBridge rule (see `infrastructure/eventbridge_rules.json`) | DevOps | ☐ |
| 1.1.2 | Package `lambda/batch_event_handler.py` as Lambda (Python 3.12, layer with httpx) | Backend | ☐ |
| 1.1.3 | Grant Lambda `batch:DescribeJobs` IAM permission | DevOps | ☐ |
| 1.1.4 | Grant EventBridge permission to invoke the Lambda | DevOps | ☐ |
| 1.1.5 | Test with a mock Batch job; verify `BILLING_API_URL` receives POST | Backend | ☐ |

### 1.2 S3 Event Consumer

| # | Task | Owner | Done |
|---|------|-------|------|
| 1.2.1 | Enable S3 event notifications on the results bucket → SQS | DevOps | ☐ |
| 1.2.2 | Create SQS queue `biomate-s3-billing-events`; DLQ `...-dlq` | DevOps | ☐ |
| 1.2.3 | Package `lambda/s3_event_handler.py` as Lambda | Backend | ☐ |
| 1.2.4 | Grant Lambda `s3:GetObjectTagging`, `s3:HeadObject` IAM permissions | DevOps | ☐ |
| 1.2.5 | Test with a manual S3 upload; confirm billing API receives s3_put | Backend | ☐ |

### 1.3 LLM Call Interceptor

| # | Task | Owner | Done |
|---|------|-------|------|
| 1.3.1 | Add `user_id` to all Claude API call sites in the existing AI agent code | Backend | ☐ |
| 1.3.2 | Update `tracking_decorator.py` to call `RealtimeCostService.record_llm_cost()` | Backend | ☐ |
| 1.3.3 | Update `tracking_decorator.py` to call `LagoClient.emit_llm()` | Backend | ☐ |
| 1.3.4 | Ensure session_id ↔ user_id mapping is available at intercept point | Backend | ☐ |

### 1.4 Job Tag Convention

| # | Task | Owner | Done |
|---|------|-------|------|
| 1.4.1 | Batch job submission: add tags `user_id`, `workflow_id`, `org_id`, `instance_type`, `capacity_type` | Backend | ☐ |
| 1.4.2 | S3 upload: add tags `user_id`, `workflow_id` on every `put_object` call | Backend | ☐ |
| 1.4.3 | Document the tagging convention in team wiki | Backend | ☐ |

### 2.1 Batch Pricing Engine

| # | Task | Owner | Done |
|---|------|-------|------|
| 2.1.1 | Review `EC2_INSTANCE_PRICING` table in `cost_calculator.py`; add missing instance types used in your Batch compute environments | Backend | ☐ |
| 2.1.2 | Decide Spot vs On-Demand strategy; set `capacity_type` tag in job submission | Backend | ☐ |
| 2.1.3 | Unit-test `batch_job_cost()` against known scenarios (1h c6i.2xlarge = $0.34) | Backend | ☐ |
| 2.1.4 | Evaluate actual vs estimated — run 10 real jobs, compare to AWS CUR after 24h | Backend | ☐ |

### 2.4 Running Job Estimator

| # | Task | Owner | Done |
|---|------|-------|------|
| 2.4.1 | Confirm `POLL_INTERVAL=10s` is acceptable; tune if CPU overhead is visible | Backend | ☐ |
| 2.4.2 | Verify background thread starts correctly inside Gunicorn workers (use `--workers 1` or shared state) | Backend | ☐ |
| 2.4.3 | Add dead-letter cleanup: if a job key lives in Redis >12h with no terminal event, expire it | Backend | ☐ |

### 3.x Redis Ledger

| # | Task | Owner | Done |
|---|------|-------|------|
| 3.1 | Provision ElastiCache Redis (cache.t4g.small, Multi-AZ) in same VPC as EC2 | DevOps | ☐ |
| 3.2 | Set `REDIS_URL` env var in Docker container / ECS task definition | DevOps | ☐ |
| 3.3 | Verify key TTL is sufficient (35 days covers current + previous billing month) | Backend | ☐ |
| 3.4 | Add Redis health-check to application startup | Backend | ☐ |

### 4.x Lago Setup

| # | Task | Owner | Done |
|---|------|-------|------|
| 4.1 | Deploy Lago via Docker on a dedicated EC2 instance (t3.small) or alongside BioMate | DevOps | ☐ |
| 4.2 | Configure PostgreSQL for Lago (RDS t3.micro or local) | DevOps | ☐ |
| 4.3 | Create billable metrics in Lago UI for each EventCode (see lago_client.py) | Product/Backend | ☐ |
| 4.4 | Create plans in Lago matching BioMate tiers: free, basic, pro, enterprise | Product | ☐ |
| 4.5 | Set `LAGO_API_URL` and `LAGO_API_KEY` env vars | DevOps | ☐ |
| 4.6 | Register Lago webhook URL in Lago UI: `https://api.biomate.ai/webhooks/lago` | DevOps | ☐ |
| 4.7 | Set `LAGO_WEBHOOK_SECRET` env var; verify signature verification | Backend | ☐ |
| 4.8 | Connect Lago to Stripe (or chosen payment provider) | Product | ☐ |

### 5.x Quota Enforcer

| # | Task | Owner | Done |
|---|------|-------|------|
| 5.1 | Add `check_and_reserve()` call in the Batch job submission handler | Backend | ☐ |
| 5.2 | Handle `QuotaExceededError` → return HTTP 402 with user-friendly message | Backend | ☐ |
| 5.3 | Call `ensure_quota_set()` on user login (read plan from Lago or user DB) | Backend | ☐ |
| 5.4 | Call `ensure_quota_set()` in Lago subscription webhook handler (already wired) | Backend | ☐ |
| 5.5 | Test: create a free-tier user, exhaust $5 quota, verify job submission is blocked | Backend | ☐ |

### 6.x Billing API

| # | Task | Owner | Done |
|---|------|-------|------|
| 6.1 | Mount `billing_router` in main FastAPI app | Backend | ☐ |
| 6.2 | Replace `current_user_id()` stub with real JWT validation | Backend | ☐ |
| 6.3 | Add rate limiting to `/api/billing/usage` (max 10 req/s per user) | Backend | ☐ |
| 6.4 | Test all 8 endpoints with Postman / pytest | Backend | ☐ |
| 6.5 | Expose `GET /api/billing/usage` to frontend via existing API proxy | Frontend | ☐ |

### 7.x Infrastructure

| # | Task | Owner | Done |
|---|------|-------|------|
| 7.1 | Create Lambda execution role with `batch:DescribeJobs`, `s3:GetObjectTagging`, `s3:HeadObject` | DevOps | ☐ |
| 7.2 | Package Lambda with httpx dependency (Lambda layer or container image) | DevOps | ☐ |
| 7.3 | Configure VPC endpoints for Batch, S3, Lambda so traffic stays within VPC | DevOps | ☐ |
| 7.4 | Enable CloudWatch Logs for both Lambdas | DevOps | ☐ |
| 7.5 | Set up CloudWatch alarms: Lambda errors > 5/min, DLQ depth > 0 | DevOps | ☐ |

---

## Level 4: Code-Level Details

### 4.1 Lago Billable Metric Configuration

Create these in Lago UI (Settings → Billable Metrics):

| Code | Name | Aggregation | Field Name | Unit |
|------|------|-------------|------------|------|
| `llm_input_tokens` | LLM Input Tokens | SUM | `tokens` | tokens |
| `llm_output_tokens` | LLM Output Tokens | SUM | `tokens` | tokens |
| `batch_vcpu_seconds` | Batch vCPU Seconds | SUM | `seconds` | vCPU·s |
| `batch_gpu_seconds` | Batch GPU Seconds | SUM | `seconds` | GPU·s |
| `batch_memory_gb_sec` | Batch Memory GB·s | SUM | `gb_seconds` | GB·s |
| `s3_storage_gb_hours` | S3 Storage | SUM | `gb_hours` | GB·hr |
| `s3_put_requests` | S3 PUT Requests | COUNT | `count` | reqs |
| `s3_get_requests` | S3 GET Requests | COUNT | `count` | reqs |
| `s3_data_transfer_gb` | S3 Data Transfer | SUM | `gb` | GB |

### 4.2 Lago Plan Configuration

Create these plans in Lago UI (Plans):

```
Plan: free
  - Monthly flat fee: $0
  - Charge: llm_input_tokens  → $0.25/1M tokens
  - Charge: llm_output_tokens → $1.25/1M tokens
  - Charge: batch_vcpu_seconds → $0.05/3600 (per vCPU-hour)
  - Charge: s3_storage_gb_hours → $0.023/720 (per GB-month)

Plan: basic
  - Monthly flat fee: $50
  - Same usage charges as free tier
  - Included credits: $50 toward usage

Plan: pro
  - Monthly flat fee: $200
  - 20% discount on all usage charges
  - Included credits: $200

Plan: enterprise
  - Custom pricing negotiated per customer
  - Lago custom plan with negotiated rates
```

### 4.3 Batch Job Submission Code Pattern

```python
# In BioMate's workflow_executor.py

import boto3
from lib.galaxy.ai.billing.core.quota_enforcer import (
    check_and_reserve, estimate_job_cost, QuotaExceededError
)

batch = boto3.client("batch")

def submit_workflow_job(
    user_id: str,
    workflow_id: str,
    job_definition: str,
    instance_type: str,
    vcpus: float,
    memory_mb: int,
    gpu_count: int,
    expected_minutes: float,
    container_overrides: dict,
) -> str:
    # 1. Estimate cost and check quota BEFORE submission
    est_cost = estimate_job_cost(
        instance_type=instance_type,
        vcpus=vcpus,
        memory_mb=memory_mb,
        gpu_count=gpu_count,
        expected_duration_minutes=expected_minutes,
    )
    try:
        check_and_reserve(user_id, estimated_cost_usd=est_cost)
    except QuotaExceededError as e:
        raise  # caller returns HTTP 402

    # 2. Submit the job with required tags
    resp = batch.submit_job(
        jobName=f"biomate-{workflow_id}",
        jobQueue="biomate-cpu-queue",   # or biomate-gpu-queue
        jobDefinition=job_definition,
        containerOverrides=container_overrides,
        tags={
            "user_id":       user_id,
            "workflow_id":   workflow_id,
            "instance_type": instance_type,     # ← KEY: batch_event_handler reads this
            "capacity_type": "ON_DEMAND",       # or "SPOT"
            "service":       "biomate",
        },
    )
    return resp["jobId"]
```

### 4.4 LLM Interceptor Integration

```python
# In existing tracking_decorator.py — add these lines after the LLM call:

from lib.galaxy.ai.billing.core.realtime_cost_service import get_cost_service
from lib.galaxy.ai.billing.core.cost_calculator import CostCalculator
from lib.galaxy.ai.billing.core.lago_client import get_lago_client

calc = CostCalculator()

def _bill_llm_call(user_id: str, session_id: str, model: str,
                   input_tokens: int, output_tokens: int) -> None:
    cost = calc.llm_call_cost(user_id, session_id, model, input_tokens, output_tokens)
    # Write to Redis (real-time dashboard)
    get_cost_service().record_llm_cost(
        user_id=user_id,
        input_usd=cost.input_cost,
        output_usd=cost.output_cost,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
    )
    # Send to Lago (billing)
    get_lago_client().emit_llm(
        user_id=user_id,
        session_id=session_id,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        model=model,
    )
```

### 4.5 S3 Upload Tagging Pattern

```python
# Any code that writes results to S3 must tag the object:

import boto3

s3 = boto3.client("s3")

def upload_result(
    user_id: str,
    workflow_id: str,
    local_path: str,
    bucket: str,
    key: str,
) -> None:
    s3.upload_file(
        local_path, bucket, key,
        ExtraArgs={
            "Tagging": f"user_id={user_id}&workflow_id={workflow_id}",
        }
    )
    # The S3 Lambda picks up the ObjectCreated event automatically.
```

### 4.6 Docker Compose for Local Dev

```yaml
# docker-compose.yml (billing services only)
version: "3.9"
services:

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  lago-db:
    image: postgres:15
    environment:
      POSTGRES_DB:       lago
      POSTGRES_USER:     lago
      POSTGRES_PASSWORD: lago
    volumes: [lago_pg:/var/lib/postgresql/data]

  lago:
    image: getlago/lago:latest
    depends_on: [lago-db]
    ports: ["3000:3000"]
    environment:
      DATABASE_URL:    postgres://lago:lago@lago-db:5432/lago
      REDIS_URL:       redis://redis:6379/1
      SECRET_KEY_BASE: dev-secret-change-in-prod
      LAGO_RSA_PRIVATE_KEY: ""   # generate with: openssl genrsa 2048 | base64

  biomate-billing:
    build: .
    ports: ["8081:8081"]
    environment:
      REDIS_URL:       redis://redis:6379/0
      LAGO_API_URL:    http://lago:3000
      LAGO_API_KEY:    your-lago-api-key
      BILLING_API_KEY: internal-secret
    depends_on: [redis, lago]

volumes:
  lago_pg:
```

### 4.7 Environment Variables Reference

```bash
# BioMate EC2 / container
REDIS_URL=redis://elasticache-endpoint:6379/0
LAGO_API_URL=http://lago-internal-alb:3000
LAGO_API_KEY=lago_api_key_from_lago_ui
LAGO_WEBHOOK_SECRET=webhook_signing_secret
BILLING_API_KEY=internal_service_key   # shared between Lambdas and BioMate

# Lambda functions (set in Lambda console or Terraform)
BILLING_API_URL=http://biomate-internal-alb:8081
BILLING_API_KEY=internal_service_key
USER_TAG_NAME=user_id                  # S3 object tag key
```

### 4.8 IAM Policy for Batch Lambda

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["batch:DescribeJobs"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": ["ec2:CreateNetworkInterface","ec2:DescribeNetworkInterfaces","ec2:DeleteNetworkInterface"],
      "Resource": "*",
      "Condition": { "Comment": "Required when Lambda is VPC-attached" }
    }
  ]
}
```

### 4.9 IAM Policy for S3 Lambda

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObjectTagging", "s3:HeadObject"],
      "Resource": "arn:aws:s3:::biomate-results-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": ["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],
      "Resource": "arn:aws:sqs:*:*:biomate-s3-billing-events"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

---

## Data Flow Summary

```
USER ACTION                  BioMate App           Redis           Lago
─────────────────────────────────────────────────────────────────────────
1. User sends chat
   → LLM called             ─billing_decorator──► record_llm()   emit_llm()
                                                   HINCRBYFLOAT

2. Job submitted
   → quota check            ─check_and_reserve()─► GET quota key
   → Batch job created      ─tags: user_id, ...─►

3. Job starts (RUNNING)
   ← EventBridge            ─Lambda──────────────► register_job() (no Lago yet)
                                                   SETEX running key

4. Every 10s (background)
                            ─poller thread───────► SETEX est_usd updated

5. User polls /api/billing/usage
                            ─FastAPI─────────────► HGETALL + SCAN running keys
                                                   (< 5ms response)

6. Job ends (SUCCEEDED)
   ← EventBridge            ─Lambda──────────────► record_batch_job() emit_batch_job()
                                                   HINCRBYFLOAT     POST /events/batch

7. File uploaded to S3
   ← S3 → SQS              ─Lambda──────────────► record_s3_put()  emit_s3_put()

8. End of month
                            ─Lago auto────────────────────────────► generate invoice
   ← Lago webhook           ─billing_router.py──────────────────── log/notify
```

---

## Testing Checklist

```
[ ] Unit: cost_calculator.py — batch_job_cost() for CPU and GPU instance types
[ ] Unit: cost_calculator.py — s3_put_cost() and s3_get_cost()
[ ] Unit: cost_calculator.py — llm_call_cost() for all model tiers
[ ] Unit: realtime_cost_service.py — record_llm_cost() increments Redis keys correctly
[ ] Unit: quota_enforcer.py — QuotaExceededError raised at correct threshold
[ ] Integration: submit a real Batch job with user_id tag → verify Lambda fires → Redis updated
[ ] Integration: upload to S3 with user_id tag → verify Lambda fires → Redis updated
[ ] Integration: call /api/billing/usage → verify running job estimate included
[ ] Integration: exhaust free-tier quota ($5) → verify job submission returns 402
[ ] Integration: Lago webhook subscription.started → verify quota set in Redis
[ ] End-to-end: full RNA-seq workflow → verify cost shows in /api/billing/usage in < 30s
[ ] Load: 100 concurrent users, each running 1 job → Redis handles concurrent HINCRBYFLOAT
```

---

## Effort Estimate

| Area | Effort |
|------|--------|
| Infrastructure (EventBridge, SQS, Lambda, Redis) | 2 days |
| Lago setup + billable metrics + plans | 1 day |
| Core code (calculator, Redis service, quota) | 2 days (already drafted) |
| Batch/S3 Lambda packaging and deployment | 1 day |
| Billing API + JWT integration | 1 day |
| LLM interceptor integration into existing code | 1 day |
| Job submission tagging | 0.5 days |
| Testing + fixes | 2 days |
| **Total** | **~10.5 days** |

---

## Files Delivered (Draft Code)

```
lib/galaxy/ai/billing/
├── core/
│   ├── cost_calculator.py        ← EC2/S3/LLM pricing, pure functions
│   ├── lago_client.py            ← Lago REST wrapper + event emitters
│   ├── realtime_cost_service.py  ← Redis ledger + background poller
│   └── quota_enforcer.py         ← Pre-job quota check middleware
├── api/
│   └── billing_router.py         ← FastAPI endpoints (public + internal + webhook)
├── lambda/
│   ├── batch_event_handler.py    ← Lambda for Batch EventBridge events
│   └── s3_event_handler.py       ← Lambda for S3 → SQS events
├── infrastructure/
│   └── eventbridge_rules.json    ← EventBridge rule + deploy commands
└── IMPLEMENTATION_PLAN.md        ← This document
```
