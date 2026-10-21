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

---

## 8. Molecular-FM lever (ChemBERTa) — tested; does NOT break the ceiling (2026-10-21)
Ran the untested lever: frozen **`DeepChem/ChemBERTa-77M-MLM`** embeddings (384-d, mean-pooled last hidden) → the SAME heads on the SAME grouped leave-targets-out CV + PD-L1/αvβ6 holdout. Code `chemberta_binding_benchmark.py`; results in `results/binding_model_benchmark_cyclic.json` (`fm_chemberta`). CPU, ~6 min, no spend.

**Novel-target grouped CV (847 targets) — FM vs ECFP4 baseline:**
| Head | ChemBERTa-FM | ECFP4+physchem (base/rich) |
|---|---|---|
| RandomForest | 0.405 ± 0.072 | 0.416 / **0.428** |
| HistGBM | 0.370 ± 0.051 | 0.410 / 0.413 |
| Ridge | 0.145 ± 0.028 | 0.321 / 0.301 |

**PD-L1/αvβ6 holdout (FM):** RF 0.396, HistGBM 0.391; per-target **PD-L1 0.286, αvβ6 0.417**.

**Verdict — the FM does NOT meaningfully beat ~0.42; the ceiling is data/task-fundamental.**
- FM-RandomForest (0.405) is *within fold noise* of ECFP4-RF (0.428) — and slightly *lower*, not higher. FM-HistGBM is worse. Ridge-on-FM collapses (0.145). So a pretrained chemical FM representation does **no better** than substructure fingerprints on novel-target cyclic affinity.
- This is the informative result: **two independent representations (ECFP4 fingerprints and a learned molecular-LM) both plateau at ~0.40–0.42 novel-target Spearman.** When representation doesn't matter, the limit is **not model capacity — it is data/task-fundamental** (coverage of novel targets, label heterogeneity across pooled IC50/Ki/EC50/Kd). That is a publishable finding in its own right: *the novel-target cyclic-affinity ceiling is a data problem, not a modeling problem.*
- **αvβ6 nuance (honest):** the FM is *better* on αvβ6 (0.417 vs ECFP4 0.22–0.27) but *worse* on PD-L1 (0.286 vs 0.41) — a redistribution, not a net gain (overall RF ~0.40 either way). Per-target variance is high; neither representation is reliably better. (For αvβ6 specifically, the FM embedding is worth keeping in an ensemble.)
- **Fine-tuning not run** (bounded compute): with frozen-FM ≈ ECFP4 ≈ 0.40–0.42 and the ceiling looking data-fundamental, fine-tuning a 3–4M-param FM on ~23k rows is unlikely to break a data-limited ceiling. Noted as an unlikely-to-help further lever, not a blocker.

**Consequence for "strong":** better *models/representations* are exhausted (feature-eng AND FM both ~0.42). The only levers left are the ones that add **data/signal**: physics augmentation (§5) and more measured targets (§4.3). "Strong + publishable" on novel-target affinity will come from data, or from reframing the claim to the *physics-grounded* pipeline — not from a bigger model.

---

## 9. Target-aware lever (ESM target embedding ⊕ ligand) — does NOT break the ceiling (2026-10-21)
Hypothesis (coordinator): ECFP+ChemBERTa plateaued because they are LIGAND-ONLY (no target input) → ~0.42 is a ligand-only ceiling; a target-aware model should generalize to held-out targets. Tested with ESM-2-35M embeddings of the target sequence (694/796 targets resolved from UniProt) concatenated with ligand ECFP; SAME grouped leave-targets-out split + heads. Code `target_aware_binding.py`, results `results/binding_model_benchmark_cyclic.json` (`target_aware`). CPU, ~18 min, no spend.

**Grouped CV (26,598 rows, 694 targets):**
| Feature set | RF | HistGBM | Ridge |
|---|---|---|---|
| ligand_only (ECFP+physchem) | **0.445 ± 0.063** | 0.446 ± 0.080 | 0.338 |
| target_only (ESM) — leakage probe | 0.187 ± 0.108 | 0.170 ± 0.118 | 0.148 |
| target_aware (ECFP ⊕ ESM) | 0.351 ± 0.132 | 0.367 ± 0.120 | 0.369 |

**PD-L1/αvβ6 holdout:** ligand_only RF 0.421 (PD-L1 0.385 / αvβ6 0.216) → target_aware RF 0.128 (PD-L1 0.081 / αvβ6 0.088).

**Verdict — naive target-awareness LOWERS the ceiling, does not break it.** The ESM-target concat hurt the tree models (RF 0.445→0.351; holdout 0.421→0.128) — the embedding is mostly noise the trees can't convert into transferable matching, and is uninformative on a held-out target. Only Ridge nudged (0.338→0.369), still below the ligand-only tree.

