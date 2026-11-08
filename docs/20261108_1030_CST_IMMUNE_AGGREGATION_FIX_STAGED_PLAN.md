# Staged plan: fix the knowledge aggregation, re-test the 2×2 (gated, cheap-before-GPU)

Recorded: 2026-11-08 ~10:30 CST. Spark unreachable at write time (mDNS name not resolving — the
intermittent same-Wi-Fi condition). Everything here is **staged and ready to fire** when Spark returns.

## Where the investigation stands

The feature-level 2×2 (docs `20261108_0905_...WHY_KNOWLEDGE_WORKS...`) established: our pathway/TF **mean**
knowledge channel wins only under {scarce labels × held-out cell type}; it LOSES under held-out tissue
at every budget. Proposed mechanism: a per-cell MEAN inherits the compartment OFFSET, so across tissues
the features carry a tissue-batch term that breaks transfer (the E2 flaw in the 2026-09-02
`KNOWLEDGE_BOTTLENECK_V1_ERROR_ANALYSIS`).

## Gate 1 (CHEAP, CPU, no encoder) — run FIRST

**`docs/20261108_knowledge_features_baseline/percellnorm/run_percellnorm_crosstissue.py`** (staged,
syntax-checked). Tests the falsifiable prediction of the mechanism: strip the per-cell offset BEFORE
aggregating (`know_pc` = gene-set means over per-cell z-scored HVG) and the cross-tissue transfer
failure should shrink/vanish. Decisive contrast per (held-out tissue, budget): `know_pc − raw` vs the
current `know_mean − raw`.

Run when Spark is back:
```
WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
  python3 run_percellnorm_crosstissue.py        # from ~/immune_fm_spark/eval_repair_20261107
```
Interpretation / branch:
- **`know_pc − raw` ≫ `know_mean − raw` (ideally ≥ 0):** offset confirmed as the cause; per-cell-norm
  is a cheap aggregation fix. → proceed to Gate 2 to get the same benefit inside a trained model.
- **`know_pc − raw` ≈ `know_mean − raw` (still negative):** offset is NOT the (sole) cause. Do NOT
  spend GPU on the expiMap retrain yet — the transfer gap is deeper (raw is simply more
  tissue-invariant for this signal); revisit the mechanism before training.

## Gate 2 (GPU, expiMap/VEGA decoder) — run ONLY if Gate 1 is positive

Build the knowledge integration the error-analysis prescribed, replacing the frozen lossy mean:
1. **expiMap masked DECODER** from `z_cell`: linear decoder whose weights are masked by the gene-set
   membership matrix, so z must reconstruct expression *through* the programs (gradient flows INTO z,
   fixing the knowledge2 bypass). Reuse scArches/expiMap; do not hand-roll.
2. **De-novo unconstrained latent nodes** alongside the constrained ones (recovers the capacity the
   v1 mean-replacement destroyed, −0.092 F1).
3. **Learnable soft mask** init from the GMT membership (+ optional group-lasso), not frozen.
4. **Per-cell-normalized input** to the program aggregation (Gate 1's fix, inside the model).
Then **re-run this exact 2×2** (cell-type and tissue holdout × abundant/scarce) on the trained z.
Win condition: knowledge now also wins (or ties) the tissue-shift cells — i.e. the TRANSFER slice is
recovered, not just the sample-efficiency slice.

Caveats carried forward: single donor D534, within-dataset shifts (tissue/cell-type) as transfer
proxies; a truly independent cohort + pretraining-overlap audit is the eventual gold test (overlap
audit matters only at Gate 2, since Gate 1 is encoder-free). Batch-clean latent remains the
precondition for any clinical-endpoint knowledge claim (separate from this stimulation endpoint).

## Status
- Gate-1 script: written, commented, syntax-checked, staged in repo. Not yet run (Spark down).
- Gate-2: design only; do not start until Gate 1 is positive.
