# sandbox/workflow_search_v2/

**Status:** sandbox — nothing here imported by production.

Workflow-level analog to `sandbox/retrieval_v2/`. The retrieval_v2 sandbox
addressed Galaxy-wrapper-level search (12,274-row catalog). This sandbox
addresses workflow-level search (~40 nf-core + biomate workflows) — a
different problem shape (semantic adjacency, not noise) but the same
"data over schema" lesson applies.

## Proposal

See `docs/20260519_WORKFLOW_SEARCH_IMPROVEMENT_PROPOSAL.md` for the full
analysis. Three candidate levers ranked, with an investigation step gating
which one to build.

## Layout

```
data/        # intent_anchors.yaml — built only when Lever 1 picked
scripts/     # measure_workflow_routing.py — 155-case A/B harness
docs/        # findings from each investigation step
```

## Promotion criteria

Same as retrieval_v2:
1. Investigation report shows the lever matches the actual failure distribution
2. A/B re-run shows top-1 ≥ +5pp on the existing 155-case benchmark
3. Tests pass against live search stack
4. **Then** propose production wiring behind a feature flag
