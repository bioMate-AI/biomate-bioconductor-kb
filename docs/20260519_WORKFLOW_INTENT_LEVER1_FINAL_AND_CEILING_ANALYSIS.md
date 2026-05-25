# Workflow Intent Anchor — Final A/B + Hard Ceiling Analysis

**Date:** 2026-05-19
**Status:** Lever 1 implementation complete in sandbox. Asymptote reached.
**Final lift:** Top-1 HIT 69.7% → **76.1%** (**+6.5pp**), 10 flips to correct, **0 flips to wrong**.

## Where this lands relative to the hard ceiling

Categorization of the 155 cases by where the correct workflow lands in raw `UnifiedWorkflowSearch.search` results (BGE disabled, local environment):

| Where correct workflow lands | Count | % | Closable by Lever 1? |
|---|---|---|---|
| Top-1 HIT (baseline) | 108 | 69.7% | already there |
| In top-3 (rank 2 or 3) | 17 | 11.0% | YES — intent promotes |
| In top 4-10 | 7 | 4.5% | YES — intent promotes |
| **NOT in top-10** | **23** | **14.8%** | **NO — retrieval-engine issue** |

So the **upper bound for any reranker is 85.2%** (close all 24 in-top-10 misses). My current 76.1% captured 10 of those 24 (41.7% capture rate).

Why we didn't close more:
- 5–6 of the remaining 14 in-top-10 misses are long-tail workflows (e.g., `nf-core/methylarray`, `cite_seq_preprocessing`) that I added YAML entries for but where the trigger terms don't match the user's natural-language phrasing.
- Several are queries that ask about specific tools/sub-steps where the library **deliberately** doesn't fire (e.g., "Generate BigWig coverage tracks" — the search returns `CoverageView`, a tool, and the user's phrasing legitimately asks for a tool, not a pipeline).
- The 23 NOT-in-top-10 cases are out of reach by definition — promotion can't surface what retrieval didn't return.

## Diminishing returns curve

Three iterations of YAML expansion + tightening:

| Iteration | # anchors | Top-1 % | Δ vs baseline | Flips to wrong |
|---|---|---|---|---|
| baseline | 0 | 69.7% | — | — |
| 1st pass (initial 21) | 21 | 72.9% | +3.2pp | 4 |
| 2nd pass (tightened, +3 anchors) | 24 | 74.8% | +5.2pp | 0 |
| 3rd pass (long-tail, +15 anchors) | 39 | 76.1% | +6.5pp | 0 |

The 3rd pass added 15 anchors but lifted only +1.3pp. **Most remaining failures are out-of-top-10 retrieval misses; no amount of reranker work fixes those.**

## Final per-domain breakdown (n=39 anchors)

| Domain | n | baseline | treatment | Δ |
|---|---|---|---|---|
| variant_calling | 17 | 11 | 15 | **+4** |
| rna_seq | 15 | 8 | 10 | **+2** |
| genomics | 6 | 4 | 5 | +1 |
| metagenomics | 13 | 8 | 9 | +1 |
| single_cell | 25 | 20 | 21 | +1 |
| transcriptomics | 11 | 8 | 9 | +1 |
| drug_discovery | 17 | 8 | 8 | 0 |
| epigenomics | 17 | 14 | 14 | 0 |
| immunology | 6 | 6 | 6 | 0 |
| proteomics | 13 | 12 | 12 | 0 |
| virtual_cell | 15 | 9 | 9 | 0 |

The wins are concentrated where pipeline-intent matters most. Domains that already perform well (epigenomics 82%, immunology 100%, proteomics 92%) saw no movement.

## Honest gap between proposal estimate and final result

| Step | Estimate | Actual |
|---|---|---|
| Original proposal (uninformed) | +10pp ship threshold | — |
| After failure categorization | +15.5pp | — |
| Final | — | **+6.5pp** |

Each estimate was overconfident relative to the next measurement. The systematic biases:

