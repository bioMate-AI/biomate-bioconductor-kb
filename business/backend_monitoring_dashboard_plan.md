# BioMate — Backend Monitoring Dashboard: Current State & Improvement Plan
*Engineering · March 2026 · Internal*

---

## What Is Already Built

BioMate has a solid monitoring foundation. This document describes what exists, what each component covers, and where the gaps are for production-grade backend observability during the pilot study.

---

### 1. Error-Rate Dashboard (Backend API)

**Endpoint:** `GET /api/admin/error-rates`
**Where:** `frontend/server/routes.ts`

Returns 7-day aggregated error metrics, computed from the telemetry `api_request` event stream:

```json
{
  "period": "7d",
  "metrics": {
    "error_rate_5xx_pct":  0.42,
    "timeout_rate_pct":    0.18,
    "ai_error_count":      3,
    "total_errors":        7,
    "total_requests":      1648
  },
  "sla": {
    "error_rate_target_pct":  1.0,
    "error_rate_ok":          true,
    "timeout_target_pct":     0.5,
    "timeout_ok":             true
  },
  "by_day": [...],
  "by_event": { "api_request": 1648, "api_error_5xx": 7, "workflow_timeout": 3, ... }
}
```

**SLA targets enforced:**
- HTTP 5xx rate: `< 1.0%`
- Workflow timeout rate: `< 0.5%`

**Current gap:** This endpoint exists but has no frontend UI panel displaying it. It is callable via `curl` or Postman; not yet wired into the admin dashboard page.

---

### 2. Admin Feedback & Telemetry Dashboard (Frontend UI)

**Route:** `/admin/feedback-dashboard`
**Where:** `frontend/client/src/pages/admin/feedback-dashboard.tsx`
**Access:** Admin accounts only (feature-flagged by `UX_FEEDBACK_ADMIN_ENABLED`)

**What it currently shows:**
- UX feedback summary: total count, breakdown by feedback type, by rating, by reason, by date
- Top UX issues: ranked by frequency with sample IDs and last-seen timestamp
- Telemetry event summary: total events, counts by event name, time series by day
- Confusion triage: grouped workflow confusion signals by root run ID, severity, and session

**Data sources:**
- `GET /api/feedback/summary` — feedback counts
- `GET /api/feedback/issues` — ranked issue list
- `GET /api/telemetry/summary` — all telemetry events by name/day
- `GET /api/telemetry/confusion-triage` — AI confusion signals

---

### 3. Billing & Cost Dashboard (Backend API)

**Where:** `backend/lib/galaxy/ai/billing/api/billing_router.py`

**Public endpoints (per-user):**
| Endpoint | What it returns |
|---|---|
| `GET /api/billing/usage` | Real-time cost breakdown: LLM (input/output USD, tokens), compute (vCPU/GPU/mem), S3, transfer — current month |
| `GET /api/billing/usage/history` | Past N months of cost data |
| `GET /api/billing/usage/cohort` | User's spend position relative to anonymised cohort (avg, p50, p75, p90) |
| `GET /api/billing/quota` | Plan limits and % consumed |
| `GET /api/billing/jobs/running` | In-flight Batch jobs with live cost estimate |

**Admin endpoint (internal key required):**
| Endpoint | What it returns |
|---|---|
| `GET /internal/billing/admin/cohort_cost?months=N` | Per-month cohort spend: active user count, mean spend, p50/p75/p90/p99 distribution across all users |

**Compute pricing table:** EC2 instances from m6i.large ($0.096/hr) through p4d.24xlarge ($32.77/hr), GPU g4dn/g5/p3 instances, Fargate vCPU/memory rates, S3 per-GB and per-request pricing — all wired into `cost_calculator.py`.

**Current gap:** The billing endpoints are fully functional but there is no admin-facing UI page that aggregates and visualises them. User-facing `/dashboard` page shows static placeholder data rather than real Redis-backed numbers.

---

### 4. Analytics Event Tracking (Client-Side)

**Where:** `frontend/client/src/lib/analytics.ts`, `frontend/client/src/lib/ux-telemetry.ts`

**Events tracked (30+ types):**
```
page_viewed, user_registered, user_logged_in, user_logged_out
query_sent, clarification_answered
workflow_suggested, workflow_started, workflow_completed, workflow_failed, workflow_cancelled
pilot_run_started, pilot_run_skipped
qc_passed, qc_failed, qc_warning, qc_report_exported
compute_settings_changed
subscription_page_viewed, checkout_started, subscription_upgraded
tool_searched, dataset_uploaded
pipeline_started, pipeline_step_completed, pipeline_failed
```

