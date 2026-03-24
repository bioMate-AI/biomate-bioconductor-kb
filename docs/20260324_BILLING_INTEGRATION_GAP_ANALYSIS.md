# BioMate × Java Billing Service — Integration Gap Analysis & Plan

**Date**: 2026-03-24
**Authors**: BioMate team
**Status**: Draft — for discussion
**Related repo**: `bioMate-AI/billing` (branch: `dev`)
**Java service (dev)**: `http://35.86.137.71:8080`
**Cloned to**: `billing_system/` in project root

---

## 1. Background

Two parallel workstreams produced two billing implementations:

| Component | Owner | Technology | Location |
|---|---|---|---|
| BioMate billing layer | BioMate team | Python / FastAPI | `backend/lib/galaxy/ai/billing/` |
| Billing microservice | Colleague | Java / Spring Boot | `billing_system/` (external repo) |

The BioMate Python layer talks **directly to Lago**. The Java service is a **middleware** that owns Lago, Stripe, PostgreSQL, and Prometheus/Grafana. The goal is to re-route BioMate through the Java service so both systems share one billing source of truth, visible in Grafana.

### Target Architecture

```
BioMate (Python backend + TS frontend)
    │
    ▼
Java Billing Service (:8080)
    ├── POST /api/billing/customers        ← user registration
    ├── POST /api/billing/usage/events     ← usage metering
    ├── GET  /api/billing/usage/current    ← usage query
    ├── GET  /api/billing/usage/summary    ← trend data
    ├── POST /api/billing/quota/acquire    ← before job
    └── POST /api/billing/quota/release    ← after job
         │
         ├── Lago (metering + invoicing)
         ├── Stripe (payment processing)
         ├── PostgreSQL (event journal + customer DB)
         └── Prometheus → Grafana (observability)
```

### Current (to be replaced/re-routed)

```
BioMate Python billing layer
    ├── lago_client.py      → Lago API directly
    ├── realtime_cost_service.py → Redis (local cache)
    ├── quota_enforcer.py   → Redis (local quota check)
    └── billing_router.py   → exposes /api/billing/* to frontend
```

---

## 2. Java Service — API Reference Summary

All endpoints are under `http://<host>:8080/api/billing/`. No authentication on the API currently (internal network only). All responses use `{"code": 0, "message": "success", "data": {...}}` envelope.

### 2.1 Customer Management

#### Create / Update Customer
```
POST /api/billing/customers
Content-Type: application/json

{
  "externalId": "string",      // required — BioMate user ID
  "name":       "string",      // required
  "email":      "string",      // optional
  "currency":   "USD",         // optional
  "country":    "string"       // optional
}
```
- New customer → auto-subscribed to `default_plan` (1-month subscription)
- Existing customer → field-level diff, only changed fields sent to Lago
- Returns `CustomerVO` with `subscriptionId`, `planCode`, `paymentMethodBound`

#### Generate Checkout URL (Stripe payment binding)
```
POST /api/billing/customers/{externalId}/checkout-url
→ { "checkoutUrl": "https://checkout.stripe.com/pay/cs_xxx..." }
```

#### Terminate Subscription
```
DELETE /api/billing/customers/{externalCustomerId}
```

### 2.2 Usage Events

#### Report Usage Event
```
POST /api/billing/usage/events
Content-Type: application/json

{
  "externalCustomerId": "string",     // required
  "code":               "string",     // required — see event codes below
  "transactionId":      "string",     // optional — UUID auto-generated if absent
  "timestamp":          1742000000.0, // optional — Unix epoch
  "properties":         {}            // code-dependent
}
```

**Supported event codes and required properties:**

| `code` | Description | Required properties |
|---|---|---|
| `ec2_instance` | AWS EC2 compute (converted to Credits) | `instanceType` (e.g. `m5.large`), `region` (e.g. `us-west-2`), `value` (seconds as string) |
| `ebs_storage` | AWS EBS storage (converted to Credits) | `volumeType` (e.g. `gp3`), `sizeGb` (integer), `value` (seconds as string) |
| `llm` | LLM API call (pass-through) | `model` (e.g. `claude-sonnet-4-6`), `value` (token count or quantity as string) |
| *(custom)* | Any other code (pass-through) | `value` (or `units`/`count`/`amount` — first found wins; defaults to 1) |

