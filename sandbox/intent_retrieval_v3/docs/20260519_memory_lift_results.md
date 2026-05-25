# Memory-Recall A/B Lift Results (n=20)

**Date:** 2026-05-19
**Source:** sandbox/intent_retrieval_v3/data/memory_eval_set.yaml
**Library:** sandbox/intent_retrieval_v3/adapters/memory.py
**Intents:** sandbox/intent_retrieval_v3/data/memory_intents.yaml (8 entries)
**Memory files indexed:** 69

## Headline

| Method | Top-1 | Top-3 |
|---|---|---|
| BASELINE (lexical overlap) | 17/20 (85.0%) | 18/20 (90.0%) |
| **TREATMENT (+ memory adapter)** | **20/20 (100.0%)** | **20/20 (100.0%)** |
| Δ top-1 | **+3** (+15.0pp) | +2 (+10.0pp) |

## Flips to correct (3)

- **q01** `what's the latest status of the regulatory LLM v6 v7 training?`
  - expected: `project_regulatory_llm_v6.md`
  - baseline top-3: `['project_regulatory_llm_v4.md', 'project_regulatory_llm_v6.md', 'feedback_inline_data_and_status.md']`
- **q13** `show me the ADMET auto-loop architecture`
  - expected: `project_drug_dev_gaps.md`
  - baseline top-3: `['project_memory_architecture_gaps.md', 'project_cryoem_autoloop.md', 'project_biomate_exec_arch.md']`
- **q14** `tell me about the unified workflow search hybrid retrieval`
  - expected: `project_session5_benchmarking.md`
  - baseline top-3: `['project_hybrid_workflow_search.md', 'project_workflow_pricing_table.md', 'project_boin_100pct.md']`

## Flips to wrong (0)

**None.** Memory adapter never demoted a correct top-1.

## Still failing (0)

