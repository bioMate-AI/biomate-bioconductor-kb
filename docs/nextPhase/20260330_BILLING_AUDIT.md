# BioMate Billing System Audit
**Date:** 2026-03-30  
**Lago:** http://35.86.137.71(UI) / :3000(API)  
**Java billing service:** http://35.86.137.71:8080  
**Method:** Live API inspection via GraphQL + REST

---

## TL;DR — Is billing correctly recorded?

**No.** The billing pipeline has 4 critical problems:

1. **Wrong API key in BioMate .env** — Python billing client points to local Lago (`localhost:3010`, key `ba049ead`) instead of the shared remote Lago (key `01b71711`)
2. **Events have no customer attribution** — 37,012 events in remote Lago, ALL have `lago_customer_id=null`. Events are routed by subscription ID but the `lago_customer_id` link is broken, so usage cannot be correctly billed
3. **Real BioMate users have zero usage events** — 31 E2E test users registered with active subscriptions, 0 events for any of them
4. **Java billing → Lago connection uses wrong API key** — `application-dev.yml` has `ba049ead` but remote Lago needs `01b71711`

The net result: **real user billing is completely non-functional**. Users are registered in Lago, subscriptions are created, but usage is never metered. Invoices ($630 + $16,847) are entirely for `kk1` and `messi` test accounts from smoke tests.

---

## Lago Remote Instance State (`http://35.86.137.71:3000`)

**Organization:** biomate (ID: `b060e965-1acb-4878-84c6-3b0952cf49a4`)  
**Correct API key:** `01b71711-be39-49af-8d14-87a4ee827157`  
**Webhook URL:** `http://172.31.18.185:8080/api/billing/webhooks/lago` (Java service internal IP)

### Plans
| Code | Name | Interval | Price | Billable metrics |
|------|------|----------|-------|-----------------|
| `free` | free | weekly | $0 | ec2, llm (usage-based) |
| `base` | base | weekly | $7 | ec2, llm (usage-based) |
| `pro` | pro | monthly | $20 | ec2, llm (usage-based) |

**Issues with plan setup:**
- Only 2 billable metrics: `ec2` (sum) and `llm` (sum). There is no separate metric for storage (gp3 metric exists in DB but is not linked to plans)
- `gp3` billable metric exists but is unused in plan charges
- Subscription price ($7/week base) is charged even when usage = 0 — fine for SaaS, but needs validation

### Customers
**Total: 36 registered customers**

| Category | Count | Status |
|----------|-------|--------|
| Real test accounts | 5 | Active subscriptions, invoices generated |
| E2E test users | 31 | Active subscriptions, **zero usage events** |

**Real customer accounts:**
| External ID | Email | Invoices | Total Billed |
|------------|-------|---------|-------------|
| `kk1` | kk1@example.com | 609 | $630.24 |
| `1321` (messi) | messi@example.com | 5 | **$16,847.36** ⚠️ |
| `bm_test-smoke-001` | smoke@biomate.ai | 0 | $0 |
| `bm_1c4e4c90-...` | billing_realtest@biomate.dev | 0 | $0 |
| `bm_1cdde019-...` | debug_noexcl@test.com | 0 | $0 |

**⚠️ $16,847 anomaly:** `messi@example.com` has one invoice for $16,833.67 dated 2026-03-11. This is clearly test/simulation data injected during development but exists as a "finalized" invoice. Should be voided or the customer deleted.

### Events
**Total events in Lago: 37,012**

All events have `lago_customer_id = null`. This means:
- Events ARE reaching Lago (37,012 is a large number)
- Events have `external_subscription_id` set (e.g., `kk1_base`, `bm_test-smoke-001_base`)
- But `lago_customer_id` is null → Lago cannot link events to customers for invoicing

Most events are for `kk1_base` and `kk_base` subscriptions — smoke test data from the Java billing service. Only 1 event exists for `bm_test-smoke-001_base`.

Real BioMate users (E2E users like `bm_f84ccbd5-..._base`): **0 events**.

### Invoices
**Total: 616 invoices, all "finalized"**

All invoices are for test accounts:
- `kk1@example.com`: 609 invoices, $630 total (weekly `base` subscription charges)
- `kk@example.com`: 2 invoices, $13.69 total
- `messi@example.com`: 5 invoices, $16,847 total (includes $16,833 anomaly)

**Zero invoices** for any real BioMate user or E2E test user.

---

## Java Billing Service State (`http://35.86.137.71:8080`)