**Credit conversion** (Java service internal):
- EC2: `credits = ceil(pricePerHr × value_seconds / 3600 / 0.001)`, min 10 credits
- EBS: `credits = ceil(size_gb × pricePerGbMonth × value_seconds / (30×24×3600) / 0.001)`
- 1 Credit = $0.001 USD

#### Query Current Usage (live from Lago)
```
GET /api/billing/usage/current?externalCustomerId=<id>
→ {
    "fromDatetime": "...", "toDatetime": "...",
    "amountCents": 15000, "totalAmountCents": 16500, "currency": "USD",
    "charges": [
      {"code": "ec2", "amountCents": 10000, "units": 500.0, "eventsCount": 120},
      {"code": "llm", "amountCents": 5000,  "units": 1000.0, "eventsCount": 1000}
    ]
  }
```

#### Query Usage Details (paginated, from local DB)
```
GET /api/billing/usage/details
  ?externalCustomerId=<id>
  &startDate=2026-03-01
  &endDate=2026-03-31
  &page=0&size=20
```

#### Query Usage Summary (trend data for dashboards)
```
GET /api/billing/usage/summary
  ?externalCustomerId=<id>
  &startDate=2026-03-01
  &endDate=2026-03-31
→ {
    "byCode": [
      {"code": "ec2_instance", "lagoMetricCode": "ec2", "totalUnits": 2400, "eventCount": 50},
      {"code": "llm",          "lagoMetricCode": "llm", "totalUnits": 1200, "eventCount": 1200}
    ],
    "dailyTrend": [
      {"date": "2026-03-15", "code": "ec2_instance", "totalUnits": 96, "eventCount": 2}
    ]
  }
```

### 2.3 Quota (Concurrent Resource Slots)

```
POST /api/billing/quota/acquire
{ "externalCustomerId": "...", "specCode": "gpu.1x", "resourceId": "<run_id>" }

POST /api/billing/quota/release
{ "externalCustomerId": "...", "specCode": "gpu.1x", "resourceId": "<run_id>" }

GET /api/billing/quota/usage?externalCustomerId=<id>
→ per-metric quota limits and current usage
```

### 2.4 Invoices

```
GET /api/billing/invoices?externalCustomerId=<id>&page=0&perPage=10
GET /api/billing/invoices/{lagoId}
```

### 2.5 Observability

```
GET /actuator/health       — service health
GET /actuator/prometheus   — Prometheus metrics scrape endpoint
```

Grafana dashboard pre-built at `billing_system/monitoring/grafana/dashboards/billing-overview.json`.
Prometheus + Grafana stack: `billing_system/monitoring/docker-compose.yml`.

---

## 3. Gap Analysis

### GAP 1 — Customer Registration (Blocker for everything else)

**Current behaviour**: BioMate's `POST /internal/billing/register_user` calls `lago_client.upsert_customer()` → Lago directly. The Java service has no record of any BioMate user. All usage event calls to the Java service will fail with error `2003: 客户无有效订阅` (no active subscription).

**Required change**: On BioMate user sign-up (and for existing users via backfill), call:
```
POST /api/billing/customers
{ "externalId": "<user.id>", "name": "<fullName>", "email": "<email>", "currency": "USD" }
```

**Open question**: `externalId` convention. Options:
- Raw UUID: `"550e8400-e29b-41d4-a716-446655440000"`
- Prefixed: `"bm_550e8400"` (easier to identify in Lago/Java DB)
- **Recommendation**: prefixed `bm_{user.id}` to namespace BioMate users from any future tenants.

---

### GAP 2 — Event Schema Mismatch (Core Integration Problem)

BioMate's Python `lago_client.py` emits **granular metric events** directly to Lago. The Java service expects **coarser event codes**. These do not map 1:1:

