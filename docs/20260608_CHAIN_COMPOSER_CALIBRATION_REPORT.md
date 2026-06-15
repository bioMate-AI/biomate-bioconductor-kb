# Chain Composer — Calibration Report (Run 1, Stub Path)

**Date**: 2026-06-08
**Eval set**: `backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl` (20 queries spanning all 11 active patterns + 3 deliberately-vague + 1 time-series gap probe)
**Path**: stub-only (no LLM calls, deterministic; cost = 0)
**Driver**: `python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl`

## Headline numbers

| Metric | Value |
|---|---|
| Mode match rate | **80% (16/20)** |
| Pattern top-3 hit rate | **90% (18/20)** |
| Confidence median | 0.855 |
| Confidence histogram | 1 / 0 / 1 / 2 / 8 / 8 across bins [0, 0.2, 0.45, 0.6, 0.75, 0.9, 1.0] |
| Sources | 15 curated_passthrough, 5 stub |

## Five mismatches — each is a different lesson

### 1. ADMET auto-loop: `upfront → stepwise` at confidence 0.67
Pattern correctly identified (`iterative_refinement`). Confidence landed at 0.67 — right between the upfront (0.75) and stepwise (0.45) thresholds. **Threshold-tuning candidate**: maybe lower upfront to 0.70 to capture this class. Or the expected value was wrong (iterative QC retry could reasonably default to stepwise so the user sees the first try before committing).

### 2. rRNA branching: `stepwise → upfront`, wrong pattern
Expected `branching_on_qc`, got `sequential_omics_pipeline`. **Retrieval miss** — the pattern library's `when` text for `branching_on_qc` says "QC outcome cleanly partitions the data into branches" but doesn't include keywords like "switch to", "if … over", "threshold". Fix is in the pattern doc.

### 3. "do something cool with the data I have": `reactive → stepwise` at 0.75
Vague query, no NER entities, but BM25 still pulled `filter_cascade` via token overlap on "data". Score 0.75 is exactly at the upfront threshold. **Hard-floor candidate**: when NER entity count = 0, force surfacing mode to `reactive` regardless of other signals. The query has no actionable specificity.

### 4. Mouse WGBS methylation: top pattern wrong but mode right
Got `multi_omics_integration` instead of `sequential_omics_pipeline`. Both modes ended up `upfront` so the mode-match counter passed, but the underlying retrieval was wrong (WGBS is a single modality). **Pattern doc fix**: `sequential_omics_pipeline.When` should explicitly mention WGBS / methylation / single-modality cases.

### 5. Time-course: `stepwise → upfront`, no good pattern
Time-course queries have no pattern in v1 library. The retrieval picked `discovery_then_validation` as a least-bad fit. **Confirmed gap**: `time_series_longitudinal` is in the deferred-candidate list (`docs/20260608_CHAIN_DESIGN_FINDINGS_OPEN_QUESTIONS.md` B1). Worth promoting to v2 of the library.

## Pattern hit-rate by category

All 5 mismatches above are accounted for. Strong hits:

| Pattern | Queries | Top-3 hit |
|---|---|---|
| sequential_omics_pipeline | 3 | 3/3 |
| multi_omics_integration | 2 | 2/2 |
| multi_method_consensus | 2 | 2/2 |
| ensemble_annotation | 2 | 2/2 |
| iterative_refinement | 1 | 1/1 |
| discovery_then_validation | 1 | 1/1 |
| cross_cohort_replication | 1 | 1/1 |
| hierarchical_re_evaluation | 1 | 1/1 |
| filter_cascade | 2 | 2/2 |
| resampling_uncertainty | 1 | 1/1 |
| branching_on_qc | 1 | **0/1** (#2 above) |

Branching-on-QC is the only pattern with a retrieval miss. Easily fixed by pattern doc edit.

## Signal medians

```
normalized_chain_score:     1.0
normalized_pattern_score:   1.0
query_specificity:          0.4
downstream_determinism:     1.0
pattern_chain_agreement:    1.0
```

- `pattern_chain_agreement = 1.0 median` confirms most queries have aligned pattern+chain domains. Disagreement signal won't fire often — and that's OK: it's a guard against the rare case (the biomarker→target_to_lead_full failure we saw before), not a generic dampener.
- `query_specificity = 0.4` median says half the eval queries have only ~2 entities. The eval set may be a bit sparse; real users likely write longer queries with more entities.

## Threshold recommendations (low-confidence — needs more data)

Current: `upfront ≥ 0.75`, `stepwise ≥ 0.45`. From the histogram, 16/20 = 80% upfront ≥ 0.75 — feels right for this corpus but the eval set is small and skewed toward well-formed queries.

**Don't change thresholds yet.** Three fixes are cheaper and more impactful:
1. Add the "zero-entity → reactive" hard floor.
2. Fix the `branching_on_qc` pattern `When` text.
3. Promote `time_series_longitudinal` from deferred to v2 of the library.

## Cost & runtime

- 20 queries, stub path: ~3 seconds wall-clock, zero API cost.
- LLM path (`--use-llm`): ~$0.10-$0.40 estimated and 60-90 seconds (haven't run yet).

## Reproducibility

```bash
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614
export PYTHONPATH=$PWD/backend/lib
python -m galaxy.ai.chain_composer.calibrate \
  backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl
```

Add `--use-llm` after sourcing `backend/.env` to run the real-LLM path.

## Next actions (deferred from this commit)

1. Add zero-entity reactive floor in `composer.py` (small).
2. Edit `branching_on_qc.When` in the pattern library to include "switch", "threshold", "if/else" cues.
3. Author `time_series_longitudinal` pattern (entry 13 in the library).
4. Re-run calibration after each — track mode_match_rate over time.
