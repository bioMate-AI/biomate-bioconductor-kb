# A Comprehensive Survey of Patient Stratification Approaches

*Compiled 2026-08-17. Every citation traces to a real paper (PubMed/PMC/journal/FDA), the great majority verified against NCBI E-utilities or the primary record this session. Vendor claims, contested results, and unverified items are explicitly flagged. No DOIs are fabricated.*

**Scope.** A mechanistic, honestly-caveated overview of **all major current approaches to patient stratification** — sorting an apparently-homogeneous disease population into subgroups that differ in prognosis or treatment response — across oncology, immunology, and common disease, **not limited to any one modality**. Organized by **approach family**: (Part A) established molecular subtypes & unsupervised class discovery; (Part B) multi-omics, single-cell/spatial, and signature-scoring stratifiers; (Part C) clinical/genomic biomarkers, PRS, imaging, and the regulatory frame; (Part D) ML/AI, causal HTE, adaptive trials, EHR phenotyping, and immunotherapy stratification. For each: *what it is → how it defines the subgroup (mechanism) → key tools → clinical use → strengths → limitations*, closing with an honest read on **what is actually adopted / winning now**.

**Two distinctions that unify the whole field.**
1. **Predictive vs prognostic.** A *prognostic* marker informs likely outcome *regardless of treatment*; a *predictive* marker informs *differential benefit from a specific treatment* and requires a significant treatment-by-biomarker interaction (Ballman, *JCO* 2015, [10.1200/JCO.2015.63.3651](https://pubmed.ncbi.nlm.nih.gov/26392104/)). Plain ML captures the prognostic signal; causal/HTE methods and enrichment designs target the predictive signal. Conflating them drives wrong decisions.
2. **Supervised vs unsupervised.** Discover subgroups *de novo* (clustering) vs assign a new sample to a *pre-defined* subtype (nearest-centroid/classifier). The systems that reach the clinic pair a robust **single-sample classifier** with a specific, mechanism-linked decision.

**The recurring, generalizable caution:** bulk-expression subtypes are routinely **contaminated by non-tumor/stromal/immune content** (always ask *what cells produced the signal*), stability statistics measure *reproducibility of a procedure, not biological reality*, and **a valid endotype biomarker does not guarantee a successful drug** or a perfect responder-predictor.

---

# Part A — Established Molecular Subtypes & Unsupervised Class Discovery

## A1. Transcriptomic molecular subtypes (the deployed workhorse)

Partition a disease by genome-wide mRNA using either unsupervised clustering (discover) or a supervised nearest-centroid classifier (assign), then tie subtypes to biology and outcome.

- **PAM50 breast cancer** (Luminal A/B, HER2-enriched, Basal-like, Normal-like). Derived from the Perou/Sørlie intrinsic-subtype concept; **Parker et al. 2009** (*JCO*, [10.1200/JCO.2008.18.1370](https://pmc.ncbi.nlm.nih.gov/articles/PMC2667820/)) minimized to **50 genes** and a **nearest-centroid (Spearman) classifier** + a continuous **Risk-of-Recurrence (ROR)** score. Commercialized as **Prosigna** on NanoString nCounter; **FDA 510(k)-cleared Sept 2013** as a *prognostic* assay (10-yr distant-recurrence risk in postmenopausal HR+ early breast cancer). *(Note: Oncotype DX/TAILORx is the assay with level-1 *predictive* chemo-benefit evidence; Prosigna's cleared claim is prognostic.)* **Limit:** subtype instability near centroid boundaries (LumA/LumB flip); **Normal-like** is largely a low-cellularity artifact/QC flag.
- **Consensus Molecular Subtypes (CMS) of colorectal cancer** (CMS1 MSI-immune / CMS2 canonical / CMS3 metabolic / CMS4 mesenchymal). **Guinney et al. 2015** (*Nat Med*, [10.1038/nm.3967](https://pubmed.ncbi.nlm.nih.gov/26457759/)) for the CRC Subtyping Consortium reconciled six competing classifiers via **network-based consensus** on ~4,000 transcriptomes → subtypes stable to method choice. ~13% are mixed/indeterminate (honest "unclassified" bin). Frequencies ~CMS1 14% / CMS2 37% / CMS3 13% / CMS4 23%. Classifiers: CMSclassifier, CMScaller (**Eide 2017**, [10.1038/s41598-017-16747-x](https://pubmed.ncbi.nlm.nih.gov/29192179/)). CMS1 rationalizes checkpoint blockade (aligns with dMMR/MSI-H pembrolizumab); CMS4 (worst prognosis) is stroma/TGF-β-driven. **Limit:** CMS4 signal is stroma-driven (cellularity-sensitive); single-sample calls less stable than the pooled consensus.
- **TCGA expression subtypes.** **GBM** (Proneural/Neural/Classical/Mesenchymal; **Verhaak 2010**, [10.1016/j.ccr.2009.12.020](https://pubmed.ncbi.nlm.nih.gov/20129251/)) — later refined to **three** subtypes after **Wang 2017** ([10.1016/j.ccell.2017.06.003](https://pubmed.ncbi.nlm.nih.gov/28697342/)) **removed Neural as a normal-brain contamination artifact** (the canonical bulk-contamination cautionary tale). **Bladder** (6-class consensus, **Kamoun 2020**, [10.1016/j.eururo.2019.09.006](https://pubmed.ncbi.nlm.nih.gov/31563503/)); **Gastric** (EBV/MSI/GS/CIN, TCGA 2014, [10.1038/nature13480](https://pubmed.ncbi.nlm.nih.gov/25079317/)) — EBV/MSI → checkpoint immunotherapy.
- **SLE / autoimmune interferon-signature subtypes** (IFN-high vs IFN-low) — a *pathway-activation* subtype from coordinated ISG over-expression (**Baechler 2003**, *PNAS* [10.1073/pnas.0337679100](https://pubmed.ncbi.nlm.nih.gov/12604793/)); the **Chaussabel modular framework** (*Immunity* 2008, [10.1016/j.immuni.2008.05.012](https://pubmed.ncbi.nlm.nih.gov/18631455/)) and longitudinal **Banchereau 2016** (*Cell*, [10.1016/j.cell.2016.03.008](https://pubmed.ncbi.nlm.nih.gov/27040498/)) added plasmablast/neutrophil modules tracking flares/nephritis. Trial-enrichment closed the loop: **anifrolumab** (anti-IFNAR1) had larger effect in IFN-high patients (**TULIP-2, Morand 2020**, *NEJM* [10.1056/NEJMoa1912196](https://pubmed.ncbi.nlm.nih.gov/31851795/)); **FDA-approved Aug 2, 2021**. **Limit:** the IFN signature is dynamic (flares/infection/treatment); IFN-high *enriches* but doesn't guarantee response.
- **Asthma T2-high/T2-low** — a 3-gene bronchial-epithelial signature **POSTN/CLCA1/SERPINB2** (**Woodruff 2009**, *AJRCCM* [10.1164/rccm.200903-0392OC](https://pubmed.ncbi.nlm.nih.gov/19483109/) — *not PNAS, a common miscitation*). Underpins eosinophil/FeNO-guided biologics (anti-IL-5/IL-4Rα). **Cautionary tale:** serum periostin as a predictive biomarker for anti-IL-13 **failed** in Phase 3 (LAVOLTA, **Hanania 2016**, [10.1016/S2213-2600(16)30265-X](https://pubmed.ncbi.nlm.nih.gov/27616196/)) — a valid endotype biomarker did not yield a successful drug.

## A2. Unsupervised clustering / class discovery (how subtypes are found de novo)

The hard problem is not *finding* clusters (algorithms always return a partition) but proving they are **real, reproducible, biologically meaningful**.

- **Hierarchical clustering** (Eisen heatmap/dendrogram, **Eisen 1998**, *PNAS* [10.1073/pnas.95.25.14863](https://pubmed.ncbi.nlm.nih.gov/9843981/)) — foundational; discovered breast intrinsic subtypes (**Perou 2000**) and DLBCL GCB-vs-ABC cell-of-origin (**Alizadeh 2000**, [10.1038/35000501](https://pubmed.ncbi.nlm.nih.gov/10676951/)). **Limit:** greedy/irreversible; metric+linkage sensitive; cut-height arbitrary; no significance test.
- **Consensus clustering / ConsensusClusterPlus** — resampling meta-method quantifying stability and selecting *k* via consensus matrix / CDF / Δ(k) (**Monti 2003**, *Mach Learn* [10.1023/A:1023949509487]; package **Wilkerson & Hayes 2010**, [10.1093/bioinformatics/btq170](https://academic.oup.com/bioinformatics/article/26/12/1572/281699)). The TCGA-subtyping workhorse.
- **NMF / metagenes** — parts-based, interpretable factorization with cophenetic-correlation rank selection (**Brunet 2004**, *PNAS* [10.1073/pnas.0308531101](https://pubmed.ncbi.nlm.nih.gov/15016911/)); conceptual basis of mutational-signature extraction.
- **The reproducibility caveat (load-bearing).** **Şenbabaoğlu 2014** (*Sci Rep* [10.1038/srep06207](https://pubmed.ncbi.nlm.nih.gov/25158761/)) showed consensus clustering produces **crisp, stable-looking heatmaps on structureless null data**; Δ(k) is often uninformative; proposes **PAC (Proportion of Ambiguously Clustered pairs)** and a reference/null model. **Guardrails:** compare against a null (M3C/SigClust/gap), report PAC, require external-cohort validation, rule out batch/technical covariates, and confirm biological+clinical coherence before claiming a subtype exists.

---

# Part B — Multi-Omics, Single-Cell/Spatial & Signature-Scoring Stratifiers

## B1. Multi-omics integrative clustering

Given *N* omics on the *same* patients, find one subtype set reflecting joint structure — better than any single layer.

- **iCluster / iClusterPlus / iClusterBayes** — joint latent-variable models (shared **Z** drives every layer). iClusterPlus adds mixed-data GLM likelihoods + lasso; iClusterBayes is fully Bayesian (MCMC, spike-and-slab, posterior uncertainty). Bioconductor `iClusterPlus`; TCGA workhorse. **Shen 2009** ([Bioinformatics 25:2906](https://pubmed.ncbi.nlm.nih.gov/19759197/)); **Mo 2018** (*Biostatistics* [10.1093/biostatistics/kxx017]). **Limit:** compute-heavy grid search; linear.
- **MOFA / MOFA+** — unsupervised Bayesian PCA-generalization → interpretable **factors** with per-modality variance decomposition; handles missing assays and mixed likelihoods; **MOFA+** scales to single-cell. **Argelaguet 2018** (*Mol Syst Biol* e8124), **2020** (*Genome Biol* [10.1186/s13059-020-02015-1](https://pubmed.ncbi.nlm.nih.gov/32393329/)). Canonical **CLL** application recovered IGHV/trisomy-12 + an oxidative-stress factor predictive of survival. **Limit:** linear; clustering is a downstream choice.
- **Similarity Network Fusion (SNF)** — build per-omic patient-similarity networks, fuse via iterative cross-diffusion, spectral-cluster the fused network. Nonlinear, noise-robust, a top benchmark performer. **Wang 2014** (*Nat Methods* [10.1038/nmeth.2810](https://www.nature.com/articles/nmeth.2810)); GBM/kidney examples. **Limit:** black-box (no feature drivers); needs complete data; hyperparameter-sensitive.
- **MOVICS** — ensemble meta-framework running **10 algorithms** + consensus + full cancer-subtyping downstream (**Lu 2020**, *Bioinformatics* [10.1093/bioinformatics/btaa1018]). **DIABLO / mixOmics** — the **supervised** counterpart: multi-block sparse PLS-DA toward a *known* outcome → compact cross-omics biomarker panel (**Singh 2019**, [10.1093/bioinformatics/bty1054](https://pubmed.ncbi.nlm.nih.gov/30657866/)).
- **Benchmarks (no universal winner).** **Rappoport & Shamir 2018** (*NAR* [10.1093/nar/gky889](https://pubmed.ncbi.nlm.nih.gov/30295871/)) — SNF/similarity methods among the strongest across 10 TCGA types; performance varies by cancer and metric. **Cantini 2021** (*Nat Commun* [10.1038/s41467-020-20430-7](https://pubmed.ncbi.nlm.nih.gov/33402734/)) — intNMF best for clustering, MCIA most consistent, MOFA strongest for interpretability. **Practical rule:** match method to data type + clinical question; validate on survival/external cohorts.

## B2. Single-cell & spatial stratification

Convert high-dimensional expression into patient-level features — a composition vector, a latent multicellular program, a whole-TME archetype, or a spatial neighborhood.

- **Cell-composition / cell-state signatures** — stratify by relative abundance of cell types/states; because proportions are **compositional**, use **scCODA** (Bayesian Dirichlet-Multinomial) or **Milo** (kNN-neighborhood NB-GLM, captures continuous states). Verified disease examples: COVID-19 severity (**Stephenson 2021**, *Nat Med* [10.1038/s41591-021-01329-2]), SLE (**Perez 2022**, *Science* [10.1126/science.abf1970] — ISG-high monocytes + GZMH+ CD8 split patients into two molecular subtypes), UC anti-TNF resistance via **IL13RA2+/IL11+ inflammatory fibroblasts** (**Smillie 2019**, *Cell* [10.1016/j.cell.2019.06.029], PMID 31348891). **Limit:** compositionality trap; annotation non-portability; dissociation bias; discards space.
- **Ecotypes / EcoTyper** — deconvolve bulk (CIBERSORTx) → NMF cell states → **ecotypes** (co-occurring multicellular communities) that stratify prognostically; unlocks single-cell-like structure from large legacy bulk cohorts. **Luca 2021** (*Cell* [10.1016/j.cell.2021.09.014], 10 conserved carcinoma ecotypes) and **Steen 2021** (*Cancer Cell* [10.1016/j.ccell.2021.08.011], DLBCL ecotypes). *(Flag: exact "CE1–CE10"/"LE1–LE10" labels are high-confidence but not line-verified.)* **Limit:** deconvolution reference-bound; co-occurrence ≠ physical co-localization.
- **TME archetypes** — coarse, deployable pan-cancer taxonomy. **Bagaev 2021** (*Cancer Cell* [10.1016/j.ccell.2021.04.014]) — 29 functional signatures → **4 conserved TME subtypes (IE / IE-F / F / D)** that **predicted anti-PD-1/PD-L1/CTLA-4 response** across melanoma/bladder/gastric (immune-favorable respond best). **Combes 2022** (*Cell* [10.1016/j.cell.2021.12.004], PMID 34963056 — *corrected from a common mislabel*) — **12 dominant immune archetypes** recurring across cancers. **Limit:** coarse-graining; batch/cohort-sensitive; correlative, not a qualified CDx.
- **Spatial neighborhoods** — the only family that measures *who is next to whom*. **Schürch 2020** (*Cell* [10.1016/j.cell.2020.10.021]) CODEX CRC → **9 conserved cellular neighborhoods**; CN *coupling/fragmentation* predicted outcome (organization, not just abundance, stratifies — why some "infiltrated" tumors still fail immunotherapy). Tools: SpaGCN, BayesSpace, squidpy. **Limit:** low throughput; small cohorts; immature standardization.

## B3. Signature scoring & deconvolution (expression → a per-patient score)

- **Enrichment/module scoring** — **ssGSEA** (rank-based per-sample enrichment; **Barbie 2009**, *Nature* [10.1038/nature08460]) and **GSVA** (**Hänzelmann 2013**, *BMC Bioinformatics* [10.1186/1471-2105-14-7]); **Seurat AddModuleScore** (background-corrected module activity; **Tirosh 2016**, *Science* [10.1126/science.aad0501]). Continuous scores (IFN, proliferation, exhaustion) thresholded into strata. **Limit:** scores are cohort-relative (GSVA), gene-set-dependent, arbitrary thresholds, conflate cell source.
- **Deconvolution** — **CIBERSORT/CIBERSORTx** (ν-SVR against the LM22 22-cell-type matrix + batch correction + cell-type-specific expression imputation; **Newman 2015** *Nat Methods* [10.1038/nmeth.3337], **2019** *Nat Biotechnol* [10.1038/s41587-019-0114-2]); plus **xCell**, **MCP-counter**, **EPIC** (absolute fractions), **quanTIseq** (RNA-seq TIL10). Immune fractions (CD8, M1/M2) stratify prognosis/ICB response. **Limit:** relative-vs-absolute confusion, reference-matrix dependence, spillover between correlated subsets, platform/batch effects.
- **Companion-diagnostic-adjacent: the 18-gene T-cell-inflamed GEP / TIS** — **Ayers 2017** (*JCI* [10.1172/JCI91190](https://pmc.ncbi.nlm.nih.gov/articles/PMC5531419/)); LASSO-derived across 9 tumor types on pembrolizumab, fixed weights + fixed cutoff (−1.540), AUC ~0.75 (vs PD-L1 IHC ~0.65). The closest of these to a CDx role (still decision-support, not an FDA-approved CDx replacing PD-L1 IHC).

---

# Part C — Clinical/Genomic Biomarkers, PRS, Imaging & the Regulatory Frame

## C1. Single-analyte & genomic biomarkers (the mature, adopted layer)

- **Driver mutations** (EGFR, BRAF, ALK/ROS1/RET/NTRK fusions, KRAS G12C) → matched TKIs, via tissue NGS or plasma cfDNA. **FoundationOne CDx** (tissue) and **Guardant360 CDx** (liquid) are FDA companion diagnostics. **Limit:** acquired resistance; a positive test ≠ response (BRAF V600E colorectal responds poorly to BRAF-inhibitor monotherapy — context matters).
- **HER2** (IHC → reflex ISH) → trastuzumab/T-DXd; **HercepTest** was the first protein-based FDA CDx. The emerging **"HER2-low"** category exposes the limits of the original binary cut-point.
- **ER/PR** (IHC) → endocrine therapy — oldest predictive biomarker; predicts *candidacy*, not magnitude (why gene-expression assays were layered on top).
- **MSI-H / dMMR** → the basis of the **first-ever tissue-agnostic FDA approval** (pembrolizumab, 23 May 2017; **Le 2017**, *Science* [10.1126/science.aan6733](https://pmc.ncbi.nlm.nih.gov/articles/PMC5576142/), ORR 53%).
- **TMB** ≥10 mut/Mb → tissue-agnostic pembrolizumab (16 Jun 2020). **Key nuance:** **no universal pan-cancer threshold** — the predictive cut-point varies by histology (**Samstein 2019**, *Nat Genet* [10.1038/s41588-018-0312-8](https://pmc.ncbi.nlm.nih.gov/articles/PMC6365097/)).
- **PD-L1 IHC** — companion *or* complementary depending on drug/indication; the "harmonization problem" (non-interchangeable clones 22C3/28-8/SP263/SP142; TPS/CPS/IC scoring; interobserver variability; **Blueprint** discordance, **Hirsch 2017**).
- **Multigene expression assays** — **Oncotype DX** (21-gene RS; the only assay validated for *chemo-benefit prediction*, TAILORx/RxPONDER) and **MammaPrint** (70-gene, MINDACT). *Routine, reimbursed.*

## C2. Polygenic risk scores (PRS)

Aggregate hundreds-to-millions of common variants (GWAS-weighted) into one liability score that *shifts* an individual relative to a clinical baseline (a **risk enhancer**, not a binary call). CAD/ASCVD example (AHA 2025, Genomics plc): adding PRS to the AHA PREVENT tool gave ~6% NRI, reclassified ~8%, and high-PRS near-threshold individuals were ~2× likelier to develop ASCVD *(vendor press release — directionally reliable, not peer-reviewed)*. **ESC 2025** formally endorsed cautious PRS use. **Central limitation — ancestry portability:** European-dominated GWAS training degrades PRS performance in non-European populations (the PRIMED consortium exists to fix this). Adoption: mostly LDT/research; harder to validate than single-analyte assays.

## C3. Protein/serum panels & imaging/pathology

- **High-plex proteomics** — **Olink** (PEA, ~21–5,000 proteins from 1–2 µL) and **SomaScan** (aptamer, ~1,300→11,000 proteins) → learned multi-protein *signatures* that beat single markers for CV risk and immune phenotyping. Mostly **research/translational**, few FDA-cleared CDx; platform-specific units (NPX vs RFU) not comparable; overlapping inflammatory pathways make disease-*specific* signatures hard.
- **Radiomics** — quantitative CT/MRI/PET features (increasingly DL) for prognosis/response/subtype inference; predominantly research-grade, growing use for trial enrichment.
- **Digital-pathology foundation models (2024 frontier)** — self-supervised on millions of WSI tiles → transferable embeddings predicting subtype/biomarker/mutation/prognosis directly from cheap H&E. **UNI** (**Chen 2024**, *Nat Med* [10.1038/s41591-024-02857-3]; >100M images/100k WSIs/20 tissues), **Virchow** (**Vorontsov 2024**, *Nat Med* [10.1038/s41591-024-03141-0]; 1.5M WSIs, 0.95 specimen-level AUROC incl. rare cancers), **Prov-GigaPath** (**Xu 2024**, *Nature* [10.1038/s41586-024-07441-w]). Strong benchmarks, mostly **not yet standalone FDA-cleared** (task-specific products like Paige Prostate are the cleared exceptions).

## C4. Regulatory & trial framing

- **Companion (CDx)** = information *essential* for safe/effective use (must run before prescribing; co-approved with the drug). **Complementary** = *aids* the benefit/risk decision but not required (e.g. some PD-L1 tests).
- **FDA Biomarker Qualification Program** — three-stage pathway (21st Century Cures Act) qualifying a biomarker for a defined **"context of use"** reusable across programs.
- **Enrichment (FDA guidance, final Mar 2019)** — decrease heterogeneity; **prognostic enrichment** (likelier to have the event); **predictive enrichment** (likelier to respond by mechanism — the biomarker-driven, CDx-co-development case).

---

# Part D — ML/AI, Causal HTE, Adaptive Trials, EHR Phenotyping & Immune Stratification

## D1. Supervised ML for outcome/response prediction (the prognostic workhorse)

Penalized regression (**glmnet**, elastic-net signatures) → deep survival (**DeepSurv**, **Cox-nnet**) → multimodal fusion (attention-MIL **PORPOISE**, *Cancer Cell* 2022, [PMID 35944502](https://pubmed.ncbi.nlm.nih.gov/35944502/) — WSI + RNA-seq/CNV/mutation → per-patient hazard; high-attention regions containing TILs corroborate favorable prognosis in 12/14 cancers). **The dominant story is failure-by-methodology, not algorithm:** **Roberts 2021** (*Nat Mach Intell* [10.1038/s42256-021-00307-0]) — of 2,212 COVID imaging-ML studies, **none of 62 fully-reviewed were clinically usable** (leakage, no external validation/calibration); **Kapoor & Narayanan 2023** (*Patterns* [10.1016/j.patter.2023.100804]) — leakage in 294 papers across 17 fields. External validation + calibration + leakage control decide whether a stratifier is real.

## D2. Causal inference / heterogeneous treatment effects (the *predictive* signal)

Estimate the **CATE** τ(x)=E[Y(1)−Y(0)|X] under unconfoundedness + overlap, then stratify by who benefits — distinct from D1 (which predicts outcome level, not treatment *effect*).
- **Meta-learners** — **X-learner** (**Künzel 2019**, *PNAS* [10.1073/pnas.1804597116]; robust under imbalanced assignment), **R-learner** (**Nie & Wager 2021**, *Biometrika*; quasi-oracle, Neyman-orthogonal).
- **Forests** — **Causal Forests** (**Wager & Athey 2018**, *JASA*; honesty → valid CIs) and **Generalized Random Forests** (`grf`; IV forests under unobserved confounding).
- **Bayesian trees** — **BART** (**Hill 2011**) and **Bayesian Causal Forests** (**Hahn 2020**; prognostic+treatment reparameterization removes regularization-induced confounding, fewer spurious subgroups).
- **Neural** — **DragonNet** (**Shi 2019**; targeted regularization → doubly-robust).
- **Subgroup ID + honest intervals** — **Virtual Twins**, **SIDES/SIDEScreen** (splits on a *differential-effect* criterion → recovers *predictive* biomarkers), **conformal ITE intervals** (**Lei & Candès 2021**; distribution-free coverage). **Limit:** all assume unconfoundedness + overlap (silently violated in RWD); subgroup methods risk multiplicity-driven false discovery.

## D3. Adaptive & enrichment trial designs (the deployed oncology winner)

Governed by FDA **Enrichment** (2019), **Adaptive Designs** (2019), and **Complex Innovative Trial Designs** (2020) guidances (prospectively-planned adaptations, study-wide Type-I control, simulation reports). Methods: **Adaptive Signature/Enrichment Designs** (Freidlin & Simon; Simon & Simon 2013). **Master protocols** (**Woodcock & LaVange 2017**, *NEJM* [10.1056/NEJMra1510062]): **basket** (one therapy across diseases), **umbrella** (one disease, biomarker-matched arms), **platform** (perpetual). Landmark trials: **VE-BASKET** (**Hyman 2015**, *NEJM* — BRAF V600 across histologies; taught the falsifiable lesson **biomarker ≠ histology-agnostic guarantee**: colorectal did not respond), **Lung-MAP**, **BATTLE** (response-adaptive randomization), **I-SPY 2** (Bayesian RAR within 8 biomarker signatures, arms "graduate"), **NCI-MATCH** (**Flaherty 2020**, *JCO* — 5,954 profiled, 37.6% actionable, ~26% assignable — the real-world yield of genomic matching at scale). **Limit:** predictive enrichment narrows the label + assumes a locked assay; Bayesian borrowing trades power for Type-I risk in discordant baskets.

## D4. EHR / real-world phenotyping

Rule-based portable algorithms (**eMERGE**, **Kho 2012** — replicated TCF7L2 across 5 EMRs; shared via **PheKB**) → **PheWAS** (**Denny 2010**) → unsupervised subtyping (**TDA T2D 3 subtypes**, **Li 2015**, *Sci Transl Med*; **Deep Patient**, **Miotto 2016**) → weakly-supervised (**Anchor & Learn**; APHRODITE/OHDSI) → **federated learning** (**EXAM**, **Dayan 2021**, *Nat Med* — 20 institutions, +16% AUC, +38% generalizability without pooling data) → **EHR foundation models** (**Med-BERT**, **BEHRT**, **ETHOS** — zero-shot health-timeline forecasting; *ETHOS is npj Digital Medicine, not Nat Med*). **Limit:** billing codes are noisy phenotype proxies; unsupervised subtypes need clinical validation; FMs inherit coding/site bias.

## D5. Immune / immunotherapy stratification (converging on combinations, not single markers)

- **Expression signatures** — **TIDE** (**Jiang 2018**, *Nat Med* [10.1038/s41591-018-0136-1] — models T-cell dysfunction vs exclusion via CTL-interaction genes), **GEP** (Ayers, §B3), **IMPRES** (**Auslander 2018** — 15 checkpoint-gene pairwise inequalities; ⚠️ **contested**: **Carter 2019** matters-arising [10.1038/s41591-019-0671-4] showed it doesn't robustly replicate).
- **Mutational/DNA-repair** — **TMB** (Samstein, no universal threshold) and **MSI-H/dMMR** (Le, tissue-agnostic approval).
- **irAE risk (an open problem)** — **Jing 2020** (*Nat Commun*) multi-omic prediction; ⚠️ **no locked clinical-grade irAE biomarker exists** (HLA, autoantibodies, IL-6/CRP, microbiome, TCR clonality all candidate-only).
- **The incumbent & its limits** — PD-L1 IHC is predictive *on average* but unreliable (**SITC taskforce, Kluger 2020**; Blueprint discordance). **Independent benchmark** (**Litchfield 2021**, *Cell* [10.1016/j.cell.2020.11.041]): **clonal TMB + GEP + CXCL9** carry **independent** predictive information — combinations outperform singletons.

## D6. Emerging (frontier with a credibility gap)

**Digital twins** (Unlearn PROCOVA prognostic covariate → ~9–26% sample-size reduction in a peer-reviewed AD trial; ⚠️ the circulated "35% smaller control arms" is vendor marketing), **generative EHR models** (ETHOS, Foresight), **LLMs over records** (⚠️ LLM phenotyping still needs expert refinement; Med-PaLM is QA-benchmarked, not real cohort stratification), and **single-cell FMs** (scGPT/Geneformer; ⚠️ independent benchmarks report zero-shot sometimes underperforms simple baselines — do not overstate).

---

# What's Actually Adopted / Winning Now (the honest split)

| Layer | Adoption state |
|---|---|
| Driver mutations, HER2, ER/PR, MSI-H/dMMR, TMB, PD-L1 + FDA CDx | **Standard of care**, guideline-embedded (oncology) |
| Oncotype DX / multigene breast signatures | **Routine, reimbursed**, prospectively validated (TAILORx/RxPONDER, MINDACT) |
| Transcriptomic subtypes reaching clinic (Prosigna/PAM50, IFN-signature, eosinophil/FeNO endotypes) | **Deployed** — each pairs a robust single-sample classifier with a mechanism-linked decision |
| Master protocols + genomic matching (I-SPY 2, Lung-MAP, NCI-MATCH) | **Operationalized, FDA-endorsed** reality of stratified oncology trials |
| Multi-omics integrative clustering (MOFA/SNF/iCluster) | **Research-standard** for subtype discovery; no universal winner; validate on survival/external cohorts |
| Immune signatures (TIDE/GEP/TMB) | **Research→translational**; combinations > singletons; PD-L1 unreliable alone; IMPRES contested; irAE unsolved |
| PRS | **Early clinical entry** (ESC 2025 cautious); risk-enhancer use; ancestry portability is the blocker |
| High-plex proteomics (Olink/SomaScan), radiomics | **Research/translational**; strong discovery signal, standardization gap |
| Pathology & EHR foundation models, digital twins | **Fast-moving frontier**; strong transfer/benchmarks, real validation gaps, mostly pre-CDx |

**Three throughlines:**
1. **The predictive-vs-prognostic discipline decides what licenses a treatment claim** — effect-modification methods (causal forests, R-/X-learners, BCF, SIDES, adaptive enrichment), not plain outcome prediction.
2. **The mature, adopted layer is single-analyte/genomic oncology biomarkers with FDA companion diagnostics + validated multigene assays**, deployed inside adaptive master protocols.
3. **The dominant failure mode across the ML/omics frontier is methodological, not algorithmic** — leakage, no external validation, no calibration, arbitrary thresholds, bulk contamination, and stability mistaken for biology. The field is moving toward **multimodal, causally-grounded, uncertainty-aware stratification embedded in adaptive trials** — bottlenecked less by model capacity than by validation rigor and locked, assay-ready biomarkers.

---

## Verification & honesty notes

- **Verified this session (NCBI E-utilities / PMC / primary record):** all Part-A transcriptomic-subtype refs (PAM50/CMS/TCGA/SLE-IFN/asthma) and clustering refs (Eisen/Perou/Alizadeh/Monti/Wilkerson/Brunet/Şenbabaoğlu); Part-B multi-omics (iCluster/MOFA/SNF/MOVICS/DIABLO + Rappoport & Cantini benchmarks), single-cell/spatial (scCODA/Milo, Stephenson/Perez/Smillie, Luca/Steen EcoTyper, Bagaev/Combes, Schürch), signature/deconvolution (ssGSEA/GSVA, CIBERSORT/x, AddModuleScore, GEP, xCell/MCP/EPIC/quanTIseq); Part-C genomic biomarkers, PRS evidence, pathology FMs, regulatory framework; Part-D ML/causal/trial/EHR/immune (~55 sources, DOIs resolving).
- **Corrections surfaced:** Woodruff 2009 = *AJRCCM* not PNAS; GBM "Neural" subtype = contamination artifact (Wang 2017); Combes archetypes = PMID 34963056 (*Cell* 2022), not the commonly-attached Cancer Cell PMID; ETHOS = *npj Digital Medicine* not *Nat Med*.
- **Flagged contested / vendor / unverified:** IMPRES robustness (Carter rebuttal); irAE has no locked biomarker; single-cell FM zero-shot gains contested; digital-twin "35%" figure is vendor marketing; AHA-2025 PRS numbers are a press release; UNI/Virchow training numbers from abstract-level summaries; MammaPrint/MINDACT is widely-reported background; EcoTyper CE/LE exact labels high-confidence-not-line-verified; SLE "Bennett 2003" and "sifalimumab Khamashta 2016" flagged UNVERIFIED. Publisher bot-blocks (Science/Cell/AACR/FDA/NEJM) cross-verified via PMC/PubMed. **No DOIs were fabricated.**

*Companion document: `docs/20260817_TARGET_IDENTIFICATION_SURVEY.md`.*
