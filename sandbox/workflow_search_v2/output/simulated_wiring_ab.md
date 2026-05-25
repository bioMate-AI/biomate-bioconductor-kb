# workflow_intent Simulated Wiring A/B

**Date:** 2026-05-20
**Eval:** `evaluation/datasets/cross_domain_routing/queries.yaml` (n=155)
**BGE dense retrieval:** DISABLED (local)
**Approach:** call UnifiedWorkflowSearch.search() directly, then apply prioritize_workflow_by_intent — same as wiring patch would do in ai_assistant.search_ranked. No production modifications.

## Utility

| Metric | Baseline | Treatment | Δ |
|---|---|---|---|
| Top-1 hit rate | 108/155 (69.7%) | 122/155 (78.7%) | **+14 hits (+9.0pp)** |

## Time cost

### Full call latency (search + maybe-prioritize)

| Metric | Baseline | Treatment | Δ |
|---|---|---|---|
| mean | 138.8ms | 137.1ms | -1.69ms |
| p95 | 152.9ms | 149.0ms | -3.98ms |

### Prioritize-only overhead

| Metric | Value |
|---|---|
| mean | -1.687ms |
| p50 | 0.399ms |
| p95 | 16.696ms |
| p99 | 22.327ms |
