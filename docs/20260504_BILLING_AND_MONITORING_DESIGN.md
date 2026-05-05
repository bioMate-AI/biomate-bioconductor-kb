# BioMate Billing & Monitoring Design
**Date:** 2026-05-04  
**Audience:** Backend engineer (backend + infra collaboration)  
**Purpose:** Shared reference for (1) structured log output points per module, (2) quota tier design, (3) billing page data model and backend↔frontend quota communication

---

## 1. Module Log Output Points

All logs must emit structured JSON to stdout so Grafana / CloudWatch Logs Insights can parse them. Every log line carries a minimum envelope:

```json
{
  "ts": "<ISO8601>",
  "level": "INFO|WARN|ERROR",
  "module": "<module_name>",
  "event": "<event_slug>",
  "user_id": "<int or null>",
  "trace_id": "<uuid — propagated from upstream X-Trace-Id header>",
  ...event-specific fields
}
```

**Tooling:** `structlog` with JSON renderer on Python; `pino` (or existing `logger.ts` extended to JSON mode) on Node.js. Generate `X-Trace-Id` at the Node.js gateway entry point and thread it through every downstream HTTP call and Lambda invocation.

---

### 1.1 `frontend/server/galaxy-assistant.ts` — LLM Orchestration

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `llm.stream.start` | Chat POST received, LLM call initiated | `session_id`, `model`, `provider` (claude/gemini), `input_tokens_est`, `trace_id` |
| `llm.stream.end` | Stream finishes (all chunks delivered) | `input_tokens`, `output_tokens`, `cost_usd`, `latency_ms`, `cache_hit` (bool) |
| `llm.stream.error` | Stream throws or times out | `error_type`, `error_msg`, `tokens_so_far`, `latency_ms` |
| `llm.cost.emitted` | `/internal/billing/llm_cost` POST succeeds | `transaction_id`, `cost_usd`, `lago_ok` (bool), `redis_ok` (bool) |
| `llm.cost.error` | Billing POST fails | `error_msg`, `retry_count` |
| `workflow.routed` | AI returns a workflow suggestion | `workflow_id`, `workflow_name`, `domain`, `routing_score`, `match_type` |
| `workflow.disambiguation` | Disambiguation card sent to user | `candidate_ids[]`, `candidate_scores[]` |
| `chat.session.start` | New session created | `session_id` |
| `chat.session.restore` | Existing session loaded | `session_id`, `message_count` |

---

### 1.2 `backend/lib/galaxy/ai/ai_assistant.py` — Python AI Engine

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `ai.request.start` | `process_request()` entered | `user_id`, `intent_class`, `domain`, `query_len` |
| `ai.workflow.search` | `unified_workflow_search()` called | `query_excerpt`, `top_score`, `top_id`, `candidate_count` |
| `ai.workflow.match` | High-confidence match found | `workflow_id`, `workflow_name`, `score`, `match_type` |
| `ai.workflow.no_match` | No workflow found | `query_excerpt`, `top_score` |
| `ai.run_code.start` | `run_code` tool invoked | `language`, `code_len`, `user_id` |
| `ai.run_code.end` | `run_code` finishes | `exit_code`, `stdout_len`, `stderr_len`, `latency_ms` |
| `ai.llm.call` | LLM API call sent from Python | `model`, `input_tokens`, `purpose` (routing/extraction/analysis) |
| `ai.llm.response` | LLM API response received | `output_tokens`, `cost_usd`, `latency_ms`, `finish_reason` |
| `ai.param.extracted` | Parameter extraction completed | `workflow_id`, `param_count`, `rule_hits`, `llm_hits`, `validation_errors` |
| `ai.error` | Unhandled exception | `error_type`, `error_msg`, `stack_trace_hash` |

---

### 1.3 `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — Workflow Execution

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `batch.job.submit` | `submit_batch_job()` called | `job_id`, `workflow_id`, `user_id`, `queue`, `vcpus`, `memory_mb`, `gpu_count`, `instance_type_requested` |
| `batch.job.running` | Batch sends RUNNING event | `job_id`, `instance_type`, `start_time` |
| `batch.job.succeeded` | Batch sends SUCCEEDED | `job_id`, `duration_s`, `cost_usd`, `compute_mode` (spot/on_demand), `output_s3_prefix` |
| `batch.job.failed` | Batch sends FAILED | `job_id`, `duration_s`, `exit_code`, `reason`, `was_spot_interruption` (bool) |
| `batch.job.timeout` | Job exceeded max runtime | `job_id`, `limit_s`, `budget_cap_usd` |
| `batch.job.budget_exceeded` | Job cost crossed per-job budget cap | `job_id`, `cost_so_far`, `budget_cap_usd` |
| `nf.step.start` | Nextflow step begins | `job_id`, `step_name`, `phase` |
| `nf.step.end` | Nextflow step completes | `job_id`, `step_name`, `exit_code`, `duration_s` |
| `billing.job_started.sent` | `/internal/billing/job_started` POST | `job_id`, `user_id`, `est_cost_usd`, `ok` (bool) |
| `billing.job_completed.sent` | `/internal/billing/job_completed` POST | `job_id`, `cost_usd`, `lago_ok`, `java_ok`, `redis_ok` |
| `quota.check` | `check_and_reserve()` called before submit | `user_id`, `plan`, `current_usd`, `limit_usd`, `allowed` (bool) |
| `quota.exceeded` | `QuotaExceededError` raised | `user_id`, `current_usd`, `limit_usd` |
| `cost.estimate.computed` | Pre-job estimate shown to user | `job_id`, `workflow_id`, `input_data_gb`, `est_gpu_hours`, `est_cost_usd`, `instance_type` |

