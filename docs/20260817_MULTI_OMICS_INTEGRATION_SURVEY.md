# Multi-Omics Data Integration: A State-of-the-Art Survey

*Prepared 2026-08-17. Every citation verified by resolving the DOI/PMID against NCBI PubMed (E-utilities) and/or the publisher page. No DOI is fabricated; residual unverified items are flagged.*

## Introduction

Modern biology rarely measures one thing at a time. A single patient sample can now yield mRNA expression, DNA methylation, copy-number alterations, protein and phospho-protein levels, metabolites, and — at single-cell and spatial resolution — paired transcriptome + surface protein (CITE-seq) or transcriptome + chromatin accessibility (Multiome). **Multi-omics data integration** is the family of statistical and machine-learning methods that jointly analyze these heterogeneous "views" of the same samples to find shared structure: disease subtypes, patient strata, co-regulated modules, and multi-modal biomarkers that no single assay reveals. The central challenge is that the views differ in scale, noise model, dimensionality (often *p ≫ n*), and biological meaning, so naïvely concatenating them lets the highest-variance modality dominate. The field is organized below by **approach family**; for each we give mechanism, tools, use, strengths, limitations, and verified citations. Two large independent benchmarks (Rappoport & Shamir 2018; Cantini et al. 2021) converge on one honest headline: **there is no universal winner — the best method is task- and data-dependent.**

---

## 1. Joint latent-variable / factor models

**What it is.** Posit that all omics views are noisy, view-specific projections of a small set of shared **latent factors**. Integration = inferring those factors.

**Mechanism.** A generative model links latent factors **Z** to each view **X_m** through view-specific loadings **W_m** (`X_m ≈ W_m Z + noise_m`), with a per-view noise model:
- **iCluster / iClusterPlus / iClusterBayes** — joint latent Gaussian (later GLM / fully Bayesian) model; samples clustered in the shared space; Bayesian variants use sparsity priors + MCMC, each view carrying its own likelihood.
- **MOFA / MOFA+** — Bayesian group factor analysis with **ARD** priors + spike-and-slab sparsity; ARD prunes unneeded factors and reveals, per factor, **which views it is active in**. MOFA+ adds stochastic variational inference scaling to millions of cells + multiple groups.
- **JIVE** — decomposes total variation into **joint** structure common to all views + **individual** private structures + noise.
- **MCIA** — multivariate ordination maximizing **co-inertia** (squared covariance) between each view and a synthetic reference; unsupervised, fast.

**Tools.** `iClusterPlus`/`iClusterBayes` (R); `MOFA2` (R+Python); `r.jive`; `omicade4`/`mogsa` (MCIA).