All events flow to `POST /api/telemetry/event` → PostgreSQL `telemetry_events` table → queryable via `/api/telemetry/summary`.

---

## Gap Analysis: What Is Missing for Production Backend Monitoring

The following are not yet captured or surfaced in the admin dashboard.

### Gap 1: Nextflow Job Queue Visibility
**What is missing:** No view of how many Nextflow/Batch jobs are currently queued vs. running vs. failed on AWS Batch, or how long jobs are sitting in queue before starting (queue wait time).

**Why it matters for pilot:** If a partner's workflow sits in queue for 30 minutes before starting, BioMate's "under 30 minutes" promise fails — but we won't know unless we're watching queue depth.

**What to build:** Poll `AWS Batch describe-jobs` and `list-jobs` for BioMate's job queue; expose `GET /api/admin/batch/queue-depth` returning running/pending/failed counts and p50 queue wait time.

---

### Gap 2: AutoFix Event Rates
**What is missing:** No aggregate view of how often the AutoFix engine fires, what failure categories it detects (resource, parameter, data-format, environment), and what fraction it resolves vs. escalates.

**Why it matters for pilot:** AutoFix is a key selling point. If it fires 40% of the time, that tells us workflow generation quality needs improvement. If it resolves 90% of what it fires on, that is a powerful evidence point. Neither number is currently visible.

**What to build:** Emit a `workflow_autofix_triggered` telemetry event with fields: `failure_category`, `resolved: bool`, `restart_count`. Surface these counts in the admin dashboard.

---

### Gap 3: Backend Process Health
**What is missing:** No visibility into whether the Galaxy backend, Nextflow monitor, AutoFix orchestrator, and Redis are healthy at any given moment. The only current health check is `GET /api/health` which returns `{ ok: true }` without checking downstream dependencies.

**Why it matters for pilot:** If Redis is down, billing and SSE events silently fail. If the Galaxy backend is unreachable, all workflow execution silently fails. Without process health checks, a partial failure is invisible until a user complains.

**What to build:** Extend `GET /api/health` to include: Redis connectivity, Galaxy backend reachability, Nextflow binary availability, billing service connectivity. Return component-level status:
```json
{
  "ok": true,
  "components": {
    "redis":   { "ok": true, "latency_ms": 1 },
    "galaxy":  { "ok": true, "latency_ms": 45 },
    "nextflow": { "ok": true, "version": "23.10.1" },
    "billing": { "ok": true }
  }
}
```

---

### Gap 4: User Dashboard Shows Static Data
**What is missing:** The user-facing `/dashboard` page currently shows hardcoded placeholder data ("127 workflows run", "24.3 GB used") rather than real values from the billing and telemetry APIs.

**Why it matters for pilot:** Pilot users will see this dashboard and lose trust if their real usage does not appear there.

**What to build:** Wire `/dashboard` to call `GET /api/billing/usage`, `GET /api/billing/quota`, and count from `workflow_completed` telemetry events to show real numbers.

---

### Gap 5: Admin Error-Rate Panel Not in UI
**What is missing:** The `/api/admin/error-rates` endpoint exists and returns correct data, but there is no UI panel displaying it in the admin feedback dashboard.

**Why it matters for pilot:** The team needs to see error rates at a glance, not run curl commands.

**What to build:** Add an "Error Rates" card to `/admin/feedback-dashboard` that fetches `/api/admin/error-rates` and renders a small table with green/red SLA indicators.

---

## Improvement Plan

### Priority 1 — Add to admin dashboard (1–2 days)

**A. Error-rate card in `/admin/feedback-dashboard`**

Add a new section below the existing telemetry panel:

```tsx
// Fetch error rates
const errRates = await fetch('/api/admin/error-rates').then(r => r.json())

// Render:
// ┌ Error Rates (7-day) ──────────────────────────────────────┐
// │  5xx rate:       0.42%   ✅ (target <1.0%)               │
// │  Timeout rate:   0.18%   ✅ (target <0.5%)               │
// │  AI errors:      3 events                                 │
// │  Total requests: 1,648                                    │
// └───────────────────────────────────────────────────────────┘
```

**B. Cohort billing card**

Add a section calling `/internal/billing/admin/cohort_cost`:

```
┌ Cost — Current Month ──────────────────────────────────────┐
│  Active users: 12                                          │
│  Mean spend:   $1.43 / user                                │
│  p50: $0.82    p75: $2.10    p90: $4.50    p99: $12.30    │
└────────────────────────────────────────────────────────────┘
```

