# BioMate Agent Orchestration & Parallelism — current state + parallel-campaign design

**Date:** 2026-10-05 · **Status:** architecture assessment (code-grounded) + forward design.
**Method:** read-only code investigation of `/Users/kky/biomate-review` (branch
`cursor/tutorial-live-recording-and-report-editing-4ea7`) + `/Users/kky/biomate-connector`.
**Honesty contract:** every "exists" claim carries a file:line; sequential/aspirational parts are
labelled as such. This is an internal engineering doc.

## 1. Executive summary
BioMate turns **one request into one workflow** via a deterministic, **search-first single-pass**
pipeline, then relies on **Nextflow + AWS Batch for genuine intra-workflow parallelism**. Its *agent*
and *campaign* machinery is **sequential and single-track**, with only narrow, fixed-degree parallel
LLM/IO calls. It is a strong **execution engine**, not a parallel autonomous-agent "virtual pharma."
That latter characterization would be an overclaim. ("Virtual Pharma" appears in the repo once — as a
*competitor* in `docs/20261005_MARKETING_WORKSTREAM_HANDOFF.md:51`, not as a BioMate capability.)

## 2. Orchestration control flow (how a request becomes action)
**Live path = `generate_workflow_unified` (search-first, single-pass).**
- Default/stable path: `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:3658,3810`; impl
  `backend/lib/galaxy/ai/ai_assistant.py:4181`. Sequence: deterministic intent router
  (`UnifiedIntentRouter`, `ai_assistant.py:3263-3277`, Instant/Cloud lane map `:3141-3146`) → search the
  catalog (UnifiedWorkflowSearch, ~950+ indexed) → inject long-term-memory corrections → assemble **one**
  workflow. No `asyncio.gather` / ThreadPool / agent fan-out in this path.
- **Multi-agent orchestrator = dormant on chat.** `generate_workflow_multi_agent` endpoint exists
  (`ai_assistant.py:4136`; impl `backend/lib/galaxy/ai/ai_assistant.py:1303`; proxy *defined but uncalled*
  `frontend/server/galaxy-api-proxy.ts:814`) — no live chat call site. Even when invoked, the orchestrator
  (`backend/lib/galaxy/ai/agents/agent_orchestrator.py:113-226`) is a **fixed 3-phase sequential pipeline**:
  route once → consult ≤3 domain specialists → assemble once → **one** workflow. No planner, no ReAct/
  tool-calling agent loop, no delegation tree.
- **Chain composer = shadow/telemetry-only** (default off, log-only, never load-bearing):
  `backend/lib/galaxy/ai/ai_assistant.py:504-507` (`BIOMATE_COMPOSER_SHADOW=1`).
- **QC auto-loop (design→make→test / PROCEED-RETRY) = per single run, sequential.** Gates keyed by
  `invocation_id` (`nextflow_executor.py:554,3335,3465`); remediation maps error classes → `auto_fixable`
  retry (`:1003-1051`, e.g. OOM → retry with more memory); SSE `autoloop_gate_results`/`autoloop_update`
  for one run (`:3443-3520`). One workflow at a time, not a parallel loop.

## 3. Parallelism inventory
| Dimension | Reality | Evidence |
|---|---|---|
| **Within one workflow** (Nextflow tasks → AWS Batch) | ✅ **Real, load-bearing** (~200 concurrent tasks, spot fleet). But it is Nextflow's DAG scheduling, not an *agent* capability. No hand-authored `maxForks`/array-jobs found — relies on NF defaults. | `nextflow_executor.py:1357,2247-2253,5932`; spot retry `:3068-3072` |
| **Parallel domain specialists** | ⚠️ Real but **fixed-degree 1–3**, only in the dormant multi-agent mode; falls back to sequential. | `backend/lib/galaxy/ai/agents/domain_specialist.py:119-160` (`ThreadPoolExecutor`, 30s/25s timeouts) |
| **Literature / federated search** | ✅ Concurrent **I/O** fan-out (not agents). | `literature_clients.py:626,735`; `federated_query.py:573-579`; `research_agent.py:1636` |
| **GP-Pareto / ADMET optimizer** | ⚠️ **Batch of candidates per round** (EHVI + Tanimoto diversity), but **rounds are sequential** and within-round selection is a greedy loop. | `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py:175-201,323-326,395` |
| **Across runs** (many workflows at once) | ❌ A concurrency **cap** (`BIOMATE_NF_MAX_CONCURRENT`≈10 `BoundedSemaphore`) — a **throttle**, not a fan-out. No product-level "launch N runs." | `nextflow_executor.py:140-141,5101-5110` |
| **Multi-campaign / portfolio / concurrent multi-target design** | ❌ **Not implemented.** DBTL loop is one campaign, one build-test, sequential rounds. | see §4 |
| **Parallel multi-run firing** | only in **dev/benchmark harnesses**, not product. | `scripts/sweep_drug_dev_workflows.sh:16,124-133` (`PARALLELISM=10`); `benchmark_suite.py:1100` |

