# BioMate Workflow Catalog

*Generated: 2026-03-04 | 2,063+ subworkflows across 24 domains*

This document is the canonical reference for all Nextflow workflows in the BioMate
platform. It covers the full domain index, deep documentation of 15 recently-implemented
or high-priority workflows, the QC gate integration map, all 25 named QC profiles, and
execution profile guidance.

---

## Table of Contents

1. [Domain Index](#1-domain-index)
2. [Top-Level Composite Workflows](#2-top-level-composite-workflows)
3. [Detailed Workflow Reference](#3-detailed-workflow-reference)
   - 3.1 [Drug Discovery / Structural Biology](#31-drug-discovery--structural-biology)
   - 3.2 [Cryo-EM / CryoSPARC SPA](#32-cryo-em--cryosparc-spa)
   - 3.3 [Pharmacology / PK-PD](#33-pharmacology--pk-pd)
   - 3.4 [Genomics — Connectors & CRISPR](#34-genomics--connectors--crispr)
   - 3.5 [RNA-seq / Transcriptomics — Bioconductor Tier](#35-rna-seq--transcriptomics--bioconductor-tier)
   - 3.6 [Single-Cell & Trajectory](#36-single-cell--trajectory)
   - 3.7 [Pre-existing Core Genomics (samples)](#37-pre-existing-core-genomics-samples)
4. [QC Gate Integration](#4-qc-gate-integration)
5. [Named QC Profiles](#5-named-qc-profiles)
6. [Execution Profiles](#6-execution-profiles)
7. [Adding a New Workflow](#7-adding-a-new-workflow)

---

## 1. Domain Index

All subworkflows live under:
```
backend/biomni_workflows/nextflow_nfcore/subworkflows/<domain>/<workflow_name>/main.nf
```

Top-level composite workflows live under:
```
backend/biomni_workflows/nextflow_nfcore/workflows/<pipeline_name>/main.nf
```

### 1.1 Subworkflow counts by domain

| Domain | Count | Description |
|---|---|---|
| **bioconductor** | ~2,241 | One subworkflow per Bioconductor package (87.8% have clean workflows); covers R/Bioc ecosystem for omics analysis |
| **pharmacology** | ~30 | ADMET prediction, molecular docking, NCA, PopPK, PGx, drug-label, IVIVE, QSAR |
| **molecular_biology** | ~22 | Primer design, Golden Gate assembly, sgRNA design, plasmid annotation, restriction digest, sequence alignment |
| **genomics** | ~28 | scRNA-seq embeddings, GSEA, chromatin, trajectory inference, GEO connector, Perturb-seq, scVI/Harmony, Hi-C |
| **bioimaging** | ~16 | Image registration (ANTs), nnU-Net segmentation, rigid/affine/deformable transforms, NIfTI QC |
| **microbiology** | ~16 | Bacterial growth modelling, colony counting, RNA structure prediction, microbial image segmentation, biofilm QC |
| **immunology** | ~13 | Bacterial growth curves, ATAC-seq accessibility, EBV titres, cytokine production, CFSE proliferation |
| **bioengineering** | ~13 | Drug release kinetics, cell migration, calcium imaging, CRISPR-Cas9 engineering, whole-cell ODE models |
| **genetics** | ~11 | Cas9 editing outcomes, CRISPR analysis, finemapping, phylogeny, PCR, demographic simulation |
| **physiology** | ~9 | Brain ADC maps, cosinor rhythm, amyloid quantification, auditory brainstem, fatty acid GC |
| **biochemistry** | ~9 | Enzyme kinetics (Michaelis-Menten), dose-response, ITC thermodynamics, CD spectra, RNA secondary structure |
| **systems_biology** | ~10 | FBA, protein signalling ODE, RAS system dynamics, metabolic network perturbation, ChatNT query |
| **cancer_biology** | ~6 | Copy-number/purity/ploidy, somatic mutation, structural variation, NMF expression, DDR network, senescence |
| **synthetic_biology** | ~9 | Barcode sequencing, bifurcation diagrams, SBML model creation, gene circuits, codon optimisation |
| **pathology** | ~7 | Aortic geometry, ATP luminescence, bone microCT, thrombus histology, corneal nerve fibre quantification |
| **cell_biology** | ~4 | Flow cytometry immunophenotyping, FACS sorting, mitochondrial morphology, cell motility clustering |
| **lab_automation** | ~6 | PyLabRobot liquid/material handling, async execution, script testing |
| **database** | ~5 | BLAST sequence search, HPO lookup, cCRE annotation, ENCODE region-to-cCRE |
| **glycoengineering** | ~3 | N-glycosylation motifs, O-glycosylation hotspots, glycoengineering resources |
| **literature** | ~3 | Advanced Claude web search, PDF extraction, URL content extraction, DOI supplementary fetch |
| **drug_discovery** | 1 | AlphaFold3 + DiffDock + AutoDock Vina integrated docking pipeline |
| **cryo_em** | 1 | Full 23-step CryoSPARC SPA pipeline (import → sharpen) |
| **proteomics** | 1 | Chemoproteomics pulldown enrichment analysis |
| **biophysics** | ~2 | Tissue deformation flow, cell morphology and cytoskeleton |

**Total (non-bioconductor subworkflows): ~246**
**Total (including bioconductor): ~2,487**

---

## 2. Top-Level Composite Workflows

These orchestrate multiple subworkflows into end-to-end pipelines:

| Workflow | Path | Description | Key Subworkflows |
|---|---|---|---|
| `drug_discovery` | `workflows/drug_discovery/` | SMILES → physicochemical props → ADMET → DiffDock → FDA safety | 6 pharmacology subworkflows |
| `molecular_cloning` | `workflows/molecular_cloning/` | Gene CDS → Golden Gate oligos → assembly → annotate plasmid → digest | 5 molecular biology subworkflows |
| `bioconductor_rnaseq_de` | `workflows/bioconductor_rnaseq_de/` | Salmon/kallisto → tximport → DESeq2 (+edgeR/limma) → GSEA → KEGG viz | DESeq2, edgeR, limma, clusterProfiler, pathview |
| `bioconductor_scrna_seq` | `workflows/bioconductor_scrna_seq/` | Cell Ranger → tximeta → scran norm → SingleR annotation → miloR → GSEA | tximeta, scran, SingleR, miloR, clusterProfiler |
| `bioconductor_chipseq` | `workflows/bioconductor_chipseq/` | ChIP-seq peak analysis and motif discovery | DiffBind, ChIPseeker, clusterProfiler |
| `bioconductor_methylation` | `workflows/bioconductor_methylation/` | Bisulfite methylation analysis and DMR calling | minfi, methylKit, bumphunter |
| `bioconductor_metabolomics` | `workflows/bioconductor_metabolomics/` | LC-MS metabolomics processing | XCMS, metaboanalyst |
| `bioconductor_multiomics` | `workflows/bioconductor_multiomics/` | Multi-omics factor analysis (RNA + proteomics + metabolomics) | MultiAssayExperiment, MOFA2, DESeq2, clusterProfiler |
| `rnaseq_patient_stratification` | `workflows/rnaseq_patient_stratification/` | Expression matrix → consensus clustering → Kaplan-Meier → Cox PH | ConsensusClusterPlus, survival (KM + Cox) |

---

## 3. Detailed Workflow Reference

### 3.1 Drug Discovery / Structural Biology

---

#### `structure_prediction_docking` — AlphaFold3 + DiffDock + AutoDock Vina

| Field | Value |
|---|---|
| **Domain** | `drug_discovery` |
| **Path** | `subworkflows/drug_discovery/structure_prediction_docking/` |
| **Style** | Sprint 1 (new; multi-process with parallel docking) |
| **Processes** | `ALPHAFOLD3_STRUCTURE_PREDICTION` → [`DIFFDOCK_BLIND_DOCKING` ∥ `AUTODOCK_VINA_DOCKING`] |
| **Key inputs** | `[meta, sequence.fasta]`, `ligand.sdf`; params: `af3_mode` (mock/server/local), `diffdock_poses=10`, `vina_exhaustiveness=32`, `vina_num_modes=9` |
| **Key outputs** | `*_structure.cif`, `*_structure.pdb`, `*_pae.json`, `*_af3_scores.json`, `diffdock_results/`, `*_vina_summary.json` |
| **Mock mode** | 100-residue synthetic alpha-helix PDB (full backbone); PAE matrix with pTM=0.85; 10 DiffDock poses with confidence scores; 9 Vina binding modes with affinity values |
| **Live mode** | AF3: alphafoldserver.com API (Bearer token) or local model (`/opt/alphafold3/models`). DiffDock: GPU-accelerated diffusion inference. Vina: pocket derived from AF3 PAE low-confidence regions |
| **Containers** | `docker.io/catgumag/alphafold3:latest`, `simonelenz/diffdock:latest`, `cford38/autodockvina:latest` |
| **QC gates** | `MOLPROBITY` / `MODEL_QUALITY` → MolProbity Ramachandran outliers >2% [BRONZE advisory]; EMRinger score <1.0 [BRONZE advisory]; `DOCKING` → top Vina affinity > −5 kcal/mol [BRONZE advisory] |
| **Profiles** | `standard` (mock), `docker`, `singularity`, `gpu`, `aws`, `slurm` |
| **Paper** | Paper 4 (Drug Discovery, Nature Chemical Biology) |

---

#### `drug_discovery` composite pipeline — SMILES → ADMET → Docking → FDA check

| Field | Value |
|---|---|
| **Domain** | `drug_discovery` (composite workflow) |
| **Path** | `workflows/drug_discovery/` |
| **Processes** | `CALCULATE_PHYSICOCHEMICAL_PROPERTIES` ∥ `PREDICT_ADMET_PROPERTIES` → `RUN_DIFFDOCK_WITH_SMILES` → `CHECK_DRUG_COMBINATION_SAFETY` → `CHECK_FDA_DRUG_RECALLS` → `GET_FDA_DRUG_LABEL_INFO` |
| **Key inputs** | `--smiles "CCO"`, `--target_protein "EGFR"`, `--drug_name "aspirin"`, `--combination_drugs []` |
| **Key outputs** | PhysChem JSON, ADMET predictions CSV, DiffDock poses, safety report, FDA recall status, drug label text |
| **QC gates** | ADMET gates: hERG IC50 < 1 µM [GOLD], DILI score "high" [GOLD], Ames prob ≥ 0.7 [SILVER], ClinTox prob ≥ 0.8 [SILVER]; SMILES validity [GOLD blocking]; compound MW, logP, HBD/HBA |
| **Notes** | Steps 1 and 2 execute in parallel. `--smiles` is required; all other params are optional |

---

### 3.2 Cryo-EM / CryoSPARC SPA

---

#### `cryosparc_standard_spa` — Full 23-step SPA pipeline

| Field | Value |
|---|---|
| **Domain** | `cryo_em` |
| **Path** | `subworkflows/cryo_em/cryosparc_standard_spa/` |
| **Style** | Full pipeline (import-to-sharpening) — all processes in a single main.nf |
| **Processes (in order)** | `IMPORT_MOVIES` → `PATCH_MOTION_CORRECTION` → `PATCH_CTF_ESTIMATION` → `MICROGRAPH_DENOISER` → `BLOB_PICKER` → `JUNK_2D_DETECTOR` → `INSPECT_PICKS` → `EXTRACT_PARTICLES_R1` → `CLASSIFY_2D_R1` → `SELECT_2D_R1` → `TEMPLATE_PICKER` → `INSPECT_PICKS_R2` → `EXTRACT_PARTICLES_R2` → `CLASSIFY_2D_R2` → `SELECT_2D_R2` → `AB_INITIO` → `HOMOGENEOUS_REFINEMENT` → `VOLUME_TOOLS` → `VALIDATION_FSC` → `LOCAL_CTF_REFINEMENT` → `NON_UNIFORM_REFINEMENT` → `LOCAL_RESOLUTION` → `SHARPEN` |
| **Key inputs** | `--movies_path *.{tif,mrc,eer}`, `--pixel_size 1.05`, `--voltage 300`, `--spherical_aberration 2.7`, `--total_dose 50.0`, `--symmetry C1`, `--sample_type membrane_protein\|virus\|ribosome\|small_protein` |
| **Key outputs** | `movies.cs`, `motion_corrected/*.mrc`, `ctf_params.cs`, `particles_r1.cs`, `class2d_r1/`, `particles_r2.cs`, `ab_initio_volume.mrc`, `refined_volume.mrc`, `fsc_curve.pdf`, `sharpened_map.mrc`, `local_resolution_map.mrc` |
| **Mock mode** | Synthetic `.cs` files with realistic metadata; motion stats (drift ~20Å); CTF params (defocus ~1.5µm, fit_quality~0.85); 500 particle picks; 5 2D class averages; FSC curve (0.143 resolution = 3.2Å); B-factor ~−80Å² |
| **Live mode** | CryoSPARC v5 API via `cryosparc-tools`; `--use_cryosparc true --cryosparc_license <id>` activates full API; sample-type-aware parameter recommendations via `get_sample_recommendations()` |
| **Containers** | Mock: Python stdlib only. Live: CryoSPARC v5 (license required); `--cryosparc_host localhost --cryosparc_port 39000` |
| **Phase plate** | `--phase_plate true` → emits `avg_phase_shift_rad` in `ctf_report.json`; activates VPP advisory gates (depleted < 0.2 rad, over-charged > 1.5 rad) |
| **QC gates** | `PATCH_MOTION_CORRECTION`: total drift > 50Å [SILVER blocking], > 30Å [advisory warning]; `PATCH_CTF_ESTIMATION`: fit_quality < 0.7 [GOLD blocking], astigmatism > 1000Å [BRONZE advisory], ice thickness > 50% thick [advisory], VPP phase shift depletion/over-charge [advisory]; `BLOB_PICKER`/`TEMPLATE_PICKER`: particle count < 1000 [blocking]; `CLASSIFY_2D_R1/R2`: junk fraction > 70% [blocking], 50-70% [advisory]; `HOMOGENEOUS_REFINEMENT`/`NON_UNIFORM_REFINEMENT`: orientation anisotropy ratio > 10× [blocking], 5-10× [advisory]; `LOCAL_RESOLUTION`: std spread σ > 3.0Å [advisory]; `SHARPEN`: B-factor > 0Å² or < −300Å² [advisory] |
| **Profiles** | `standard` (mock), `docker`, `local_gpu`, `multi_gpu`, `slurm`, `singularity`, `opensource` (RELION/CTFFIND/Topaz/Phenix), `aws`, `test` |
| **Paper** | Paper B (Cryo-EM SPA Benchmark, Nature Methods / Nature Communications) |

**Sample-type parameter presets:**

| Sample type | 2D classes | Ab-initio iters | Refinement mask |
|---|---|---|---|
| `membrane_protein` | 100 | 100 | 0.50 |
| `virus` | 50 | 50 | 0.40 |
| `ribosome` | 200 | 150 | 0.35 |
| `small_protein` | 100 | 100 | 0.45 |
| `unknown` (default) | 100 | 100 | 0.40 |

---

### 3.3 Pharmacology / PK-PD

---

#### `nlmixr2_population_pk` — Population PK with SAEM/FOCE+

| Field | Value |
|---|---|
| **Domain** | `pharmacology` |
| **Path** | `subworkflows/pharmacology/nlmixr2_population_pk/` |
| **Process** | `NLMIXR2_POPULATION_PK` |
| **Key inputs** | `--pk_data_csv data/pk_data.csv` (required columns: ID, TIME, DV, AMT, EVID; optional: WT, AGE, SEX, CRCL, ALB); `--model_type 1cmt_oral\|2cmt_oral\|1cmt_iv\|2cmt_iv`; `--algorithm saem\|focei\|rxSolve`; `--covariates WT,AGE` |
| **Key outputs** | `popPK_report.html`, `parameter_estimates.csv` (THETA/OMEGA/SIGMA), `individual_estimates.csv` (EBEs/η), `vpc_plot.pdf`, `goodness_of_fit.pdf`, `nlmixr2_results.json` |
| **Mock mode** | Simulated 1cmt oral PK for 30 subjects × 8 timepoints; realistic SAEM convergence; CL=5 L/h, V=30 L, ka=1.2 h⁻¹; η shrinkage ~15%; condition number ~50 |
| **Container** | `nlmixr2/nlmixr2:latest` (R; rxode2, xpose, xpose.nlmixr2, ggplot2, jsonlite, data.table) |
| **QC gates** | `NLMIXR2_POPULATION_PK` / `POP_PK`: convergence [GOLD blocking — SAEM OFV must stabilise ±0.1%]; ETA shrinkage < 30% [SILVER advisory]; condition number < 1000 [BRONZE advisory] |
| **Profiles** | `docker`, `standard` |
| **Paper** | Paper 4 (Drug Discovery, PK/PD phase) |

---

#### `nca_pknca` — Non-Compartmental Analysis

| Field | Value |
|---|---|
| **Domain** | `pharmacology` |
| **Path** | `subworkflows/pharmacology/nca_pknca/` |
| **Process** | `NCA_PKNCA` |
| **Key inputs** | `--pk_data_csv data/phase1_pk.csv` (columns: subject_id, time, concentration, dose, route); `--route oral\|iv`; `--lambda_z_adj auto`; `--sparse false` |
| **Key outputs** | `nca_results.csv` (all subjects × parameters), `nca_summary.csv` (mean±SD/CV%), `nca_report.html`, `pk_profiles.pdf`, `nca_results.json` |
| **NCA parameters computed** | AUClast, AUCinf, Cmax, Tmax, t½, lambda_z, CL/F, Vz/F, AUC%extrap, MRT |
| **Container** | `rocker/tidyverse:latest` (R; PKNCA, ggplot2) |
| **QC gates** | `NCA_PKNCA`: AUC%extrap > 20% [advisory]; subjects with no estimable terminal slope [advisory count] |
| **Reference** | Bacon et al. 2016 CPT:PSP 5(1):e65 — PKNCA; regulatory-grade NCA matching Phoenix WinNonlin / SAS PROC NCA |
| **Paper** | Paper 4 (Drug Discovery, Phase I NCA) |

---

### 3.4 Genomics — Connectors & CRISPR

---

#### `geo_data_connector` — GEO / TCGA data ingestion

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/geo_data_connector/` |
| **Processes** | `GEO_FETCH` → `GEO_COUNT_MATRIX` → `GEO_CLINICAL_METADATA` |
| **Key inputs** | `--accession GSE123456` (GSE series or GSM sample); `--local_series_matrix <path>` (optional, skips download) |
| **Key outputs** | `series_matrix.rds` (ExpressionSet-like), `sample_metadata.csv` (pData with standardised clinical columns), `count_matrix.csv` (genes × samples) |
| **Mock mode** | 200 genes × 20 samples; landmark genes (GAPDH, TP53, BRCA1, EGFR, MYC…) + GENE0001–GENE0180; NB-like counts with treatment effect; GSM-style sample IDs; complete pData with condition, age, tissue |
| **Container** | `quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0` |
| **QC gates** | None currently (data connector; downstream DE workflow gates apply) |
| **Notes** | Sprint 2 RNA-seq gap closure. Emits channels directly usable by `bioconductor_rnaseq_de` composite workflow |
| **Reference** | Davis S & Meltzer PS (2007) Bioinformatics 23(14):1846-1847 — GEOquery |

---

#### `perturb_seq_analysis` — Genome-wide CRISPR screen + scANVI embedding

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/perturb_seq_analysis/` |
| **Processes** | `MAGECK_COUNT` → `MAGECK_MLE` → `SCVI_SCÁNVI_EMBEDDING` |
| **Key inputs** | `--fastq *.fastq.gz`, `--library_csv guide_library.csv` (columns: sgRNA, gene, sequence), `--design_matrix design.txt`, `--anndata_h5ad screen.h5ad`; `--batch_key batch`, `--guide_key guide` |
| **Key outputs** | `*.count.txt`, `*.count_normalized.txt`, `mageck_count_summary.json`, `mle_results.txt`, `mle_gene_summary.txt`, `scvi_embedding.h5ad`, `scvi_latent.csv` |
| **Mock mode** | 500 guides × 100 genes × 5,000 cells; realistic count distribution (Gaussian µ=100); MAGeCK MLE beta scores; scVI 10-dim latent embedding |
| **Containers** | `quay.io/biocontainers/mageck:0.5.9.5--py39h7cff6ad_2`; `biomate/biomni-tools:latest` (scVI/scANVI) |
| **QC gates** | `MAGECK_COUNT` / `PERTURB_SEQ`: guide library coverage [SILVER]; mapped reads per guide [SILVER]; Gini index of count distribution [BRONZE advisory]; `scrna_perturbation` profile adds guide_library_coverage_pct ≥ 70%, transfection_efficiency_pct ≥ 30%, max_doublet_fraction_pct ≤ 10% |
| **Reference** | Replogle JM et al. 2022 Cell 185(14):2559-2575 |
| **Paper** | Paper 1 (QC governance, CRISPR screen domain) |

---

### 3.5 RNA-seq / Transcriptomics — Bioconductor Tier

---

#### `bioconductor/survival` — Kaplan-Meier + Cox PH survival analysis

| Field | Value |
|---|---|
| **Domain** | `bioconductor` |
| **Path** | `subworkflows/bioconductor/survival/` |
| **Processes** | `CRAN_SURVIVAL_KAPLANMEIER` and/or `CRAN_SURVIVAL_COX` (called independently) |
| **Key inputs (KM)** | `[meta, clinical_csv]`, `time_col`, `event_col`, `group_col` |
| **Key inputs (Cox)** | `[meta, clinical_csv]`, `time_col`, `event_col`, `covariates` (comma-separated) |
| **Key outputs (KM)** | `*_km_fit.rds`, `*_km_summary.csv`, `*_logrank_pvalue.txt` |
| **Key outputs (Cox)** | `*_cox_fit.rds`, `*_cox_table.csv` (HR, 95% CI, p-value per covariate), `*_cox_plot.pdf` |
| **Container** | `quay.io/biocontainers/r-survival:3.5_8--r44_0` |
| **Conda** | `r-survival r-broom` |
| **QC gates** | None (statistical output; p-value interpretation is user's responsibility) |
| **Used by** | `rnaseq_patient_stratification` composite workflow (step 2 + step 3) |
| **Reference** | Therneau TM (2024). A Package for Survival Analysis in R |

---

#### `bioconductor/consensusclusterplus` — Unsupervised molecular subtype discovery

| Field | Value |
|---|---|
| **Domain** | `bioconductor` |
| **Path** | `subworkflows/bioconductor/consensusclusterplus/` |
| **Process** | `BIOC_CONSENSUSCLUSTERPLUS` |
| **Key inputs** | `[meta, expr_matrix_rds]` (numeric matrix genes × samples), `max_k=8`, `n_reps=500` |
| **Key outputs** | `*_cluster_assignments.csv`, `*_icl_scores.csv`, `*_consensus_plots.pdf`, `*_optimal_k.txt` |
| **Pre-processing** | Median-centering of rows (genes) prior to clustering — standard for expression data |
| **Container** | `quay.io/biocontainers/bioconductor-consensusclusterplus:1.70.0--r44_0` |
| **Conda** | `bioconductor-consensusclusterplus` |
| **QC gates** | None |
| **Used by** | `rnaseq_patient_stratification` composite workflow (step 1) |
| **Reference** | Monti S et al. (2003) J Classification 20:107-136 |

---

#### `bioconductor/immune_deconvolution` — Bulk RNA-seq immune cell fraction estimation

| Field | Value |
|---|---|
| **Domain** | `bioconductor` |
| **Path** | `subworkflows/bioconductor/immune_deconvolution/` |
| **Processes** | `BIOC_DECONRNASEQ` → `IMMUNEDECONV_SUMMARY` |
| **Key inputs** | `[meta, counts_matrix, signature_matrix]`; optional `clinical_metadata` for correlation; `--method DeconRNASeq\|EPIC\|BayesDeBulk`; `--scale_counts true` |
| **Key outputs** | `*_cell_fractions.csv` (8 immune cell types), `*_deconvolution_plot.pdf`, `*_deconvolution.rds`, `*_immune_scores.csv`, `*_correlation_heatmap.pdf` |
| **Cell types** | CD8_T_cell, CD4_T_cell, NK_cell, B_cell, Monocyte, Dendritic_cell, Neutrophil, Mast_cell |
| **Mock mode** | 200 genes × 20 samples with Dirichlet-sampled fractions summing to 1.0 |
| **Container** | `quay.io/biocontainers/bioconductor-deconrnaseq:1.46.0--r44_0` |
| **QC gates** | None (exploratory analysis) |

---

#### `rnaseq_patient_stratification` — Full patient stratification pipeline

| Field | Value |
|---|---|
| **Domain** | `workflows/` (composite) |
| **Path** | `workflows/rnaseq_patient_stratification/` |
| **Processes** | `BIOC_CONSENSUSCLUSTERPLUS_WORKFLOW` → `CRAN_SURVIVAL_KAPLANMEIER` → `CRAN_SURVIVAL_COX` |
| **Key inputs** | `--expr_matrix expr.rds`, `--clinical clinical.csv`, `--time_col OS_days`, `--event_col OS_event`, `--covariates "age,stage"`, `--max_k 8`, `--n_reps 500` |
| **Key outputs** | Cluster assignments CSV, KM curve PDF, log-rank p-value, Cox HR table, Cox forest plot |
| **QC gates** | None (downstream of DE pipeline; p-values are output, not gates) |
| **Notes** | Sprint 2 RNA-seq composite. Designed to follow `bioconductor_rnaseq_de` output or accept any expression RDS |
| **Reference** | Monti 2003 (CCP); Therneau 2024 (survival) |

---

### 3.6 Single-Cell & Trajectory

---

#### `trajectory_inference` — Monocle3 pseudotime ∥ scVelo RNA velocity

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/trajectory_inference/` |
| **Processes** | `MONOCLE3_TRAJECTORY` ∥ `SCVELO_DYNAMICS` (parallel execution) |
| **Key inputs** | `--adata_h5ad input.h5ad` (AnnData with spliced/unspliced layers + UMAP); `--root_cell <barcode>`; `--monocle_cluster leiden`; `--velocity_mode dynamical\|stochastic\|deterministic` |
| **Key outputs (Monocle3)** | `*_trajectory_pseudotime.csv`, `*_trajectory_plot.png`, `*_monocle3_cds.rds` |
| **Key outputs (scVelo)** | `*_velocity_embedding.h5ad`, `*_velocity_plot.png`, `*_velocity_confidence.csv` |
| **Mock mode** | 200 cells, linear trajectory (pseudotime 0-100); scVelo velocity vectors with >0.5 confidence |
| **Containers** | Monocle3: `quay.io/biocontainers/bioconductor-monocle3:1.3.4--r44_0`; scVelo: `biomate/biomni-tools:latest` (Python/GPU) |
| **QC gates** | `MONOCLE3_TRAJECTORY` / `SCVELO_DYNAMICS`: no dedicated gate currently; scVelo velocity confidence < 0.3 → advisory warning |
| **Notes** | Sprint 3. Both branches run concurrently via DSL2 fork. GPU recommended for scVelo dynamical mode (`-profile gpu`) |

---

#### `create_scvi_embeddings_scRNA` — scVI batch-corrected latent embedding

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/create_scvi_embeddings_scRNA/` |
| **Process** | `CREATE_SCVI_EMBEDDINGS_SCRNA` |
| **Key inputs** | `--adata_filename pbmc3k_tiny.h5ad`; `--batch_key batch`; `--label_key cell_type`; `--data_dir /path/to/data` |
| **Key outputs** | `create_scvi_embeddings_scRNA_results.json`, `create_scvi_embeddings_scRNA_output.txt` |
| **Implementation** | Galaxy wrapper → self-contained Python; uses scvi-tools (scVI/scANVI); reads h5ad, trains VAE, outputs latent space |
| **Container** | `biomate/biomni-tools:latest` (scVI, scanpy, torch, numba) |
| **QC gates** | None |
| **Notes** | Pre-existing; generated from tested Galaxy wrapper. Default data: PBMC 3k from Galaxy test data |

---

### 3.7 Pre-existing Core Genomics (samples)

---

#### `gene_set_enrichment_analysis` — GSEA via gget

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/gene_set_enrichment_analysis/` |
| **Process** | `GENE_SET_ENRICHMENT_ANALYSIS` |
| **Key inputs** | `--genes '["CCNA2","CDK1","TP53","RB1"]'` (JSON list); `--database ontology\|pathway\|transcription`; `--top_k 10`; `--background_list null`; `--plot false` |
| **Key outputs** | `gene_set_enrichment_analysis_results.json`, `gene_set_enrichment_analysis_output.txt` |
| **Implementation** | Uses `gget` Python library for Enrichr-based enrichment; no custom containers required |
| **Container** | `biomate/biomni-tools:latest` |
| **QC gates** | None |
| **Notes** | Pre-existing Galaxy wrapper. Default genes: cell cycle panel (CCNA2, CCNB1, CDK1, CDK2, TP53, RB1, E2F1, PCNA, MCM2, CDC6) |

---

#### `analyze_chromatin_interactions` — Hi-C TAD and enhancer-promoter interaction analysis

| Field | Value |
|---|---|
| **Domain** | `genomics` |
| **Path** | `subworkflows/genomics/analyze_chromatin_interactions/` |
| **Process** | `ANALYZE_CHROMATIN_INTERACTIONS` |
| **Key inputs** | `--hic_file_path data.hic`; `--regulatory_elements_bed enhancers.bed`; `--demo_mode true` |
| **Key outputs** | `analyze_chromatin_interactions_results.json`, `analyze_chromatin_interactions_output.txt` |
| **Implementation** | Python/numpy; HiC contact matrix parsing; TAD detection; regulatory element overlap; demo mode for development without data |
| **Container** | `biomate/biomni-tools:latest` |
| **QC gates** | `MARKDUPLICATES` gate (Hi-C domain): Hi-C false-positive suppressed — `hic`, `hic_seq`, `hi_c` domains are excluded from the PCR duplicate gate (PCR deduplication is inappropriate for Hi-C proximity ligation data) |
| **Notes** | Pre-existing Galaxy wrapper. Hi-C QC note: paper P0 fix suppresses false Hi-C duplicate gate |

---

## 4. QC Gate Integration

The `NextflowQCGateHandler` in `backend/lib/galaxy/jobs/qc_trace_monitor.py` monitors
Nextflow trace files, detects completed processes by name pattern, parses output files,
and emits Server-Sent Events (`qc_gate` or `qc_warning`) when thresholds are crossed.

### 4.1 Process → QC gate mapping

| Process pattern | Domain | Parser method | Gate | Level | Threshold |
|---|---|---|---|---|---|
| `MOTION_CORRECTION` | cryo_em | `_parse_motion_correction_metrics` | total_drift_angstrom | SILVER | > 50Å blocking; > 30Å advisory |
| `CTF_ESTIMATION`, `CTF_ESTIMATE` | cryo_em | `_parse_ctf_metrics` | fit_quality | GOLD | < 0.7 blocking |
| `CTF_ESTIMATION` | cryo_em | `_parse_ctf_metrics` | astigmatism | BRONZE | > 1000Å advisory |
| `CTF_ESTIMATION` | cryo_em | `_parse_ctf_metrics` | ice_thickness_pct | BRONZE | > 50% thick advisory |
| `CTF_ESTIMATION` + VPP | cryo_em | `_parse_ctf_metrics` | avg_phase_shift_rad | BRONZE | < 0.2 rad (depleted) or > 1.5 rad (over-charged) advisory |
| `PARTICLE_PICKING`, `PICKING` | cryo_em | `_parse_picking_metrics` | particle_count | SILVER | < 1000 blocking |
| `CLASSIFY_2D`, `CLASS_2D`, `2D_CLASSIFICATION` | cryo_em | `_parse_2d_classification_metrics` | junk_fraction | SILVER | > 70% blocking; 50-70% advisory |
| `HOMOGENEOUS_REFINEMENT`, `NONUNIFORM_REFINEMENT`, `AB_INITIO` | cryo_em | `_parse_refinement_metrics` | orientation_anisotropy_ratio | SILVER | > 10× blocking; 5-10× advisory |
| `SHARPEN`, `POSTPROCESS` | cryo_em | `_parse_sharpening_metrics` | b_factor_angstrom | BRONZE | > 0Å² or < −300Å² advisory |
| `MOLPROBITY`, `MODEL_QUALITY`, `ALPHAFOLD_FIT` | structural | `_parse_model_quality_metrics` | ramachandran_outlier_pct | BRONZE | > 2% advisory |
| `MOLPROBITY`, `EMRINGER` | structural | `_parse_model_quality_metrics` | emringer_score | BRONZE | < 1.0 advisory |
| `LOCAL_RESOLUTION`, `MONORES` | cryo_em | `_parse_local_resolution_metrics` | local_res_std_angstrom | BRONZE | σ > 3.0Å advisory |
| `FASTQC`, `MULTIQC` | rnaseq | `_parse_fastqc_metrics` | q30_pct | SILVER | < 75% |
| `FASTP`, `TRIMGALORE`, `TRIMMOMATIC` | rnaseq | `_parse_trimming_metrics` | reads_surviving_pct | SILVER | < 70% (red-line: 50%) |
| `STAR_ALIGN`, `HISAT2_ALIGN`, `BOWTIE2_ALIGN` | rnaseq | `_parse_alignment_metrics` | alignment_rate | SILVER | < 70% (red-line: 5%) |
| `FEATURECOUNTS`, `HTSEQ` | rnaseq | `_parse_featurecounts_metrics` | assigned_reads_pct | SILVER | < 50% |
| `SALMON_QUANT`, `KALLISTO` | rnaseq | `_parse_salmon_metrics` | mapping_rate | SILVER | < 60% |
| `FLAGSTAT`, `SAMTOOLS_FLAGSTAT` | dna_seq | `_parse_flagstat_metrics` | mapped_pct | GOLD | < 70% |
| `MARKDUPLICATES`, `PICARD_MARKDUP` | dna_seq | `_parse_picard_dup_metrics` | duplicate_pct | SILVER | > 40% (domain-aware: skips rna_seq, atac, chip, hi-c, scrna) |
| `MOSDEPTH`, `SAMTOOLS_COVERAGE`, `PICARD_WGS` | dna_seq | `_parse_coverage_metrics` | mean_coverage | GOLD | < 30× WGS; < 80× WES |
| `MAGECK_COUNT`, `GUIDE_ASSIGN`, `PERTURB_SEQ` | crispr | `_parse_guide_library_metrics` | guide_library_coverage_pct | SILVER | < 70% |
| `CELLRANGER_COUNT`, `STARSOLO`, `ALEVIN` | scrna | `_parse_singlecell_metrics` | mito_fraction_pct | BRONZE | > 20% blocking; 10-20% advisory |
| `CELLRANGER` | scrna | `_parse_singlecell_metrics` | sequencing_saturation_pct | BRONZE | < 30% advisory |
| `MACS2`, `MACS3`, `CALLPEAK` | chip_atac | `_parse_peakcalling_metrics` | peak_count | SILVER | < 1000 blocking |
| `ATAC_QC`, `TSS_ENRICH` | atac | `_parse_atac_metrics` | tss_enrichment | GOLD | < 5.0 blocking (< 7.0 advisory) |
| `ATAC_QC`, `TSS_ENRICH` | atac | `_parse_atac_metrics` | nrf_score | GOLD | < 0.9 |
| `ATAC_QC`, `TSS_ENRICH` | atac | `_parse_atac_metrics` | frip_score | GOLD | < 0.2 (ENCODE4 floor) |
| `KRAKEN2`, `BRACKEN`, `METAPHLAN` | metagenomics | `_parse_metagenomics_metrics` | classified_pct | SILVER | < 30% critical; < 60% warning |
| `MAXQUANT`, `MAXQUANT_ANDROMEDA` | proteomics | `_parse_maxquant_metrics` | protein_fdr | GOLD | > 1% |
| `MAXQUANT` | proteomics | `_parse_maxquant_metrics` | missed_cleavage_pct | SILVER | > 20% |
| `MAXQUANT` | proteomics | `_parse_maxquant_metrics` | cv_pct | SILVER | > 20% |
| `DIANN`, `SPECTRONAUT` | proteomics | `_parse_diann_metrics` | protein_fdr | GOLD | > 1% |
| `CHEMOPROTEOMICS_PULLDOWN`, `PULLDOWN` | proteomics | `_parse_pulldown_metrics` | enrichment_ratio | SILVER | < 3× blocking |
| `SMILES_QC`, `COMPOUND_QC`, `ADMET_PRECHECK` | cheminformatics | `_parse_smiles_metrics` | invalid_smiles_pct | GOLD | > 0% blocking (any invalid SMILES) |
| `SMILES_QC` | cheminformatics | `_parse_smiles_metrics` | salt_fraction_pct | SILVER | > 20% advisory |
| `ADMET_TOXICITY`, `HERG_SCREEN`, `ADMET_PRED` | drug_discovery | `_parse_admet_toxicity_metrics` | herg_ic50_um | GOLD | < 1 µM blocking |
| `ADMET_TOXICITY` | drug_discovery | `_parse_admet_toxicity_metrics` | dili_score | GOLD | "high" blocking |
| `ADMET_TOXICITY` | drug_discovery | `_parse_admet_toxicity_metrics` | ames_probability | SILVER | ≥ 0.7 advisory |
| `ADMET_TOXICITY` | drug_discovery | `_parse_admet_toxicity_metrics` | clintox_probability | SILVER | ≥ 0.8 advisory |
| `PGX_COVERAGE`, `CYP_COVERAGE` | pharmacogenomics | `_parse_pgx_coverage_metrics` | pgx_min_coverage | GOLD | < 30× per CYP gene (pgx_clinical) |
| `NCA_PKNCA`, `PKNCA` | pharmacology | `_parse_nca_results` | auc_extrap_pct_max | advisory | > 20% extrapolated |
| `NLMIXR2`, `POPULATION_PK` | pharmacology | `_parse_nlmixr2_results` | convergence | GOLD | must converge (OFV ±0.1%) |
| `NLMIXR2` | pharmacology | `_parse_nlmixr2_results` | eta_shrinkage_pct | SILVER | > 30% advisory |
| `NLMIXR2` | pharmacology | `_parse_nlmixr2_results` | condition_number | BRONZE | > 1000 advisory |
| `MOLECULAR_DOCKING`, `AUTODOCK`, `VINA` | drug_discovery | `_parse_docking_results` | top_affinity_kcal_mol | BRONZE | > −5 kcal/mol advisory |
| `QSAR_RF_MODEL`, `QSAR` | cheminformatics | `_parse_qsar_results` | cross_val_r2 | SILVER | < 0.5 advisory |

### 4.2 QC event types and SSE payloads

Two SSE event types are emitted:

| Event | Trigger | Payload key |
|---|---|---|
| `qc_gate` | One or more **blocking** failures | `"failures": [...]` containing all blocking + advisory items |
| `qc_warning` | Only advisory items (all gates passed) | `"warnings": [...]` for near-threshold warnings |

**Advisory items** (non-blocking) are always included in the `failures` list with `"advisory": true`.
When all blocking gates pass, advisory items are re-emitted as warnings in a `qc_warning` event.

### 4.3 Red-line bounds (cannot be overridden)

| Metric | Bound | Direction | Rationale |
|---|---|---|---|
| `reads_surviving_pct` | 50.0% | min | > 50% loss → adapter-dominated library; invalid |
| `fit_quality` | 0.5 | min | Complete CTF failure; picking results invalid |
| `mito_fraction_pct` | 80.0% | max | Dead-cell lysates, not transcriptomes |
| `alignment_rate` | 5.0% | min | < 5% → species/sample swap; halt unconditionally |

---

## 5. Named QC Profiles

Named profiles provide curated threshold overrides for well-characterised assay contexts.
Select with `--qc_profile <name>` at workflow launch or via the Compute Settings UI.

**Priority order (highest to lowest):**
1. Per-invocation `qc_overrides` (explicit, per-run)
2. Named profile `overrides` (set at launch)
3. Platform defaults

GOLD metrics (`mapped_pct`, `tss_enrichment`, `nrf_score`) cannot be relaxed by any profile.

API: `GET /api/qc/profiles` returns all profiles with descriptions and references.

### 5.1 RNA-seq profiles (5)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `rnaseq_polya_standard` | rnaseq | Standard polyA-selected RNA-seq — no adjustments | (none) |
| `rnaseq_ribodepleted` | rnaseq | Total RNA / RiboZero: 10-20 pp lower alignment expected | alignment_rate ≥ 50%, reads_surviving ≥ 65%, assigned_reads ≥ 40% |
| `rnaseq_ffpe` | rnaseq | FFPE-preserved tissue: highly fragmented, low Q30 | alignment_rate ≥ 45%, reads_surviving ≥ 60%, q30 ≥ 65% |
| `rnaseq_single_nucleus` | rnaseq | snRNA-seq: intronic reads dominate; PCR dup gate suppressed | alignment_rate ≥ 50% |
| `rnaseq_nonmodel_organism` | rnaseq | Draft genome / incomplete annotation; expect low mapping | alignment_rate ≥ 40%, assigned_reads ≥ 30% |

**References:** Zhao et al. 2020 RNA Biol; Sinicropi et al. 2012 PLoS ONE; 10x Genomics snRNA-seq Guide v2.0

### 5.2 DNA-seq / WGS / WES profiles (6)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `wgs_germline_standard` | wgs | Germline WGS default (GATK Best Practices, 30×) | (none) |
| `wgs_germline_lowpass` | wgs | Low-pass WGS (0.5-10×) for imputation/polygenic scores | mean_coverage ≥ 4×, duplicate_pct ≤ 60% |
| `wgs_somatic_tumor_only` | wgs | Tumor-only WGS (Mutect2 recommendation, 80×) | mean_coverage ≥ 80×, duplicate_pct ≤ 50% |
| `wgs_ffpe` | wgs | FFPE-derived WGS; PCR bias elevates duplicate rate | mean_coverage ≥ 30×, duplicate_pct ≤ 65% |
| `wes_research` | wes | Research WES — 50× sufficient for germline discovery | mean_coverage ≥ 50× |
| `wes_clinical_germline` | wes | Clinical WES — ACMG 2016 standard (80×) | mean_coverage ≥ 80× |

**References:** GATK Best Practices 2023; Rubinacci et al. 2021 Nat Genet; Robbe et al. 2018 Nat Med; ACMG/AMP 2016 NGS Standards

### 5.3 Single-cell RNA-seq profiles (4)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `scrna_standard` | scrna_seq | 10x Genomics Chromium default | (none) |
| `scrna_cardiac` | scrna_seq | Cardiomyocytes: mito 30-40% is biologically expected | mito_fraction_pct ≤ 40%, warning ≤ 25% |
| `scrna_neuronal` | scrna_seq | Brain tissue: elevated mito; narrower transcriptomes | mito_fraction_pct ≤ 30%, median_genes_per_cell ≥ 300 |
| `scrna_perturbation` | scrna_seq | Perturb-seq / CROP-seq: guide coverage + doublet gates | guide_library_coverage ≥ 70%, transfection ≥ 30%, doublets ≤ 10% |

**References:** 10x Genomics Cell Ranger v7; Simonson et al. 2023 Circ Res; Bakken et al. 2021 Nature; Replogle et al. 2022 Cell; Datlinger et al. 2021 Nat Methods

### 5.4 Metagenomics profiles (4)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `metagenomics_human_gut` | metagenomics | Well-characterised gut microbiome (Kraken2 Standard) | classified_pct_critical ≥ 50%, warning ≥ 60% |
| `metagenomics_soil` | metagenomics | High microbial dark matter fraction (5-40% normal) | classified_pct_critical ≥ 3%, warning ≥ 8% |
| `metagenomics_marine` | metagenomics | Open-ocean: poor DB coverage (10-50% normal) | classified_pct_critical ≥ 4%, warning ≥ 10% |
| `metagenomics_clinical_pathogen` | metagenomics | Clinical pathogen detection (bloodstream / CSF) | classified_pct_critical ≥ 60%, warning ≥ 70% |

**References:** HMP Consortium 2012 Nature; Bahram et al. 2018 Nature; Sunagawa et al. 2015 Science; IDSA 2024

### 5.5 Cryo-EM profiles (4)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `cryoem_spa_purified` | cryo_em | Standard SPA of purified complexes — default | (none) |
| `cryoem_spa_membrane` | cryo_em | Membrane proteins in micelles/nanodiscs: higher drift | total_drift_angstrom ≤ 80Å, fit_quality ≥ 0.65 |
| `cryoem_spa_phase_plate` | cryo_em | Volta Phase Plate: relaxed CTF fit + VPP phase gates | fit_quality ≥ 0.65, avg_phase_shift_rad advisory gates |
| `cryoem_tomo_in_situ` | cryo_em | FIB-SEM lamellae cryo-ET: extreme drift expected | total_drift_angstrom ≤ 150Å, fit_quality ≥ 0.5 (red-line), correlation_score ≥ 0.3 |

**References:** EMPIAR/EMDB standards; Danev & Bharat 2018 Trends Cell Biol; CryoSPARC VPP tutorial 2023; Bharat & Bharat 2024

### 5.6 Proteomics profiles (4)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `proteomics_standard` | proteomics | Standard label-free DDA bottom-up LC-MS/MS | (none; GOLD PSM/protein FDR < 1%, SILVER CV < 20%, missed cleavage < 20%) |
| `proteomics_phospho` | proteomics | Phosphopeptide enrichment (TiO2/IMAC): fewer PSMs expected | psm_count ≥ 500, missed_cleavage ≤ 30%, cv_pct ≤ 25% |
| `proteomics_plasma_biomarker` | proteomics | Depleted plasma DIA/DDA for biomarker discovery | cv_pct ≤ 15%, missing_value_pct ≤ 30% |
| `proteomics_chemoproteomics` | proteomics | Affinity proteomics / ABPP pulldown | psm_count ≥ 200 (pulldown reduces coverage) |

**References:** Elias & Gygi 2007 Nat Methods; EuBIC 2018; Beausoleil et al. 2006 Nat Biotechnol; Geyer et al. 2017 Cell Systems

### 5.7 Compound / Cheminformatics profiles (3)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `compound_druglike` | cheminformatics | Lipinski Ro5 oral small-molecule drug discovery | MW ≤ 500 Da, logP ≤ 5, HBD ≤ 5, HBA ≤ 10 |
| `compound_natural_product` | cheminformatics | Macrolides / terpenes / glycosylated scaffolds | MW ≤ 1000 Da, logP unlimited |
| `compound_peptidomimetic` | cheminformatics | Stapled peptides / peptidomimetics | MW ≤ 900 Da, HBD ≤ 10, HBA ≤ 15 |

**References:** Lipinski et al. 2001 Adv Drug Deliv Rev; Veber et al. 2002 J Med Chem; Newman & Cragg 2020 J Nat Prod; Giordanetto & Kihlberg 2014 J Med Chem

### 5.8 Pharmacogenomics profiles (2)

| Profile name | Domain | Description | Key overrides |
|---|---|---|---|
| `pgx_clinical` | pharmacogenomics | CPIC-compliant WGS QC: ≥ 30× per CYP gene | pgx_min_coverage ≥ 30× (CPIC tier 1 genes: CYP2D6, CYP2C19, CYP3A4, DPYD, TPMT…) |
| `pgx_research` | pharmacogenomics | Research-grade PGx: ≥ 15× accepted with advisory flags | pgx_min_coverage ≥ 15× (provisional calls at 15-29×) |

**References:** CPIC guidelines (cpicpgx.org); GATK Best Practices VQSR; PharmVar CYP2D6

**Total named profiles: 25** (5 RNA-seq + 6 WGS/WES + 4 scRNA + 4 metagenomics + 4 cryo-EM + 4 proteomics + 3 compound + 2 PGx)

---

## 6. Execution Profiles

All workflows support these Nextflow profiles via `-profile <name>`:

| Profile | Executor | Container engine | Typical use case | Notes |
|---|---|---|---|---|
| `standard` | local | none | Development and testing; `mock_mode=true` | Default; no external tools required |
| `test` | local | none | CI/CD; minimal synthetic data | Smallest input sizes; fast completion |
| `docker` | local | Docker | Local laptop/workstation (any OS) | Pulls containers automatically |
| `singularity` | local | Singularity | HPC without Docker daemon | Uses Singularity pull; no root needed |
| `gpu` | local | Docker/Singularity | AlphaFold3, DiffDock, scVelo, cryo-EM GPU tools | Requires CUDA driver + NVIDIA GPU; `process_gpu_high` label |
| `aws` | awsbatch | Docker (ECR) | Production cloud execution | `biomate-gpu-queue` (g4dn.2xlarge) + `biomate-cpu-queue` (m5.4xlarge); S3 scratch in `s3://biomate-nextflow-work` |
| `slurm` | SLURM | Singularity | University / national HPC cluster | GPU partition for CUDA processes; CPU partition for others |
| `opensource` | local | Docker | Cryo-EM SPA with open-source tools | Maps processes: RELION (motion/CTF/pick/classify/refine), CTFFIND4, Topaz, Phenix; no CryoSPARC license needed |

### Per-executor configuration (via BioMate Compute Settings UI)

The Nextflow Compute Settings UI (Settings → Compute tab) exposes per-executor fields:

| Executor | Required fields | Optional fields |
|---|---|---|
| `local` | — | `local_output_dir` |
| `slurm` | SLURM host reachable via PATH | Partition names, `--account`, `--qos` |
| `awsbatch` | `s3_bucket` (scratch), `aws_region` | `batch_queue`, IAM role ARN |

Configuration is stored in `userSettingsSchema.nextflowComputeConfig` and forwarded
per-invocation via `compute_config` in the execute API call.

---

## 7. Adding a New Workflow

### 7.1 File structure

Every subworkflow follows this layout:

```
backend/biomni_workflows/nextflow_nfcore/subworkflows/<domain>/<workflow_name>/
├── main.nf              # Required — DSL2 workflow definition
└── nextflow.config      # Optional — profile and label definitions
```

If the workflow is a composite of multiple subworkflows, place it under:
```
backend/biomni_workflows/nextflow_nfcore/workflows/<pipeline_name>/
└── main.nf              # Imports subworkflows via `include { ... } from ...`
```

### 7.2 DSL2 main.nf template

```nextflow
#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.outdir    = './results/<workflow_name>'
params.mock_mode = true
// ... other params ...

process MY_PROCESS {
    tag "${meta.id}"
    label 'process_medium'   // process_low | process_medium | process_high | process_gpu_high
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container 'quay.io/biocontainers/<tool>:<version>'

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_results.json"), emit: results
    path "versions.yml",                               emit: versions

    script:
    if (params.mock_mode) {
        """
        # Generate realistic mock output matching live format
        python3 - << 'PYEOF'
import json
# ... mock generation code ...
json.dump({"metric_a": 0.95, "metric_b": 42}, open("${meta.id}_results.json","w"))
PYEOF
        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            toolname: \$(toolname --version 2>&1 | head -1)
        END_VERSIONS
        """
    } else {
        """
        # Live tool invocation
        toolname --input ${input_file} --output ${meta.id}_results.json
        """
    }
}

workflow MY_WORKFLOW_NAME {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    MY_PROCESS(ch_input)

    emit:
    results  = MY_PROCESS.out.results
    versions = MY_PROCESS.out.versions
}

// Entry point for standalone execution
workflow {
    ch_input = Channel.of([
        [id: 'test'],
        file(params.input_file ?: 'test_data.txt')
    ])
    MY_WORKFLOW_NAME(ch_input)
}
```

### 7.3 Mock mode pattern

Mock mode must generate output files that are structurally identical to live mode
(same column names, same JSON keys, same file extensions). The QC gate parsers in
`qc_trace_monitor.py` read these files to extract metrics.

**Best practices:**
- Use `random.seed(42)` for reproducible mock data
- Generate realistic numerical ranges (not zeros or perfect values)
- Emit a `versions.yml` capturing the tool version string
- Name output files using `${meta.id}_<suffix>.<ext>` convention

### 7.4 QC integration

To add QC monitoring for a new process:

1. Add a parser method to `NextflowQCGateHandler`:
   ```python
   def _parse_my_tool_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
       # Read output files, return dict of {metric_key: value}
   ```

2. Add a pattern match in `_get_metrics_for_process()`:
   ```python
   elif any(k in process_upper for k in ("MY_TOOL", "MY_PROCESS")):
       return self._parse_my_tool_metrics(task_work_dir)
   ```

3. Add threshold checks in `_check_qc_thresholds()`:
   ```python
   # GOLD blocking gate
   if metrics.get("my_metric", 1.0) < 0.95:
       failures.append({"metric": "my_metric", "value": v,
                        "threshold": 0.95, "level": "GOLD",
                        "advisory": False})
   ```

4. Optionally add to a named profile in `QC_NAMED_PROFILES`.

5. Add tests to `backend/tests/test_qc_e2e_domains.py` following the existing
   `TestJamesSMILESCompoundQC` or `TestPriyaCryoEM_P1Gates` pattern.

### 7.5 Registering in the Galaxy tool database

After the `main.nf` is written:

```python
# In bioconductor_skill/skill_generation/ or a one-off script:
conn = sqlite3.connect("backend/galaxy_ai_tools.db")
cursor = conn.cursor()

# Insert tool entry
cursor.execute("""
    INSERT INTO tools (name, description, domain, nextflow_path, ...)
    VALUES (?, ?, ?, ?, ...)
""", ("my_tool_name", "Description", "domain_name",
      "subworkflows/domain/workflow_name/main.nf", ...))

conn.commit()
```

The AI assistant will then route relevant user requests to this workflow via the
intent classifier → `generate_workflow_unified()` → `run_native_nextflow()` chain.

---

*Last updated: 2026-03-04*
*Maintainers: BioMate core team*
*For QC threshold evidence, see: `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`*
*For cryo-EM gate implementation details, see: `docs/QC/20260226_1106_CRYOEM_P1_GATES_IMPLEMENTED.md`*
*For drug discovery capabilities, see: `research_repos/biomate_drug_discovery_paper/20260301_1057_BIOMATE_DRUG_DEVELOPMENT_CAPABILITIES.md`*