| BioMate Python event | Java service event | Mapping difficulty |
|---|---|---|
| `llm_input_tokens` + `llm_output_tokens` (separate) | `llm` (combined) | **Medium** — need to combine or change |
| `batch_vcpu_seconds` | `ec2_instance` with `instanceType`+`region` | **Hard** — need instance metadata |
| `batch_gpu_seconds` | `ec2_instance` (GPU instance type) | **Hard** — same |
| `batch_memory_gb_sec` | *(no equivalent)* | **Gap** — missing in Java service |
| `s3_storage_gb_hours` | `ebs_storage` (EBS semantics, not S3) | **Hard** — semantically different |
| `s3_put_requests` / `s3_get_requests` | *(no equivalent)* | **Gap** — missing in Java service |

**Decision needed** (discuss with colleague):

Option A — **BioMate adapts**: collapse granular events to match Java service's schema. Lose input/output token breakdown. Drop S3 + memory tracking.

Option B — **Java service extends**: colleague adds `llm_input`, `llm_output`, `batch_memory`, `s3_put`, `s3_get` event codes. Full granularity preserved.

Option C — **Hybrid**: BioMate sends `llm` combined to Java service for billing, AND keeps sending granular events to Lago directly for analytics. Double-write during transition.

**Recommendation**: Option B for LLM (input/output split matters for cost accuracy), Option A for S3 (acceptable to track storage as EBS equivalent).

---

### GAP 3 — Compute Event Source: Missing Instance Metadata

**Current**: AWS Lambda (`batch_event_handler.py`) fires `POST /internal/billing/job_completed` → `lago_client.emit_batch_job(vcpus, gpu_count, memory_gb, duration_seconds)`. No instance type or region in the payload.

**Java service needs**: `instanceType` (e.g. `m5.2xlarge`) + `region` (e.g. `us-west-2`) to look up EC2 price from its DB and convert to Credits.

**Required change**: Lambda must extract `containerInstanceArn` from the Batch event → call AWS ECS/Batch API to resolve the EC2 instance type → include in the billing event payload.

Alternatively: BioMate passes instance type when submitting the Nextflow job and stores it in run metadata (`_runs[run_id]`).

---

### GAP 4 — Usage Display: Frontend Data Source

**Current**: BioMate billing page (`frontend/client/src/pages/billing.tsx`) calls Python endpoints → Redis for real-time cost data. Python layer owns the display.

**Target**: Java service is source of truth for billing data. Two options:

**Option A — Proxy** (recommended): BioMate's Python `GET /api/billing/usage` proxies to Java service's `GET /api/billing/usage/current`. Frontend unchanged. BioMate adds Java service client in billing_router.py.

**Option B — Direct**: Frontend calls Java service directly. Requires CORS config and auth on Java service. Higher coupling.

**What changes on the BioMate side**:
- `GET /api/billing/usage` → proxy to `/api/billing/usage/current?externalCustomerId=bm_{user.id}`
- `GET /api/billing/usage/history` → proxy to `/api/billing/usage/summary` with date ranges
- `GET /api/billing/quota` → proxy to `/api/billing/quota/usage`
- Invoice endpoints → proxy to `/api/billing/invoices`

---

### GAP 5 — Quota Enforcement: Split Authority

**Current**: `quota_enforcer.py` reads Redis before job submission. Fast (<1ms) but only BioMate-local — doesn't coordinate with other services.

**Java service has**: `POST /api/billing/quota/acquire` + `release` for concurrent GPU/resource slots, backed by Lago plan metrics.

**Required change**:
1. Before `nextflow_executor.py` submits a run → `POST /api/billing/quota/acquire` with `specCode` = GPU spec of the workflow, `resourceId` = run ID.
2. On run completion (success or failure) → `POST /api/billing/quota/release` with same `resourceId`.
3. On BioMate server restart → release any acquired slots for runs no longer in `_runs` dict (orphan cleanup).

Redis quota check can remain as a fast local pre-check; Java service is the authoritative gate.

---

### GAP 6 — Per-User Tracking in Grafana

**Current state**: The Java service's Prometheus metrics are **aggregate only** (total events processed, total credits consumed). The existing `billing-overview.json` Grafana dashboard shows platform-wide numbers. The dev instance has only one test customer (`kk1`).

