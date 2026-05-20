# family_dedup Held-Out Safety Eval (n=30)

**Date:** 2026-05-20
**Source:** `sandbox/retrieval_v2/tests/suite_eval_heldout.yaml`
**Library:** `backend/lib/galaxy/ai/retrievers/family_dedup.py`
**Maps:** alias (155 rules) + canonical (60 entries) — both PRODUCTION YAMLs

## What this measures

Each query is about a tool family NOT in `tool_family_canonical.yaml` or `tool_family_aliases.yaml`. For uncovered queries, `prioritize_query_family()` should leave the candidate list unchanged. Any difference is a false positive (library acting on queries it wasn't curated for).

## Headline

| Metric | Value |
|---|---|
| Queries identical to baseline | 30/30 (100%) |
| False-positive differences | 0 |

✅ **Library passes held-out safety.** Zero behavior change on 30 uncovered families. The disqualifier discipline holds: `_infer_target_family()` correctly returns None when no known family-keyword appears in the query.

## Interpretation

This is the same honest-measurement discipline applied to the memory adapter (`docs/20260520_memory_heldout_results.md`). For the wrapper-level family_dedup library, 'safety on held-out' means: when the YAML doesn't know about a family, the library returns input unchanged. No magic generalization, no false promotion.

Combined with the earlier 40-query covered-set lift (25% → 90%), this completes the honest evaluation of family_dedup:

| Subset | n | Result |
|---|---|---|
| covered (canonical YAML) | 40 | top-1 25% → 90% (+65pp) |
| **held-out (no YAML entry)** | **30** | **30/30 identical, 0 false positives** |