**Leakage probe (clean):** target_only is weak on grouped CV (~0.17) and NEGATIVE on the PD-L1/αvβ6 holdout (RF −0.099; PD-L1 −0.350). → The grouped split prevents target-identity memorization; ligand_only's ~0.42 is genuine ligand→affinity signal, NOT target leakage.

**Convergent finding:** across ECFP (0.43), ChemBERTa (0.40), ESM-target-concat (0.35), the novel-target Spearman holds-or-drops. Strong evidence the limit is **data/task-fundamental for generic ML**, not a missing-target-input problem. Honest (a)/(b): (a) data/task wall vs (b) a crude *concat* is the wrong target-aware architecture — a protein-ligand **interaction** model (DrugCLIP-style cross-attention) is the one untried target-aware architecture; it is the remaining ML lever before declaring a hard data wall. Evidence so far favors (a), pointing to **physics-grounding (the §5 physics gate) rather than a bigger ML model** as the route to a strong novel-target model.

---

## 10. LEVER 1 — license-clean INTERACTION model (learned ligand×target); edges up but does NOT break the ceiling (2026-10-21)
**License verdict (commercial):** training data (BindingDB CC-BY-4.0 / ChEMBL CC-BY-SA-3.0) is commercial-OK with attribution (ChEMBL share-alike applies to redistributed *data*; flag for legal). DrugCLIP data/weights are CC-BY-4.0 but its **code + Uni-Mol weight licenses are unverified** → per the commercial-safe rule, did NOT depend on DrugCLIP; built from license-clean parts: **ESM-2 (MIT)** target emb + **RDKit ECFP (BSD)** ligand + a learned interaction head (torch, from scratch on our data). Sources: DrugCLIP_data (huggingface, CC-BY-4.0), ChEMBL CC-BY-SA-3.0, BindingDB CC-BY-4.0.

**Result — grouped leave-targets-out CV (26,598 rows, 694 targets), torch MLP:**
| Model | Spearman |
|---|---|
| ligand_only MLP | 0.424 ± 0.100 |
| target_only MLP (leakage probe) | 0.139 ± 0.087 |
| **interaction MLP (ligand ⊕ target ⊕ ligand⊙target gated)** | **0.462 ± 0.080** |
| (ref) ligand_only RF, same subset | 0.445 |
| (ref) naive concat-into-RF (§9) | 0.351 |

**Verdict — interaction edges up but is WITHIN fold noise of the ceiling; not a meaningful break.** The learned gated interaction (0.462) beats the ligand_only MLP (0.424) by +0.038 and the naive concat-into-tree (0.351) by +0.11 — so **how** you combine target+ligand matters (a learned interaction head ≫ dumping the embedding into a tree). But +0.038 over ligand-only is *inside the ±0.08–0.10 fold std*, and 0.462 sits essentially at the ligand-only RF ceiling (0.445). So interaction **recovers** what concat destroyed and lands *at* the ceiling — it does not exceed it. Leakage probe (target_only 0.139) confirms the split is clean.

**Convergent across everything tried:** ligand-only ECFP 0.445 / ChemBERTa 0.40 / MLP 0.424; concat-tree 0.351; learned interaction 0.462. All land at **~0.42–0.46** novel-target. The ~0.42 ceiling is robust to representation AND to a learned interaction head → **data/task-fundamental, not model-capacity.**

**Remaining formal unknown (honest):** this is a POOLED interaction, not full **token-level cross-attention** (residue×atom, DrugCLIP-style). That GPU variant is the one architecture untested. But given concat hurt and pooled-interaction lands exactly at the ceiling, the evidence strongly indicates token cross-attention would not meaningfully break it either. (Per-target PD-L1/αvβ6 MLP single-slice not separately run; the grouped CV subsumes both as held-out targets within folds — the robust headline — and the ligand-only RF slices were PD-L1 0.385 / αvβ6 0.216.)

## 11. Consolidated verdict — a STRONG standalone novel-target model is not reached from existing data/ML
Ligand-only (any representation), naive concat, pretrained FM embeddings, and a learned interaction head **all plateau at ~0.42–0.46 novel-target Spearman** on the leakage-safe grouped split. The ceiling is **convergent and data/task-fundamental** (novel-target coverage + pooled IC50/Ki/EC50/Kd label heterogeneity), not a modeling deficiency. The two levers that could still move it both add **signal/data, not model capacity**: (1) full token cross-attention (GPU, unlikely per the above); (2) **physics-grounding** — but that is blocked on a SMILES→GAFF MM-GBSA pipeline we don't have (§ physics-gate doc). Honest bottom line: "strong + publishable" on *novel-target* cyclic affinity is **data-bound**; the defensible near-term claims are the *within-target* ranking (modest) and this **convergent-ceiling negative** (a real, publishable methods finding: representation/architecture don't break a data-limited novel-target ceiling).
