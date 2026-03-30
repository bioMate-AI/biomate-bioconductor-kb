# BioMate → Java Billing Service: Remote Lago Revision Spec

**Date:** 2026-03-25
**Author:** BioMate team
**Purpose:** This document gives the colleague everything needed to reconfigure the remote Lago instance
and the Java billing service so that BioMate's detailed cost tracking is preserved end-to-end.

---

## 1. Problem with Current Remote Lago Config

The remote Lago (35.86.137.71) currently has **3 coarse metrics and wrong plans**:

| Current metric code | Problem |
|---------------------|---------|
| `ec2` | Mixes vCPU + GPU + memory into one number — cannot break down cost by resource type |
| `gp3` | Only one S3 metric — cannot distinguish storage vs requests vs transfer |
| `llm` | Combines input and output tokens — cannot apply different per-token pricing |

| Current plan | Problem |
|--------------|---------|
| `free` / `base` / `pro` | Weekly billing period — BioMate uses monthly |
| `base` at $7/week | Wrong price — BioMate `basic` plan is $0 base fee (pure usage-based) |
| Missing `enterprise` | |
| All plans have 0 active subscriptions | Nobody is on a plan yet |

---

## 2. Required Billable Metrics (9 total)

All metrics: aggregation = **`sum_agg`**, group_by = none, recurring = no.

The Java service should forward these exact `code` values to Lago unchanged.

### 2.1 LLM Tokens

| Field | Value |
|-------|-------|
| **Name** | LLM Input Tokens |
| **Code** | `llm_input_tokens` |
| **Field name** | `tokens` |
| **Description** | AI assistant input (prompt) tokens per API call |

| Field | Value |
|-------|-------|
| **Name** | LLM Output Tokens |
| **Code** | `llm_output_tokens` |
| **Field name** | `tokens` |
| **Description** | AI assistant output (completion) tokens per API call |

> Input and output are separate because they have different prices (output costs 5× more).

### 2.2 AWS Batch Compute

| Field | Value |
|-------|-------|
| **Name** | Batch vCPU-Seconds |
| **Code** | `batch_vcpu_seconds` |
| **Field name** | `seconds` |
| **Description** | vCPU × duration_seconds for completed Batch jobs |

| Field | Value |
|-------|-------|
| **Name** | Batch GPU-Seconds |
| **Code** | `batch_gpu_seconds` |
| **Field name** | `seconds` |
| **Description** | GPU count × duration_seconds for GPU Batch jobs |

| Field | Value |
|-------|-------|
| **Name** | Batch Memory GB-Seconds |
| **Code** | `batch_memory_gb_sec` |
| **Field name** | `gb_seconds` |
| **Description** | memory_GB × duration_seconds for completed Batch jobs |

### 2.3 S3 Storage & Operations

| Field | Value |
|-------|-------|
| **Name** | S3 Storage GB-Hours |
| **Code** | `s3_storage_gb_hours` |
| **Field name** | `gb_hours` |
| **Description** | GB × retention_hours projection (30-day default) |

| Field | Value |
|-------|-------|
| **Name** | S3 PUT Requests |
| **Code** | `s3_put_requests` |
| **Field name** | `count` |
| **Description** | Number of PUT/COPY/POST/LIST operations |

| Field | Value |
|-------|-------|
| **Name** | S3 GET Requests |
| **Code** | `s3_get_requests` |
| **Field name** | `count` |
| **Description** | Number of GET/SELECT operations |

| Field | Value |
|-------|-------|
| **Name** | S3 Data Transfer GB |
| **Code** | `s3_data_transfer_gb` |
| **Field name** | `gb` |
| **Description** | Outbound data transfer in GB (egress only; ingress is free) |

---

## 3. Required Plans (4 total)

All plans: billing period = **monthly**, currency = **USD**.

### 3.1 Free Plan

| Field | Value |
|-------|-------|
| **Code** | `free` |
| **Base fee** | $0.00/month |
| **Trial** | None |
| **Spend cap** | $5.00/month (enforced by BioMate quota enforcer) |

Charges on all 9 metrics at $0 (tracking only — so usage appears in Lago even if not billed).

