# BioMate Beta Stabilization & Evidence-Based Business Model
## Implementation Plan — 2026-02-24

**Framework**: Beta Stabilization (Sheet 4) + Evidence Based Model (Sheet 5)
**Timeline**: 90 days — target completion 2026-05-24
**Team**:
- **Alice** — UI/Research
- **Bob** — AWS/Workflows
- **Carol** — Backend/Billing

All three tracks run **in parallel from Day 1**. Dependencies are called out explicitly.
Gates block only the downstream work that needs them — not the entire team.

---

## Parallel Track Overview

```
         WEEK 1        WEEK 2        WEEK 3    ||  WEEKS 4–8   ||  WEEKS 9–11  ||  WEEK 12
ALICE    Instrument    Survey        Protocol  ||  Sessions     ||  Cohort 2    ||  Paper
         frontend      component     + outline ||  + paper      ||  + paper     ||  narrative

BOB      Stage         Benchmark     Run       ||  50 runs      ||  Runs 6–10   ||  Methods
         datasets      protocol      protocol  ||  + cost exp   ||  + write-up  ||  section
                       + configs     + chaos   ||               ||              ||

CAROL    Wire billing  Cost report   Nightly   ||  LLM audit    ||  Unit econ   ||  Cost
         pipeline      endpoint      CI +      ||  + weekly     ||  + quota     ||  analysis
                       + health dash monitor   ||  snapshots    ||  + lock      ||  section
```

---

## Week-by-Week Parallel Schedule

### Weeks 1–3: Instrumentation & Setup

All three members work simultaneously. Zero blockers at the start.

---

#### Alice — Week 1

**A1. Frontend Event Instrumentation**
Ship a thin analytics layer so every meaningful user action is recorded.

New file: `frontend/client/src/lib/analytics.ts`
```typescript
// Single function: track(event_name, properties)
// POSTs to /api/events — no external SDK, no network dependency
```

Events to wire at each UI touch point:

| Event | Where to add it | File |
|---|---|---|
| `workflow_generated` | SSE completion handler | `chat-with-artifacts.tsx` |
| `pilot_run_triggered` | auto-pilot trigger + manual button | `workflow-artifact.tsx` |
| `qc_gate_shown` | modal open | `qc-gate-modal.tsx` |
| `qc_gate_accepted` | accept/reject/skip button | `qc-gate-modal.tsx` |
| `result_exported` | download/export click | `workflow-artifact.tsx` |
| `session_abandoned` | `beforeunload` event | `App.tsx` |
| `clarification_sent` | follow-up message send | `chat-with-artifacts.tsx` |
| `workflow_accepted` | first Nextflow execute fires | `workflow-artifact.tsx` |

Each event carries: `{ session_id, timestamp, ...properties }`.
`session_id` = UUID stored in localStorage on app load.

Backend: add `POST /api/events` in `frontend/server/routes.ts` → writes to SQLite:
```sql
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    event_name TEXT NOT NULL,
    properties TEXT,      -- JSON blob
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**Deliverable (end of Week 1)**: Fire all 8 events manually in dev, verify rows appear in DB.

---

#### Bob — Week 1

**B1. Stage Benchmark Datasets to S3**
All datasets must be in S3 before any benchmark run. Download to EC2, push to S3.

| Domain | Dataset | Source | Est. Size | S3 path |
|---|---|---|---|---|
| RNA-seq | ENCODE ENCSR000AED (GM12878, 4 samples) | ENCODE portal wget | ~10 GB | `s3://biomate-production-data-399683337364/benchmarks/rnaseq/` |
| scRNA-seq | 10X PBMC 3k | 10x Genomics CDN | ~150 MB | `s3://biomate-production-data-399683337364/benchmarks/scrna/` |
| cryo-EM | EMPIAR-10028 (T20S, 10 micrograph subset) | EMDB download tool | ~2 GB | `s3://biomate-production-data-399683337364/benchmarks/cryoem/` |
| ChIP-seq | ENCODE K562 H3K27ac (ENCSR000AKF) | ENCODE portal wget | ~5 GB | `s3://biomate-production-data-399683337364/benchmarks/chipseq/` |
| Metagenomics | HMP SRS011061 (5 gut samples) | SRA fasterq-dump | ~8 GB | `s3://biomate-production-data-399683337364/benchmarks/metagenomics/` |

