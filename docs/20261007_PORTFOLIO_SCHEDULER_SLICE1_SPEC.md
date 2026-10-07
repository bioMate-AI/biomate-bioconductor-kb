# Portfolio Scheduler (Slice 1) — Executable Spec

**Date:** 2026-10-07
**Parent design:** `docs/20261005_AGENT_ORCHESTRATION_AND_PARALLELISM.md §5`
**Status:** spec ready; **one architecture decision pending** (§4 below) before the driver is built.
**Target branch:** `integration/next-phase` (forward/roadmap tier, not a dev hotfix).

This converts the §5 "portfolio scheduler" proposal into a concrete build, grounded
in the real building blocks (read-only recon, 2026-10-07). It deliberately splits the
slice into a **decision-independent foundation** (safe to build now) and a
**concurrent driver** (blocked on the §4 decision).

---

## 1. Building blocks it sits on (verified)

| Need | Existing primitive | Location | Nature |
|---|---|---|---|
| One DBTL round | `DeNovoPipeline.run_round(...)` | `backend/lib/galaxy/ai/drug_discovery/denovo_pipeline.py:144` | **sync**; stateless |
| Round/state tracking | `BayesianOptimizer._round_number` → SQLite `bo_proposals` | `.../bayesian_optimizer.py:114,127,309,473` | **sync**; per-campaign DB |
| Continuous driver (today) | `auto_retrain.start_background_loop` / `refit_and_propose` | `.../auto_retrain.py:365,261` | **in-process daemon thread, module-global dicts** |
| Campaign identity + listing | `campaigns` table in `campaigns_registry.db` | `.../drug_discovery/api_router.py:260,272,2214` | SQLite registry |
| Run concurrency ceiling | `_nf_launch_semaphore = BoundedSemaphore(BIOMATE_NF_MAX_CONCURRENT)` | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:140-141,5205-5254` | **in-process, per gunicorn worker** |
| Durable single-owner precedent | `RedisRunStateStore` + `acquire_completion_lock` (SETNX); chain reconciler `chainrehydrate:<id>` | `.../api/nextflow_executor.py`, `.../api/workflow_chain.py` | Redis, cross-worker |

**No `portfolio`/grouping abstraction exists** — green field. The only multi-campaign
object is the flat `campaigns` registry.

## 2. Scope of Slice 1

**Goal:** a driver that owns N campaigns and advances their DBTL loops concurrently,
with a `portfolio_id → [campaign_id]` registry and a round-scheduler. Reuses the
per-campaign API; adds the grouping + the concurrent driver.

### 2a. Foundation (decision-independent — buildable now)
Purely additive; no change to existing campaign behavior:
- **New table `portfolios`** in `campaigns_registry.db`: `portfolio_id PK, user_id,
  name, created_at, spend_cap_usd, max_concurrent, status`. Mirror the existing
  `_registry_conn()` pattern exactly (`api_router.py:265`).
- **New join table `portfolio_campaigns`**: `portfolio_id, campaign_id, added_at,
  priority` (round-scheduler fairness weight).
- **Additive REST (prefix `/api/drug-discovery`)**: `POST /portfolios` (create),
  `GET /portfolios` (list by user), `GET /portfolios/{id}` (status: member campaigns +
  each one's `round_number` via `get_campaign_state`), `POST /portfolios/{id}/campaigns`
  (attach), `DELETE /portfolios/{id}/campaigns/{cid}` (detach).
- **Unit tests** (no live Batch): registry CRUD, membership, status aggregation.

### 2b. Concurrent driver (BLOCKED on §4)
- A `PortfolioScheduler` that, per round-tick, iterates member campaigns by priority
  and advances each (`refit_and_propose` when new assay data has landed, else idle),
  honoring per-portfolio `max_concurrent` and `spend_cap_usd`, with backpressure
  against the NF `BoundedSemaphore`.
- Single-owner across gunicorn workers (see §4).

## 3. Cost & safety rails (from §5.4)
Per-portfolio spend cap + concurrency cap enforced in the driver; the on-prem scope
gate (`docs/20261005_ONPREM_SCOPE_LAYER_PLAN.md`) applied per campaign. These ride on
the driver, so they are gated behind the §4 decision too.

## 4. The one decision I will not make unilaterally

**How should the concurrent driver own and persist its scheduling, given dev runs
4 gunicorn workers (`--workers=4`, per CLAUDE.md "Run-State Persistence")?**

- **Option A — in-process daemon threads** (mirror `auto_retrain.start_background_loop`).
  *Pro:* zero new infra, matches today's per-campaign loop. *Con:* repeats the exact
  anti-pattern the team already abandoned for run-state — with 4 workers each worker
  would double-drive every campaign (duplicate proposals, duplicate spend), and a
  worker recycle silently drops the schedule. Unsafe for unattended spend.

- **Option B — Redis single-owner (RECOMMENDED).** One scheduler instance elected via
  SETNX lease (`portfolio:scheduler:owner`, TTL-renewed), exactly like the chain
  reconciler's `chainrehydrate:<id>` and `acquire_completion_lock`. Schedule state in
  Redis (already provisioned on dev: `RUN_STATE_STORE=redis`). *Pro:* cross-worker
  safe, survives recycles, consistent with the codebase's established durability
  pattern, correct for unattended spend. *Con:* more code than A; depends on Redis
  (already a hard dependency on dev).

**Recommendation: Option B.** It is the only option consistent with the run-state
persistence lessons already documented in CLAUDE.md, and the driver advances real
spend unattended, so correctness under multi-worker/recycle is mandatory.

A secondary confirmation: **build location** — this tier belongs on
`integration/next-phase` (roadmap), not the `cursor/tutorial` dev-hotfix lineage.
Please confirm.

## 5. Plan once §4 is decided
1. Build 2a (foundation) + unit tests on `integration/next-phase`. *(Decision-independent;
   can start the moment the build location is confirmed.)*
2. Build 2b (driver) on the chosen durability model, with spend/concurrency rails.
3. Integration test: a 2-campaign portfolio advancing concurrently against dev, with the
   NF semaphore honored and the spend cap enforced — no speculative large Batch spend.
4. External characterization stays "roadmap, not shipped" until 2b is validated
   (per the no-overclaiming norm).

## 6. Evidence index
Recon 2026-10-07 (read-only). All file:line citations above verified against the tree
at commit `e717e1a51`.
