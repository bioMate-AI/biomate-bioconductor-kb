# Orchestration + Retrieval workstreams — S1/S2 build & validation record

**Date:** 2026-10-08
**Branch:** `feat/orch-retrieval-s2-20261008` (off `integration/next-phase`; merges the two S1 branches
`feat/pattern-router-20261008` + `feat/corpus-fs-20261008`).
**Posture:** everything additive, **disabled-by-default**, no network, no live-behavior change unless a
flag is explicitly set. Nothing deployed.

## What shipped
| Piece | Module | Commit |
|---|---|---|
| Pattern Router S1 (capability-gated decision + flagged dispatch) | `ai/pattern_router.py` | `d1bb6372a` |
| corpus_fs S1 (CorpusIndex Protocol + FTS5 backend + ls/cat/grep/find) | `ai/corpus_fs/` | `5740c2f36` |
| Shared map-reduce fan-out | `ai/map_reduce.py` | `ada899f13` |
| corpus_map + federated_query `corpus_fs` fetcher | `ai/corpus_fs/map.py`, `ai/federated_query.py` | `20085d27b` |
| PARALLEL_FANOUT via map_reduce + real-signal baselines + flagged live hook | `ai/pattern_router.py`, `ai/ai_assistant.py` | `6f4da7a04` |

## Validation performed (2026-10-08) — all green
- **Tests: 63/63.** Direct runs: map_reduce 11, pattern_router 12, pattern_router_s2 15, corpus_fs 14,
  corpus_map 11. `pytest` collection across all five: **63 passed** (lone warning = pre-existing
  `asyncio_mode` config option in repo `pytest.ini`, unrelated).
- **Production-runtime syntax gate:** `py_compile` passes on **real Python 3.9** (not just 3.14) for all
  six new/edited files — rules out the PEP 604 union import-crash class (CLAUDE.md pre-sync step 3).
- **Live-hook no-op proof (read firsthand, `ai_assistant.py:557-591`):** when
  `BIOMATE_PATTERN_ROUTER_ENABLED` is unset/false the body executes only one stdlib env read and falls
  through to the **unchanged** `generate_workflow_unified` call (lines 589-591) — byte-for-byte today's
  single-pass path. When enabled it only short-circuits if a dispatch returns a dict; every exception is
  caught and falls through. The default workflow-routing strength is not touched.
- **No regression:** `federated_query` change is additive/opt-in (the `corpus_fs` fetcher returns `[]`
  unless `CORPUS_INDEX_BACKEND=fts5` + `CORPUS_INDEX_DB` present); no existing `federated_query`/
  `ai_assistant` test exists to break (only the new consumer test references `federated_query`).

## Known-not-done (intentional; for whoever continues)
- **verification_layer.py is NOT on `next-phase`** (lives on the dev/cursor lineage). Reviewer-gate
  wiring (§5.2 ensemble-consensus) is deferred until it's ported.
- **Real benchmark baseline signal is dormant on this branch** (no `evaluation/results/` here) → the
  router currently resolves to the conservative static table; it auto-lights-up if those summaries exist
  at runtime or `BIOMATE_EVAL_RESULTS_DIR` is set.
- **PaperQA2 synthesis** in `corpus_map` is a marked injection point (`synthesis: None`), not wired —
  no LLM/network called.
- **Live wiring is flag-gated only.** Turning the router on in a real environment
  (`BIOMATE_PATTERN_ROUTER_ENABLED=true`) is a deliberate, separately-reviewed step — and it depends on
  the dormant `agent_orchestrator`'s real result shape, which is unverified at runtime.

## Relationship to the composer/execution gap
This fan-out substrate (`map_reduce` + `corpus_map`) is the **execution** complement to the
task-decomposition/composer plan in `docs/20261008_REQUIREMENT_COMPOSER_EXECUTION_SUBSTRATE.md`
(P2 parallel DAG executor consumes the LLM's plan; this provides the bounded parallel map+reduce it runs
on). They converge; keep them consistent.