Verify checksums (ENCODE provides md5). Create `business/benchmark_datasets.md` with exact S3 paths, versions, checksums.

**B2. Nextflow Config Audit**
Audit every domain's `nextflow.config` in `backend/biomni_workflows/nextflow_nfcore/subworkflows/`:

Check each config for:
- Correct instance family (cryo-EM: `g6.2xlarge`+ ; RNA-seq/ChIP: `c5.4xlarge`; scRNA: `r5.4xlarge`)
- Spot pricing enabled: `queue = "spot"` in awsbatch profile
- `maxRetries = 3` for spot interruptions
- Memory limits correct (CryoSPARC v5: ≥ 24 GB)
- `errorStrategy = 'retry'` on memory-intensive processes

Create `business/batch_optimization_audit.md` documenting every finding and fix.

**Deliverable (end of Week 1)**: All 5 datasets in S3. Audit doc with at least first 2 configs reviewed.

---

#### Carol — Week 1

**C1. Wire Billing Pipeline End-to-End**
The infrastructure is deployed but `REDIS_URL` and `BILLING_INTERNAL_KEY` are not set on the EC2.

Steps:
1. SSH to `lt-v6-test` (35.89.57.94)
2. Add to the gunicorn environment (systemd unit or `.env`):
   ```
   REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
   BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
   ```
3. Restart backend
4. Run one RNA-seq workflow and verify:
   - Redis key `billing:run:<invocation_id>` exists with `llm_cost`, `gpu_minutes`, `s3_gb`
   - `batch-billing` Lambda received RUNNING + SUCCEEDED events
   - `s3-billing` Lambda received S3 events for the output bucket

New file: `backend/tests/verify_billing_e2e.py`
- Triggers a test workflow
- Polls Redis 120s for the key
- Asserts all required fields non-zero
- Prints cost breakdown

**C2. Build Cost Report Endpoints**
New file: `backend/lib/galaxy/ai/billing/api/cost_report_router.py`

```
GET /api/billing/cost-report?user_id=<id>&days=30
  → { total_runs, total_llm_cost_usd, total_gpu_minutes, total_s3_gb,
      estimated_total_usd, runs: [...] }

GET /api/billing/cost-report/summary?days=7
  → { cost_per_domain, cost_per_active_user_avg, projected_monthly_cogs }
```

Cost rates to hardcode (update from actual invoices once available):
- GPU: `gpu_minutes × $0.00805` (g6.2xlarge spot)
- S3: `s3_gb × $0.023` (us-east-1 storage)
- LLM: already in `llm_cost` from `_emit_llm_billing()`

Wire into `billing_router.py` as a sub-router.

**Deliverable (end of Week 1)**: `verify_billing_e2e.py` passes 3 consecutive runs. Cost endpoints return real data.

---

#### Alice — Week 2

**A2. In-App Micro-Survey**
Show a 2-question survey after every completed workflow run (once per session).

New component: `frontend/client/src/components/run-survey.tsx`
```
"How confident are you in this result?"   ★ ★ ★ ★ ★
"What's one thing that could be clearer?" [optional text]
```
POST response as event `run_survey_completed` to `/api/events`.
Wire into `workflow-artifact.tsx` — show after SSE `workflow_complete` event fires.

**A3. Usability Session Protocol**
Output: `business/usability_session_protocol.md`

Session structure (60 min per participant):
- 0–5 min: Consent + orientation ("No wrong answers. We're testing the tool, not you.")
- 5–10 min: Read dataset description (one paragraph, no extra context)
- 10–50 min: Open task — "Use BioMate to analyze this dataset to a result you'd show your PI." No help unless blocked >5 min.
- 50–60 min: Post-session interview

Participant criteria: PhD student or postdoc, domain expertise in one of the 5 domains, zero prior BioMate experience, no CLI coaching for the session.