**What's needed for per-user tracking**:

1. Every BioMate user registered as a Java service customer (→ GAP 1)
2. Every event tagged with `externalCustomerId = bm_{user.id}` (→ GAPs 1-3)
3. **Grafana data source**: The `billing_raw_event` PostgreSQL table has per-user event records. A Grafana PostgreSQL datasource can query it directly for user-level dashboards.
4. **Prometheus labels**: Check with colleague whether `externalCustomerId` is a label on any Prometheus counters. If yes, Grafana can already filter/group by user without a DB query.

**Proposed per-user Grafana panels**:
- Monthly cost by user (bar chart)
- Top 10 spenders this period
- Per-user: LLM vs compute cost breakdown
- Per-user: daily cost trend
- Quota utilization by user

---

### GAP 7 — No Authentication Between BioMate and Java Service

**Current**: Java service API endpoints have **no inbound auth**. Any caller on the network can submit usage events for any `externalCustomerId`.

**Risk**: A compromised BioMate instance (or any internal service) could submit fraudulent events.

**Short-term**: Acceptable for dev/staging if services are on the same VPC private subnet.

**Production requirement**: Add one of:
- Static API key header (`X-Api-Key`) on all requests, configured via env var on both sides
- mTLS between BioMate and Java service
- VPC security group restriction (Java service port 8080 only reachable from BioMate's security group)

---

### GAP 8 — Subscription Tier Mapping

BioMate has user tiers: `free | academic | professional | enterprise | admin`

Java service uses Lago plan codes (currently only `default_plan` confirmed in dev).

**Required**: Agreement on plan code names and when BioMate triggers `POST /api/billing/customers` with updated plan (or `POST /api/billing/customers/{id}/checkout-url` for upgrade flow).

| BioMate tier | Lago plan code (proposed) |
|---|---|
| `free` | `biomate_free` |
| `academic` | `biomate_academic` |
| `professional` | `biomate_professional` |
| `enterprise` | `biomate_enterprise` |

---

## 4. Integration Plan

### Phase 1 — Registration Bridge (Estimated: 1–2 days)
**Goal**: Every BioMate user exists as a customer in the Java service.

- [ ] Add `BillingServiceClient` class in BioMate Python (thin HTTP client wrapping Java service endpoints)
- [ ] Hook user registration: `POST /api/billing/customers` on new user sign-up
- [ ] Write backfill script: iterate existing users → register any missing ones
- [ ] Agree on `externalId` convention (`bm_{user.id}`)
- [ ] Test: create user → verify in Java service DB → verify Lago customer exists

**Files to change**:
- `backend/lib/galaxy/ai/billing/` — add `java_billing_client.py`
- `frontend/server/routes.ts` — hook `/api/auth/register` success path

---

### Phase 2 — LLM Event Routing (Estimated: 2–3 days)
**Goal**: LLM usage events flow through Java service, visible in Grafana.

- [ ] Decide event schema with colleague: combined `llm` or split `llm_input`/`llm_output`
- [ ] Modify `billing_router.py` `POST /internal/billing/llm_cost` to call `java_billing_client.send_event(code="llm", ...)`
- [ ] Map model names: BioMate uses `claude-sonnet-4-6` → confirm Java service recognises it
- [ ] Verify in Java service Grafana dashboard that events appear per user
- [ ] Keep direct Lago emission as fallback during transition (feature flag `BILLING_USE_JAVA_SERVICE`)

**Files to change**:
- `backend/lib/galaxy/ai/billing/api/billing_router.py`
- `backend/lib/galaxy/ai/billing/core/lago_client.py` (optionally wrap with feature flag)

---

### Phase 3 — Compute (Nextflow/Batch) Event Routing (Estimated: 3–4 days)
**Goal**: Nextflow run costs tracked per user in Java service.

- [ ] Enrich Lambda payload: extract EC2 `instanceType` + `region` from Batch job
- [ ] Modify `batch_event_handler.py` to POST `ec2_instance` event to Java service on job completion
- [ ] Wire `quota/acquire` in `nextflow_executor.py` before Batch submission
- [ ] Wire `quota/release` in `nextflow_executor.py` on run terminal state
- [ ] Add orphan cleanup on executor startup (release stale acquired slots)

**Files to change**:
- `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py`
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

---

### Phase 4 — Usage Query Proxy (Estimated: 1–2 days)
**Goal**: BioMate billing UI reads from Java service.

- [ ] `GET /api/billing/usage` → proxy to Java service `/usage/current`
- [ ] `GET /api/billing/usage/history` → proxy to Java service `/usage/summary` with date range
- [ ] `GET /api/billing/quota` → proxy to Java service `/quota/usage`
- [ ] `GET /api/billing/invoices` → proxy to Java service `/invoices`
- [ ] Frontend billing page: no changes needed (if proxy approach)

**Files to change**:
- `backend/lib/galaxy/ai/billing/api/billing_router.py`

---

### Phase 5 — Per-User Grafana Dashboards (Estimated: 2–3 days)
**Goal**: Grafana shows usage broken down by individual BioMate user.

- [ ] Confirm with colleague: does Java service emit `externalCustomerId` as Prometheus label?
- [ ] Add PostgreSQL datasource to Grafana pointing at Java service's DB
- [ ] Build per-user panels: top spenders, per-user daily trend, LLM vs compute split
- [ ] Extend `billing-overview.json` dashboard with user-drill-down row

---

### Phase 6 — Production Hardening (Estimated: 1–2 days)
**Goal**: Secure the integration.

- [ ] Add `X-Api-Key` header to all BioMate → Java service requests
- [ ] Java service: add API key validation middleware (discuss with colleague)
- [ ] Verify both services in same VPC security group
- [ ] Set up Prometheus alert rules for billing event failure rate (>1% triggers alert)

---

## 5. Open Questions for Discussion

| # | Question | Who decides |
|---|---|---|
| Q1 | `externalId` format: raw UUID vs `bm_{uuid}`? | Both teams |
| Q2 | LLM events: combined `llm` (simple) or split `llm_input`/`llm_output` (accurate)? | Both teams |
| Q3 | What to do with `batch_memory_gb_sec` — add to Java service or drop? | Both teams |
| Q4 | S3 events: map to `ebs_storage` (approximate) or add real S3 event codes to Java service? | Both teams |
| Q5 | Lago plan codes for each BioMate tier? What are current plans configured in Lago? | Colleague |
| Q6 | Does Java service Prometheus emit per-`externalCustomerId` labels on any metrics? | Colleague |
| Q7 | Timeline for adding API key auth to Java service? | Colleague |
| Q8 | Java service DB host/credentials for Grafana PostgreSQL datasource? | Colleague |
| Q9 | Should BioMate stop calling Lago directly immediately, or dual-write during transition? | Both teams |

---

## 6. Current State Summary

| Capability | BioMate Python layer | Java service | After integration |
|---|---|---|---|
| User registration | ✅ Lago only | ❌ Not called | ✅ Java service → Lago |
| LLM cost tracking | ✅ Lago direct | ⚠️ Only test user `kk1` | ✅ Java service → Lago |
| Compute cost tracking | ✅ Lago direct | ⚠️ Missing instance metadata | ✅ Java service → Lago |
| S3 cost tracking | ✅ Lago direct | ❌ No equivalent events | ⚠️ Partial (map to EBS) |
| Quota enforcement | ✅ Redis local | ✅ Lago-backed slots | ✅ Both, Java authoritative |
| Usage display | ✅ Redis cache | ✅ Lago live | ✅ Proxy to Java service |
| Invoice access | ❌ None | ✅ Lago-backed | ✅ Proxy to Java service |
| Per-user Grafana | ❌ None | ❌ Aggregate only | ✅ (Phase 5) |
| Stripe payment flow | ✅ Frontend direct | ✅ Via Lago checkout URL | ✅ Consolidate to Java service |
| Prometheus metrics | ❌ None | ✅ `/actuator/prometheus` | ✅ BioMate feeds Java service |
