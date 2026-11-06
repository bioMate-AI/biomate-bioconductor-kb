# Reconciliation — built+validated components vs the Integrated Harness Roadmap

**Date:** 2026-10-11
**Purpose:** `docs/20261009_INTEGRATED_HARNESS_AND_MODEL_ROADMAP.md` (Track A) is now the authoritative
plan. Several of its priorities were **already built and validated** (2026-10-08) and are sitting
**inert on feature branches, not merged**. This note maps them so the roadmap owner **reuses rather
than rebuilds** — especially the fan-out primitive. Nothing here is wired live.

## Built components → roadmap priorities
| Roadmap item (Track A) | Already built | Branch / status |
|---|---|---|
| **P1 — "Durable fan-out/join integration"** (the bounded parallel map+reduce primitive; roadmap: *"distinguish workflow parallelism from parallel LLM agents"*) | **`backend/lib/galaxy/ai/map_reduce.py`** — bounded `ThreadPoolExecutor` fan-out, input-order results, per-unit fault isolation (`errors` list), optional `reduce_fn`. **11/11 tests on Python 3.9.** | `feat/orch-retrieval-s2-20261008` — **REUSE this; do not rebuild the fan-out.** (Note: this is the in-process primitive; the *durable* restart/cancel/no-duplicate-jobs semantics P1 also asks for belong on the executor + RunStateStore, layered above this.) |
| Orchestration layer — single-vs-multi / "selective specialist agents" (P2) | **`backend/lib/galaxy/ai/pattern_router.py`** — capability-gated decision (NMI saturation rule + task-shape → SINGLE / MULTI_SPECIALIST / PIPELINE / PARALLEL_FANOUT); flag-gated `ai_assistant.py` hook that is a **verified no-op when off**; activates the dormant `agent_orchestrator`. 12+15 tests on 3.9. | `feat/orch-retrieval-s2-20261008` — the logical-plan→executable adapter (P0) can consult this for the single-vs-multi call. |
| Retrieval / "intent+context resolution + skill retrieval", grounded synthesis | **`backend/lib/galaxy/ai/corpus_fs/`** — `CorpusIndex` Protocol + FTS5 backend + `ls/cat/grep/find` (grounded-by-construction) + `corpus_map` (per-doc fan-out via `map_reduce`). 14+11 tests on 3.9. + a `corpus_fs` fetcher in `federated_query`. | `feat/corpus-fs-20261008` / `feat/orch-retrieval-s2-20261008` — the grounded-evidence substrate; AACT/target-id plan (`docs/20261008_AACT_TARGET_IDENTIFICATION_INGESTION_PLAN.md`) builds on it. |
| Parallel-campaign ("virtual pharma") tier | **portfolio scheduler slices 1–2** (registry + Redis single-owner driver + managed run queue) | **already on `integration/next-phase`** (`5aad63b92`…`3067ab18a`). |

Full validation evidence: `docs/20261008_ORCHESTRATION_RETRIEVAL_S1_S2_VALIDATION.md` (63/63 on Py3.9,
live-hook no-op proof, no regressions).

## What is NOT mine / stays with the roadmap owner (don't duplicate)
- **P0 foundation** — plan/dependency/context preservation across transport, benchmark-ranking +
  completion semantics, the **logical-plan→executable-plan adapter**, and the **parent evidence/report
  contract**. These precede P1. The adapter is the right place to *consume* the LLM plan (fixing the
  `ai_assistant.py:724` plan-discard noted in `project_composer_execution_bottleneck`) and to call into
  `map_reduce` for the fan-out stage.
- The agent-runtime trial (Hermes/DeepSeek as a separate worker) and Track B skills.

## Decision needed
These branches are inert + validated but **unmerged**. Options: (a) merge `feat/orch-retrieval-s2`
into `next-phase` so the roadmap's P1 can import `map_reduce`/`pattern_router`/`corpus_fs` directly;
(b) leave on-branch and have the roadmap owner cherry-pick; (c) hand this note to that session to
reconcile first. Recommend (a) once the roadmap owner confirms the `map_reduce` interface fits their
P1 — it avoids a second, divergent fan-out implementation.