---

### Priority 2 — Extended health check (1 day)

Extend `GET /api/health` in `frontend/server/routes.ts`:

```typescript
app.get('/api/health', async (req, res) => {
  const checks = await Promise.allSettled([
    checkRedis(),       // ping Redis
    checkGalaxy(),      // HEAD galaxy/api/version
    checkNextflow(),    // exec nextflow -version
    checkBilling(),     // GET /api/billing/quota with a test token
  ])
  const components = {
    redis:    checks[0].status === 'fulfilled' ? checks[0].value : { ok: false },
    galaxy:   checks[1].status === 'fulfilled' ? checks[1].value : { ok: false },
    nextflow: checks[2].status === 'fulfilled' ? checks[2].value : { ok: false },
    billing:  checks[3].status === 'fulfilled' ? checks[3].value : { ok: false },
  }
  const allOk = Object.values(components).every(c => c.ok)
  res.status(allOk ? 200 : 503).json({ ok: allOk, components })
})
```

---

### Priority 3 — AutoFix telemetry (0.5 days)

In `backend/lib/galaxy/ai/workflow_ops/autofix/base.py`, emit a telemetry event after each AutoFix run:

```python
# After fix attempt:
telemetry.track("workflow_autofix_triggered", {
    "invocation_id": context.invocation_id,
    "failure_category": diagnosis.category,   # resource | parameter | data_format | env
    "resolved": fix_result.success,
    "restart_count": context.restart_count,
})
```

Then surface in admin dashboard as:
```
AutoFix (7d):  fired 24x  |  resolved 20/24 (83%)  |  top category: resource (12x)
```

---

### Priority 4 — Wire user dashboard to real data (1 day)

Replace static values in `frontend/client/src/pages/dashboard.tsx`:

```tsx
// Replace static stats with real data:
const { data: usage }   = useQuery({ queryKey: ['/api/billing/usage'] })
const { data: quota }   = useQuery({ queryKey: ['/api/billing/quota'] })
const { data: telemetry } = useQuery({ queryKey: ['/api/telemetry/summary'] })

const stats = [
  { label: "Workflows Run",  value: telemetry?.byEventName?.workflow_completed ?? '—' },
  { label: "Storage Used",   value: `${usage?.storage?.s3_gb?.toFixed(1) ?? '—'} GB` },
  { label: "Spend This Month", value: `$${usage?.total?.toFixed(2) ?? '—'}` },
  { label: "Quota Used",     value: `${quota?.pct_used?.toFixed(0) ?? '—'}%` },
]
```

---

### Priority 5 — Nextflow Batch queue depth (1 day)

New backend endpoint:

```python
# backend/lib/galaxy/ai/billing/api/billing_router.py
@router.get("/internal/billing/admin/batch_queue")
def admin_batch_queue():
    """AWS Batch job queue depth for BioMate's compute environment."""
    import boto3
    batch = boto3.client("batch")
    statuses = ["SUBMITTED", "PENDING", "RUNNABLE", "STARTING", "RUNNING", "FAILED"]
    counts = {}
    for status in statuses:
        resp = batch.list_jobs(jobQueue=BATCH_JOB_QUEUE, jobStatus=status)
        counts[status.lower()] = len(resp["jobSummaryList"])
    return { "queue": BATCH_JOB_QUEUE, "counts": counts }
```

---

## Summary Table

| Improvement | Effort | Priority | Value |
|---|---|---|---|
| Error-rate card in admin UI | 0.5 days | **High** | Team visibility without curl |
| Cohort billing card in admin UI | 0.5 days | **High** | Cost per user visible at a glance |
| Extended health check (Redis, Galaxy, Nextflow) | 1 day | **High** | Silent partial failures become visible |
| AutoFix telemetry events + admin card | 0.5 days | Medium | Quantify a key selling point |
| Wire user dashboard to real billing/telemetry data | 1 day | **High** | Pilot users see real numbers |
| Nextflow Batch queue depth endpoint | 1 day | Medium | Catch queue saturation before users complain |
| Nightly CI alert script | 1 day | Medium | Automated regression detection |

**Total estimated effort: ~5.5 days**

---

## What to Leave for a Later Version

- Grafana/Prometheus integration — too heavy for a 12-pilot-user beta; the existing telemetry table is sufficient
- Per-step Nextflow progress tracking — non-deterministic; confirmed out of scope by UX decision
- Alerting via PagerDuty / OpsGenie — relevant at 100+ concurrent users; not now
- Data warehouse / dbt pipeline — scale concern for a later version