Datasets → Bob provides S3 access. Alice prepares the one-paragraph briefing for each domain.

**Observer metrics sheet** (filled immediately after, not during):
```
Session N — Domain — Date — Participant code
T_first_run:              (HH:MM from session start → Nextflow executing)
task_completed:           Yes / No
clarification_rounds:     N
qc_gate_shown:            Yes / No
qc_gate_correct:          Yes / No / N/A
confidence_self_report:   1–5
confusion_moments:
  MM:SS — [what happened]
Post-session quote:       "[verbatim]"
Would pay:                Yes / No — $X/mo
```

Post-session interview questions:
1. "Walk me through what you expected vs. what happened."
2. "What would have made you quit?"
3. "What would you pay for this monthly?"
4. "Would you recommend this to your labmates?"

**Deliverable (end of Week 2)**: Protocol doc finalized, reviewed by Bob + Carol. Survey component shipping.

---

#### Bob — Week 2

**B3. Benchmark Run Protocol**
Output: `business/benchmark_run_protocol.md`

For each domain, define and lock:
1. **Exact S3 input path** (from B1)
2. **Exact BioMate prompt** (the natural-language question — locked, cannot change between runs)
3. **Success criterion**: specific output files that must exist
4. **Failure definition**: Nextflow exit ≠ 0, OR required output missing, OR wall time > 2× expected
5. **Run log row** format for `business/benchmark_results.csv`:
   ```
   run_id, domain, prompt_hash, timestamp_start, timestamp_end,
   success, wall_time_min, cost_usd, batch_instance_type, failure_reason
   ```

Locked prompts (examples, finalize with Alice):
- RNA-seq: "Find differentially expressed genes between conditions A and B in these 4 human RNA-seq samples. Use hg38."
- scRNA-seq: "Identify cell types in this 10X PBMC dataset and produce a UMAP with cluster annotations."
- cryo-EM: "Run a standard SPA reconstruction on these micrographs through 2D classification and initial model."
- ChIP-seq: "Call H3K27ac peaks and identify enriched motifs in these K562 samples."
- Metagenomics: "Perform taxonomic profiling on these 5 gut metagenome samples and compare community composition."

**B4. Chaos Test Scenarios**
Coordinate with Carol (who owns the monitor code). Design 5 scenarios:

| # | Trigger | Expected behavior | Who executes |
|---|---|---|---|
| 1 | Kill gunicorn mid-job, restart | Job completes, billing not duplicated | Bob triggers, Carol verifies Redis |
| 2 | Kill Nextflow process mid-job | Monitor detects FAILED within 60s, SSE sends error | Bob kills PID, Alice verifies UI |
| 3 | Revoke S3 IAM role mid-job | Clean error reported, not silently swallowed | Bob via IAM console |
| 4 | Stop Batch instance (spot sim) | Retry fires, job eventually completes | Bob via EC2 console |
| 5 | Exceed maxRetries | FAILED state in UI, billing records partial compute | Bob sets maxRetries=0, triggers job |

**Deliverable (end of Week 2)**: Protocol doc locked. Chaos scenario definitions written up in `business/chaos_test_results.md` (headers only, results filled in Week 3).

---

#### Carol — Week 2

**C3. Health Dashboard Endpoint**
New endpoint: `GET /api/health/stability`

```json
{
  "window_days": 7,
  "technical_stability": {
    "total_runs": 12,
    "successful_runs": 11,
    "success_rate_pct": 91.7,
    "crash_count": 0,
    "p95_queue_to_start_sec": 45,
    "p95_workflow_gen_sec": 18
  },
  "workflow_clarity": {
    "sessions_with_data": 4,
    "task_completion_rate_pct": 75.0,
    "avg_clarification_rounds": 1.2,
    "qc_gate_correct_action_pct": 80.0,
    "avg_confidence_score": 4.1
  },
  "cost_monitoring": {
    "avg_cost_per_run_usd": 1.82,
    "avg_cost_per_active_user_usd": 14.50,
    "estimated_gross_margin_pct": 62.0
  },
  "gates": {
    "technical_stability_pass": true,
    "workflow_clarity_pass": false,
    "cost_monitoring_pass": true
  }
}
```

