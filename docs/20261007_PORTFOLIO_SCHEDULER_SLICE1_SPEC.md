# Portfolio Scheduler (Slice 1) — Executable Spec

**Date:** 2026-10-07
**Parent design:** `docs/20261005_AGENT_ORCHESTRATION_AND_PARALLELISM.md §5`
**Status:** ✅ **Slice 1 SHIPPED** on `integration/next-phase` (commit `5aad63b92`, 2026-10-07) —
decision §4 approved as **Option B (Redis single-owner)**. Registry + driver + REST + 9 unit tests
(all green). Scheduler is **inert until explicitly enabled** (see "Remaining to activate" below).
**Target branch:** `integration/next-phase` (forward/roadmap tier, not a dev hotfix).

### What shipped (commit `5aad63b92`)
- `backend/lib/galaxy/ai/drug_discovery/portfolio.py` — additive registry (`portfolios` +
  `portfolio_campaigns` tables beside the campaign registry); CRUD + membership + best-effort
  per-campaign round status. No change to existing campaign behaviour.
- `backend/lib/galaxy/ai/drug_discovery/portfolio_scheduler.py` — the concurrent driver:
  Redis single-owner lease (SETNX+EX, mirrors `run_state_store.acquire_completion_lock`),
  disabled by default (`BIOMATE_PORTFOLIO_SCHEDULER_ENABLED`), refuses to run without Redis,
  fail-closed per-portfolio spend cap.
- `api_router.py` — additive REST: `POST/GET /portfolios`, `GET /portfolios/{id}`,
  `POST /portfolios/{id}/campaigns`, `DELETE /portfolios/{id}/campaigns/{cid}`.
- `test_portfolio.py` — 9 hermetic unit tests, all green; `py_compile` clean (3.9-safe via
  `from __future__ import annotations`).

### Remaining to activate (deliberate, not yet done)
1. **Startup wiring** — call `portfolio_scheduler.start_scheduler_if_enabled()` once per worker
   at app boot, alongside where the other background threads (e.g. CompletionPoller) start. It
   no-ops unless the env flag is set AND Redis is reachable, so wiring it is safe; left for a
   deliberate placement in the boot path rather than an unattended guess.
2. **Enable on an environment** — set `BIOMATE_PORTFOLIO_SCHEDULER_ENABLED=true` (needs
   `RUN_STATE_STORE=redis` + `REDIS_URL`, already present on dev) once startup is wired.
3. **Spend source** — implement `billing.core.realtime_cost_service.portfolio_spend_usd(...)`;
   until then any portfolio with a `spend_cap_usd` is skipped (fail-closed by design).
4. **Slice 2+** — the §5.2–5.4 items below (managed run queue, planner promotion, full rails).

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

## 5b. Slice 2 — managed run queue ✅ SHIPPED (`integration/next-phase`)

**Tech-committee decision (unanimous, 2026-10-07)** — three reviewers (concurrency/systems,
blast-radius, codebase-fit) all voted:
- **(a) A1** — a *separate* portfolio-level run queue layered ABOVE the per-worker
  `_nf_launch_semaphore`; leave `BIOMATE_NF_MAX_CONCURRENT` untouched. A2 (promoting the
  semaphore into a cross-worker queue) was rejected: it rewrites a load-bearing OOM guard on
  the hot path of *every* run and re-opens the cross-worker stuck-slot hazard the run-state
  persistence project closed.
- **(b) Redis**, as a `run_state_store`-style Protocol (InMemory + Redis + factory).

**Mitigations all three flagged, now implemented:**
1. Admission counts against a **global cross-worker in-flight counter** (Redis `SCARD`), so the
   per-worker semaphore behaves as a true global cap when the single owner drains.
2. Launch-path **503 ⇒ requeue** (bounded retries), never a run failure.
3. **Fail-closed** without Redis (`get_portfolio_queue()` returns `None` → scheduler dormant).
4. Spot-killed runs → requeue with bounded retries (only possible because the queue is in Redis).

**Shipped commits:**
- `01ff43ac1` — `portfolio_queue.py`: `PortfolioRunQueue` Protocol + `InMemoryPortfolioQueue` +
  `RedisPortfolioQueue` + `get_portfolio_queue()` factory (fail-closed). 6/6 tests (both backends).
- `3067ab18a` — dispatcher: owner-only drain in `PortfolioScheduler.tick()`; global +
  per-portfolio cap admission via `try_dequeue(exclude=...)`; 503-backpressure requeue; no-op
  unless a queue AND `launch_fn` are wired. 14/14 scheduler tests.

**Remaining to activate slice 2** (deliberate, not done — same posture as slice 1's startup wiring):
- Wire a real `launch_fn`: round-robin `POST /api/nextflow/execute` across the 4 workers,
  mapping HTTP 503 → `"backpressure"`, terminal states → `mark_done` via the completion poller.
- Add the enqueue hook: where a portfolio decides a campaign needs a Batch-backed run (extend
  `_advance_portfolio`), `enqueue()` the run spec.
- Set `PORTFOLIO_QUEUE_STORE=redis` (+ the existing `REDIS_URL`) and the enable flag.

## 5c. Deferred follow-up slices (committee-recommended, kept SEPARATE)
1. **Promote `_nf_launch_semaphore` to a Redis-counted global cap.** The per-worker semaphore's
   documented OOM bound (comment `nextflow_executor.py:129-139`, "10 heads × 0.7 GB = 7 GB") is
   *already false* under 4 workers (real ceiling 10–40 heads). This is the genuine root-cause fix
   for the uncoordinated ceiling — but it belongs on its own focused, independently-testable slice
   with fail-open to today's `BoundedSemaphore`, NOT bundled into a drug-discovery feature.
2. **Converge the 3 semaphore-bypassing NF launches** onto the gated seam: fetchngs prefetch
   (`nextflow_executor.py:4739`), accession-chain main (`:5109`), validate_profile (`:9887`).
   Until then an accession-heavy portfolio can still bypass both the semaphore and the portfolio
   queue — a real OOM gap to close.

## 6. Evidence index
Recon 2026-10-07 (read-only). All file:line citations above verified against the tree
at commit `e717e1a51`. Slice 2 design = tech-committee synthesis 2026-10-07.