1. **Adjacent-failure rate was misjudged.** The categorization doc claimed "many ADJACENT-style failures" — actually only 1.3% of cases.
2. **NOT-in-top-10 fraction was miscounted.** My initial run said 0%; the correct number is 14.8%. The reranker can't help those at all.
3. **Long-tail YAML expansion has diminishing returns.** Adding 15 anchors past the top-24 workflows only captured 2 more wins.

The final +6.5pp is real and the work is genuine, but the **gap from the +15.5pp estimate to the +6.5pp actual** is a lesson on calibrating retrieval-improvement estimates. The ceiling is the ceiling.

## Beyond Lever 1: what would actually push past 76.1%

### Retrieval-engine work (~7-15pp ceiling lift, days of work)
- **Enable BGE dense retrieval locally** — production has this; my baseline doesn't. With BGE on, the 14.8% NOT-in-top-10 group would shrink, possibly closer to 0 per the earlier `routing_v5` benchmark memory (~84% top-1).
- **Query expansion** — synonyms ("RNA-seq" → "transcriptome", "bulk RNA"), better tokenization for hyphenated terms.
- **Description boosting** — the existing `nf-core/rnaseq` description doesn't include phrases like "from raw FASTQ" that users actually type. Curated workflow descriptions matter more than tool-list expansion.

### Lever 2 (domain-gated context injection)
- Per the proposal: inject only the 3-4 routing-prompt rules relevant to the detected domain. Reduces LLM prompt size by 60-80% and may improve LLM verification accuracy. Estimated +1-3pp; complementary to Lever 1, not a replacement.

### Lever 3 (tighter disambiguation gate)
- Skip the disambiguation card when intent-anchor confidence is high. UX improvement, not a top-1 lift.

## Final state of sandbox

```
sandbox/workflow_search_v2/
├── README.md
├── data/
│   └── intent_anchors.yaml          (39 entries)
├── library/
│   ├── __init__.py
│   └── workflow_intent.py            (130 lines, pure function)
├── scripts/
│   ├── categorize_failures.py        (investigation harness)
│   └── measure_intent_lift.py        (A/B harness)
├── tests/
│   ├── __init__.py
│   └── test_workflow_intent.py       (15 tests, all passing)
└── docs/
    ├── 20260519_failure_categorization.md
    └── 20260519_intent_lift_results.md   (auto-regenerated)
```

Production: zero changes.

## Production wiring recipe (unchanged from earlier doc)

```python
# in ai_assistant.py search_ranked endpoint, around line 1700
import os
if os.environ.get("BIOMATE_WORKFLOW_INTENT_PRIORITIZE") == "1":
    from backend.lib.galaxy.ai.retrievers.workflow_intent import prioritize_workflow_by_intent
    wf_results = prioritize_workflow_by_intent(request.query, wf_results)
```

After moving:
- `sandbox/workflow_search_v2/library/workflow_intent.py` → `backend/lib/galaxy/ai/retrievers/workflow_intent.py`
- `sandbox/workflow_search_v2/data/intent_anchors.yaml` → `backend/config/workflow_intent_anchors.yaml`
- Update `_DEFAULT_YAML` path in the library.
- Move tests from `sandbox/workflow_search_v2/tests/` to `backend/tests/`.

Effort: ~30 min code + half day production validation. Sandbox-first stance maintained.

## Cumulative session output (4 commits on origin/integration/next-phase)

| Layer | Lift | Status |
|---|---|---|
| Wrapper-level (`family_dedup`) | 25% → 90% (+65pp, n=40) | library + 60-entry canonical + 155-entry alias data + 29 tests |
| Workflow-level (`workflow_intent`) | 69.7% → 76.1% (+6.5pp, n=155) | library + 39-entry intent data + 15 tests |

Both layers ship the same architectural pattern: curated YAML + pure-function reranker, opt-in via env flag, no production consumers wired this session. Both are reproducible (regenerable from scripts), tested, and documented.
