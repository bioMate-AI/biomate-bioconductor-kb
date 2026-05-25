# Memory-Recall A/B — Held-Out Subset Honest Measurement

**Date:** 2026-05-20
**Source:** `sandbox/intent_retrieval_v3/data/memory_eval_set_v2.yaml` (n=50)
**Library:** `sandbox/intent_retrieval_v3/adapters/memory.py`
**Intents:** `sandbox/intent_retrieval_v3/data/memory_intents.yaml` (10 entries)
**Memory files indexed:** 69

## Why this run exists

The earlier 20-case A/B (`20260519_memory_lift_results.md`) hit 100% top-1 after 2 alias entries were added to close 2 specific misses. That risks overfitting. This run splits the eval into a **covered** subset (20 queries the intent YAML has entries for) and a **held-out** subset (30 queries with NO intent entries). Honest measurement of whether the adapter helps queries it wasn't curated for.

## Headline

| Subset | n | BASELINE top-1 | TREATMENT top-1 | Δ |
|---|---|---|---|---|
| covered | 20 | 17/20 (85%) | 20/20 (100%) | +3 |
| heldout | 30 | 28/30 (93%) | 28/30 (93%) | +0 |
| **TOTAL** | 50 | 45/50 (90%) | 48/50 (96%) | **+3** |

## Critical: false positives by subset

| Subset | Flips to correct | Flips to wrong |
|---|---|---|
| covered | 3 | 0 |
| heldout | 0 | 0 |

## Interpretation

✅ **Safe on held-out**: 0 false positives on 30 queries the YAML doesn't cover. Adapter does no harm on uncovered queries; lift on those is +0/30.

## Architectural conclusion

The framework + memory adapter is **production-safe** only if the held-out false-positive count stays at 0. The lift comes from curating intent entries for known query patterns — and the adapter's value is bounded by how well the YAML covers real user queries. This is the data-not-schema tradeoff: cheap to extend, fast feedback loop, but no magic generalization to queries you didn't anticipate.
