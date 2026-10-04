# Cyclic-Peptide Designability Speed Surrogate — Built on Existing Data (Honest Results)

**Date:** 2026-10-04 · **Code:** `research/guangzhou_all_atom/speed_surrogate.py` ·
**Data:** `data/processed/designability_v1.csv` (949 designs) · **Eval:** `results/speed_surrogate_loto.json` ·
**Commits:** `bc5b79a24` (build), `5aea56b7a` (correction).

## Goal
The DBTL throughput bottleneck is the self-consistency **co-fold** (~90 s/candidate: re-fold a
generated design and measure scRMSD to its designed pose). A surrogate that predicts designability
(scRMSD < 2 Å) **from pre-fold information** lets the expensive co-fold run only on the promising
fraction — the "faster" contribution.

## Correction that motivated this (honesty record)
An earlier note called the surrogate "data-gated — only 2 designs locally," implying it had to wait
for a GPU fold corpus (and was wrongly bundled with work waiting on the CRO round). **That was wrong**
and was challenged directly ("there are so many public data why insist on waiting"). The designability
label `filter_rmsd` is **target-agnostic** (it measures whether a sequence folds back to its own
backbone), so it trains on ANY prior generation+refold run. We already had **949 labelled designs
across 7 targets** from BoltzGen oversample/benchmark runs on S3
(`s3://knowledge-datasets-1759951976/cyclic_peptide/runs/.../all_designs_metrics.csv`). The 2-row
local file was one sample. Same under-counting-our-own-assets error flagged in prior memory
(`feedback_verify_data_existence`, `feedback_overclaiming_conclusions`).

## Dataset
949 unique designs, 7 targets, sequence length 7–46, overall designable rate 25.8 %.
Per-target designable rate varies widely: 1yf4 98 %, 9xmm 94 %, 1u8p 64 %, 5o45 (PD-L1) 8 %, 1kc4 0 %.
Columns: `sequence, target, filter_rmsd, designable` + pre-fold design-time features
(`design_to_target_iptm, min_design_to_target_pae, design_ptm, design_hydrophobicity, loop, helix,
sheet, num_tokens`). **No `*_refolded` / label-derived columns** are used as features (that would be
circular — they come from the co-fold we are trying to skip).

## Method
- **Features (pre-fold only):** `seq` (length, 20 AA fractions, Kyte-Doolittle hydropathy, net charge,
  aromatic/Gly/Pro fractions), `design` (the generator's own design-time confidence, produced before
  the independent refold), and `combined`.
- **Model:** HistGradientBoosting (classifier for designable, regressor for scRMSD ranking).
- **Two honest evaluations:**
  - **within-target** stratified 5-fold CV — triage designs for a target once a seed batch is folded
    (the actual use-case);
  - **leave-one-target-out (LOTO)** — cold-start a brand-new target with zero prior folds (the harder,
    separate question), including holding out 5o45 (PD-L1) and 9xmm (αvβ6).
- **Operational metric:** rank candidates by predicted designability, co-fold only the top fraction;
  report co-fold work saved at 80 % recall of the true designables.

## Results (honest, including what fails)

| Feature set (pre-fold only) | Within-target triage macro-AUC | Cold-start (LOTO) macro-AUC |
|---|---|---|
| sequence-only | 0.544 (chance) | 0.555 (chance) |
| generation-time confidence | 0.646 | 0.573 |
| **combined** | **0.669** | 0.509 (chance) |

Within-target per-target (combined): 5o45/PD-L1 AUC 0.676 (n=695), 9xmm/αvβ6 0.759 (n=100),
1u8p 0.572 (n=56).

- **Within-target triage works** — saves **~24–34 % of co-fold compute** at 80 % recall of true
  designables (5o45: 34 %). Strongest single signal is the generator's own `min_design_to_target_pae`
  / `design_to_target_iptm` (5o45 raw-feature AUC 0.78 / 0.77).
- **Sequence-only is genuinely chance** (AUC ≈ 0.54). A naive sequence→designability surrogate does
  not work on this corpus; the signal is the generator's self-confidence, not composition.
- **Cold-start a brand-new target (LOTO) does not work** (AUC ≈ 0.51–0.57). Designable rate is
  target-dependent and does not transfer; the surrogate triages *within* a target that has a seed
  batch folded, it cannot predict a target with zero prior folds. Stated as a limitation, not hidden.
- **Timing:** featurize + GBM forward ≈ 5 µs/seq vs ~90 s/co-fold.

## Honest contribution & limits
- Real, bounded, available-now: a within-target designability triage that cuts co-fold compute by
  roughly a quarter to a third at fixed recall, from data already in hand — no new wet-lab, no CRO
  round. This is the "faster" axis of the program, measured not asserted.
- Caveat on marginal novelty: BoltzGen already ranks partly on these confidence metrics, so the
  surrogate's value is specifically *triaging before the independent refold*, not out-ranking the
  generator. Report it that way.
- Open improvement (still no new wet-lab needed): add **structural** features from the designed
  backbone `.cif` poses on S3 (geometry / inverse-folding score) to push cold-start above chance —
  the next honest step for cross-target generalization.

## Reproduce
```
python3 speed_surrogate.py --selftest
python3 speed_surrogate.py --out results/speed_surrogate_loto.json   # full LOTO + within-target
```
Tests: `test_speed_surrogate.py` (7 pass).
