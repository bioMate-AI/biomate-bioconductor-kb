# Cyclic-peptide membrane permeability on CycPeptMPDB: fair, pre-registered attempt (2026-10-25)

**Status at time of this commit: PRE-REGISTRATION. No predictive model has been fitted on any split yet.**
Things done *before* this commit (all label-free or purely descriptive): data audit/cleaning (`data_prep.py`), split construction
(`make_splits.py`; uses no labels), a descriptive audit of the published CycPeptMP split (`published_split_audit.py`; reports test-set label SD
and neighbour similarity, no model), a conformer-featurisation job (`conf_features.py`, label-free) and a ChEMBL pool download
(`fetch_chembl_pool.py`, label-free). Everything below that says "result" is filled in only in later commits; deviations are listed in
section 9 with the commit that introduced them.

## 0. Why this exists
The program previously compared its own scaffold-split R2 (0.12 ChemBERTa / 0.23 2D descriptors / 0.30 ECFP+3D-PSA proxy) with
"published CPMP ~0.67 and CycPeptMP ~0.77" (stored as `SOTA_CycPeptMP_scaffold_R2: 0.77` in `results/perm_oracle_chemberta.json`).
That label is wrong as far as I can verify (section 2): the published numbers are not scaffold-split numbers.

## 1. Data
* `research/guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv` (already in repo): 8,466 rows, 56 source publications,
  CycPeptMPDB versions 1.0 (7,451 rows) + 1.2 (1,015 rows). Official site http://cycpeptmpdb.com/ ; database paper Li et al., J. Chem. Inf. Model. 2023, 63(7):2240 (DOI 10.1021/acs.jcim.2c01573). Licence: not verified by me (**UNVERIFIED**; check the site's terms before redistributing; this repo only ships a derived cleaned table for internal research).
* Target `y` = the headline log10 Papp of the row's *primary assay* (priority PAMPA > Caco-2 > RRCK > MDCK; 99.1% of rows equal the DB `Permeability` column; the 0.9% that differ are rows with two assays where DB priority differs from mine - we use the assay-specific column).
* Filters (conservative, all counted in `results/data_report.json`): invalid SMILES 0, unparsable HELM 0, **censored/detection-limit rows dropped (384)**: any row with a `Detection_Limit_*` note or `y <= -10` (CycPeptMPDB sets -10 for "poor recovery"). Result: **8,082 rows / 7,612 unique peptides** (PAMPA 6,925; Caco-2 1,069; RRCK 65; MDCK 23). MDCK and RRCK are too small for reliable per-assay claims and are reported with that flag only.
* Peptide identity = canonical isomeric SMILES (md5 `pid`). 434 peptides appear in >1 row (391 in >1 source).
* Feature provenance: ECFP/RDKit descriptors computed by us from SMILES; monomers from HELM; the DB's own precomputed `CHCl3_3DPSA`/`H2O_3DPSA` columns are used only in the "in-repo 3D-PSA" baseline; **DB `EPSA`/`PSA`/`_3DPSA` experimental columns are never used** (label-like).

