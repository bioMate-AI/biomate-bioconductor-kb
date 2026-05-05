# Billing & Monitoring Work Split
**Date:** 2026-05-04  
**References:** `20260504_BILLING_AND_MONITORING_DESIGN.md`, `20260504_OPERATION_COST_BREAKDOWN.md`

---

## Summary

| Owner | Scope |
|---|---|
| **You** | Frontend UI (billing page, quota bar, workflow cost banner, 402 card), Node.js gateway (JSON logging, trace ID), product decisions (tier config, thresholds), Stripe display, Grafana config |
| **Backend engineer** | Python structlog migration, all AWS infrastructure (Spot, r6i, VPC endpoints, EFS), PostgreSQL billing migrations, new billing API endpoints, GPU charge fix, SSE quota push, rollup job, Lambda updates |

Dependencies run left-to-right: backend engineer unblocks frontend. The one exception is the billing page, which you can build against mock data in parallel.

---

## Your Work

### P0 — Unblock yourself immediately (no backend dependency)

**1. Rename `pro` → `premium` everywhere in frontend code**
- `frontend/server/routes.ts` — any plan string literals
- `frontend/client/src/` — any tier display strings, plan comparison UI
- `frontend/.env` — any `STRIPE_PRICE_PRO_*` env var names
- Do NOT touch backend Python or DB yet — coordinate the DB enum rename with the backend engineer as part of migration 0011

**2. Switch Node.js logger to structured JSON**  
Replace `frontend/server/logger.ts` custom logger with `pino`. Every log line must emit:
```json
{"ts":"…","level":"info","module":"routes","event":"http.request","method":"GET","path":"/api/…","user_id":…,"trace_id":"…"}
```
Use `pino-http` middleware to auto-log every request/response with `latency_ms` and `status_code`. This is self-contained Node.js work.

**3. Add `X-Trace-Id` at the Node.js gateway**  
In `frontend/server/routes.ts`, on every inbound request: if `X-Trace-Id` header is absent, generate a `uuid()` and attach it. Forward it on every proxy call to Galaxy backend (`X-Trace-Id` header) and include it in every pino log line. This is the correlation key that links a user action across Node.js → Galaxy → Batch Lambda logs in Grafana.

**4. Build billing page UI — can mock the API responses**  
Build the six sections from `20260504_BILLING_AND_MONITORING_DESIGN.md §3.1` against hardcoded fixture data first. The backend engineer will wire up the real endpoints later.

| Section | Component to build | Mock data shape |
|---|---|---|
| A — Monthly summary | Stacked progress bar (Compute / AI / Storage) | `{used_usd, quota_usd, llm_cost_usd, compute_cost_usd, storage_cost_usd}` |
| B — Time-series chart | Daily stacked bar chart (use Recharts or similar) | `[{date, llm_cost_usd, compute_cost_usd, storage_cost_usd}]` |
| C — Running jobs | Live list with cost ticker (poll every 30s) | `[{job_id, workflow_name, est_cost_usd, started_at, compute_mode}]` |
| D — Run history | Table with drawer (instance type, markup, cost breakdown) | `[{job_id, workflow_name, duration_s, compute_mode, total_cost_usd}]` |
| E — Invoice history | Table with PDF link | `[{period_month, amount_cents, status, pdf_url}]` |
| F — Plan & payment | Current plan card + Overage toggle + Alert threshold slider | from `users` table |

GPU usage analytics (Section G) is Premium+ only — include but gate behind tier check.

**5. Add quota bar to sidebar**  
In `frontend/client/src/components/app-sidebar.tsx`, add a compact bar below the nav items showing `quota_state.pct_used`. Color: green (<80%), amber (80–99%), red (100%), purple (overage). Poll `GET /api/billing/quota` every 60 seconds. Store `quotaState` in React context so any component can read it without re-fetching.

**6. Wire SSE `quota_update` subscriber**  
In `frontend/client/src/components/chat-with-artifacts.tsx`, listen for `event: quota_update` on the existing chat SSE stream. On receipt, call `refreshQuota()` from the quota context. This eliminates the 60s polling lag when a job completes and quota changes.

**7. Add 402 error card in workflow panel**  
In `frontend/client/src/components/nextflow-workflow-viewer.tsx`, wrap the Run button click handler. If the submit returns HTTP 402, render an inline card (not a toast) with the error body from the backend:
```
┌────────────────────────────────────────────────────────┐
│  ⛔ Monthly credit limit reached                        │
│  $200.00 used of $300.00 (100%)                        │
│  [Enable overage billing]    [Upgrade to Team]         │
└────────────────────────────────────────────────────────┘
```

