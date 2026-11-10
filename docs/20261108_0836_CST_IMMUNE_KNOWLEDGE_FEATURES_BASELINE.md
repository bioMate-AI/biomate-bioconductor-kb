# Direct knowledge-features baseline: content vs. channel, with a shuffled-null control

Recorded: 2026-11-08T08:36 CST

## Why this run

The prior restored-input diagnostic (`20261108_0110_..._SAVED_SCALER_KNOWLEDGE_RESULTS.md`)
found that switching the encoder's RNA-derived pathway/TF channel **on** lowered frozen transfer
(AUPRC 0.6847 on vs. 0.7092 off at C=1). The user's standing question: *everyone reports knowledge
helps — why worse here?* That toggle cannot answer it, because it confounds two things: whether the
knowledge **content** carries endpoint signal, and whether the **neural channel integration** uses it.

This run removes the encoder entirely and tests the exact features the channel computes —
`transform(scaled_HVG)` = per-cell **mean over each gene-set's HVG members** — as plain
logistic-regression inputs, against a **size/coverage-matched shuffled-gene-set null**. Same
GSE261278 15,000 cells (14.27% stimulation-positive, flu/sars vs. unstimulated), same three
cell-type-holdout folds, three label-sampling seeds, 10% label budget, same corpus scaler, same
fixed logistic C-grid with labelled-row StandardScaler and enforced convergence. CPU-only, no encoder.

512 pathway + 256 TF features (768-dim); gene-set sizes min/median/max = 58/107/612; 1,988/2,000
HVG aligned. Runtime 419 s, peak RSS 1.9 GiB, all 864 fits converged. **The `raw` arm reproduced
the prior restored probe exactly (0.8770 @ C=1, 0.8823 @ C=0.01)** — independent pipeline validation.

## Results (AUPRC, mean ± sd over 3 seeds; primary metric, positives = 14.3%)

| Arm | C=0.01 | C=0.1 | C=1 | C=10 | best |
|---|---:|---:|---:|---:|---:|
| **raw** (scaled HVG, 2000-d) | **0.8823**±.012 | 0.8793 | 0.8770 | 0.8751 | **0.8823** |
| **know_real** (real sets, 768-d) | 0.8462±.012 | 0.8166 | 0.7960 | 0.7833 | 0.8462 |
| know_shuf0 (null, 768-d) | 0.8160±.026 | 0.7953 | 0.7799 | 0.7701 | 0.8160 |
| know_shuf1 (null) | 0.8039±.025 | 0.7767 | 0.7585 | 0.7471 | 0.8039 |
| know_shuf2 (null) | 0.8145±.016 | 0.7939 | 0.7799 | 0.7711 | 0.8145 |
| **raw_plus_know** (concat, 2768-d) | 0.8763±.009 | 0.8751 | 0.8736 | 0.8727 | 0.8763 |

Nulls are three independent draws of random HVG index sets with the **same size distribution** as the
real sets (destroys biological membership, preserves dimensionality/coverage). Means over seeds, no
significance test. AUROC tracks AUPRC (raw 0.956, know_real 0.936, nulls 0.90–0.92; full table in
`results.json`).

## What this establishes

Three comparisons, all consistent across every C and all three null seeds:

1. **Biological membership carries a small but real increment, not zero.** At best regularization
   (C=0.01) know_real 0.8462 beats the null mean 0.8115 by **+0.035** AUPRC (vs. the best single null,
   +0.030); the gap holds at every C and every null seed. So the channel is **not** purely
   decorative — curated gene-set structure does add endpoint-relevant signal over same-size random
   sets. This is a more careful statement than "it's just dimensionality."

2. **But the summary features are lossy vs. raw expression.** know_real (0.846 best) sits **−0.036**
   below raw (0.882). Averaging expression over gene sets discards fine-grained stimulation signal
   that raw HVG retains. The real-vs-null gain (+0.035) and the real-vs-raw deficit (−0.036) are
   nearly equal in magnitude — the biological content recovers about what mean-pooling throws away,
   and no more.

3. **The features add nothing on top of raw RNA.** raw_plus_know (0.876 best) ≈ raw (0.882),
   fractionally **lower**. Concatenating the 768 summaries to raw expression does not help and
   slightly dilutes under shared regularization. On this endpoint the channel is redundant-at-best
   with the raw input.

**Reconciliation of the encoder result:** the earlier "channel on < off" (0.685 < 0.709) is now
expected, not a neural-integration pathology. The underlying features carry only a small biological
increment that is **already redundant with raw RNA**, so making the frozen encoder attend to them
cannot help and can slightly hurt. The limiter on this task is the feature **content/construction**
(mean over HVG-covered sets, sets chosen by HVG coverage), not solely the integration.

## Answer to "everyone reports knowledge helps — why worse here"

Not a contradiction of the surveys; a scope mismatch, now quantified.

- The surveys' "knowledge helps" covers mechanisms **not built or tested here** — training-time
  structured priors (GeneCompass-style), graph propagation to unseen genes (GEARS), literature
  embeddings (GenePT/scELMo), retrieval. Our channel is **mean-pooling over RNA-derived gene sets**,
  which the `20261108_0118_..._SURVEY_RECONCILIATION.md` mechanism map already flagged as only one
  row of the design.
- That pooling channel **does** hold a little real biological signal (+0.035 over random same-size
  sets) but is **lossy and redundant** on a well-powered, in-distribution stimulation endpoint —
  precisely the regime where the surveys predict knowledge helps **least** (abundant direct signal,
  no scarcity/OOV to compensate for).
- Where surveys predict benefit — scarce/unseen genes, low-data cross-study transfer, OOD
  perturbations — remains **untested**. This result does not speak to those.

## Limits (do not over-read)

One exploratory antiviral-stimulation endpoint; cell-type holdout, not donor/cohort; 3 folds × 3
seeds; no significance test; pretraining-overlap and donor audits still open. Nulls are size-matched,
not degree/expression-matched (a stronger null; size-matched already removes the dimensionality
confound). Tests this specific pooling construction only — not signed regulatory models, graphs,
text embeddings, or knowledge-informed **training**. Keep stimulation as one task, not the sole gate
on the knowledge strategy.

## Next (per the reconciliation doc's remaining priorities)

- Priority #5: matched **training** with/without the structured prior (identical data/objective/
  budget), accounting for knowledge-derived prototype init — the only test that estimates the total
  benefit of knowledge-informed training rather than an inference-time input toggle.
- Priority #6: evaluate where the surveys predict benefit — unseen-gene / low-data cross-study /
  OOD-perturbation endpoints — before any verdict on the knowledge direction.

## Artifacts

`docs/20261108_knowledge_features_baseline/`: `run_knowledge_features_probe.py` (executable probe),
`results.json` (full per-seed/per-C table, fit records, set-size + provenance), `memory.json`.
Predictions `knowledge_features_20261108/predictions.npz` retained on Spark
(`~/immune_fm_spark/eval_repair_20261107/`). Earlier diagnostics retained.