**Use.** Cancer subtyping (breast, lung, ovarian, glioma), patient stratification, factor–survival/covariate association (MOFA's canonical CLL analysis: a factor ↔ IGHV status + drug response).

**Strengths.** Interpretable factors with per-view weights; principled heterogeneous noise; MOFA/ARD auto-downweights junk views; JIVE separates shared vs private.

**Limitations.** Linear/Gaussian misses nonlinearity; iCluster MCMC is slow/tuning-sensitive (λ, K); factor count K must be chosen; MCIA needs prior standardization or a high-magnitude view swamps others.

**Citations.** Shen et al. 2009, *Bioinformatics* 25:2906 (10.1093/bioinformatics/btp543, PMID 19759197); Mo et al. 2013, *PNAS* 110:4245 (10.1073/pnas.1208949110, PMID 23431203); Mo et al. 2018, *Biostatistics* 19:71 (10.1093/biostatistics/kxx017, PMID 28541380); Argelaguet et al. 2018, *Mol Syst Biol* 14:e8124 (10.15252/msb.20178124, PMID 29925568); Argelaguet et al. 2020, *Genome Biol* 21:111 (10.1186/s13059-020-02015-1, PMID 32393329); Lock et al. 2013, *Ann Appl Stat* 7:523 (10.1214/12-AOAS597, PMID 23745156); Meng et al. 2014, *BMC Bioinformatics* 15:162 (10.1186/1471-2105-15-162, PMID 24884486).

---

## 2. Network fusion

**What it is.** Fuse **patient-similarity networks** (one graph per view) into a consensus network, then cluster.

**Mechanism.** **SNF** builds a sample×sample similarity graph per view, then iteratively updates each via **cross-diffusion / message-passing** — weak view-specific edges wash out, cross-view-supported edges reinforce; spectral-cluster the fused graph. **NEMO** simplifies to a closed-form average of per-view relative-similarity matrices (no iteration) and natively handles **partial data** (samples missing some views).

**Tools.** `SNFtool` (R/MATLAB/Python); `NEMO` (R).

**Use.** Subtype discovery from mRNA + methylation + miRNA (SNF's original GBM/kidney/lung); incomplete-assay cohorts (NEMO).

**Strengths.** Nonparametric; combines any views with a definable similarity; SNF robust to view-specific noise; NEMO handles missing modalities and is fast.

**Limitations.** SNF's equal-weight fusion is **fragile to a wholly-uninformative view**; output is a graph, not per-feature loadings (indirect biomarker attribution); hyperparameters (K, iterations) need tuning.

**Citations.** Wang et al. 2014, *Nat Methods* 11:333 (10.1038/nmeth.2810, PMID 24464287); Rappoport & Shamir 2019, *Bioinformatics* 35:3348 (10.1093/bioinformatics/btz058, PMID 30698637) (NEMO).

---

## 3. Matrix factorization (non-negative)

**What it is.** Factorize each view's non-negative matrix into a **shared sample-coefficient matrix** + view-specific non-negative bases → parts-based, additive "metafeature" modules.

**Mechanism.** Joint NMF minimizes `Σ_m ‖X_m − W_m H‖²` with non-negativity and **H** shared across views. **intNMF** is the canonical integrative-clustering implementation.

**Tools.** `IntNMF` (R); joint-NMF in `scikit-fusion` (Python).

**Use.** Cancer subtyping; extracting co-varying multi-omics modules.

**Strengths.** Highly interpretable additive factors; **best-in-class for recovering ground-truth clusters** in the Cantini benchmark; minimal distributional assumptions.

**Limitations.** Requires non-negative inputs (shift/transform signed data); non-convex (local optima, init-dependent); rank K must be chosen.

**Citations.** Chalise & Fridley 2017, *PLoS ONE* 12:e0176278 (10.1371/journal.pone.0176278, PMID 28459819). *(Source-brief correction: the verified title contains no "CoRal.")*

---

## 4. Supervised integration

**What it is.** Uses a **known outcome/label** to guide integration toward jointly-discriminative features across views.

**Mechanism.** **DIABLO** (in **mixOmics**) extends sparse PLS / generalized CCA to find sparse latent components **across all views** that are (a) mutually correlated and (b) predictive of the outcome; L1 sparsity → a compact multi-omics signature.

**Tools.** `mixOmics` (R), `block.splsda` (DIABLO).

**Use.** Multi-omics biomarker panels/classifiers (e.g., breast-cancer subtype from mRNA+miRNA+methylation+protein).

**Strengths.** Directly optimizes for the outcome; compact interpretable cross-modal signatures; rich diagnostics/CV.

**Limitations.** Needs labels (no pure discovery); overfitting risk at small n/high p (nested CV mandatory); linear/correlational; design-matrix is a modeling choice.

**Citations.** Singh et al. 2019, *Bioinformatics* 35:3055 (10.1093/bioinformatics/bty1054, PMID 30657866); Rohart et al. 2017, *PLoS Comput Biol* 13:e1005752 (10.1371/journal.pcbi.1005752, PMID 29099853).

---

## 5. Deep-learning integration

**What it is.** Autoencoders, VAEs, and GNNs learn a shared nonlinear embedding; dominant for **single-cell & spatial** multi-omics.

**Mechanism (by tool).**
- **MOGONET** — one GCN per view (nodes=patients) + a View Correlation Discovery Network fusing cross-omics label correlations; classification + biomarker ID (bulk).
- **totalVI** — VAE jointly modeling CITE-seq RNA (NB) + surface protein (with background) → denoised, batch-corrected joint latent space.
- **MultiVI** — VAE integrating **paired and unpaired** RNA/ATAC/protein, imputing missing modalities (mosaic regime).
- **WNN / Seurat v4** — learns per-cell **relative modality weights** → a single weighted neighbor graph.
- **GLUE** — VAE integration of **unpaired** modalities linked by a **prior-knowledge guidance graph** (ATAC peaks→genes), enabling regulatory inference with no shared cells.
- **SpatialGlue** — GNN with **dual-attention** integrating spatial location with each omics (intra) then across omics (cross) to resolve spatial domains.

**Tools.** `MOGONET` (PyTorch); `scvi-tools` (totalVI, MultiVI); `Seurat` v4 (WNN); `scglue`; `SpatialGlue`.

**Use.** Atlas building; cell-type/state discovery across RNA+protein+chromatin; cross-modality imputation; spatial domains; patient classification (MOGONET).

**Strengths.** Nonlinear; scale to millions of cells; handle batch, unpaired/mosaic designs, prior graphs; SOTA on single-cell/spatial.

**Limitations.** Data/compute-hungry (GPU); low interpretability; many hyperparameters + stochastic training; preprocessing-sensitive; over-integration risk. Deep does **not** automatically beat tuned classical baselines — must be shown per task.

**Citations.** Wang et al. 2021, *Nat Commun* 12:3445 (10.1038/s41467-021-23774-w, PMID 34103512); Gayoso et al. 2021, *Nat Methods* 18:272 (10.1038/s41592-020-01050-x, PMID 33589839); Ashuach et al. 2023, *Nat Methods* 20:1222 (10.1038/s41592-023-01909-9, PMID 37386189); Hao et al. 2021, *Cell* 184:3573 (10.1016/j.cell.2021.04.048, PMID 34062119); Cao & Gao 2022, *Nat Biotechnol* 40:1458 (10.1038/s41587-022-01284-4, PMID 35501393); Long et al. 2024, *Nat Methods* 21:1658 (10.1038/s41592-024-02316-4, PMID 38907114).

---

## 6. Ensemble / consensus meta-frameworks

**What it is.** Run **many** integration/clustering methods and reconcile into a **consensus** + standardized downstream evaluation.

**Mechanism.** Each method produces a clustering; a **consensus** step (co-association / majority voting) merges into a stable partition, then computes standardized metrics (silhouette, survival, clinical enrichment) — operationalizing "no universal winner." **MOVICS** wraps ~10 algorithms (iClusterBayes, SNF, MoCluster, CIMLR, IntNMF, ConsensusClustering, LRAcluster, PINSPlus, NEMO, COCA). **CancerSubtypes** unifies consensus clustering, SNF, iCluster.

**Tools.** `MOVICS` (R); `CancerSubtypes` (R).

**Strengths.** Robustness through aggregation; standardized reproducible evaluation; lowers barrier to running many methods.

**Limitations.** Consensus can wash out a genuinely-best single method; still needs K + method choice; cancer-oriented; heavy dependency stacks.

**Citations.** Lu et al. 2020, *Bioinformatics* 36:5539 (10.1093/bioinformatics/btaa1018, PMID 33315104); Xu et al. 2017, *Bioinformatics* 33:3131 (10.1093/bioinformatics/btx378, PMID 28605519).

---

## 7. Benchmarks — how the field is actually measured

- **Rappoport & Shamir 2018** (*NAR* 46:10546, 10.1093/nar/gky889, PMID 30295871): 9 algorithms × 10 TCGA cancers (expression+methylation+miRNA). **No algorithm universally wins**; in aggregate **MCCA** gave the best prognostic value, **rMKL-LPP** the most enriched clinical parameters.
- **Cantini et al. 2021** (*Nat Commun* 12:124, 10.1038/s41467-020-20430-7, PMID 33402734): 9 joint-dimensionality-reduction methods across simulated + TCGA + single-cell. **No universal winner**; **intNMF** best at cluster recovery, **MCIA** most consistent all-rounder.

---

## What's Winning / Honest State

- **No universal winner** — the single most reproducible message; performance is task- and data-dependent.
- **Reference performers by objective:** cluster recovery → **intNMF**; consistent bulk all-rounder → **MCIA**; interpretable view-attributable factors → **MOFA/MOFA+**; survival prognosis → **MCCA/rMKL-LPP**; supervised signatures → **DIABLO**; robustness → **SNF/NEMO** + consensus (**MOVICS**).
- **Single-cell & spatial are deep-learning-led** (totalVI/MultiVI, Seurat WNN, GLUE, SpatialGlue) — but deep ≠ automatic win over tuned baselines.
- **Practical implication:** run several methods and compare with a fair quantitative harness on *your* data.

### BioMate Positioning

*(Accurate, from BioMate's records; a tool/resource, not a new method or benchmark finding.)*

- **Multiple SOTA methods behind one plain-English → cloud pipeline.** Seven integration methods run end-to-end on AWS Batch (Nextflow): **MOFA2, SNF, intNMF, MCIA, MFA, iClusterPlus, JIVE** (StabMap in progress), via a **universal CSV interface** (features×samples per modality, sample-intersected).
- **Head-to-head on real data, scored reproducibly.** A worked pilot compared MOFA2 vs SNF (and others) on real **CLL (Dietrich 2018)** and TCGA cohorts, matched-k, scored by a reproducible metric harness against gold-standard labels (IGHV for CLL, PAM50 for BRCA). It **reproduces the literature's message on the user's own data**: MOFA2 led on CLL, MCIA led on TCGA — leader changes by cohort, validating Cantini's "MCIA most robust."
- **SOTA per-modality normalization** applied automatically (log2-CPM bulk RNA/miRNA, log1p-CP10k scRNA, M-value methylation, TF-IDF scATAC, median-centering proteomics) — precisely the step that fixes the high-magnitude-view-dominance failure mode.
- **What BioMate does NOT claim:** not a new algorithm, not a new benchmark result; several modalities (MS proteomics, metabolomics, spatial, CNV, microbiome) have the universal interface in principle but are not yet runtime-validated end-to-end. The genuine differentiator under construction: unifying bulk + single-cell integration under one maintained, your-own-data cloud platform, plus a wet-lab design-build-test-learn loop software-only competitors cannot copy.

---

*Verification note: all 22 core citations confirmed via NCBI E-utilities / publisher. Source-brief corrections: DIABLO DOI is `bty1054`; intNMF title has no "CoRal"; NEMO PMID 30698637. SpatialGlue co-author names beyond first author UNVERIFIED (title/journal/DOI/PMID confirmed). No DOIs fabricated. Companion showcase: `blog-multi-omics.html`. Related BioMate surveys: target identification, patient stratification, virtual cell modeling, protein conformation.*