**8. Add pre-job cost estimate banner**  
When required params are filled (file path detected), call `POST /api/billing/estimate`. Show result above the Run button:
```
┌─────────────────────────────────────────────────────────────┐
│  Estimated: ~$117  ·  ~11 h  ·  Spot  ·  g5.12xlarge       │
│  Balance after run: $183 remaining  ✓                       │
│  [Switch to on-demand: ~$486]                               │
└─────────────────────────────────────────────────────────────┘
```
Show a spinner while estimate loads. If the endpoint returns `quota_ok: false`, replace the Run button with the 402 card immediately.

**9. Plan & payment section wiring**  
- Overage toggle: `PATCH /api/users/me` with `{overage_enabled: bool}` — backend engineer exposes this
- Spend alert threshold: slider at 50/80/90/100%, same endpoint
- Stripe last-4 display: read from `stripe_customer_id` via backend endpoint — backend engineer provides `GET /api/billing/payment-method`
- Change plan: redirect to Stripe Customer Portal URL from `GET /api/billing/portal`

**10. Set up Grafana Cloud**  
- Sign up for Grafana Cloud free tier (10K metrics, 50 GB logs — sufficient for current scale)
- Point it at CloudWatch Logs in us-west-2 using the CloudWatch data source plugin
- Build 8 panels from `20260504_BILLING_AND_MONITORING_DESIGN.md §1.8` using the event slugs the backend engineer emits
- You do this; backend engineer just needs to confirm log group names when structured logging is live

---

### P1 — After backend engineer delivers endpoints

**11. Replace mock billing API responses with real calls**  
Swap fixture data for real `GET /api/billing/usage/daily`, `GET /api/billing/jobs`, `GET /api/billing/invoices`.

**12. Wire the Spot toggle in workflow panel**  
Backend engineer exposes `compute_mode` param on job submission. Add a "Use Spot (save ~60%)" toggle in the workflow panel footer. Pass `compute_mode: "spot"` in the run request body.

**13. Per-job budget cap input**  
Add an optional "Max spend" field in the workflow panel (e.g. `$____ cap`). Pass `budget_cap_usd` in the run request. Show an amber banner when SSE `run_budget_exceeded` fires (Section 3.2 Channel 5 of billing design).

---

## Backend Engineer's Work

### P0 — Critical: fixes incorrect billing math today

**1. Fix GPU billing: instance-cost passthrough (replaces triple-charge)**  
File: `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py`  
File: `backend/lib/galaxy/ai/billing/core/cost_calculator.py`

Current behavior: emits `batch_vcpu_seconds`, `batch_gpu_seconds`, `batch_memory_gb_sec` separately to Lago → on a g5.12xlarge these three sum to 2.7× the actual AWS cost.

