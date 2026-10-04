# Track A — Real-Data Cyclic-Peptide Binding Predictor + Principled Multi-Objective Selection

**Date:** 2026-10-04
**Plan ref:** `docs/20261004_PEPTIDE_PROGRAM_PLAN.md` (Track A: A1 binding model, A2 qNEHVI MO wrapper, A3 pool re-score)
**Code:** `research/guangzhou_all_atom/{binding_features.py, train_binding_model.py, mo_select_qnehvi.py}`
**Compute:** CPU only, local (no GPU, no Batch). Python 3.12 venv.

---

## Lead with the honest gap

**The binding model ranks well in-distribution but has near-zero ranking power on the novel targets we actually care about (PD-L1 especially).** On a random split the model reaches Spearman ≈ 0.72–0.74 (R² ≈ 0.54); when PD-L1 and αvβ6 are held out of training entirely and used as the test set, Spearman collapses to **0.37 overall, and 0.18 for PD-L1 alone (R² ≈ 0)**. Predicted affinities for the PD-L1 pool peptides regress to the training mean (~6–7 pAff, ~100 nM–1 µM) — the textbook symptom of a ligand-only QSAR model extrapolating to an unseen target.

**Consequence for A3:** re-ranking the existing PD-L1 pool with this model is **not trustworthy** and must not be used to overrule the existing panel. The αvβ6 novel-target signal is modestly better (Spearman ≈ 0.40–0.47) but still weak. This is exactly the generalization reality the surveys predicted; we report it rather than hide it. The model's legitimate near-term use is (a) an in-distribution QSAR/triage tool and (b) a *replacement in principle* for the MM-GBSA/iPTM proxy once per-target measured data exists (e.g., after the GenScript round-1 SPR returns).

---

## A1 — Binding model

### Data & target
- Source: `binding_affinity_v1.csv` — **136,730** measured rows. Every row carries a ligand SMILES (the `sequence` column is empty), so **features are ligand-only**.
- Target: `pAff = 9 − log10(affinity_nM)` (pKd-like; higher = stronger binder).
- **Censored relations excluded** (documented): kept `=`/`~` only; dropped 17,690 `>`, 4,698 `<`, and the handful of `>=`/`<=`/`<<`. Rationale: a `>`/`<` bound is a one-sided constraint; treating it as a point value injects label noise. (Censored-aware likelihood is a future upgrade.)
- Affinity sanity filter: 1 pM ≤ affinity ≤ 100 mM.
- Duplicate `(smiles, target, assay_type)` rows collapsed to their **median** pAff → prevents identical-measurement leakage across train/test.
- Assay types pooled (IC50 79.7k, Ki 32.8k, EC50 17.4k, Kd 6.8k) with **assay type as a one-hot feature** (not silently mixed).
- After clean + dedup: **107,823** usable rows (28,875 cyclic).

### Features & models
- Features: **ECFP4 (Morgan r=2, 2048 bits) + 16 interpretable RDKit physchem descriptors + assay one-hot (4)** = 2,068 dims.
- Baselines: **Ridge**, **RandomForest (300 trees)**, **XGBoost (600 trees, depth 8, hist)**.
- Chemprop/DMPNN: **not run** (needs GPU/extra setup); XGBoost/RF is the strong CPU baseline. Documented gap.

### Results — full dataset (all chemotypes)

| Split | Model | n | RMSE | Spearman | R² | MAE | within 1 log | calib. slope |
|---|---|---|---|---|---|---|---|---|
| **Random (in-dist)** | Ridge | 21,565 | 1.259 | 0.546 | 0.317 | 1.000 | 0.58 | 0.94 |
| | **RandomForest** | 21,565 | **1.010** | **0.736** | **0.561** | 0.780 | 0.70 | 1.14 |
| | XGBoost | 21,565 | 1.034 | 0.716 | 0.539 | 0.805 | 0.68 | 1.12 |
| **Novel-target (PD-L1+αvβ6 held out)** | Ridge | 566 | 1.591 | 0.231 | −0.369 | 1.241 | 0.50 | 0.30 |
| | RandomForest | 566 | 1.322 | 0.252 | 0.055 | 1.020 | 0.58 | 1.15 |
| | **XGBoost** | 566 | 1.331 | **0.370** | 0.042 | 1.027 | 0.58 | 0.97 |
| ↳ PD-L1 only | XGBoost | 379 | 1.504 | **0.176** | −0.101 | 1.221 | 0.48 | 0.70 |
| ↳ αvβ6 only | XGBoost | 187 | 0.882 | 0.404 | 0.166 | 0.633 | 0.79 | 0.97 |