---

### 1.4 `backend/lib/galaxy/ai/billing/api/billing_router.py` — Billing API

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `billing.llm_cost.received` | `POST /internal/billing/llm_cost` | `user_id`, `transaction_id`, `cost_usd`, `input_tokens`, `output_tokens` |
| `billing.job_completed.received` | `POST /internal/billing/job_completed` | `job_id`, `user_id`, `cost_usd`, `duration_s`, `compute_mode` |
| `billing.s3_put.received` | `POST /internal/billing/s3_put` | `user_id`, `object_key`, `size_bytes`, `cost_usd` |
| `billing.usage.served` | `GET /api/billing/usage` | `user_id`, `month`, `total_usd`, `cache_hit` |
| `billing.quota.served` | `GET /api/billing/quota` | `user_id`, `pct_used`, `plan` |
| `billing.webhook.lago` | Lago webhook received | `event_type`, `customer_id`, `subscription_id` |
| `billing.alert.80pct` | 80% quota warning triggered | `user_id`, `current_usd`, `limit_usd` |
| `billing.alert.100pct` | Quota exhausted | `user_id` |
| `billing.redis.error` | Redis write fails | `key_pattern`, `error_msg` |
| `billing.lago.error` | Lago API call fails | `endpoint`, `http_status`, `error_msg`, `retry_count` |

---

### 1.5 `billing/core/realtime_cost_service.py` — Redis Ledger

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `redis.cost.written` | `record_llm_cost()` / `record_batch_job_cost()` | `user_id`, `month`, `category`, `delta_usd` |
| `redis.cost.read` | `get_current_costs()` | `user_id`, `month`, `total_usd`, `latency_ms` |
| `redis.quota.set` | Plan quota written to Redis | `user_id`, `limit_usd`, `plan`, `source` (webhook/manual) |
| `redis.health.fail` | Redis ping fails on startup or health check | `error_msg` |

---

### 1.6 `billing/lambda/batch_event_handler.py` — AWS EventBridge Lambda

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `lambda.batch.event` | EventBridge fires | `job_id`, `status`, `job_name`, `container_exit_code` |
| `lambda.batch.cost_calc` | Duration and instance resolved | `job_id`, `instance_type`, `duration_s`, `compute_mode`, `vcpus`, `mem_gb`, `gpu_count`, `aws_instance_cost_usd`, `biomate_charge_usd` |
| `lambda.batch.redis_write` | Redis write completes | `job_id`, `ok` (bool), `latency_ms` |
| `lambda.batch.error` | Unhandled exception in handler | `job_id`, `error_msg` |

---

### 1.7 `frontend/server/routes.ts` — Node.js API Gateway

| Event slug | Trigger | Key fields to log |
|---|---|---|
| `http.request` | Every inbound API request | `method`, `path`, `user_id`, `ip_hash`, `trace_id` |
| `http.response` | Response sent | `status_code`, `latency_ms`, `bytes_sent` |
| `auth.login.ok` | Successful login | `user_id`, `email_hash` |
| `auth.login.fail` | Bad credentials | `email_hash`, `reason` |
| `auth.token.refresh` | JWT refresh | `user_id` |
| `file.upload.start` | Multipart upload begins | `user_id`, `filename`, `size_bytes`, `mime_type` |
| `file.upload.end` | Upload complete | `user_id`, `s3_key`, `latency_ms` |
| `billing.proxy` | Request proxied to `/api/billing/*` | `endpoint`, `user_id` |

---

### 1.8 Grafana Dashboard Panels (Recommended)

Use CloudWatch Log Insights (or Loki if self-hosted) to build panels from the structured logs above. Key panels for day-1:

| Panel | Query basis | Alert threshold |
|---|---|---|
| LLM cost per hour | `llm.stream.end` → sum `cost_usd` | > $50/hr |
| Batch job success rate | `batch.job.succeeded` / (`succeeded` + `failed`) | < 95% |
| GPU utilization by job | `lambda.batch.cost_calc` → `gpu_count` × `duration_s` heatmap | n/a (visibility) |
| Spot interruption rate | `batch.job.failed` where `was_spot_interruption=true` | > 5%/hr |
| Quota exceeded events | `quota.exceeded` count | > 5/hr |
| Budget cap terminations | `batch.job.budget_exceeded` count | > 0/hr (alert immediately) |
| Redis error rate | `redis.*.error` count | > 0/5min |
| Lago emission failures | `billing.lago.error` count | > 0/5min |
| P99 LLM latency | `llm.stream.end` → p99 `latency_ms` | > 30s |
| P99 batch job duration | `batch.job.succeeded` → p99 `duration_s` | > 1800s |
| API 5xx rate | `http.response` where `status_code >= 500` | > 1% |
| Large-job cost outliers | `billing.job_completed.received` where `cost_usd > 200` | immediate alert |

---

## 2. Quota Tier Design

### 2.1 Competitive Reference Summary

| Platform | Free tier | Mid tier | Premium/Enterprise |
|---|---|---|---|
| Seqera Platform | 250 runs/mo, 3 concurrent, 100 GB storage | Custom (quotes only) | On-prem Enterprise |
| Biomni Lab | Free research preview (no quota published) | Contact sales | Enterprise: SSO + audit |
| Anthropic Claude API | Tier 1: $100/mo cap, 50 RPM, 30K TPM | Tier 3: $1K/mo cap, 2K RPM | Tier 4: $200K/mo cap |
| OpenAI API | Free: $100 cap, 3 RPM | Tier 3: $1K, 5K RPM | Tier 5: $200K cap |