## 2. Published state of the art (what it actually reports; verified by fetching the papers, via automated page summarisation, so please re-check numbers against the PDFs before external use)
| model | paper | data | split | headline | code / weights |
|---|---|---|---|---|---|
| CycPeptMP | Li, Yanagisawa, Akiyama, Brief. Bioinform. 2024, 25(5):bbae417 | PAMPA only, 6,889 peptides (CycPeptMPDB, duplicates removed) | **Kennard-Stone selection of 5% (344) as test set** "uniformly covering the multidimensional space"; 3 random validation sets of 344 from the rest | R2 0.772 +/- 0.011, R 0.883, RMSE ~0.50, MAE 0.355 (test); 10-fold CV MAE 0.352 | code + weights public (github akiyamalab/cycpeptmp, MIT); **needs MOE (commercial) descriptors + external input files -> cannot be re-run here** |
| CPMP (MAT-based) | Frontiers in Bioinformatics 2025 (doi 10.3389/fbinf.2025.1566174) | PAMPA 6,701; Caco-2 1,310; RRCK 185; MDCK 64 (log Pe < -10 excluded) | **8:1:1 train/val/test (PAMPA, Caco-2), 7:3 (RRCK, MDCK); random vs scaffold not stated in the paper text I retrieved** | R2 PAMPA 0.671, Caco-2 0.746, RRCK 0.623, MDCK 0.727 (their own SVR 0.390 / RFR 0.388 on PAMPA) | github panda1103/CPMP; preprocessing ~5 h/assay, data 6.2 GB -> **not re-runnable here (disk 2 GB free, shared CPU)** |
| 13-method benchmark (D-MPNN best) | Liu, Li, Verma, Lee, J. Cheminform. 2025 (s13321-025-01083-4) | PAMPA, 5,826 samples, lengths 6/7/10 only | random 8:1:1 x10 seeds **and** one fixed Murcko-scaffold split | random-split regression R2: DMPNN 0.555, MPNN 0.512, AttentiveFP 0.502, RF 0.475, SVM 0.456; scaffold split: "significant drop for all models" (exact R2 in supplement, **not retrieved: UNVERIFIED**) | data/code github Gobliu/BenchmarkCycPeptMP |
Other newer works seen in search results but **not verified** (not used): MSF-CPMP (Comput. Struct. Biotechnol. J. 2025), EnsembleCycPerm (PubMed 42406990), decoupled alignment kernel (J. Cheminform. 2026), CycDelta (bioRxiv 2026.09.18.752569).

**Comparability finding (descriptive, `results/published_split_audit.json`, no model fitted):** CycPeptMP's published test set (344 peptides; 208 from 2013_CHUGAI) is *not* a random split and *not* a scaffold split. 51% of its test peptides share a generic Murcko scaffold with training (random 5%: 89%; scaffold-held-out: 0%), mean nearest-neighbour ECFP4 Tanimoto to train 0.83 (random 0.96), and its **test label SD is 1.05 vs 0.82 for a random 5% sample** (R2 scales with test variance, so an R2 on a deliberately spread-out test set is not comparable to an R2 on a random or scaffold fold). So neither "easy random split" nor "scaffold split" describes it. Part of the gap between our 0.23-0.30 and 0.77 is a comparability artefact; how much is measured below (split "P0").

## 3. Splits (fixed before fitting; fold files `data/folds.csv`; `make_splits.py`)
* **S0 reference-only**: random row-level 80/10/10, 5 seeds (as the CPMP-style protocol; duplicates are *not* grouped, replicating the published practice).
* **S1**: generic Bemis-Murcko scaffold groups (`MakeScaffoldGeneric` of the Murcko scaffold; 1,233 groups), balanced 5-fold grouped CV; whole groups held out.
* **S2**: monomer-composition clusters: Jaccard similarity on the *set* of HELM monomers, leader (Butina-style) clustering at similarity >= 0.5 (197 clusters, largest 1,681 rows), balanced 5-fold grouped CV, whole clusters held out. (Clusters are large; folds are therefore chemotype-level hold-outs and harsh.)
* **S3**: leave-one-source-publication-out over the 8 sources with >= 100 clean rows (Townsend 2,866; Kelly 1,519; CHUGAI-2013 842; Furukawa-2016 680; Ohta-2023 584; CHUGAI-2018 369; Faris-2024 207; Bhardwaj-2022 136; 7,203 rows). Smaller sources are always in training. For each held-out source, **training rows whose peptide (`pid`) occurs in the held-out source are removed**.
* **P0 (reference replica of the CycPeptMP split)**: the published test/train indices (`eval_index/Test_ID`, `Train_ID_cv0`+`Valid_ID_cv0`) on their own PAMPA pool (`desc/peptide_used.csv`), so that generic baselines can be compared to 0.772 on *their* split.
* Inside every outer training set, a validation subset (10% of train groups, same grouping type as the split; random rows for S0/P0) is used for early stopping, HP selection and conformal calibration. Test folds are never used for any choice.
* Per-assay: every result is also reported for PAMPA rows and Caco-2 rows separately (pooled models receive an assay term; RRCK/MDCK reported but flagged n<100).

