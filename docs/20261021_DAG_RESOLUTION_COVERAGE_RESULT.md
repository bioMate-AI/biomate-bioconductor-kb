# DAG composer — resolution coverage (offline measurement)

**Date:** 2026-10-21
**Probe:** `evaluation/local_trial/dag_resolution_coverage.py`
**Question:** Is enabling the multi-task DAG composer a wiring/flag task, or is resolution
confidence the real gap (a retrieval/training project)?
**Answer:** **Wiring, not training.** The harness resolves real decomposition subtasks ~fully.

## Setup
- 68 real topologies from `decomposition_real` (nf-core/chain/GTN), assuming a **perfect
  decomposition** (uses the gold subtasks) to isolate the HARNESS resolution + assembly gate.
- Real production resolver: `UnifiedWorkflowSearch.search(desc)` → `pick_workflow_match` with
  score ≥ `DAG_RESOLVE_MIN_SCORE` (6.0) — the exact path `ai_assistant._resolve_task_to_workflow`
  uses. Over the present workflow DB (324 MB).
- `build_dag_plan` returns None if ANY subtask fails to resolve, so per-plan "all-resolve" is the
  FIRE upper bound.

## Result

| Subtask description | per-subtask resolved | per-plan all-resolve (fire upper bound) | top-match score (min/med/max) |
|---|---|---|---|
| natural (`role + domain`) | **246/246 = 100%** | **68/68 = 100%** | 14.6 / 24.2 / 81.0 |
| raw token (`sub_task`)     | 206/246 = 84%      | 48/68 = 71%                              | 0.0 / 22.1 / 102.2 |

By structure (natural desc): sequential 60/60, mixed 5/5, parallel 3/3 — all resolve.

## Interpretation
- **Resolution is NOT the bottleneck.** With a natural description, every subtask of every real
  topology clears the ≥6 confidence bar by a wide margin (median 24). The composer would fire on
  essentially all real multi-task queries.
- The raw-token row (84%/71%) shows resolution is phrasing-sensitive: a decomposition must emit
  natural descriptions (role/domain prose), not bare tool-id tokens. Real LLM decompositions do.
- **P1 is a wiring task, not a training project** — consistent with `20261012` (composer is on
  `generate_workflow`, not the live `generate_workflow_unified`). The lever is the endpoint hook,
  not retraining resolution confidence or a bigger model.

## Caveats (honest)
- **FTS/BM25 only** — the embedding model was blocked for env reasons (anaconda scipy ABI). Dense
  retrieval OFF; production with embeddings ON can only add coverage, and scores already sit ~4×
  above the bar, so the conclusion is robust.
- **Perfect-decomposition assumption** — this measures the harness ceiling given correct subtasks;
  LLM decomposition QUALITY is a separate, already-benchmarked axis (decomposition_real,
  DECOMP_SOLVE_LADDER).
- **Type-handoff gate NOT measured** — dependent steps (60/68 sequential) also need a
  type-compatible handoff (`_workflow_io_types`/`_get_workflow_types`). That can only lower fire
  from 100%; it is the next cheap check (needs importing `workflow_chain`). It does not change the
  "wiring not capacity" conclusion.

See `20261021_PERFORMANCE_DIAGNOSIS.md`, `20261012_COMPOSER_FLAG_ENABLED_AND_WIRING_GAP.md`.