---

### 2.2 GPU Large-Data Economics — Why the Simple Per-Resource Rate Breaks

Before showing the tiers, the team must understand why CryoEM and large single-cell jobs stress the pricing model.

#### Case: 2 TB CryoEM dataset (full workflow)

A real structural biology run on 2 TB of raw micrograph movies (≈80,000 frames from a K3 camera):

| Step | Instance | Duration | AWS on-demand cost |
|---|---|---|---|
| Motion correction (MotionCor2) | g5.12xlarge (4× A10G, 48 vCPU, 192 GB) | ~8 h | $45 |
| Particle picking (TOPAZ/crYOLO) | g5.12xlarge | ~17 h | $96 |
| 2D classification | g5.12xlarge | ~8 h | $45 |
| 3D refinement + polish | g5.12xlarge | ~10 h | $57 |
| **Total compute** | | **~43 h** | **~$243 AWS** |
| S3 storage (2 TB input + 3 TB intermediate) | | ~2 days | ~$8 |
| **Total AWS cost** | | | **~$251** |

At our original **triple-charge model** (GPU + vCPU + memory all metered separately on the same instance):
- 4 GPUs × $2.50 × 43 h = $430
- 48 vCPU × $0.09 × 43 h = $186
- 192 GB × $0.006 × 43 h = $49
- **BioMate total: $665 → 2.65× AWS cost**

The 2.65× markup is reasonable _in principle_, but the model has two failure modes:

1. **Triple-charging problem**: On a GPU instance, the vCPU and memory are physically bundled into the machine — charging separately for all three components inflates the bill in a way that is hard to explain to users. They will compare to Seqera (which charges a flat CPU-hr + mem-hr on Fargate, no GPU tier, because Seqera doesn't run GPU workloads) and feel cheated.

2. **Tier cliff problem**: A Premium user ($199/mo, $200 compute credit) would exhaust their entire monthly allowance on **less than one third of a single 2 TB CryoEM run**. If overage is disabled, the job is blocked. If overage is enabled, they receive a $465 overage charge on top of the $199 subscription — with no prior warning. This will generate chargebacks and angry emails.

#### Case: Large single-cell permutation test

500K cells × 33K genes, 1,000 permutations (e.g. Seurat FindMarkers with permutation.test.use):
- Needs a high-memory instance: r5.8xlarge (32 vCPU, 256 GB RAM, $2.016/hr)
- Runtime: 6–10 hours depending on gene set
- AWS cost: ~$16–20
- At our rates (no GPU): 32 vCPU × $0.09 × 8h + 256 GB × $0.006 × 8h = $23 + $12 = **$35**
- BioMate charge: $35 — **1.75× AWS cost, very acceptable**

Single-cell at scale is not a GPU problem; it's a high-memory CPU problem. The current per-resource rates cover it well. CryoEM and protein dynamics are the GPU outliers.

---

### 2.3 Fixed Billing Model for GPU Workloads

**Replace the triple-charge model with instance-cost passthrough for GPU instances.**

```
BioMate charge per job = aws_instance_on_demand_price × duration_hours × platform_markup
```

| Markup by compute mode | Rate | Reasoning |
|---|---|---|
| On-demand, no GPU | 2.2× | Covers Nextflow orchestration overhead, platform margin |
| On-demand, GPU (any) | 2.0× | Slightly lower markup; GPU users are large-spend, high-retention customers |
| Spot, no GPU | 1.8× | User accepts interruption risk; we pass 60–70% Spot savings through |
| Spot, GPU | 1.6× | Same logic; large cryo labs need this to be economical |

**Implementation:** the `batch_event_handler.py` Lambda already reads `instance_type` from the job environment. Look up `EC2_INSTANCE_PRICING[instance_type]` (already in `cost_calculator.py`), multiply by actual `duration_s / 3600`, apply the markup, emit that single number. **Stop emitting separate `batch_vcpu_seconds`, `batch_gpu_seconds`, `batch_memory_gb_sec` Lago metrics for GPU jobs.** For CPU-only Fargate jobs keep the per-resource model since there is no bundled GPU to confuse things.

Add a boolean `is_gpu_instance` field to `billing_job_runs` so the billing page can display the charge methodology transparently ("Instance-based pricing: 1× g5.12xlarge × 43.2 h × 2.0× markup").

#### Revised 2 TB CryoEM cost at new model

| Compute mode | AWS cost | BioMate charge | User delta vs old model |
|---|---|---|---|
| On-demand | $243 | $486 | −$179 (27% cheaper) |
| Spot (if available) | $73 | $117 | −$548 (82% cheaper) |

A Premium user with $200 included credits who runs on Spot would pay **$117 total** — comfortably within their monthly allowance.

---

### 2.4 Pre-Job Cost Estimate (Required UX)

**The billing page alone is not enough.** For GPU-heavy workflows, the user must see the estimate *before* they submit, inside the workflow panel. This requires:

**Backend:** add `POST /api/billing/estimate` endpoint:
```json
Request:  { "workflow_id": 12833, "params": { "movies_path": "s3://bucket/cryo/", ... }, "compute_mode": "spot" }
Response: { "est_gpu_hours": 43, "instance_type": "g5.12xlarge", "est_cost_usd": 117.40,
            "est_duration_h": 10.8, "included_credit_remaining": 200.00,
            "overage_usd": 0, "quota_ok": true }
```

Backend logic: resolve `movies_path` glob count → estimate input GB → look up workflow's typical GPU-hr/TB coefficient (stored per workflow in the DB) → compute markup.

**Frontend:** in `nextflow-workflow-viewer.tsx`, before the "Run" button activates, fire this estimate call and show a cost banner:

```
┌─────────────────────────────────────────────────────────────────┐
│  Estimated cost: $117 (Spot)  ·  ~11 hours  ·  g5.12xlarge ×1  │
│  Your credit balance: $200  →  Remaining after run: $83         │
│  [Switch to On-demand: $486]        [Proceed with Spot run]     │
└─────────────────────────────────────────────────────────────────┘
```

If `quota_ok: false`:
```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠ Insufficient credits  ($117 needed, $42 remaining)           │
│  [Enable overage billing]       [Upgrade to Team]               │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2.5 BioMate Tier Table

| Tier | Monthly Fee | Included Compute Credits | Included AI Tokens | Concurrent Runs | Max Job Duration | Storage | Support |
|---|---|---|---|---|---|---|---|
| **Academic** | Free | $15/mo compute | 500K tokens/mo | 1 | 2 h | 5 GB | Community forum |
| **Starter** | $49/mo | $50/mo compute | 5M tokens/mo | 3 | 6 h | 50 GB | Email (48 h SLA) |
| **Premium** | $199/mo | $300/mo compute | 25M tokens/mo | 10 | 24 h | 200 GB | Email (24 h SLA) |
| **Team** | $599/mo | $800/mo compute | 100M tokens/mo | 30 | 72 h | 1 TB | Slack (business hours) |
| **Enterprise** | Custom | Custom | Unlimited | Unlimited | Custom | Custom | Dedicated CSM |

> **Note:** "Pro" is never used. Always say "Premium" in code, UI, DB enums, and customer-facing text.

**Key differences from first draft:**
- Premium compute credit raised from $200 → $300 (covers a full 2 TB CryoEM Spot run at $117 with $183 headroom for LLM calls)
- Team compute credit raised from $600 → $800
- Max job duration added as an explicit tier gate (replaces the rate-limit table's "max job duration" row — it now lives on the tier)

#### Overage Rates (applied when included credits are exhausted)

| Resource | Unit | Overage Price |
|---|---|---|
| Compute — CPU instance (Fargate/EC2) | instance-hour | AWS on-demand × 2.2 markup (varies by type) |
| Compute — GPU instance (EC2, on-demand) | instance-hour | AWS on-demand × 2.0 markup |
| Compute — GPU instance (EC2, Spot) | instance-hour | AWS Spot × 1.6 markup |
| AI tokens (input, blended) | 1M tokens | $4.00 |
| AI tokens (output, blended) | 1M tokens | $18.00 |
| Storage | GB-month | $0.025 |
| Extra concurrent run slot | per slot | +$20/mo |

Common GPU instance BioMate rates at current AWS prices:

| Instance | vCPU | GPU | AWS on-demand | BioMate on-demand | BioMate Spot (est.) |
|---|---|---|---|---|---|
| g5.xlarge | 4 | 1× A10G | $1.006/hr | $2.01/hr | $0.64/hr |
| g5.4xlarge | 16 | 1× A10G | $1.624/hr | $3.25/hr | $1.04/hr |
| g5.12xlarge | 48 | 4× A10G | $5.672/hr | $11.34/hr | $3.63/hr |
| g5.48xlarge | 192 | 8× A10G | $16.288/hr | $32.58/hr | $10.43/hr |
| p3.2xlarge | 8 | 1× V100 | $3.06/hr | $6.12/hr | $1.96/hr |
| p4d.24xlarge | 96 | 8× A100 | $32.77/hr | $65.54/hr | $20.97/hr |

These rates go into a published pricing page and into `EC2_INSTANCE_PRICING` in `cost_calculator.py`.

#### Spot Instance Option

- Accessible to: Starter and above
- User opt-in per run (toggle in workflow panel before submission)
- If Spot instance is interrupted: job is re-queued automatically up to 3 times; if still failing, user is notified via SSE and email; they can retry on on-demand
- Flag in DB: `billing_job_runs.compute_mode` = `"spot"` | `"on_demand"`
- BioMate does **not** charge for time on a Spot run that was interrupted (only successful duration billed)

#### Volume GPU Tiers (automatic, no configuration)

To reward heavy GPU users (CryoEM core facilities, structural biology labs) without requiring Enterprise:

| GPU instance-hours consumed this month | Effective markup on GPU jobs |
|---|---|
| 0–10 h | 2.0× |
| 10–100 h | 1.85× |
| 100–500 h | 1.65× |
| 500+ h | 1.45× |

This is calculated at invoice time (not per-job). The user sees the effective markup on the billing page.

#### Job Budget Cap

- User sets a max spend per job in the workflow panel (optional, no default)
- `billing_job_runs.budget_cap_usd` stores this value
- `nextflow_executor.py` polls estimated cost every 5 minutes against the cap; if exceeded, issues `CancelJob` to Batch and emits `batch.job.budget_exceeded` log event
- User receives SSE event `run_budget_exceeded` in the chat panel with explanation

#### Quota Enforcement Rules

1. **Soft limit at 80%** — email alert sent; user can continue; yellow quota bar in sidebar.
2. **Hard limit at 100%** — new job submissions blocked (HTTP 402); running jobs complete (never killed mid-run).
3. **Grace period** — Enterprise tier gets 20% buffer above quota before hard block.
4. **Overage opt-in** — Starter and above can enable auto-overage billing in Settings → Billing; once enabled, quota enforcement is replaced by metered charges with no hard block. Requires a valid payment method on file.
5. **Overage cap** — when overage is enabled, user can set an optional `overage_cap_usd`; charges stop at that cap (job is then blocked until next month or cap is raised).
6. **Trial** — 14-day trial with $20 compute credits and 2M AI tokens; converts to Academic on expiry; trial users cannot enable overage.

#### Rate Limits (platform stability gates, separate from cost)

| Tier | API requests/min | Concurrent SSE streams | Max concurrent batch jobs |
|---|---|---|---|
| Academic | 30 | 1 | 1 |
| Starter | 120 | 3 | 3 |
| Premium | 300 | 10 | 10 |
| Team | 600 | 30 | 30 |
| Enterprise | Custom | Unlimited | Unlimited |

---

## 3. Backend ↔ Frontend Quota Communication

This section specifies exactly how quota state travels from the backend to the user in the UI. Missing this means the frontend team will invent ad-hoc polling that diverges from the billing state.

### 3.1 Quota State Object

Every quota-related response uses this canonical shape:

```typescript
interface QuotaState {
  plan: "academic" | "starter" | "premium" | "team" | "enterprise";
  status: "ok" | "warning" | "exceeded" | "overage";
  // "ok"       = < 80% used
  // "warning"  = 80–99% used
  // "exceeded" = 100% used, overage disabled
  // "overage"  = 100%+ used, overage enabled (metered charges active)
  included_usd: number;       // monthly included credit for this plan
  used_usd: number;           // amount consumed this month
  remaining_usd: number;      // included_usd - used_usd (can go negative in overage)
  pct_used: number;           // 0–100 (or > 100 in overage)
  overage_enabled: boolean;
  overage_used_usd: number;   // charges above included_usd this month
  overage_cap_usd: number | null;
  reset_date: string;         // ISO8601 — first day of next billing month
}
```

### 3.2 Channels

**Channel 1: Polling (`GET /api/billing/quota`)**  
- Called by the frontend on every page load and every 60 seconds while user is active.
- Returns `QuotaState` (sourced from Redis with DB fallback).
- Response time: < 5 ms (Redis hit) / < 50 ms (DB fallback).
- Used to drive the persistent quota bar in the sidebar and the billing page summary.

**Channel 2: SSE push (`quota_update` event)**  
- Emitted over the existing chat SSE stream whenever the backend records a cost event that crosses a threshold (80%, 90%, 95%, 100%).
- Format: `event: quota_update\ndata: <QuotaState JSON>\n\n`
- Frontend subscribes inside `chat-with-artifacts.tsx` and updates the sidebar quota bar and any open billing panel instantly without waiting for the next poll.
- The 80% threshold event also triggers an email (backend sends via `billing_router.py:billing.alert.80pct`).

**Channel 3: HTTP 402 on job submission**  
- When `check_and_reserve()` blocks a submission, `nextflow_executor.py` returns HTTP 402 to the Node.js server, which proxies it to the frontend.
- Response body:
```json
{
  "error": "quota_exceeded",
  "message": "Monthly compute limit reached ($200.00). Enable overage billing or upgrade your plan.",
  "quota": { ...QuotaState... },
  "upgrade_url": "/billing?action=upgrade"
}
```
- Frontend intercepts 402 in the "Run" button handler: shows an inline error card in the workflow panel (not a toast — the user needs to read it and act).

**Channel 4: Pre-job estimate (`POST /api/billing/estimate`)**  
- Called when the user opens the workflow panel and fills required params (especially file paths).
- Returns cost estimate + quota impact before any job is submitted.
- Frontend shows the cost banner (see Section 2.4).
- Not a hard gate — user can dismiss the estimate and still run (unless 402 fires at actual submission).

**Channel 5: In-run budget alert (SSE `run_budget_exceeded`)**  
- If the user set a job budget cap and the running job is approaching it, the backend polls every 5 minutes and sends an SSE event when cost reaches 80% of cap.
- Format: `event: run_budget_exceeded\ndata: {"job_id":"...", "cost_so_far": 95.0, "cap": 120.0}\n\n`
- Frontend shows an amber banner in the workflow panel: "This run has used $95 of your $120 budget cap and will stop at $120."

### 3.3 Quota UI State Machine

```
QuotaState.status
       │
       ├─ "ok"       → sidebar bar: green; no banners
       │
       ├─ "warning"  → sidebar bar: amber
       │               Toast (once per session): "You've used 80% of your monthly credits"
       │               Billing page: amber usage bar
       │
       ├─ "exceeded" → sidebar bar: red
       │               Persistent banner at top of chat: "Credit limit reached — new runs blocked"
       │               Run button: disabled, shows [Enable overage] or [Upgrade] CTA
       │               Billing page: red bar, modal on first visit explaining options
       │
       └─ "overage"  → sidebar bar: purple (overage active)
                       Persistent banner: "Overage billing active — charges above plan limit"
                       Run button: enabled; pre-job estimate shows overage amount in orange
                       Billing page: shows overage line item separately
```

### 3.4 Frontend State Storage

```typescript
// In app-level React context (not localStorage — can go stale):
const { quotaState, refreshQuota } = useQuota();

// Refresh triggers:
// 1. On app load
// 2. Every 60s via setInterval
// 3. On SSE quota_update event
// 4. After any successful workflow run completion
// 5. After user changes plan or enables overage in billing settings
```

---

## 4. Billing Page Design & Data Model

### 4.1 Billing Page — Required UI Sections

#### Section A: Current Month Summary

```
┌─────────────────────────────────────────────────────────┐
│  Usage this month                    June 2026          │
│  ─────────────────────────────────────────────────────  │
│  Compute         $82.40 of $300.00     27%  ███░░░░░   │
│  AI Tokens       $14.70 of $75 equiv   20%  ██░░░░░░   │
│  Storage          $1.20 /mo                             │
│  ─────────────────────────────────────────────────────  │
│  Total spend     $98.30    Limit: $300.00    33%        │
│                                                         │
│  [Upgrade Plan]           [Set spend alert]             │
└─────────────────────────────────────────────────────────┘
```

**DB fields needed:**
```
billing_monthly_snapshots {
  user_id, month (YYYY-MM),
  llm_input_tokens, llm_output_tokens, llm_cost_usd,
  compute_cost_usd,   -- single figure; breakdown by job is in billing_job_runs
  storage_cost_usd,
  overage_cost_usd,   -- charges above included_usd
  total_cost_usd,
  quota_usd,          -- included_usd at snapshot time (plan may change mid-month)
  updated_at
}
```

#### Section B: Usage Time-Series Chart

Daily bars for the current month, stacked by category (LLM / Compute / Storage / Overage), with tooltip showing breakdown per day and any large jobs annotated.

**DB fields needed (per day per user):**
```
billing_daily_usage {
  user_id, date (DATE),
  llm_cost_usd,
  compute_cost_usd,
  storage_cost_usd,
  overage_cost_usd,
  total_cost_usd,
  job_count,
  gpu_job_count,      -- for annotation ("3 GPU jobs")
  llm_call_count
}
```

#### Section C: Running Jobs (Live Cost Estimates)

```
┌───────────────────────────────────────────────────────────────┐
│  Running now  (2 jobs)                                        │
│  CryoSPARC 2TB run   [Spot]   ~$43.20  3h 12m  ████░░░░░░   │
│  ADMET screening              ~$0.08     3 min  █░░░░░░░░░   │
└───────────────────────────────────────────────────────────────┘
```

**Redis only (evicted on job completion):**
```
billing_running_job {
  job_id, user_id, workflow_id, workflow_name,
  started_at, instance_type, gpu_count, compute_mode,
  est_cost_usd,       -- recomputed every 30s
  budget_cap_usd,     -- null if no cap set
  last_updated_at
}
```

#### Section D: Workflow Run History

```
┌─────┬────────────────────┬──────────┬───────────┬─────────┬──────────┐
│ Run │ Workflow           │ Started  │ Duration  │ Mode    │ Cost     │
├─────┼────────────────────┼──────────┼───────────┼─────────┼──────────┤
│  47 │ CryoSPARC SPA      │ Jun 3    │ 10h 48m   │ Spot    │ $117.40  │
│  46 │ nf-core/rnaseq     │ Jun 2    │ 42 min    │ On-dem  │   $2.18  │
│  45 │ ADMET screening    │ Jun 1    │  8 min    │ On-dem  │   $0.31  │
└─────┴────────────────────┴──────────┴───────────┴─────────┴──────────┘
```

Click a row → drawer shows: instance type, markup method, cost breakdown, output files.

**DB fields needed:**
```
billing_job_runs {
  job_id (PK),
  user_id,
  workflow_id, workflow_name, domain,
  invocation_id,
  started_at, ended_at, duration_s,
  status (succeeded|failed|cancelled|budget_exceeded),
  instance_type,
  is_gpu_instance (bool),
  gpu_count,
  compute_mode (spot|on_demand),
  aws_instance_cost_usd,   -- raw AWS cost (for transparency)
  platform_markup,         -- e.g. 2.0 (logged for audit)
  compute_cost_usd,        -- aws_instance_cost_usd × platform_markup
  llm_cost_usd,
  storage_cost_usd,
  total_cost_usd,
  budget_cap_usd,          -- null if no cap
  output_s3_prefix
}
```

#### Section E: Invoice History

Lago is the system of record. Cache locally for offline access:

```
billing_invoices_cache {
  invoice_id (PK, from Lago),
  user_id,
  period_month (YYYY-MM),
  amount_cents,
  currency,
  status (finalized|paid|voided),
  line_items_json,    -- cached Lago line items: [{description, amount_cents}]
  pdf_url,
  fetched_at
}
```

#### Section F: Plan & Payment

```
┌─────────────────────────────────────────────────────────────┐
│  Current Plan: Premium  ($199/mo)                           │
│  Renews: July 1, 2026                                       │
│  Payment: Visa ···· 4242                                    │
│                                                             │
│  [Change Plan]   [Update Payment]   [Cancel]                │
│                                                             │
│  Spend Alert: Email me at 80% of quota  [Edit]              │
│  Overage billing: OFF  [Enable — continue running after     │
│                          quota is reached, pay as you go]   │
│  Per-job budget cap: not set  [Set]                         │
└─────────────────────────────────────────────────────────────┘
```

**`users` table additions:**
```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS spend_alert_threshold_pct INT DEFAULT 80;
ALTER TABLE users ADD COLUMN IF NOT EXISTS overage_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS overage_cap_usd NUMERIC(10,2);
-- subscription_tier enum must include 'premium'; never 'pro'
```

#### Section G: GPU Usage Analytics (Premium and above)

```
┌──────────────────────────────────────────────────────────────┐
│  GPU compute this month                                      │
│  Total GPU-hours: 87.3 h   Volume tier: 10–100 h (1.85×)    │
│                                                              │
│  Instance breakdown:                                         │
│  g5.12xlarge  ████████████████████░░  72.1 h   $977         │
│  g5.xlarge    ████░░░░░░░░░░░░░░░░░░  15.2 h    $91         │
│                                                              │
│  Spot savings this month: $634  (vs. all on-demand)         │
└──────────────────────────────────────────────────────────────┘
```

**Adds to `billing_monthly_snapshots`:**
```
  gpu_instance_hours_json,  -- {"g5.12xlarge": 72.1, "g5.xlarge": 15.2}
  spot_savings_usd,         -- (on_demand_price - spot_price) × duration, summed
  effective_gpu_markup       -- weighted average markup this month after volume discount
```

---

### 4.2 Shared Billing DB — Complete Schema

```sql
-- Per-day usage (drives time-series chart, fast reads)
CREATE TABLE billing_daily_usage (
    user_id              UUID REFERENCES users(id),
    date                 DATE NOT NULL,
    llm_input_tokens     BIGINT DEFAULT 0,
    llm_output_tokens    BIGINT DEFAULT 0,
    llm_cost_usd         NUMERIC(10,6) DEFAULT 0,
    compute_cost_usd     NUMERIC(10,6) DEFAULT 0,
    storage_cost_usd     NUMERIC(10,6) DEFAULT 0,
    overage_cost_usd     NUMERIC(10,6) DEFAULT 0,
    total_cost_usd       NUMERIC(10,6) DEFAULT 0,
    job_count            INT DEFAULT 0,
    gpu_job_count        INT DEFAULT 0,
    llm_call_count       INT DEFAULT 0,
    PRIMARY KEY (user_id, date)
);
CREATE INDEX ON billing_daily_usage(date);

-- Per-run records (drives run history drawer + analytics)
CREATE TABLE billing_job_runs (
    job_id               TEXT PRIMARY KEY,
    user_id              UUID REFERENCES users(id),
    invocation_id        TEXT,
    workflow_id          INT,
    workflow_name        TEXT,
    domain               TEXT,
    started_at           TIMESTAMPTZ,
    ended_at             TIMESTAMPTZ,
    duration_s           INT,
    status               TEXT,  -- succeeded|failed|cancelled|budget_exceeded
    instance_type        TEXT,
    is_gpu_instance      BOOLEAN DEFAULT FALSE,
    gpu_count            INT DEFAULT 0,
    compute_mode         TEXT DEFAULT 'on_demand',  -- spot|on_demand
    aws_instance_cost_usd  NUMERIC(10,6) DEFAULT 0,
    platform_markup      NUMERIC(4,2) DEFAULT 2.0,
    compute_cost_usd     NUMERIC(10,6) DEFAULT 0,
    llm_cost_usd         NUMERIC(10,6) DEFAULT 0,
    storage_cost_usd     NUMERIC(10,6) DEFAULT 0,
    total_cost_usd       NUMERIC(10,6) DEFAULT 0,
    budget_cap_usd       NUMERIC(10,2),
    output_s3_prefix     TEXT,
    created_at           TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON billing_job_runs(user_id, started_at DESC);
CREATE INDEX ON billing_job_runs(invocation_id);

-- Monthly snapshots (drives summary bar + Redis fallback)
CREATE TABLE billing_monthly_snapshots (
    user_id              UUID REFERENCES users(id),
    month                CHAR(7) NOT NULL,
    llm_cost_usd         NUMERIC(10,4) DEFAULT 0,
    compute_cost_usd     NUMERIC(10,4) DEFAULT 0,
    storage_cost_usd     NUMERIC(10,4) DEFAULT 0,
    overage_cost_usd     NUMERIC(10,4) DEFAULT 0,
    total_cost_usd       NUMERIC(10,4) DEFAULT 0,
    quota_usd            NUMERIC(10,4) DEFAULT 0,
    job_count            INT DEFAULT 0,
    gpu_job_count        INT DEFAULT 0,
    gpu_instance_hours_json  JSONB DEFAULT '{}',
    spot_savings_usd     NUMERIC(10,4) DEFAULT 0,
    effective_gpu_markup NUMERIC(4,2),
    llm_call_count       INT DEFAULT 0,
    updated_at           TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, month)
);

-- Raw LLM event log (audit trail, rolled up to daily)
CREATE TABLE billing_llm_events (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID REFERENCES users(id),
    transaction_id   TEXT UNIQUE,
    session_id       TEXT,
    model            TEXT,
    provider         TEXT,
    input_tokens     INT,
    output_tokens    INT,
    cache_hit        BOOLEAN,
    cost_usd         NUMERIC(10,6),
    ts               TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON billing_llm_events(user_id, ts DESC);
CREATE INDEX ON billing_llm_events(transaction_id);

-- Invoice cache (Lago is authoritative)
CREATE TABLE billing_invoices_cache (
    invoice_id       TEXT PRIMARY KEY,
    user_id          UUID REFERENCES users(id),
    period_month     CHAR(7),
    amount_cents     INT,
    currency         CHAR(3) DEFAULT 'USD',
    status           TEXT,
    line_items_json  JSONB,
    pdf_url          TEXT,
    fetched_at       TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON billing_invoices_cache(user_id, period_month DESC);

-- User plan settings (extend existing users table)
ALTER TABLE users ADD COLUMN IF NOT EXISTS spend_alert_threshold_pct  INT DEFAULT 80;
ALTER TABLE users ADD COLUMN IF NOT EXISTS overage_enabled             BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS overage_cap_usd             NUMERIC(10,2);
-- IMPORTANT: subscription_tier enum values must use 'premium', never 'pro'

-- Quota override log (invite codes, support adjustments, promos)
CREATE TABLE billing_quota_overrides (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID REFERENCES users(id),
    override_usd     NUMERIC(10,2),
    reason           TEXT,
    valid_from       TIMESTAMPTZ,
    valid_until      TIMESTAMPTZ,
    created_by       TEXT,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-job cost estimates (optional audit trail)
CREATE TABLE billing_cost_estimates (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID REFERENCES users(id),
    workflow_id      INT,
    input_data_gb    NUMERIC(12,2),
    compute_mode     TEXT,
    est_instance     TEXT,
    est_gpu_hours    NUMERIC(8,2),
    est_cost_usd     NUMERIC(10,4),
    actual_cost_usd  NUMERIC(10,4),  -- filled in on job completion
    created_at       TIMESTAMPTZ DEFAULT NOW()
);
-- Used to calibrate the per-workflow GPU-hr/TB coefficient over time
```

---

### 4.3 End-to-End Data Flow

```
User fills workflow params → opens workflow panel
       │
       ▼
Frontend: POST /api/billing/estimate
  → Backend computes: input_gb × gpu_hr_per_tb_coeff × instance_price × markup
  → Returns QuotaState + est_cost_usd
  → Frontend shows cost banner (Section 2.4)
       │
       ▼ (user clicks Run)
nextflow_executor.py
  → quota.check: check_and_reserve()
      - OK  → proceed
      - FAIL → HTTP 402 → frontend shows 402 card (Section 3.2 Channel 3)
  → batch.job.submit logged
  → POST /internal/billing/job_started (Redis: est cost running job)
  → SSE: job_started event → frontend: workflow panel shows spinner
       │
       ▼
AWS Batch RUNNING/SUCCEEDED/FAILED → EventBridge → Lambda
  → lambda.batch.cost_calc: instance_price × duration × markup (NOT triple-charge)
  → Redis: cost accumulated
  → POST /internal/billing/job_completed
       │
       ▼
billing_router.py: job_completed handler
  → INSERT billing_job_runs
  → UPSERT billing_daily_usage
  → UPSERT billing_monthly_snapshots
  → Emit to Lago (permanent)
  → Emit to Java billing service
  → Recompute pct_used → if crosses 80%/100% threshold:
      - LOG billing.alert.80pct/100pct
      - Send email
      - Push SSE quota_update event to active chat connections
       │
       ▼
Frontend receives SSE quota_update
  → Update sidebar quota bar color/percentage
  → If status = "exceeded": show banner + disable Run button
       │
       ▼
User opens Billing page
  → GET /api/billing/quota          → QuotaState (Redis, <5ms)
  → GET /api/billing/usage/daily    → billing_daily_usage (Postgres)
  → GET /api/billing/jobs           → billing_job_runs (Postgres, last 30)
  → GET /api/billing/invoices       → billing_invoices_cache (Lago refresh if stale)
```

---

## 5. Open Items for Engineering Discussion

| # | Item | Priority | Notes |
|---|---|---|---|
| 1 | Switch Lambda billing to instance-cost passthrough for GPU jobs | **Critical** | Stop triple-charging; update `cost_calculator.py` + `batch_event_handler.py` |
| 2 | Add `POST /api/billing/estimate` endpoint | **Critical** | Required for pre-job UX; implement GPU-hr/TB coefficient per workflow |
| 3 | Implement SSE `quota_update` push on threshold crossing | **Critical** | Without this, UI only learns about quota on next 60s poll |
| 4 | Implement Spot instance routing in Batch compute environment | High | Required for large cryo runs to be affordable; Batch supports Spot natively |
| 5 | Add `compute_mode`, `is_gpu_instance`, `aws_instance_cost_usd`, `platform_markup` to `billing_job_runs` | High | Needed for run history drawer transparency |
| 6 | Switch Python logging to structlog JSON renderer | High | Required for Grafana parsing |
| 7 | Switch Node.js logger.ts to emit JSON (pino recommended) | High | Align format with Python side |
| 8 | Add `X-Trace-Id` propagation at Node.js gateway | High | Cross-service request correlation |
| 9 | Rollup job: `billing_llm_events` → `billing_daily_usage` (pg_cron, every 5 min) | High | Powers time-series chart |
| 10 | Build `/api/billing/usage/daily` + `/api/billing/jobs` endpoints | High | New endpoints for billing page sections B + D |
| 11 | Add GPU Usage Analytics section (Section G) to billing page | Medium | Premium and above; adds Section G DB fields to monthly snapshot |
| 12 | Implement volume GPU tier discount at invoice time | Medium | Retroactive markup reduction applied on month-end invoice generation |
| 13 | Add per-job budget cap: poll cost in `nextflow_executor.py`, cancel at cap | Medium | SSE `run_budget_exceeded` event wired to amber banner in workflow panel |
| 14 | `subscription_tier` enum audit — replace any `'pro'` → `'premium'` in DB + code | Medium | One-time migration; grep `pro` in users table, billing_router.py, routes.ts |
| 15 | `billing_cost_estimates` table (optional) | Low | Feed back actual vs. estimated to calibrate GPU-hr/TB coefficients over time |
| 16 | Grafana Cloud log source → CloudWatch | Low | Can start with CloudWatch Insights until Grafana stack is provisioned |
| 17 | Overage email template | Low | After opt-in overage feature shipped |