## 4. Metrics
R2 (1 - SSE/SST against the test-set mean), RMSE, Spearman, computed on the pooled out-of-fold predictions of a split. 95% CIs: **cluster bootstrap, 1,000 resamples**, resampling whole groups (S1 scaffold groups, S2 clusters, S3 scaffold groups within the pooled held-out sources [source-level uncertainty is NOT captured and is shown by per-source results], S0 peptide ids). Paired differences use identical resamples.

## 5. Models (families fixed now; HP grids searched on the inner validation set only)
Baselines (reproduced by us): **M1** ECFP4-count(2048)+RF; **M2** ECFP4-count+HistGradientBoosting; **M3** RDKit 2D descriptors+HGB; **M5** "in-repo best": ECFP + DB 3D-PSA (CHCl3/H2O, delta) + HGB (a proxy of the earlier 0.301 model; **identity with that code is UNVERIFIED**, that number came from a different featurisation path); **G1** plain D-MPNN, assay one-hot at readout (our PyTorch re-implementation of the Chemprop-style model; the D-MPNN of Liu et al. is the best model in their benchmark; *not their code*).
Ours: **M4** monomer-aware trees (bag-of-HELM-monomers, ring size, N-Me/D-residue counts, shape, + 2D descriptors) ; **G2** multi-task D-MPNN (shared encoder, assay embedding + per-assay heads, masked loss); **G3** = G2 with encoder initialised by self-supervised pretraining on a ChEMBL macrocycle pool (section 6); **C1** trees on ECFP+2D desc+conformer-ensemble 3D features (RDKit ETKDGv3, 4 conformers, MMFF; 3D-PSA, Rg, asphericity, intramolecular NH...O=C H-bond count; evaluated **only on the random subset of peptides for which the featurisation finishes before the freeze time; all comparators are re-scored on that same subset**; if < 1,000 peptides finish C1 is reported as incomplete); **E1** equal-weight mean of M1, M4, G2, G3.
Compute-limited fallback (declared now): GNN fits use seeds 0-2 for S0 and one seed per fold for S1-S3 (+ extra seeds only for the learning curve if time allows).
Hyper-parameter grids: RF `max_features` in {0.3, sqrt}, `min_samples_leaf` in {1,3}; HGB `max_leaf_nodes` in {15,31}, `lr` 0.05, early stopping on inner val; GNN hidden 300, depth 4, dropout in {0.0,0.1}, early stopping on inner val, <= 40 epochs.

## 6. Pretraining pool (model G3)
ChEMBL_37 (2026-05-01) REST API, molecules with MW 700-1400, stream-filtered to peptide-like macrocycles (largest ring >= 12 atoms and >= 3 amide bonds), **minus any InChIKey first block present in CycPeptMPDB**; licence CC BY-SA 3.0; counts in `results/chembl_pool_report.json`. Pretraining target: standardised RDKit descriptors computed from the SMILES (no permeability labels; "weakly labelled" = computed properties). Reported with and without pretraining (G2 vs G3).

## 7. Claim rule (binding)
"Best" is claimed **only if** E1 beats the strongest *reproduced baseline* (best pooled R2 among M1, M2, M3, M5, G1 *on that split*, chosen on the test predictions, i.e. conservative against us) on **S1 and S2 and S3 simultaneously**, with the 95% CI of the paired R2 difference excluding 0 on each. Matching published numbers only on S0/P0 is reported as "matches reference on an easy/different split". Verdict categories: POSITIVE / MATCHES-REFERENCE-ONLY / NEGATIVE. Any statement about published SOTA is limited to "published figure, different split".

## 8. Diagnostics and tests (planned)
Learning curve on S1 (train fractions 0.1-1.0, M1/M3/M4/G2); uncertainty calibration (E1 member spread + split-conformal on inner val; coverage of nominal 90% intervals per split; Spearman(|error|, sigma)); error analysis by ring size / N-Me count / assay; **label-noise ceiling** from duplicates (same `pid`, same assay, different source: sigma2_noise = mean((y_i - y_j)^2)/2; ceiling R2 ~ 1 - sigma2_noise/Var(y), with the caveat that duplicates are biased toward well-studied peptides). `tests/`: no shared scaffold / cluster / source (+ no shared `pid` for S3) between train and test; SMILES/HELM parsing; label-permutation check (R2 ~ 0).

## 9. Deviations from this plan
(none yet; each later deviation is appended here with its commit hash)
