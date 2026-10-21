# Strong cyclic-peptide binding model — build + rigorous novel-target benchmark

**Date:** 2026-10-21 · **Goal:** a commercial+publishable cyclic-peptide binding model.
**Data:** `binding_affinity_v1` (28,875 clean cyclic measured Ki/Kd/IC50/EC50, SMILES-only, 847 targets with a usable target id, incl. PD-L1/αvβ6). Target = pAff = 9 − log10(affinity_nM).
**Code:** `research/guangzhou_all_atom/benchmark_binding_models.py` · **Metrics:** `results/binding_model_benchmark_cyclic.json` · baseline `results/binding_model_metrics_cyclic.json`.
**Headline metric:** grouped leave-targets-out CV (GroupKFold by `target_uniprot`, 5-fold) — the leakage-safe novel-target estimate. The random-split Spearman (~0.71) is analog-leaky and is NOT the headline.

## 1. Rigor upgrade over the baseline
The baseline held out only PD-L1+αvβ6 (n=327, **2 targets**) — not a robust generalization estimate. This run adds a **grouped leave-targets-out CV across all 847 targets** (per-fold Spearman + spread), which both (a) gives a robust novel-target number with a CI and (b) tests whether the baseline's 0.42 was representative. It was.

## 2. Results — leakage-safe novel-target (grouped CV, 847 targets)
| Model | BASE features (ECFP4+physchem+assay) | RICH features (+MACCS+10 RDKit desc) |
|---|---|---|
| **RandomForest** | **0.416 ± 0.084** | **0.428 ± 0.100** |
| HistGBM (xgb unavailable on py3.14) | 0.410 ± 0.121 | 0.413 ± 0.108 |
| Ridge | 0.321 ± 0.053 | 0.301 ± 0.054 |

Per-fold RF (rich): [0.582, 0.438, 0.392, 0.456, 0.272] — wide spread by target family.

**PD-L1/αvβ6 holdout (reproduces + matches the baseline):** RF 0.425, HistGBM 0.391; per-target PD-L1 **0.41**, αvβ6 **0.22–0.27**. The baseline (RF 0.42 / XGB 0.38) is confirmed representative of the broader novel-target regime.

## 3. Honest verdict — NOT strong yet; ~0.42 is a real ceiling
- **No model meaningfully beats the ~0.42 RF baseline on novel targets.** RandomForest is best; HistGBM ties it; Ridge is worse. 
- **Richer features do not help**: RF 0.416 → 0.428 and HistGBM 0.410 → 0.413 are *within the ±0.08–0.12 fold std* — i.e., noise, not a real gain. MACCS + extra RDKit descriptors add nothing over ECFP4+physchem on this task.
- **The grouped CV confirms the ceiling is real**, not a baseline artifact: ~0.41–0.43 Spearman across 847 held-out targets. A novel-target Spearman of ~0.42 explains only ~18% of rank variance — **modest, not "strong."**
- **αvβ6 (our harder program target) is the weakest slice (0.22–0.27)**; PD-L1 is ~0.41. So on the target that matters most, the current model is weak.
- Consistent with the program's recurring finding that richer/deeper featurization does not beat simple baselines on hard generalization regimes.

**Bottom line:** a feature-based chemical model (ECFP4/physchem + RF/GBM) plateaus at ~0.42 novel-target Spearman. Feature engineering is exhausted. "Strong + publishable" is **not achieved** by this route alone; it requires a different signal (below).

## 4. Levers to break the ~0.42 ceiling (not yet run)
1. **Pretrained molecular foundation-model embeddings** (ChemBERTa / Uni-Mol + a head). torch 2.13 + transformers 5.16 are present; NOT run here (23-min feature-model sweep prioritized the rigorous grouped-CV). This is the honest untested lever — a learned chemical representation may beat ECFP4 on novel targets where substructure fingerprints transfer poorly. **Documented gap, like the baseline's unrun chemprop/DMPNN.**
2. **Physics augmentation (design below).**
3. **More measured data for sparse targets** — the per-fold spread (0.27–0.58) shows generalization is target-family-dependent; coverage is the limiter.

## 5. Physics-augmentation hook (design only — FEP run held for user go)
The validated physics engine (co-fold → MM-GBSA → FEP; αvβ6 control-edge validating) is a **non-circular** binding signal (it never sees read counts/abundance). Use it to densify the novel-target regime where measured data is absent:
- **Interface:** emit `(smiles, target_uniprot, physics_pAff, source=physics, weight<1)` rows (the loop's `graded_run_store` already stores scored runs); join to the measured training set as auxiliary labels, down-weighted vs measured, with an assay/source one-hot so the model distinguishes measured vs physics labels.
- **Eval unchanged:** always on **measured** held-out targets (physics labels train only). This keeps it non-circular.
- **Expected effect:** physics labels fill the exact weak spot — targets with few/no measured rows (where novel-target Spearman is lowest, e.g. αvβ6 0.22) — so the lift, if any, shows up as improved *low-coverage-target* folds. Honest risk: the gain is bounded by how well MM-GBSA/FEP tracks real affinity (to be established by the αvβ6 control edge against measured data).
- **Not run:** generating physics labels at scale needs the GPU FEP/MM-GBSA fan-out, which is gated on the user's go.

## 6. System role
The sequence LM stays the **generator** (propose cyclic peptides → SMILES; its uncontested strengths are validity/novelty/diversity, not affinity). This chemical model is the **fast ranker/affinity screen**. Physics (FEP) is the **precise confirm** on the shortlist. Pipeline: LM generate → chemical-model rank (fast, ~0.42 novel-target today) → FEP confirm top-k. The chemical ranker is the component that must get stronger; the FM-embedding and physics-augmentation levers (§4–5) are the path.

## 7. Reproduce
```
cd research/guangzhou_all_atom
/opt/homebrew/bin/python3.14 benchmark_binding_models.py   # ~23 min CPU, reuses results/binding_feature_cache.npz
```