### 3.2 Basic Plan

| Field | Value |
|-------|-------|
| **Code** | `basic` |
| **Base fee** | $0.00/month (pure usage-based, no subscription fee) |
| **Trial** | 7 days free |
| **Spend cap** | $50.00/month |

Charges:

| Metric code | Model | Rate | Package size | Free units |
|-------------|-------|------|--------------|------------|
| `llm_input_tokens` | package | $3.00 / 1M tokens | 1,000,000 | 1,000,000 |
| `llm_output_tokens` | package | $15.00 / 1M tokens | 1,000,000 | 200,000 |
| `batch_vcpu_seconds` | graduated | $0.01126 / 1K vCPU-sec | — | 10,000 vCPU-sec |
| `batch_gpu_seconds` | graduated | $0.85 / 1K GPU-sec | — | 0 |
| `batch_memory_gb_sec` | graduated | $0.001235 / 1K GB-sec | — | 100,000 GB-sec |
| `s3_storage_gb_hours` | graduated | $0.000032 / GB-hr | — | 720 GB-hr (1 GB/month) |
| `s3_put_requests` | package | $0.005 / 1K | 1,000 | 1,000 |
| `s3_get_requests` | package | $0.0004 / 1K | 1,000 | 5,000 |
| `s3_data_transfer_gb` | graduated | $0.09 / GB | — | 1 GB |

### 3.3 Pro Plan

| Field | Value |
|-------|-------|
| **Code** | `pro` |
| **Base fee** | $20.00/month, pay in advance |
| **Trial** | None |
| **Spend cap** | $500.00/month |

Same metric charges as `basic` but with larger free tiers:

| Metric code | Free units |
|-------------|------------|
| `llm_input_tokens` | 5,000,000 |
| `llm_output_tokens` | 1,000,000 |
| `batch_vcpu_seconds` | 100,000 |
| `batch_memory_gb_sec` | 1,000,000 |
| `s3_storage_gb_hours` | 7,200 (10 GB/month) |
| `s3_put_requests` | 10,000 |
| `s3_get_requests` | 50,000 |
| `s3_data_transfer_gb` | 10 GB |

### 3.4 Enterprise Plan

| Field | Value |
|-------|-------|
| **Code** | `enterprise` |
| **Base fee** | Custom (set per contract) |
| **Spend cap** | Unlimited |

All metric charges at $0 (billed via Stripe invoice outside Lago) — or configure custom rates per customer.

---

## 4. Customer & Subscription ID Convention

BioMate uses these ID formats — the Java service must register customers using the same convention:

```
externalId (customer):     bm_{user_uuid}
externalId (subscription): sub_{user_uuid}
```

Examples already in remote Lago:
- `bm_1c4e4c90-4c4f-4a60-807f-f2ec0ca070a5` — real BioMate user ✓
- `bm_test-smoke-001` — smoke test user ✓

**Action required:** When registering a new customer via `POST /api/billing/customers`, also create a subscription to the `free` plan (or the plan matching the user's tier). Currently all 36 existing customers have 0 subscriptions — events cannot be recorded without an active subscription.

---

## 5. Event Payload Format BioMate Sends

BioMate will POST to `POST /api/billing/usage/events` with this shape for each event type:

### LLM input tokens
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "llm_input_tokens",
  "transactionId": "llm-in-{session_id}-{hex12}",
  "timestamp": 1711234567.89,
  "properties": { "tokens": 1250, "model": "claude-sonnet-4-6" }
}
```

### LLM output tokens
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "llm_output_tokens",
  "transactionId": "llm-out-{session_id}-{hex12}",
  "timestamp": 1711234567.89,
  "properties": { "tokens": 320, "model": "claude-sonnet-4-6" }
}
```

### Batch vCPU-seconds
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "batch_vcpu_seconds",
  "transactionId": "batch-vcpu-{job_id}",
  "timestamp": 1711234567.89,
  "properties": { "seconds": 338.0, "instanceType": "m6i.xlarge" }
}
```

### Batch GPU-seconds (only for GPU jobs)
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "batch_gpu_seconds",
  "transactionId": "batch-gpu-{job_id}",
  "timestamp": 1711234567.89,
  "properties": { "seconds": 169.0, "instanceType": "g4dn.xlarge" }
}
```