Data sources:
- `technical_stability`: Nextflow monitor logs + Redis billing records
- `workflow_clarity`: `events` table (Alice's A1)
- `cost_monitoring`: cost report summary from C2

`gates` auto-calculates pass/fail against the hardcoded thresholds (success_rate ≥ 95%, completion ≥ 70%, margin ≥ 60%).

**C4. Nightly CI on Live Backend**
Cron job on EC2 running at 2am UTC:
```bash
# /etc/cron.d/biomate-nightly-tests
0 2 * * * ubuntu cd /home/yzhang/biomate/backend && \
  .venv/bin/pytest tests/ -q --tb=short \
  > /tmp/nightly_logs/$(date +\%Y\%m\%d).log 2>&1
```

Alert script: `backend/scripts/parse_and_alert_test_results.py`
- Reads the log, finds `FAILED` lines
- If any: POST to Slack webhook with test name + error snippet
- Also: expose `GET /api/health/test-status` returning last nightly result

New endpoint: `GET /api/health/test-status`
```json
{ "last_run": "2026-02-24T02:00:01Z", "passed": 319, "failed": 0, "status": "pass" }
```

**Deliverable (end of Week 2)**: Health dashboard returns real data. First nightly CI run logged.

---

#### Alice — Week 3

**A4. Use-Case Paper Outline**
Output: `business/usecase_paper_outline.md`

Structure (5,000–7,000 words, journal short paper):
1. Abstract
2. Introduction — bioinformatics bottleneck in bench labs
3. System overview — intent → Nextflow → QC gate → result
4. Case studies (one per domain, ~1 page each, written as Alice gets data from Bob):
   - 4a. RNA-seq: differential expression
   - 4b. scRNA-seq: cell type annotation
   - 4c. cryo-EM: SPA reconstruction
   - 4d. ChIP-seq: peak calling + motif
   - 4e. Metagenomics: taxonomic profiling
5. Usability results (from sessions — written in Week 9 once all data is in)
6. Cost analysis (Carol writes this section — feeds from C2 data)
7. Methods (Bob writes this section — Nextflow, AWS, instance types, software versions)
8. Discussion + limitations

Writing ownership:
- Sections 1–5: Alice
- Section 6: Carol
- Section 7: Bob
- Section 8: all three, Alice leads

**Deliverable (end of Week 3)**: Outline agreed, section ownership locked. Each member starts their section in parallel during Phase 2.

---

#### Bob — Week 3

**B5. Complete Config Audit + Run Chaos Tests**
Finish auditing remaining Nextflow configs (from B2). Apply fixes: spot pricing, instance types, retries.

Run all 5 chaos scenarios from B4 with Carol:
- For each: execute the trigger, observe behavior, fill in result row in `business/chaos_test_results.md`
- All 5 must pass before Phase 2 benchmark runs start

S3 lifecycle rule: add 30-day auto-delete to `s3://biomate-nextflow-work` (Nextflow intermediate files). Implement in `aws_infrastructure/`. This is a cost control measure, not cosmetic.

**Deliverable (end of Week 3)**: All 5 chaos scenarios pass. All configs audited. S3 lifecycle rule active.

---

#### Carol — Week 3

**C5. Monitor Registry Reliability Audit**
Files to audit: `backend/lib/galaxy/jobs/runners/nextflow_monitor.py`, `backend/lib/galaxy/jobs/qc_trace_monitor.py`

Four specific checks:
1. **Re-attachment after restart**: when backend restarts mid-job, can the monitor re-attach to the running Batch job ID? If not, implement lookup via Batch `list_jobs` using the stored job ID from Redis.
2. **Billing deduplication**: `_emit_billing_final()` must fire exactly once per run. Add Redis `SET NX` lock keyed on `billing_final:<invocation_id>`. If lock already set, skip emission.
3. **Eviction safety**: before `monitor_all()` evicts a stale `_on_demand` monitor, check that billing record has all three fields non-zero (if run produced output). If incomplete, emit a warning and retain for one more cycle.
4. **`processed_tasks` cap**: verify clearing at 50K doesn't cause a missed task to re-report as new. Add a bloom filter or secondary set to track cleared task IDs.

New test file: `backend/tests/test_monitor_reliability.py` — one test per check above.

**Deliverable (end of Week 3)**: All 4 reliability tests passing. Any fixes to monitor code committed.

**Gate G1 — End of Week 3** (all three must pass before Phase 2):
- Events table has rows from 3 manual test runs (Alice)
- All 5 datasets in S3, protocol locked, chaos tests pass (Bob)
- Billing pipeline wired, cost endpoints live, nightly CI running (Carol)

---

### Weeks 4–8: Experiments (All Three Running in Parallel)

All three tracks run simultaneously. Bob's benchmark costs feed Carol's pricing model. Alice's session events feed Carol's clarity metrics. No one waits.

---

#### Alice — Weeks 4–8: Usability Sessions + Paper Drafting

**Schedule**: 2 sessions per week starting Week 4. 10 sessions total by end of Week 8.

Domain order (easiest domain first for early sessions, to de-risk the protocol):
- Week 4: 2 × RNA-seq
- Week 5: 2 × scRNA-seq
- Week 6: 2 × ChIP-seq
- Week 7: 2 × Metagenomics
- Week 8: 2 × cryo-EM

**For each session**:
1. Day before: confirm dataset S3 access with Bob. Confirm BioMate is running. Alert Carol to watch events table live.
2. During: observe silently, timestamped notes. Record screen + audio (OBS, local only).
3. Within 1 hour after: fill observer metrics sheet. Run 10-min interview.
4. Same day: commit `business/usability_sessions/session_N_DOMAIN_YYYYMMDD.md`.

**Parallel: Paper drafting**
As each domain's first 3 benchmark runs complete (Bob emails/messages when ready), Alice writes that domain's case study section. Do not wait for all 10 runs — start writing from Run 3.

**Mid-point check at Week 6** (after 4–5 sessions):
Compute running metrics. Write `business/midpoint_analysis_week6.md`:
- task_completion so far: X/N
- Most common confusion moment: [description]
- If completion < 50%: stop sessions, identify root cause, fix, resume

**Deliverable (end of Week 8)**: 10 session docs committed. Sections 3–4 of paper drafted (one per domain completed).

---

#### Bob — Weeks 4–8: 50 Benchmark Runs + Cost Experiment

**Benchmark run order** (cheapest first):
- Week 4: RNA-seq runs 1–5
- Week 5: scRNA-seq runs 1–5, ChIP-seq runs 1–3
- Week 6: ChIP-seq runs 4–5, Metagenomics runs 1–5
- Week 7: cryo-EM runs 1–5 (most expensive — GPU hours)
- Week 8: buffer + any reruns needed

**Each run**:
1. Submit via BioMate UI using the exact locked prompt from the protocol
2. Record in `business/benchmark_results.csv` (one row per run)
3. All outputs to `s3://biomate-production-data-399683337364/benchmarks/results/<domain>/run_N/`
4. After each run: message Carol the `invocation_id` → she verifies cost record is complete

If a run fails: document failure reason, do not retry more than 2× without root-causing. Failure is data too.

**Pilot vs. Full Cost Experiment** (Weeks 5–6):
Design: use RNA-seq with a synthetic 50-sample dataset (replicate the 4-sample ENCODE data 12×).

- Run A: full 50-sample run directly. Record cost.
- Run B: 5-sample pilot → QC gate pass → full run. Record pilot cost + full run cost.
- Run C: 5-sample pilot with intentional bad parameter (wrong genome/aligner mismatch) → QC gate catches it → fix → re-pilot → full run. Record total.

Key output: "Catching a parameter error via pilot saves $X vs. running the full dataset with the error propagating."
Document in `business/pilot_vs_full_cost_experiment.md`.

**Cost optimization pass** (Week 7, after seeing real cost data):
Top 3 things to check with real numbers in hand:
1. Is spot vs. on-demand actually being used? Check Batch job history.
2. Are any cryo-EM jobs using g6.12xlarge when g6.2xlarge would do?
3. Are EBS volumes from completed Batch jobs being cleaned up? Script weekly cleanup.
Target: ≥ 15% cost reduction vs. the Week 4–5 baseline.
Document in `business/cost_optimization_results.md`.

**Deliverable (end of Week 8)**: 25+ successful benchmark runs across all 5 domains. Pilot experiment results documented. Optimization pass done.

---

#### Carol — Weeks 4–8: LLM Audit, Weekly Snapshots, Pricing Model V1

**LLM Billing Audit** (Week 4–5):
Confirm every LLM provider emits correct billing events.

Procedure: run one workflow per provider, verify Redis record:

| Provider | Fields to check | Expected non-zero |
|---|---|---|
| Anthropic | `usage.input_tokens`, `usage.output_tokens` | `llm_cost`, `llm_tokens_prompt`, `llm_tokens_completion` |
| OpenAI | `usage.prompt_tokens`, `usage.completion_tokens` | same |
| Gemini | `usageMetadata.promptTokenCount`, `usageMetadata.candidatesTokenCount` | same |
| DeepSeek | OpenAI-compatible fields | same |
| Zhipu | OpenAI-compatible fields | same |
| Ollama | may have no usage object — handle gracefully | `llm_cost` = 0 (free), tokens may be 0 |

New test file: `backend/tests/test_llm_billing_all_providers.py` — one test per provider, all passing.

**Weekly Stability Snapshots** (every Friday, Weeks 4–11):
```bash
curl http://localhost:8081/api/health/stability > business/weekly_snapshots/week_N_stability.json
```
Add 3-sentence trend note: which metrics moved, which direction, any flags.
These snapshots are the week-by-week data trail for the investor narrative.

**Pricing Model V1** (Week 6–7):
Once first 15+ benchmark runs have cost data, draft `business/pricing_model_v1.md`:

1. Compute average cost per run per domain from `benchmark_results.csv`
2. Compute blended average across domains (weighted by expected usage mix)
3. Model three tiers at 65% gross margin target:
   ```
   Free:  N_free runs → $0    → sustainable if acquisition value > N_free × avg_cost
   Pro:   N_pro runs  → $29   → constraint: $29 × 0.65 ≥ N_pro × blended_avg_cost
   Lab:   N_lab runs  → $149  → constraint: $149 × 0.65 ≥ N_lab × blended_avg_cost
   ```
4. Stress test: what if cryo-EM becomes 3× current estimate?
5. Compute break-even user count per tier.

**Gate G2 — End of Week 6** (non-blocking for Alice and Bob, blocking for marketing):
- Alice: task completion ≥ 50% in first 5 sessions. If not → stop sessions, fix UX.
- Bob: ≥ 4/5 runs succeed per domain in first pass. If not → root-cause before continuing.
- Carol: cost per run within ±20% of pre-run estimates. If not → re-model.

**Deliverable (end of Week 8)**: LLM audit passing for all providers. 8 weekly snapshots in `business/weekly_snapshots/`. Pricing model V1 drafted.

---

### Weeks 9–11: Repeatability & Lock

---

#### Alice — Weeks 9–11

**Second Cohort** (Week 9): 10 more participants, same protocol, same datasets.
Goal: metrics within 15% of first cohort.

Comparison table (fill after all 20 sessions):

| Metric | Cohort 1 (n=10) | Cohort 2 (n=10) | Delta | Stable? |
|---|---|---|---|---|
| Task completion | X% | X% | ≤15%? | |
| T_first_run median | X min | X min | ≤15%? | |
| Clarification rounds | X | X | ≤15%? | |
| Confidence score | X/5 | X/5 | ≤15%? | |

If any metric exceeds 15% delta: document root cause in `business/repeatability_analysis.md`. Do not lock the model until explained.

**Finalize paper sections 1–5** (Weeks 9–11): incorporate all session data and benchmark results. Target: full draft ready for review by end of Week 11.

---

#### Bob — Weeks 9–10

**Benchmark Runs 6–10** for all 5 domains.
Same protocol. Append to `business/benchmark_results.csv`.

Repeatability check (fill after all 50 runs):

| Domain | Runs 1–5 avg cost | Runs 6–10 avg cost | Delta | Runs 1–5 success | Runs 6–10 success |
|---|---|---|---|---|---|
| RNA-seq | | | | | |
| scRNA-seq | | | | | |
| ChIP-seq | | | | | |
| Metagenomics | | | | | |
| cryo-EM | | | | | |

Target: ≥ 9/10 runs succeed per domain across all 50 runs.

**Methods section for paper** (Week 10–11): Nextflow version, instance types used, AWS region, Batch queue names, software container registry, total benchmark cost for all 50 runs.

---

#### Carol — Weeks 9–11

**Unit Economics** (Week 9–10):
New file: `business/unit_economics_v1.md`

1. **LTV estimate**: Pro user ($29/mo) × estimated retention months. Use session data ("would you continue?") as proxy. Conservative: 6 months. LTV = $174.
2. **CAC for beta**: $0 (referral). Document what referral-based acquisition looks like.
3. **Estimated marketing CAC**: research comparable bioinformatics SaaS tools (Benchling, Basepair, etc.). Estimate $50–150 per user via content/conference.
4. **LTV/CAC at estimated CAC**: must be ≥ 3:1.
5. **Break-even**: how many Pro users to cover monthly COGS (infra + LLM spend)?

**Quota Enforcement** (Week 9):
Before any paid beta, users must be blocked at tier limits.

Add to `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py`:
```python
def check_quota_before_run(self, user_id: str) -> tuple[bool, str]:
    """Returns (allowed, reason). Called before generate_workflow_unified()."""
    used = self._get_monthly_run_count(user_id)
    limit = self._get_tier_limit(user_id)  # free=3, pro=10, lab=100
    if used >= limit:
        return False, f"Monthly limit of {limit} runs reached. Upgrade to continue."
    return True, ""
```

Call this in `backend/lib/galaxy/ai/ai_assistant.py` before `generate_workflow_unified()`. Return HTTP 402 if blocked.

New test file: `backend/tests/test_quota_enforcement.py` — test all three tier limits.

**Lock Pricing Model** (Week 10–11):
After second cohort data and all 50 benchmark runs:
- Update pricing model with final real cost data (not estimates)
- Final tier boundaries: committed, not experimental
- Team sign-off required (all three agree in writing in the doc)
- Save as `business/pricing_model_FINAL.md`

**Gate G3 — End of Week 10**:
- Cohort 2 metrics within 15% of Cohort 1 (Alice)
- ≥ 9/10 runs succeed per domain in Runs 6–10 (Bob)
- Gross margin ≥ 60% at Pro tier using real cost data (Carol)
- LTV/CAC ≥ 3:1 (Carol)

If G3 fails on any dimension: that dimension gets fixed before Phase 4. The other two dimensions continue.

---

### Week 12: Narrative & Go/No-Go

All three contribute to the final evidence package simultaneously.

**Alice**: assemble `business/evidence_narrative_FINAL.md` (the investor narrative — this IS the deck, not a separate slide file):
- Paper draft (all sections, internally reviewed)
- Usability summary table (20 sessions, completion rate, confidence, key quotes)
- 3–5 minute video highlight reel (best moments from session recordings)

**Bob** contributes to narrative:
- Benchmark results table: 50 runs, 5 domains, success rates, avg cost, total benchmark cost
- Pilot vs. full savings: one number ("pilot-first saves $X per user who would have had a bad run")

**Carol** contributes to narrative:
- Unit economics summary: LTV, CAC, LTV/CAC, gross margin, break-even user count
- 12-week stability trend chart: graph of success_rate_pct, task_completion_rate_pct, gross_margin_pct across all weekly snapshots
- Cost per domain table: avg cost per run for each of the 5 domains

**Final Go/No-Go meeting** (Week 12, end):
All three attend. The health dashboard is open on screen. Review all 8 gates.

| Gate | Threshold | Pass? |
|---|---|---|
| G1: Instrumentation + dataset staging + billing wired | Binary | |
| G2: Mid-point UX (completion ≥ 50%) + runs passing + cost model within ±20% | Binary | |
| G3: Cohort repeatability ≤ 15% delta + runs ≥ 90% success + margin ≥ 60% + LTV/CAC ≥ 3:1 | 4-part | |
| G4: 10-week success rate ≥ 95% | Metric | |
| G5: Avg confidence score ≥ 4/5 | Metric | |
| G6: Cost per run matches model ±20% for all 5 domains | Metric | |

**If all 6 gates pass**: proceed to paid beta launch and enterprise outreach.
**If any gate fails**: do not launch. Fix the failing dimension. Re-run the relevant experiment. The 90-day rule is a minimum, not a deadline.

---

## Deliverables by Owner

### Alice
- [ ] `frontend/client/src/lib/analytics.ts`
- [ ] `POST /api/events` endpoint + `events` SQLite table
- [ ] `frontend/client/src/components/run-survey.tsx`
- [ ] `business/usability_session_protocol.md`
- [ ] `business/usability_sessions/session_N_*.md` × 20
- [ ] `business/midpoint_analysis_week6.md`
- [ ] `business/repeatability_analysis.md`
- [ ] `business/usecase_paper_outline.md`
- [ ] Paper sections 1–5, 8 (draft + final)

### Bob
- [ ] `business/benchmark_datasets.md`
- [ ] `business/benchmark_run_protocol.md`
- [ ] `business/benchmark_results.csv` (50 rows)
- [ ] `business/pilot_vs_full_cost_experiment.md`
- [ ] `business/batch_optimization_audit.md`
- [ ] `business/cost_optimization_results.md`
- [ ] `business/chaos_test_results.md`
- [ ] Paper section 7 (methods)

### Carol
- [ ] `backend/tests/verify_billing_e2e.py`
- [ ] `backend/lib/galaxy/ai/billing/api/cost_report_router.py`
- [ ] `GET /api/billing/cost-report` + `/summary`
- [ ] `GET /api/health/stability`
- [ ] `GET /api/health/test-status`
- [ ] `backend/scripts/parse_and_alert_test_results.py`
- [ ] `backend/tests/test_monitor_reliability.py`
- [ ] `backend/tests/test_llm_billing_all_providers.py`
- [ ] `backend/tests/test_quota_enforcement.py`
- [ ] `business/weekly_snapshots/week_N_stability.json` × 8
- [ ] `business/pricing_model_v1.md` → `pricing_model_FINAL.md`
- [ ] `business/unit_economics_v1.md`
- [ ] Paper section 6 (cost analysis)

### All Three
- [ ] `business/evidence_narrative_FINAL.md`

---

## Dependency Map (what blocks what)

```
Alice A1 (events) ──────────────────────→ Carol C3 (health dashboard needs events table)
                                         Alice A5 (sessions need instrumentation)

Bob B1 (datasets in S3) ────────────────→ Alice A5 (sessions need datasets)
                                         Bob B6 (benchmark runs need datasets)

Carol C1 (billing wired) ───────────────→ Carol C2 (cost report needs Redis data)
                                         Bob B6 (each run needs billing verified)

Bob B6 (benchmark costs) ───────────────→ Carol C8 (pricing model needs real cost data)
                                         Alice A6 (paper case studies need run results)

Carol C2 (cost endpoints) ──────────────→ Carol C3 (health dashboard cost section)
                                         Carol C8 (pricing model)

Alice A5 sessions + Carol C3 dashboard ─→ Alice A4 / Carol C8 (midpoint analysis)

All Phase 2 work ────────────────────────→ Phase 3 (repeatability, model lock)
Phase 3 ─────────────────────────────────→ Phase 4 (narrative, go/no-go)
```

Everything else is fully independent and can run in parallel from Day 1.

---

*Plan version: 2026-02-24. Gate reviews: Week 3, Week 6, Week 10, Week 12.*
