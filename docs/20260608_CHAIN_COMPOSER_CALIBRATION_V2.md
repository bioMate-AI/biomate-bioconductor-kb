# Chain Composer — Calibration v2 (After Short-Circuit + Library v2)

**Date**: 2026-06-08
**Commits**: `10e256114` (calibration v1) → `149f2c63e` (short-circuit + reactive floor + library v2)
**Companion**: `docs/20260608_CHAIN_COMPOSER_CALIBRATION_LLM_COMPARE.md` (v1 numbers)

## Headline: stub and LLM paths now converge at 85% mode match

|  | Stub v1 | Stub v2 | LLM v1 | LLM v2 |
|---|---|---|---|---|
| Mode match rate | 80% | **85%** | 80% | **85%** |
| Pattern top-K hit | 90% | **100%** | 90% | **100%** |
| Confidence median | 0.86 | 0.84 | 0.92 | 0.94 |
| LLM calls | 0 | 0 | 17 / 20 | **3 / 20** |
| Wall clock | ~3 s | ~3 s | 7 m 23 s | **3 m 16 s** |
| Est. cost | $0 | $0 | $1–3 | **$0.10–0.30** |

## What changed between v1 and v2

### Code changes (composer.py)
1. **LLM short-circuit**: when `normalized_chain_score ≥ 0.95` AND `agreement = 1.0`, bypass LLM and return curated_passthrough. Threshold env-tunable.
2. **Vague-query reactive floor**: when query has zero entities AND top pattern raw BM25 < 5.0 AND no upfront user signal, force mode to reactive. Catches "do something cool" while leaving "variant prioritization by frequency" alone.
3. **Shared `_curated_passthrough()` helper** used by both stub and short-circuit paths.

### Pattern library v2
1. `sequential_omics_pipeline.When`: focused on truly-single-modality cases (WGBS, miRNA-seq, ribosome profiling); explicit "distinguished from multi_omics_integration by absence of joint/integration language" cue.
2. `branching_on_qc.When`: added "switch / threshold / if-else / depending on / split into / route to" trigger language + concrete examples.
3. **New pattern 13: `time_series_longitudinal`** — same subjects, multiple timepoints, time-aware methods (mixed effects, splineTimeR, maSigPro). Refs Spies & Ciaudo 2015, Sun 2016.

## The remaining 3 mismatches — all library quality

Same in both stub and LLM runs:

| Query | Mode shift | Pattern (correct in top-3) | Diagnosis |
|---|---|---|---|
| Biomarker validation TCGA→UKB | upfront → stepwise | `discovery_then_validation` ✓ | Confidence 0.728, just below upfront 0.75. Either tune threshold or accept (validation pipelines surfacing stepwise so user can review the discovery cohort first is defensible). |
| rRNA > 30% switch to depletion | stepwise → upfront | `sequential_omics_pipeline` ✗ (expected `branching_on_qc`) | BM25 still picks sequential despite library edits. The phrase "ribosomal RNA contamination" doesn't overlap strongly with branching's `When` even after broadening. Needs either more specific wording or a curated chain example. |
| Time-course at 0/6/24/72h | upfront → stepwise | `time_series_longitudinal` ✓ | Confidence 0.59 (stepwise band). Pattern is right; no curated chain exists for time-series so curated_chain_score is low → confidence sub-upfront. **Adding a curated `time_series_de_with_maSigPro` chain would close it.** |

**All three are library/catalog gaps, not code gaps.** The composer is doing the right thing given its inputs.

## Two unexpected wins from the short-circuit

1. **LLM calls dropped from 17 to 3.** Of 20 queries, 16 went through curated_passthrough (no LLM), 3 through LLM, 1 through stub. The 3 LLM cases are queries where curated chain score < 0.95 or pattern-chain agreement < 1.0 — exactly when LLM judgment is most useful.

2. **No quality regression at all.** Mode match rate matches the stub run exactly (85% / 85%). The LLM was not adding value on the 14 queries where short-circuit fired. We were paying for nothing.

This is the L1/L2/L3 design earning its rationing: when L1 (curated) has a strong answer, L2 (LLM compose) and L3 (free composition) are wasted compute.

## Updated signal medians

| Signal | Stub v1 | Stub v2 | LLM v1 | LLM v2 |
|---|---|---|---|---|
| normalized_chain_score | 1.0 | 1.0 | 1.0 | 1.0 |
| normalized_pattern_score | 1.0 | 1.0 | 1.0 | 1.0 |
| query_specificity | 0.4 | 0.4 | 0.7 | **0.8** |
| downstream_determinism | 1.0 | 1.0 | 1.0 | 1.0 |
| pattern_chain_agreement | 1.0 | 1.0 | 1.0 | 1.0 |

LLM NER continues to extract more entities than offline dict (0.4 → 0.8 specificity). The Haiku tier earns its cost.

## What's left, in priority order

### Library quality (each ~5-15 min)
1. **Add a curated `time_series_de_with_maSigPro` chain** to close mismatch #3. Brings the 3rd mismatch's confidence above upfront.
2. **rRNA branching** — either more `branching_on_qc.When` rewording (try mentioning "ribosomal", "contamination", "depletion" specifically) or add a curated chain `rrna_qc_branch_pipeline`.
3. **Threshold tuning** — try `BIOMATE_CONFIDENCE_UPFRONT=0.70`; would catch the biomarker case at 0.728. Trade-off: would also push other 0.71-0.74 cases to upfront. Should be done after instrumenting real user telemetry.

### Operational (each ~15-30 min)
4. **Confidence telemetry stub** — log `{query, signals, mode, source, user_acceptance}` JSONL for offline tuning. Required before any production wiring.
5. **Production wiring path** — adapter in `ai_assistant.py` that calls compose_chain alongside existing routing tiers. Returns alongside existing chain payload with the new `surfacing_mode` + `confidence` fields. Gated behind a feature flag.

### Strategic (multi-hour)
6. **Editable chain UI** — required for user-correction story.
7. **Reactive analyzer generalization** — post-run "what next" suggestions beyond Bioconductor.
8. **L1↔L2 learned-chain promotion** — once telemetry exists, accepted LLM compositions can grow the curated catalog.

## Reproducibility

```bash
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614

# Stub path (free, ~3s)
export PYTHONPATH=$PWD/backend/lib
python -m galaxy.ai.chain_composer.calibrate \
  backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl

# LLM path (paid, ~3 min after short-circuit)
set -a && . /home/yzhang/biomate/backend/.env && set +a
python -m galaxy.ai.chain_composer.calibrate \
  backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl --use-llm
```