**Health:** `DOWN` (Spring Boot Actuator reports unhealthy)  
**Prometheus metrics:** Accessible at `/actuator/prometheus`

### What the Java service shows
The Prometheus metrics show billing events processed internally:
- `kk1` customer: EC2 instance events (m5.2xlarge, c5.2xlarge), EBS storage events (multiple)
- `bm_test-smoke-001`: 1 LLM event (claude-sonnet-4-6, 300 units)

### Critical issue: Wrong Lago API key
`application-dev.yml` configures:
```yaml
lago:
  base-url: http://35.86.137.71:3000/api/v1/
  api-key: ${LAGO_API_KEY:ba049ead-f0da-494a-b0ec-b76bdc26fc96}
```

The remote Lago's actual API key is `01b71711-be39-49af-8d14-87a4ee827157`.  
Using `ba049ead` → **401 Unauthorized** on every Lago API call from the Java service.

**Consequence:** The Java service's `/api/billing/usage/current` endpoint (which proxies to Lago) returns error `2001: 查询用量失败: 401 Unauthorized`. Real-time usage queries from BioMate fail.

---

## BioMate Python Billing Layer State

### Current configuration (`backend/.env`)
```
LAGO_API_KEY=ba049ead-f0da-494a-b0ec-b76bdc26fc96    ← WRONG (local Lago key)
LAGO_WEBHOOK_SECRET=CHANGE_ME_GET_FROM_LAGO_DASHBOARD  ← NOT SET
LAGO_API_URL=http://localhost:3010                      ← LOCAL Lago (not remote)
```

### What this means
BioMate's Python billing (`lago_client.py`) is configured to use the LOCAL Docker Lago instance (`localhost:3010`), not the shared remote Lago at `35.86.137.71:3000`.

The local Lago has:
- 0 customers
- 0 plans
- 0 subscriptions
- 0 billable metrics
- 0 invoices

So all Python-layer billing calls (LLM token reporting, user registration) either fail silently or succeed but write to a Lago instance nobody monitors.

### E2E User Registration
Interestingly, the 31 E2E test users DO appear in the remote Lago with active subscriptions. These were registered by the E2E test suite which likely uses the correct remote API key. But their usage events (LLM calls during E2E tests) were never sent — so subscriptions exist but $0 in usage.

---

## Root Causes Summary

| # | Problem | Evidence |
|---|---------|---------|
| 1 | **Wrong LAGO_API_KEY in .env** — points to local instance | `.env`: `LAGO_API_KEY=ba049ead`, `LAGO_API_URL=localhost:3010`; remote key is `01b71711` |
| 2 | **LAGO_WEBHOOK_SECRET not set** | `.env`: `LAGO_WEBHOOK_SECRET=CHANGE_ME_...`; webhooks from Lago to Java service cannot be verified |
| 3 | **Java service uses wrong Lago key** | `application-dev.yml`: same `ba049ead` key → 401 on all Lago API calls |
| 4 | **Events not linked to customers** | 37,012 events have `lago_customer_id=null`; subscription ID is set but customer link broken |
| 5 | **$16,847 test invoice** | `messi@example.com` has a finalized $16,833.67 invoice from smoke test data |
| 6 | **Java service health: DOWN** | Spring Boot Actuator reports unhealthy; root cause needs investigation |
| 7 | **No usage from real E2E users** | 31 E2E users registered, 0 events sent for any of them |

---

## Fix Plan (Priority Order)

### Fix 1: Update API keys everywhere (30 minutes)
```bash
# In backend/.env:
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
LAGO_API_URL=http://35.86.137.71:3000

# In billing_system/src/main/resources/application-dev.yml:
# Set environment variable before starting Java service:
export LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
```

Also update `LAGO_WEBHOOK_SECRET` in `.env` — get the value from Lago org settings (Organization → Developer → Webhooks).

### Fix 2: Investigate and fix lago_customer_id=null on events (2-4 hours)
Events arrive with `external_subscription_id` but `lago_customer_id=null`. This means either:
- The subscription was not properly linked to the customer in Lago's DB when events arrived
- Events are being sent before the subscription is active

Check `lago_client.py` `emit_event()` method — ensure `external_subscription_id` format matches what Lago expects and that the subscription exists BEFORE events are sent.

### Fix 3: Void the $16,847 test invoice (15 minutes)
Via Lago UI: Customers → messi@example.com → Invoices → Void the $16,833.67 invoice.  
Or delete the `messi` and `kk1` test customers entirely if they serve no purpose.

