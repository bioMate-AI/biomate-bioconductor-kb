# Measured-affinity data — TRAINABILITY assessment for a cyclic-peptide affinity model

**Date:** 2026-10-21 · **Reframed question (correct framing):** the enrichment-trained LM was *not* trained on measured affinity, so scoring it against affinity is a category error. Measured affinity is **TRAINING data for a proper, matched affinity predictor** (a different supervised task). Is there enough non-circular measured-affinity data to TRAIN one for cyclic peptides, with a held-out split? (Display `enrichment_log2fc` is circular — abundance-null AUC≈1.0 — so it is not affinity ground truth; see `20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md`.)

## Verdict (one line)
**Not data-blocked — but only in CHEMICAL (SMILES) space.** There are ~29k clean, deduplicated, measured cyclic-peptide affinities (incl. PD-L1/αvβ6 slices), enough to train a chemical affinity predictor — and one is **already trained** (ECFP4-RF/XGB), with honest leakage-safe numbers. For a **sequence** model the path **is data-blocked**: there are **zero** cyclic peptides with plain-AA sequences carrying measured affinity. So "train a proper affinity model" = train in chemical space (done); the sequence-LM cannot be that model.

## 1. Trainability inventory (verified by reading headers/rows + public search)
| Source | Labeled examples | Distinct targets | Cyclic? | Sequence-level? | Trainable? |
|---|---|---|---|---|---|
| **binding_affinity_v1** (local `research/guangzhou_all_atom/data/raw/binding_affinity/binding_affinity_v1.csv`, 136,730 rows) | **36,102 cyclic** measured (Ki/Kd/IC50/EC50); **28,875 clean after dedup+censor-removal** (per `results/binding_model_metrics_cyclic.json`) | 2,702 (cyclic); **PD-L1 434, αvβ6 227** | yes | **NO — SMILES only (0 AA-sequences)** | **YES, as a CHEMICAL (SMILES/ECFP/GNN) model.** Already trained. |
| bindingdb_peptide_subset (local, 171,006) | raw feed → folded into v1 | — | mixed | SMILES | (provenance only) |
| **PepBenchmark / PPI_BA** ([arXiv 2604.10531](https://arxiv.org/pdf/2604.10531)) | **1,433** peptide seqs (−lgKd, PDBbind v2019) | multi | general, **not cyclic** | **YES (sequences)** | **Too small + general to TRAIN a cyclic predictor** (< few-hundred-per-task after target split; no-tiny-dataset). Use as an external **benchmark/eval**. |
| **CPSea** ([GitHub](https://github.com/YZY010418/CPSea); [NeurIPS 2025](https://papers.nips.cc/paper_files/paper/2025/hash/3eec719ab86712d32b065c5977f94ad0-Abstract-Datasets_and_Benchmarks_Track.html)) | **2.71 M** cyclic complexes | many | yes | structural | **NOT measured affinity** — AlphaFold-DB predicted structures. Trainable for structure models, not an affinity-label task. |

## 2. The clean supervised affinity task — and it already ran
`binding_affinity_v1` cyclic subset supports a proper train→held-out→eval task, and `results/binding_model_metrics_cyclic.json` is exactly that:
- **Features:** ECFP4(2048)+16 physchem+assay one-hot. **Target:** pAff = 9 − log10(affinity_nM). 28,875 clean cyclic rows.
- **random split (analog-leaky):** RF/XGB **Spearman 0.71–0.74, R² 0.52–0.56** (n=5,775).
- **novel-target split (leakage-safe; hold out whole targets):** **Spearman 0.25–0.47, R² ~0–0.26** (n=327; per-target PD-L1 ~0.31, αvβ6 ~0.47).
→ So a cyclic affinity predictor is **trainable and trained**; the honest cross-target performance is **modest** (as expected — cross-target affinity is hard), and that novel-target 0.25–0.47 is the real bar, not the leaky 0.7.

**SOTA baseline to beat:** no established leaderboard for *measured* cyclic-peptide affinity regression. Nearest comparators are structure-based cyclic models (CPSea-trained GNNs, 2025 — but on predicted structures, not measured Kd) and physics (docking/FEP). The current ECFP4-RF novel-target Spearman 0.25–0.47 is the internal baseline; beating it would need a scaffold/target-aware model or structure/physics features, benchmarked on the same novel-target split.

## 3. Design-validation-only sources (real affinity, too small to train)
- **PD-L1 (434) and αvβ6 (227)** measured-affinity slices inside binding_affinity_v1 — real affinity on OUR targets, but SMILES and small; usable to **validate designs** (score a design's SMILES with the trained chemical model) and as the held-out novel-target test (already the 0.31/0.47 numbers), not to train a per-target model.
- PepBenchmark PPI_BA (1,433) — external sequence benchmark for a sequence-affinity model, not trainable at scale.

## 4. HONEST verdict
- **Cyclic affinity model — TRAINABLE (chemical space), NOT data-blocked.** 28,875 clean measured cyclic affinities; a model exists with leakage-safe novel-target Spearman 0.25–0.47. Recommended: improve it (scaffold/target-aware split, GNN or structure/physics features) on the same novel-target protocol vs the ECFP baseline. This is the matched, non-circular supervised task.
- **SEQUENCE-based cyclic affinity model — DATA-BLOCKED.** Zero cyclic AA-sequence→measured-affinity examples exist (local or public at scale). The sequence-LM cannot be turned into an affinity predictor without a SMILES bridge (then it's a chemical model) or sequence-level assay data that does not exist publicly.
- **Therefore:** the non-circular affinity path is open in *chemical* space and blocked in *sequence* space. For cyclic+sequence+measured affinity, the only ground-truth source is **physics/assay (the slow loop / CRO)** — the αvβ6 CRO assay remains the sole route to sequence-level measured affinity on our own targets.

**Net:** a proper cyclic affinity *model* is trainable today (chemical-space, data in hand, already demonstrated at modest leakage-safe accuracy); it is simply not the enrichment sequence-LM, and the sequence-level cyclic affinity task is data-blocked outside the assay loop.