### Batch memory GB-seconds
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "batch_memory_gb_sec",
  "transactionId": "batch-mem-{job_id}",
  "timestamp": 1711234567.89,
  "properties": { "gb_seconds": 2704.0, "instanceType": "m6i.xlarge" }
}
```

### S3 storage
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "s3_storage_gb_hours",
  "transactionId": "s3-store-{hex8}",
  "timestamp": 1711234567.89,
  "properties": { "gb_hours": 0.003072 }
}
```

### S3 PUT request
```json
{
  "externalCustomerId": "bm_{user_id}",
  "code": "s3_put_requests",
  "transactionId": "s3-put-{hex8}",
  "timestamp": 1711234567.89,
  "properties": { "count": 1, "key": "users/{uid}/uploads/..." }
}
```

---

## 6. Lago API Key

**Important:** The Lago API key was rotated during investigation on 2026-03-25.

New API key: `01b71711-be39-49af-8d14-87a4ee827157`

Update this in the Java service's configuration (`application.yml` or environment variable that controls `lago.api.key`).

---

## 7. Summary of Changes Required

| # | What | Where | Priority |
|---|------|-------|----------|
| 1 | Delete 3 existing metrics (`ec2`, `gp3`, `llm`) | Remote Lago admin | Required |
| 2 | Create 9 new billable metrics (see §2) | Remote Lago admin | Required |
| 3 | Delete/recreate plans with monthly billing (see §3) | Remote Lago admin | Required |
| 4 | On `register_customer`: also create subscription to `free` plan | Java service code | Required |
| 5 | Update Lago API key to `01b71711-be39-49af-8d14-87a4ee827157` | Java service config | Required |
| 6 | Java service must forward `code` field to Lago unchanged (no translation) | Java service code | Verify |
| 7 | `POST /api/billing/usage/events` must accept the `properties` object and pass it to Lago | Java service code | Verify |

---

## 8. Pricing Reference (from BioMate cost_calculator.py)

### LLM (per 1M tokens)

| Model | Input | Output |
|-------|-------|--------|
| claude-opus-4-6 | $15.00 | $75.00 |
| claude-sonnet-4-5 | $3.00 | $15.00 |
| claude-haiku-4-5 | $0.25 | $1.25 |
| default (unknown model) | $3.00 | $15.00 |

### EC2 Instances (us-east-1, on-demand)

| Instance | vCPU | Mem | GPU | $/hr |
|----------|------|-----|-----|------|
| m6i.large | 2 | 8 GB | — | $0.096 |
| m6i.xlarge | 4 | 16 GB | — | $0.192 |
| m6i.2xlarge | 8 | 32 GB | — | $0.384 |
| m6i.4xlarge | 16 | 64 GB | — | $0.768 |
| c6i.large | 2 | 4 GB | — | $0.085 |
| c6i.2xlarge | 8 | 16 GB | — | $0.340 |
| g4dn.xlarge | 4 | 16 GB | 1 | $0.526 |
| g4dn.2xlarge | 8 | 32 GB | 1 | $0.752 |
| g5.xlarge | 4 | 16 GB | 1 | $1.006 |
| p3.2xlarge | 8 | 61 GB | 1 | $3.060 |
| p4d.24xlarge | 96 | 1152 GB | 8 | $32.77 |
| FARGATE (vCPU) | — | — | — | $0.04048/vCPU-hr |
| FARGATE (mem) | — | — | — | $0.004445/GB-hr |

Spot discount: ~65% (multiply EC2 price × 0.35 for Spot).

### S3 (us-east-1)

| Operation | Rate |
|-----------|------|
| Storage STANDARD | $0.023/GB-month |
| PUT/COPY/LIST | $0.005/1K requests |
| GET/SELECT | $0.0004/1K requests |
| Data transfer OUT | $0.09/GB (first 10 TB/month) |
| Data transfer IN | Free |
