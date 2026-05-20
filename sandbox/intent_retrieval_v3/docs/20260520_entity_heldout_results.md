# Entity Adapter Held-Out Results (n=30)

**Date:** 2026-05-20
**Eval:** `sandbox/intent_retrieval_v3/data/entity_heldout_eval.yaml`
**Adapter:** `sandbox/intent_retrieval_v3/adapters/entity.py`
**YAML coverage:** 17 entries

## What this measures

Three categories of held-out behavior:

- **empty-expected**: query has no entities in YAML → adapter must return []
- **substring traps**: similar-looking names (TPM3, TP53BP1) must not falsely match TP53
- **partial coverage**: query has SOME known + SOME unknown entities → return only the known ones

## Headline

| Metric | Value |
|---|---|
| Cases perfect (no FP, no FN) | 29/30 (96.7%) |
| **False positive extractions** | **0** |
| False negative (missed) | 1 |
| Cases with FPs | 0 |
| Cases with FNs | 1 |


## False negatives (1 cases)

- **h10** `BRCA-associated breast tumors with somatic variants`
  - expected: `['breast_cancer']`
  - extracted: `[]`
  - missed: `['breast_cancer']`

## Interpretation

✅ **Zero false positives across 30 held-out queries** — the adapter never extracts an entity that isn't actually in the query. The word-boundary substring matcher correctly rejects TPM3, TP53BP1, BRCA-substring-without-digit, and similar near-misses.

⚠️  1 missed extractions. These cost lower than FPs — a missing entity falls back to existing fuzzy retriever behavior.

