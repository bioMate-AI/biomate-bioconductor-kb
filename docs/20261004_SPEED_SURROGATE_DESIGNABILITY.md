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

Reporting two macro-AUCs per protocol: **all targets**, and **triage-relevant** (only targets with a
non-degenerate designable rate 5–70 %, i.e. where there is an actual screening decision to make — on a
target where ~everything or ~nothing is designable, AUC is unstable and triage is moot).

| Feature set (pre-fold only) | Within-target (all / triage-relevant) | Cold-start LOTO (all / triage-relevant) |
|---|---|---|
| sequence-only | 0.544 / 0.543 (chance) | 0.555 / 0.469 (chance) |
| generation-time confidence | 0.646 / 0.542 | 0.573 / 0.625 |
| **combined** | **0.669 / 0.624** | 0.509 / 0.585 |

Per-target (combined):

| target | designable rate | n | within-target AUC | cold-start (LOTO) AUC |
|---|---|---|---|---|
| 5o45 (PD-L1) | 0.08 | 695 | 0.676 | **0.731** |
| 1u8p | 0.64 | 56 | 0.572 | 0.439 (below chance) |
| 9xmm (αvβ6) | 0.94 | 100 | 0.759 | 0.846 |
| 1yf4 | 0.98 | 48 | — | 0.021 (degenerate: 1 negative) |

- **Within-target triage works** on the targets that need it — combined triage-relevant AUC **0.624**
  (5o45/PD-L1 0.676) — and saves **~24–34 % of co-fold compute** at 80 % recall of true designables
  (5o45: 34 %). Strongest single signal is the generator's own `min_design_to_target_pae` /
  `design_to_target_iptm` (5o45 raw-feature AUC 0.78 / 0.77).
- **Realistic seed-and-triage simulation** (the actual DBTL use: co-fold a random 30 % seed, train on
  it, triage the remainder; 20 random draws) — on **5o45/PD-L1 (n=695): skip ~43 % ± 9 of the
  remaining co-folds while still recovering 80 % of its designables**; on 1u8p ~21 % ± 4. This is the
  headline operational benefit, measured prospectively rather than by CV.
- **Sequence-only is genuinely chance** (AUC ≈ 0.54). A naive sequence→designability surrogate does
  not work; the signal is the generator's self-confidence, not composition.
- **Cold-start is target-dependent and NOT dependable.** It is strong on the hardest/largest target
  (5o45/PD-L1 LOTO AUC 0.73 — a real cross-target transfer, the realistic triage regime) but *below
  chance* on 1u8p (0.44). So cold-starting an arbitrary brand-new target is not a solved capability;
  it works on some targets and fails on others. (The earlier flat "cold-start = chance" was itself
  imprecise — it averaged in near-degenerate easy targets; the honest statement is "unreliable,
  works on hard targets like 5o45, fails on 1u8p".)
- A richer 127-feature pre-fold set (all `design_*` + composition + liability columns) was tested and
  did **not** beat the lean 8-feature set on macro-AUC (within 0.665 vs 0.669), so the committed
  surrogate stays lean (8 features) — more features here is added leakage surface for no gain.
- **Timing:** featurize + GBM forward ≈ 5 µs/seq vs ~90 s/co-fold.

## Honest contribution & limits
- Real, bounded, available-now: a within-target designability triage that cuts co-fold compute by
  roughly a quarter to a third at fixed recall, from data already in hand — no new wet-lab, no CRO
  round. This is the "faster" axis of the program, measured not asserted.
- Caveat on marginal novelty: BoltzGen already ranks partly on these confidence metrics, so the
  surrogate's value is specifically *triaging before the independent refold*, not out-ranking the
  generator. Report it that way.
## Structural-feature attempt for cold-start — tested, NEGATIVE (honest)

The remaining lever for dependable cold-start was structural features of the **designed backbone**.
The full designed poses are available (`intermediate_designs/<target>_<NNN>.cif` for every candidate,
not just the ranked subset — ~200/run), matched to labels by design id. A dependency-free CA-trace
featurizer (`pose_features.py`: radius of gyration, contact order, long-range contact density,
compactness, end-to-end, bond stats) was built and validated on the 5o45/PD-L1 run (199 poses):

- **CA-geometry features do NOT predict designability.** Within-run 5-fold AUC **0.470** (below
  chance); every single feature's correlation to scRMSD ≈ 0.00–0.07.

Interpretation: whether a design **refolds** is governed by sequence–structure *compatibility*
(inverse-folding fit), not gross CA geometry — and the generator's own `design_iptm`/`design_*_pae`
is already a learned structure-aware score that captures this (hence it works, AUC 0.73 on 5o45,
while hand geometry does not). A genuinely better structural feature would need a real
inverse-folding model (e.g. a ProteinMPNN score), i.e. a heavy model re-deriving what `design_iptm`
already encodes — not worth it. **Conclusion: cold-start is not cracked by structural features;
within-target triage (the ~43 % PD-L1 co-fold saving) is the real, bounded deliverable.**
`pose_features.py` is kept (tested) as reusable infrastructure for any future structure-model work.
A richer *scalar* pre-fold set (127 vs 8 features) also gave no macro gain, so the surrogate stays lean.

## Reproduce
```
python3 speed_surrogate.py --selftest
python3 speed_surrogate.py --out results/speed_surrogate_loto.json   # full LOTO + within-target
```
Tests: `test_speed_surrogate.py` (7 pass).