Required behavior:
- Look up `EC2_INSTANCE_PRICING[instance_type]` to get `price_hr`
- Calculate `aws_cost = price_hr × duration_h`
- Determine `compute_mode` (spot or on_demand) from job environment variable `BIOMATE_COMPUTE_MODE`
- Apply markup: on-demand GPU → 2.0×, Spot GPU → 1.6×, CPU → 2.2×
- Emit a single `batch_compute_cost` Lago metric with the marked-up total
- Stop emitting the three separate per-resource metrics for GPU jobs (keep them for CPU-only Fargate jobs where they're still accurate)

Add `is_gpu_instance` bool and `platform_markup` float to every cost event for audit.

**2. Switch Python logging to structlog JSON**  
All 8 modules in `20260504_BILLING_AND_MONITORING_DESIGN.md §1`:
- `billing_router.py`, `realtime_cost_service.py`, `lago_client.py`, `cost_calculator.py` — these 4 first
- `ai_assistant.py`, `nextflow_executor.py` — these second (higher volume, more impact)
- `batch_event_handler.py`, `s3_event_handler.py` Lambda functions

Use `structlog` with `JSONRenderer`. Every log line: `ts`, `level`, `module`, `event`, `user_id`, `trace_id` (read from env `BIOMATE_TRACE_ID` which the Node.js gateway injects into Batch job env). Emit all event slugs from §1 exactly as specified — names matter for Grafana queries.

**3. Add `compute_mode` + `budget_cap_usd` to job submission**  
`nextflow_executor.py`:
- Accept `compute_mode: "spot" | "on_demand"` in the run request body (default: on_demand for now until Spot environment is ready)
- Accept `budget_cap_usd: float | null`
- Pass `BIOMATE_COMPUTE_MODE` as an environment variable into the Batch job container
- Store both on `billing_job_runs` once DB tables exist

### P1 — Infrastructure (can do in parallel with P0)

**4. Create Spot GPU compute environment in Batch**  
- New compute environment: `biomate-gpu-spot`
  - `allocationStrategy: SPOT_CAPACITY_OPTIMIZED`
  - `bidPercentage: 60`
  - Allowed instance types: g5.xlarge, g5.2xlarge, g5.4xlarge, g5.12xlarge, g4dn.xlarge, g4dn.4xlarge, g4dn.12xlarge
- New queue: `biomate-gpu-spot-queue` → primary env: `biomate-gpu-spot`, fallback: existing on-demand GPU env
- Update `batch_event_handler.py`: on `SPOT_CAPACITY_EXCEEDED`, increment `spot:interruptions:{job_id}` in Redis; if counter ≥ 3, log `batch.job.spot_escalated` and note in the job record that it ran on-demand
- Set `attempts: 3` on all GPU job definitions so Batch auto-retries on Spot interruption

**5. Add EFS mount for CryoSPARC Spot jobs**  
CryoSPARC checkpoints to local project directory, not S3. Without EFS, Spot interruption loses CryoSPARC state (Nextflow `-resume` won't help here — CryoSPARC is not Nextflow).
- Create EFS file system in us-west-2 (same AZ as Batch)
- Mount point: `/cryosparc-projects` in the CryoSPARC job container
- EFS cost: $0.30/GB-month Standard; archive to EFS-IA after job completion
- Add to job definition for `cryosparc_*` workflows only

**6. Add r6i instances to Batch and cost_calculator.py**  
```python
# Add to EC2_INSTANCE_PRICING:
"r6i.xlarge":   {"vcpu": 4,  "mem_gb": 32,  "gpu": 0, "price_hr": 0.252},
"r6i.2xlarge":  {"vcpu": 8,  "mem_gb": 64,  "gpu": 0, "price_hr": 0.504},
"r6i.4xlarge":  {"vcpu": 16, "mem_gb": 128, "gpu": 0, "price_hr": 1.008},
"r6i.8xlarge":  {"vcpu": 32, "mem_gb": 256, "gpu": 0, "price_hr": 2.016},
"r6i.16xlarge": {"vcpu": 64, "mem_gb": 512, "gpu": 0, "price_hr": 4.032},
```
Add them to the Batch compute environment's allowed instance types. Tag with `Memory-Optimized=true` so the workflow router can request them for single-cell workflows.

**7. Add S3 VPC Gateway Endpoint**  
Free, eliminates S3 traffic through the NAT Gateway (the main NAT cost driver). Takes 30 min to configure in VPC console. Add to `biomate-nextflow-work` bucket policy to allow access from the VPC endpoint only. Do this before enabling Spot — Spot jobs will increase S3 traffic significantly.

**8. Reserve EC2 instances (1-year)**  
Convert both always-on EC2 instances to 1-year reserved:
- Main app EC2 (52.42.49.175) — saves ~$112/mo
- Billing server EC2 (35.86.137.71) — saves ~$56/mo
- Coordinate with you before doing this — it's a financial commitment

### P2 — New API endpoints (frontend unblocked by these)

**9. `POST /api/billing/estimate`**  
Request: `{workflow_id, params: {movies_path, …}, compute_mode}`  
Logic:
1. If `params` contains a file path → call `count_s3_objects(path)` → estimate `input_gb`
2. Look up `workflow_gpu_coeff[workflow_id]` (GPU-hours per TB of input) — start with hardcoded defaults per domain:
   - cryo_em: 21 GPU-h/TB
   - transcriptomics: 0 (CPU only)
   - genomics: 0
   - protein_structure: 15 GPU-h/TB
3. Estimate `est_gpu_hours = input_gb / 1024 × coeff`
4. Compute `est_cost_usd = gpu_hours × instance_price × markup` (on-demand or Spot)
5. Fetch quota from Redis → compute `quota_ok`, `overage_usd`
6. Return `QuotaState` + estimate fields

Response:
```json
{
  "est_gpu_hours": 43.2,
  "instance_type": "g5.12xlarge",
  "est_cost_usd": 117.40,
  "est_duration_h": 10.8,
  "compute_mode": "spot",
  "included_credit_remaining": 200.00,
  "overage_usd": 0,
  "quota_ok": true,
  "quota": { ...QuotaState... }
}
```

**10. `GET /api/billing/usage/daily?month=YYYY-MM`**  
Source: `billing_daily_usage` table (once migration is in). Fallback: aggregate from `billing_job_runs` by date until table is populated.  
Response: `[{date, llm_cost_usd, compute_cost_usd, storage_cost_usd, overage_cost_usd, total_cost_usd, job_count, gpu_job_count}]`

**11. `GET /api/billing/jobs?limit=30&offset=0`**  
Source: `billing_job_runs` table.  
Response: `[{job_id, invocation_id, workflow_name, domain, started_at, duration_s, status, instance_type, is_gpu_instance, compute_mode, aws_instance_cost_usd, platform_markup, compute_cost_usd, llm_cost_usd, total_cost_usd}]`

**12. `GET /api/billing/payment-method`**  
Proxy to Stripe API: retrieve last4, brand, expiry for `users.stripe_customer_id`. Return `{last4, brand, exp_month, exp_year}` or null if not set.

**13. `GET /api/billing/portal`**  
Generate Stripe Customer Portal session URL. Return `{url}`. Frontend redirects to it for plan changes and payment updates.

**14. `PATCH /api/users/me`**  
Accept `{spend_alert_threshold_pct, overage_enabled, overage_cap_usd}`. Update the `users` table. Existing endpoint may exist — extend it.

**15. Push SSE `quota_update` event**  
When `billing_router.py` records a cost event that crosses 80%, 90%, 95%, or 100%:
- Emit `event: quota_update\ndata: <QuotaState JSON>\n\n` to the user's active SSE connection
- The SSE connection is already open (chat stream). Add a user→SSE-connection registry in memory (or Redis pub/sub if multi-process) so billing_router can push to it
- Also emit `event: run_budget_exceeded\ndata: {job_id, cost_so_far, cap}\n\n` when a running job crosses 80% of its budget cap

### P3 — Database migrations (enables full history and analytics)

**16. Add billing migrations to `frontend/migrations/`**

These are new `.sql` files following the existing pattern:

| File | Tables |
|---|---|
| `0011_billing_daily_usage.sql` | `billing_daily_usage` |
| `0012_billing_job_runs.sql` | `billing_job_runs` |
| `0013_billing_monthly_snapshots.sql` | `billing_monthly_snapshots` |
| `0014_billing_llm_events.sql` | `billing_llm_events` |
| `0015_billing_invoices_cache.sql` | `billing_invoices_cache` |
| `0016_billing_quota_overrides.sql` | `billing_quota_overrides` + `users` column additions (`spend_alert_threshold_pct`, `overage_enabled`, `overage_cap_usd`) |

Full SQL from `20260504_BILLING_AND_MONITORING_DESIGN.md §3.2`. Also add `subscription_tier` CHECK constraint change: replace `'pro'` with `'premium'` (coordinate with you — requires a data migration if any rows have `tier='pro'`).

**17. Rollup job: `billing_llm_events` → `billing_daily_usage`**  
Run every 5 minutes via pg_cron (available on RDS PostgreSQL 15):
```sql
SELECT cron.schedule('billing-rollup', '*/5 * * * *',
  $$INSERT INTO billing_daily_usage (user_id, date, llm_input_tokens, ...)
    SELECT user_id, DATE(ts), SUM(input_tokens), ...
    FROM billing_llm_events
    WHERE ts >= NOW() - INTERVAL '10 minutes'
    GROUP BY user_id, DATE(ts)
    ON CONFLICT (user_id, date) DO UPDATE SET ...$$
);
```

**18. Backfill historical data from Lago**  
Use the Lago invoice API to reconstruct per-user monthly totals for months where `billing_monthly_snapshots` is empty. Write a one-time migration script. Not urgent — affects invoice history display only.

---

## Dependency Order

```
Week 1
  Backend P0 (items 1-3) ──────────────────────┐
  You P0 (items 1-4, billing page mock) ────────┤
                                                 ▼
Week 2                                      Backend P1 (items 4-8)
  You P0 (items 5-9, quota bar, SSE sub)   Backend P2 starts (items 9-14)
                                                 │
Week 3                                           ▼
  You P1 (items 11-13)  ←── Backend P2 done ────┤
                              Backend P3 (items 16-18)
```

---

## Handoff Checklist (what backend engineer delivers to you)

When the backend engineer says a task is done, verify against this list before starting the frontend wiring:

- [ ] Structured JSON logs visible in CloudWatch — confirm with `aws logs tail /ecs/biomate-galaxy --since 5m | jq .event` and see valid slugs
- [ ] `POST /api/billing/estimate` — test with a CryoEM workflow_id and an S3 path; confirm `est_cost_usd` is non-zero and reasonable
- [ ] `GET /api/billing/usage/daily` — returns array with `date`, `compute_cost_usd`, `llm_cost_usd`
- [ ] `GET /api/billing/jobs` — returns at least the last 5 real runs with `instance_type` and `compute_mode` populated
- [ ] Quota SSE push — submit a workflow, watch the browser network tab for `event: quota_update` arriving within 5s of job completion
- [ ] GPU billing fix — run a short GPU job, check the Lago customer event, confirm a single `batch_compute_cost` metric (not three separate resource metrics)
- [ ] Spot environment — submit a CryoEM job with `compute_mode: spot`, confirm it lands on a Spot instance (check Batch job details in AWS console)