## 4. "Virtual pharma" verdict — not present
- The **DBTL design-make-test controller is strictly sequential over one campaign**:
  `/Users/kky/biomate-connector/lab_instruments/dbtl_controller.py:81-108` — `for i in range(1, max_iterations+1): design → _build_and_test → analyze → decide`, one build/test at a time.
- The bridge binds **one** backend campaign to one controller: `campaign_dbtl_bridge.py:8,140,239-305`
  (the backend GP is "the orchestration brain" for a *single* campaign's round N→N+1).
- Backend campaign API is **per-campaign** (`backend/lib/galaxy/ai/drug_discovery/api_router.py:5-27`,
  keyed by `{campaign_id}`) — no endpoint/orchestrator advances many campaigns concurrently.
- Repo-wide search: no `portfolio` / `multi-campaign` / `parallel campaign` orchestration code; `multi-target`
  hits are container-naming utilities, not a discovery engine.

## 5. Forward design — a parallel-campaign ("virtual-pharma") tier
This is a **net-new orchestration tier on top of the existing engine**, not a rewrite. The building blocks
(per-campaign GP brain, per-campaign REST API, Batch intra-workflow parallelism) already exist; what is
missing is the concurrent driver. Proposed, smallest-risk-first:

1. **Portfolio scheduler** — a driver that owns N campaigns and advances their DBTL loops concurrently
   (one `DBTLController` per campaign, run under an async task group / worker pool). Reuses the existing
   per-campaign API; adds a `portfolio_id → [campaign_id]` registry + a round-scheduler.
2. **Managed parallel run queue** — promote the `BIOMATE_NF_MAX_CONCURRENT` *throttle* into a real queue
   with fairness + backpressure, so a portfolio can have many runs in flight safely (spot-aware, cost-capped).
3. **Promote the planner** — wire the dormant multi-agent orchestrator (or the shadow chain composer) onto a
   real path so a campaign can decompose into parallel sub-goals, rather than route→assemble-one.
4. **Cost & safety rails** — per-portfolio spend cap, concurrency cap, and the on-prem scope gate
   (`docs/20261005_ONPREM_SCOPE_LAYER_PLAN.md`) applied per campaign.

Characterization to use externally (honest): BioMate is a **parallel execution engine** today; a
**parallel-autonomy / portfolio tier** is a scoped, additive build — present it as roadmap, not as shipped
(per the "proposals are forward-looking" and "no-overclaiming" norms).

## 6. Evidence index
Live generator `ai_assistant.py:3658,3810` / `backend/lib/galaxy/ai/ai_assistant.py:4181` · multi-agent
(dormant) `agent_orchestrator.py:113-226`, proxy `galaxy-api-proxy.ts:814` · specialists
`domain_specialist.py:119-160` · run cap `nextflow_executor.py:140-141,5101-5110` · Batch
`nextflow_executor.py:1357,2247,5932` · QC loop `nextflow_executor.py:554,1003-1051,3443-3520` · composer
shadow `ai_assistant.py:504-507` · optimizer `bayesian_optimizer.py:175-201,323-326,395` · DBTL
`biomate-connector/lab_instruments/dbtl_controller.py:81-108`, `campaign_dbtl_bridge.py:8,140,239-305` ·
campaign API `drug_discovery/api_router.py:5-27` · dev sweep `sweep_drug_dev_workflows.sh:16,124-133`.