### Results — cyclic-only training (matches the peptide-pool regime)

| Split | Model | n | RMSE | Spearman | R² | within 1 log |
|---|---|---|---|---|---|---|
| **Random** | XGBoost | 5,775 | 1.001 | 0.716 | 0.529 | 0.73 |
| | RandomForest | 5,775 | 1.007 | 0.714 | 0.523 | 0.72 |
| **Novel-target** | RandomForest | 327 | 0.915 | 0.421 | 0.256 | 0.71 |
| | XGBoost | 327 | 0.962 | 0.377 | 0.178 | 0.68 |
| ↳ PD-L1 only | XGBoost | 162 | 1.065 | 0.314 | 0.116 | 0.55 |
| ↳ αvβ6 only | XGBoost | 165 | 0.849 | 0.470 | 0.206 | 0.81 |

**Reading the two tables:** training on cyclic peptides only (same chemotype as the pools) *improves* novel-target generalization (PD-L1 Spearman 0.18 → 0.31; αvβ6 0.40 → 0.47; αvβ6 R² 0.17 → 0.21) despite ~4× less data — chemotype match beats raw volume for this extrapolation. In-distribution ranking is unchanged (~0.72). **Calibration:** in-distribution RF/XGB over-spread slightly (slope 1.1–1.14); on the novel targets the calibration slope drops (0.30–0.76 for the weaker fits), consistent with regression-to-the-mean.

### Production model
`results/binding_model_prod.pkl` — XGBoost trained on **all** usable rows (incl. PD-L1/αvβ6) for A3 scoring. Scoring uses the Kd assay channel. Not committed (large `*.pkl`, gitignored); regenerate with `train_binding_model.py`.

---

## A2 — Principled multi-objective selection (qNEHVI) vs the hand-tuned composite

<!-- A2_RESULTS -->

---

## A3 — Re-score the existing pools

<!-- A3_RESULTS -->

---

## Honest framing & gaps (carried)

- **Novel-target binding is weak** (PD-L1 Spearman 0.18). This is the headline and it is the expected result. The model does not rescue novel-target ranking; it replaces the proxy *in principle* and is honest triage in-distribution.
- **Ligand-only model**: no protein channel, so an unseen target gets no target-specific signal. A target-aware model (protein descriptors / PLM embeddings) is the obvious next upgrade but cannot be validated without more per-target data.
- **Censored data excluded**, not modeled — a censored-aware (Tobit / survival) loss would recover ~22k rows of weak-binder signal.
- **Chemprop/DMPNN not run** (no GPU this session).
- **qNEHVI over a known finite pool is partly ceremonial**: when all objectives are computed deterministically, the exact principled selector is greedy hypervolume maximization; qNEHVI (GP surrogate) is the method for the *generative/BO* loop where binding is predicted with uncertainty. Both are reported; see A2.
- **Selectivity objective omitted** — not derivable from single-target pool data.
- **The loop still needs real wet-lab KD** (GenScript round-1 SPR) to validate any of this prospectively.

### Reproduce
```bash
# py3.12 venv with: numpy scipy pandas scikit-learn rdkit xgboost torch botorch
python research/guangzhou_all_atom/train_binding_model.py --csv binding_affinity_v1.csv --tag full
python research/guangzhou_all_atom/train_binding_model.py --csv binding_affinity_v1.csv --cyclic-only --tag cyclic
OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  python research/guangzhou_all_atom/mo_select_qnehvi.py --k 10   # single-thread BLAS avoids a macOS gpytorch deadlock
```