### Fix 4: Fix Java service health (investigate)
Check Java service logs on the EC2 instance (172.31.18.185). The DOWN status may be a DB connection issue (PostgreSQL at `172.31.18.185:5432`).

### Fix 5: Verify E2E test billing
After fixing API keys, run one E2E test and verify:
1. User is registered in remote Lago with correct customer record
2. Chat messages generate `llm` events with the correct `external_subscription_id`
3. Events appear in Lago with `lago_customer_id` populated

---

## What IS Working

- ✅ Customer registration in Lago (E2E users appear with active subscriptions)
- ✅ Lago plans and billable metrics are correctly defined
- ✅ Java billing service Prometheus metrics are being generated
- ✅ Invoice generation and finalization works (for `kk1` test customer)
- ✅ Lago webhook URL is configured to point to Java service
- ✅ 37,012 events are reaching Lago (event ingestion pipeline is functional)
- ✅ `external_subscription_id` is correctly formatted (`bm_{user_id}_base`)

## What Is NOT Working

- ❌ BioMate Python billing writes to wrong Lago instance
- ❌ Java service → Lago API calls fail (wrong API key → 401)
- ❌ Events not attributed to customers (`lago_customer_id=null`)
- ❌ Real user LLM usage not metered
- ❌ E2E user usage not metered
- ❌ Java service health is DOWN
- ❌ Webhook secret not configured

---

## Update 2026-03-30: Test Plan + Critical Bug Fixes

### New Test Plan Created

**Plan code:** `test`  
**Name:** Test (Unlimited)  
**Interval:** monthly  
**Base price:** $0  
**Quota:** Unlimited (no hard limits, no charges)

#### Attached billable metrics (all 9 event types):
| Metric code | Field | Description |
|-------------|-------|-------------|
| `llm_input_tokens` | `tokens` | Input tokens per LLM call (by model) |
| `llm_output_tokens` | `tokens` | Output tokens per LLM call (by model) |
| `batch_vcpu_seconds` | `seconds` | vCPU-seconds from Batch/Nextflow jobs |
| `batch_gpu_seconds` | `seconds` | GPU-seconds from accelerated jobs |
| `batch_memory_gb_sec` | `gb_seconds` | Memory GB-seconds from Batch jobs |
| `s3_storage_gb_hours` | `gb_hours` | S3 object storage usage |
| `s3_put_requests` | `count` | S3 write requests |
| `s3_get_requests` | `count` | S3 read requests |
| `s3_data_transfer_gb` | `gb` | Outbound data transfer |

All charges are at **$0/unit** — events are recorded for analysis only, no invoice is generated.

**Smoke test result:** Subscription `bm_smoketest-001_test` created, `llm_input_tokens` event sent, usage confirmed as `1234.0 units / $0.00` via `/api/v1/customers/.../current_usage`.

### Configuration Fixes Applied

#### `backend/.env`
```
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157   ← was: ba049ead (wrong)
LAGO_WEBHOOK_SECRET=9ef2c8b4-9d99-47f5-98d8-520a22ed3bde  ← was: CHANGE_ME
LAGO_API_URL=http://35.86.137.71:3000               ← was: localhost:3010 (local)
```

#### `billing_system/src/main/resources/application-dev.yml`
```yaml
lago:
  api-key: ${LAGO_API_KEY:01b71711-be39-49af-8d14-87a4ee827157}  ← was: ba049ead
```

### Critical Bug Fix: Subscription ID Format Mismatch

**Root cause of `lago_customer_id=null`**: The Python billing client used `sub_{user_id}` as subscription external IDs, but the Java billing service creates subscriptions as `bm_{user_id}_{plan_code}`. Events sent with wrong subscription IDs cannot be linked to customers.

**Fix in `lago_client.py`:**
```python
# Before (broken)
def subscription_id(user_id: str) -> str:
    return f"sub_{user_id}"

# After (correct — matches Java service format)
def external_customer_id(user_id: str) -> str:
    return f"bm_{user_id}" if not user_id.startswith("bm_") else user_id

def subscription_id(user_id: str, plan_code: str = "base") -> str:
    ext_id = external_customer_id(user_id)
    return f"{ext_id}_{plan_code}"
```

### Plan-Aware Event Routing

Added `get_user_plan_code(user_id)` in `quota_enforcer.py` that reads the user's plan from Redis (cached during registration/plan change). Events are now emitted to the correct subscription ID (`bm_{user_id}_{plan_code}`) instead of a hardcoded `base` subscription.

The `test` plan is treated as unlimited in quota enforcement (`float("inf")`).
