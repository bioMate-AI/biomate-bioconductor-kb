# BioMate — Tester Guide: 21 Services Use Cases

**Date:** 2026-07-01  
**Audience:** QA testers verifying the 21 "Try it →" workflow cards on the BioMate services page  
**Platform:** `https://dev-public.biomate.ai` (dev) or `http://localhost:5000` (local)

---

## How to Use This Document

Each section below corresponds to one services-page card. For every use case:

- **Input** — what data/text to supply to trigger the workflow
- **Chat stream** — what the AI assistant says before launching the workflow
- **Workflow panel** — phases and steps to expect in the right-side panel
- **Step outputs** — files and visualizations produced per step
- **After-run tabs** — content to verify in each tab (Findings / Methods / Report)
- **Downloaded report** — what the downloaded DOCX/PDF should contain

### General UI flow (applies to all 21)

1. User sends the query text (from the "Try it →" link or typed manually).
2. AI responds in the chat stream, optionally asking one clarifying question (e.g. "Do you have SMILES or would you like to use our defaults?").
3. A **workflow card** appears in the chat stream (blue chip with workflow name + "In panel →" badge).
4. The **workflow panel** (right side) opens and shows: param strip at top, phase cards below, footer button.
5. User clicks **Run** (or **Confirm anyway** if required params are missing).
6. Footer button shows "Running…" spinner; phase cards transition `pending → running → completed/failed`.
7. After all phases complete, the panel footer shows **Run again** and the **after-run tabs** appear below the phase cards.
8. User can click **Download Report** to get a DOCX/PDF.

### Status data-attributes to verify (automated testing)

| State | `data-status` on overall badge | Footer button label |
|-------|-------------------------------|---------------------|
| Pre-run | `idle` | Run |
| Clicked run | `running` | Running… (spinner) |
| Phase running | first phase card → `running` | Running… |
| All done | `completed` | Run again |
| Any phase failed | `failed` | Restart |

---

## Section 1: Drug Discovery

---

### 1.1 — Target Discovery

**Query:** `Identify and rank therapeutic targets by genetic support, CRISPR essentiality, tissue expression, and pocket druggability`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Disease / indication | `Parkinson's disease` (or leave blank — AI uses default indication) |
| Gene list (optional) | Leave blank; system pulls from Open Targets / GWAS Catalog |
| Tissue context (optional) | `brain` |

No file upload required. The AI will run against its internal target scoring database if no gene list is provided.

#### Chat stream

- AI confirms it will run target tractability and prioritization analysis.
- If no indication is provided, AI asks: *"What disease or indication should I use to fetch genetic association data?"*
- After user replies (or if query already contains enough context), AI says: *"I'll rank targets using genetic support (GWAS, OMIM), CRISPR essentiality (DepMap), tissue expression (GTEx), and pocket druggability (SiteMap/DoGSiteScorer). Running now."*
- Workflow chip appears: `target_tractability_assessment — In panel →`

#### Workflow panel

**Phases:**

| Phase | Steps |
|-------|-------|
| 1. Target Identification | GWAS/OMIM pull, gene set filtering |
| 2. Essentiality Scoring | DepMap CRISPR fitness score lookup |
| 3. Expression Profiling | GTEx tissue expression query |
| 4. Druggability Assessment | Pocket scoring, antibody tractability |
| 5. Ranking & Report | Weighted composite score, ranked table |

**Phase card status sequence:** pending → running → completed (each phase ~30–120 s)

#### Step outputs

| Step | Output files | Visualization |
|------|-------------|---------------|
| GWAS pull | `gwas_hits.tsv` (gene, p-value, study) | — |
| DepMap scoring | `depmap_essentiality.tsv` | Bar chart: CERES scores by gene |
| GTEx expression | `expression_matrix.tsv` | Heatmap: tissue × gene expression |
| Pocket scoring | `druggability_scores.tsv` | Scatter plot: druggability vs. essentiality |
| Ranked output | `target_ranking.csv` | Table: gene, composite score, tier (A/B/C) |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | AI narrative: "Top 5 targets ranked by composite score… Gene X (CERES = −1.2, GTEx brain TPM = 45, druggability = 0.82) is Tier A…" |
| **Methods** | Methods paragraph: "Genetic associations were pulled from GWAS Catalog (p < 5×10⁻⁸). CRISPR essentiality scores from DepMap (release 23Q4). Tissue expression from GTEx v8. Pocket druggability scored with…" |
| **Report** | Download button → `target_prioritization_report.docx` |

#### Downloaded report content

- Executive summary table (top 10 targets with tier)
- GWAS evidence table
- CRISPR essentiality plots
- Tissue expression heatmap
- Druggability spider chart per top target
- Methods section with citations

---

### 1.2 — Virtual Screening

**Query:** `Screen a compound library against a target protein using AutoDock Vina and DiffDock — score, rank, and cluster hits`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Target protein | PDB ID `6LU7` (SARS-CoV-2 Mpro, pre-loaded) OR upload `.pdb` file |
| Compound library | Leave blank → uses built-in FDA-approved fragment library (~200 compounds) OR upload `.sdf` / `.mol2` |
| Binding pocket | Auto-detected from PDB OR `x=−10.5, y=12.0, z=68.3` (manual box) |

#### Chat stream

- AI asks if a PDB ID or file is available. Tester can reply `6LU7` or just run with defaults.
- AI says: *"I'll dock the compound library against PDB 6LU7 using AutoDock Vina (rigid), then re-score top hits with DiffDock (flexible diffusion model). Estimated time: 20–40 min for 200 compounds."*
- Workflow chip: `virtual_screening_autodock_diffdock — In panel →`

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Structure Prep | Protein protonation, ligand 3D gen, grid box definition |
| 2. AutoDock Vina Docking | Batch docking, score extraction |
| 3. DiffDock Re-scoring | Top 50 from Vina re-docked with DiffDock |
| 4. Clustering & Ranking | Chemical clustering (Tanimoto), final ranked list |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Structure prep | `protein_prep.pdbqt`, `ligands_prep.sdf` | 3D viewer: protein surface with binding pocket highlighted |
| Vina docking | `vina_scores.csv` (CID, score, RMSD) | Histogram: score distribution |
| DiffDock | `diffdock_scores.csv` (confidence, RMSD) | Scatter: Vina vs. DiffDock score |
| Final ranking | `virtual_screening_hits.csv` | Table: rank, compound, Vina kcal/mol, DiffDock confidence |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Top hit: compound CID-XXXXX (Vina = −9.4 kcal/mol, DiffDock confidence = 0.81). Three distinct binding modes identified in cluster analysis." |
| **Methods** | "AutoDock Vina 1.2.5 with exhaustiveness=8. DiffDock v1.1 (score network, confidence model). Tanimoto clustering at similarity 0.4." |
| **Report** | `virtual_screening_report.docx` |

#### Downloaded report

- Top 20 compound table with 2D structures
- Docking pose images (top 3 hits)
- Cluster dendrogram
- Methods + software versions

---

### 1.3 — ADMET Full Panel

**Query:** `Run a full ADMET panel for a small molecule drug candidate — hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 drug-drug interactions, and Lipinski Ro5 compliance`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| SMILES | `CC(=O)Oc1ccccc1C(=O)O` (aspirin) — inline in chat is fine |
| Or compound name | `aspirin` — AI resolves to SMILES automatically |

No file upload needed; SMILES can be typed in-line.

#### Chat stream

- AI immediately routes to ADMET multi-predictor chain.
- Says: *"I'll run 5 ADMET predictions: hERG (QSARPred), DILI (LiverTox model), Ames mutagenicity (T.E.S.T.), CYP450 DDI (CYP3A4/2D6/2C9 inhibition), and Lipinski Ro5."*
- **QC gate**: After run, if hERG IC₅₀ predicted < 1 µM, a red QC gate alert appears: *"hERG risk: IC₅₀ = 0.35 µM (threshold: 1.0 µM) — cardiotoxicity concern flagged."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Molecular Preprocessing | SMILES parse, descriptor generation, 3D conformer |
| 2. hERG Cardiotoxicity | QSAR model prediction (IC₅₀) |
| 3. DILI Prediction | Liver injury probability score |
| 4. Ames Mutagenicity | T.E.S.T. or SVM predictor |
| 5. CYP450 DDI | CYP3A4 / 2D6 / 2C9 inhibition probability |
| 6. Lipinski Ro5 | MW, LogP, HBD, HBA, PSA check |
| 7. QC Gate | Threshold comparison, gate pass/fail |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Preprocessing | `descriptors.csv` (MW, LogP, TPSA, etc.) | Radar chart: physicochemical properties |
| hERG | `herg_prediction.json` (IC₅₀, confidence) | Gauge: IC₅₀ vs. threshold |
| DILI | `dili_score.json` (probability 0–1) | Traffic light: green/amber/red |
| Ames | `ames_result.json` (positive/negative, probability) | Badge |
| CYP450 | `cyp_inhibition.csv` (3 isoforms × probability) | Bar chart: CYP inhibition |
| Lipinski | `ro5_check.json` (violations count) | Table: pass/fail per rule |
| QC gate | `qc_gate_result.json` | Alert banner (red/green) |

**QC gate UI**: If any endpoint exceeds threshold, a red-bordered alert card appears below the phase list with:
- Measured value (red) vs. threshold (grey)
- "Edit" button → opens QC Settings section
- Auto-loop option: "Suggest structural modification to reduce hERG risk"

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Aspirin passes Lipinski Ro5 (0 violations). Ames: negative. DILI: low probability (0.12). hERG IC₅₀ predicted at 32 µM — below concern threshold." |
| **Methods** | "hERG QSAR model trained on ChEMBL patch-clamp data. DILI prediction via DILIrank-calibrated Random Forest. Lipinski rules per Lipinski et al., 1997." |
| **Report** | `admet_report.docx` |

#### Downloaded report

- Summary table: all 5 endpoints with pass/fail/value
- Structure image (2D)
- Per-endpoint detail (model, training set, confidence interval)
- Regulatory context paragraph (ICH S7B for hERG)

---

### 1.4 — Preclinical Development (PBPK)

**Query:** `Run PBPK simulation for a drug candidate and scale the dose from mouse to human using allometric scaling`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Compound | `ibuprofen` or SMILES |
| Mouse dose (mg/kg) | `10` |
| Species scaling | Mouse → Human (default) |
| Physicochemical params | Fu (fraction unbound) = 0.01, logP = 3.5, MW = 206 (auto-fetched from PubChem if compound name given) |

#### Chat stream

- AI asks: *"Do you have measured physicochemical parameters (logP, fu, Papp)? Or should I estimate from SMILES?"*
- After confirmation, says: *"Running a whole-body PBPK model in PK-Sim/mrgsolve for 10 mg/kg mouse dose, then scaling to human equivalent using allometric exponent 0.75 (Boxenbaum method)."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Param Estimation | In-silico logP, pKa, Papp (if not provided) |
| 2. Mouse PBPK | Compartmental PBPK model, plasma PK curve |
| 3. Allometric Scaling | Body weight scaling, CL and Vd adjustment |
| 4. Human PBPK | Scaled simulation, predicted human PK |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Param estimation | `compound_params.json` | Table |
| Mouse PBPK | `mouse_pk_curve.csv` (time, Cp) | Line chart: Cmax, Tmax, AUC annotated |
| Allometric | `scaling_factors.json` (CL_h, Vd_h) | Log-log allometric plot |
| Human PBPK | `human_pk_curve.csv` | Line chart: human Cp vs. time |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Human equivalent dose: 1.62 mg/kg (Cmax = 4.2 µg/mL, t½ = 2.1 h). Predicted therapeutic window is achievable with oral dosing BID at ~80 mg." |
| **Methods** | "PBPK model built in mrgsolve v1.1.1. Allometric scaling: CL ∝ BW^0.75, Vd ∝ BW^1.0." |
| **Report** | `pbpk_allometric_report.docx` |

---

## Section 2: Clinical Research

---

### 2.1 — Clinical Pharmacology (Pop PK)

**Query:** `Model population PK for a drug candidate, simulate dose-escalation to estimate MTD, and quantify drug-drug interaction risk`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| PK data file | CSV with columns: `ID, TIME, DV, AMT, EVID` (typical Phase I data format) |
| Dose levels | `10, 30, 60, 100, 200 mg` |
| Perpetrator drug for DDI | `ketoconazole` (strong CYP3A4 inhibitor) |

If no file is uploaded, AI will use a built-in simulated Phase I dataset for ibuprofen.

#### Chat stream

- AI asks: *"Do you have clinical PK data? If not, I can simulate using a virtual population."*
- Then: *"Running NONMEM-compatible 2-compartment popPK model in nlmixr2. Will simulate dose escalation to estimate Cmax at each level and flag MTD when Cmax exceeds 3× therapeutic target. Then simulating DDI with ketoconazole (CYP3A4 inhibition ratio)."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Data QC | Data format check, outlier flagging, VPC prep |
| 2. PopPK Fitting | 2-compartment nlmixr2 model fit, ETA distribution |
| 3. Dose Simulation | Monte Carlo: 1000 virtual subjects × each dose |
| 4. MTD Estimation | Cmax distribution per dose → MTD probability curve |
| 5. DDI Simulation | CYP3A4 inhibition → fold-change in AUC |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Data QC | `pk_data_summary.csv` | Observed vs. predicted scatter |
| PopPK fit | `model_params.csv` (CL, Vc, Q, Vp, IIV) | VPC plot (5th/50th/95th percentile) |
| Dose sim | `dose_sim_results.csv` | Box plots: Cmax per dose level |
| MTD | `mtd_curve.csv` | Sigmoid probability-of-toxicity vs. dose curve |
| DDI | `ddi_result.json` (AUC ratio) | Bar: AUC alone vs. + ketoconazole |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "MTD estimated at 120 mg (Cmax threshold exceeded in >10% subjects). Ketoconazole co-administration increases AUC 3.2-fold — CYP3A4-sensitive; DDI label warning recommended." |
| **Methods** | "nlmixr2 1.3.2, FOCEI estimation. DDI using static mechanistic model (Fahmi-Rowland method). 1000-subject Monte Carlo simulation." |
| **Report** | `population_pk_ddi_report.docx` |

---

### 2.2 — Pharmacovigilance (FAERS)

**Query:** `Analyze FAERS adverse event data for a drug — run ROR and PRR disproportionality scoring`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Drug name | `atorvastatin` |
| Comparator (optional) | `rosuvastatin` |
| MedDRA SOC filter | `Musculoskeletal disorders` (optional) |
| Date range | 2015–2024 (default) |

#### Chat stream

- AI says: *"I'll query the FAERS public database for atorvastatin adverse event reports (2015–2024), compute Reporting Odds Ratio (ROR) and Proportional Reporting Ratio (PRR) per PT-level term, and flag signals above ROR > 2 and PRR > 2 with χ² > 4."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. FAERS Query | Drug lookup, AE report extraction |
| 2. Data Cleaning | Deduplicate, seriousness filter |
| 3. ROR Calculation | 2×2 contingency table per PT term |
| 4. PRR Calculation | PRR + χ² per PT term |
| 5. Signal Ranking | Sort by ROR × N; apply thresholds |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| FAERS query | `faers_raw_reports.csv` (N, report IDs) | Timeline: reports per quarter |
| Dedup | `faers_clean.csv` | Pie: serious vs. non-serious |
| ROR table | `ror_results.csv` (PT, ROR, 95% CI) | Forest plot: top 20 PT terms |
| PRR table | `prr_results.csv` (PT, PRR, χ²) | Volcano plot: ROR vs. −log10(p) |
| Signal list | `disproportionality_signals.csv` | Ranked table with traffic-light significance |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Atorvastatin: 3 disproportionate signals identified — myopathy (ROR=4.2, N=1,240), rhabdomyolysis (ROR=6.1, N=312), hepatotoxicity (ROR=2.8, N=890). All meet WHO-UMC criteria for detected signal." |
| **Methods** | "FAERS Q4 2024 download. Duplicate removal per FDA guidance (keep most recent report per case). ROR = (a/b)/(c/d); PRR = (a/n1)/(c/n2). Signal threshold: ROR >2, N≥3, χ²>4." |
| **Report** | `pharmacovigilance_signal_report.docx` |

---

### 2.3 — Clinical Trial Design (BOIN)

**Query:** `Design a Phase I dose-escalation oncology trial using the BOIN model — identify the MTD and optimal dose for Phase II`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Target DLT rate | `0.30` (30%) |
| Lowest dose level | `10 mg` |
| Dose levels | `10, 20, 40, 80, 160 mg` |
| Cohort size | `3` patients per cohort |
| Max sample size | `30` |

#### Chat stream

- AI says: *"Running BOIN (Bayesian Optimal Interval) design to find the MTD with target DLT probability 30%. I'll generate the dose-escalation boundary table and simulate 1,000 trials to estimate probability of correct MTD selection."*
- Workflow chip: `boin_dose_escalation` or `boin_dose_escalation_chain`

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. BOIN Boundary Generation | Escalate/de-escalate/stay λ₁ and λ₂ boundaries per dose |
| 2. Trial Simulation | 1,000 simulated trials × dose-response scenarios |
| 3. MTD Selection | Isotonic regression (pooled adjacent violators) |
| 4. Operating Characteristics | PCS, safety metrics, expected N at MTD |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Boundaries | `boin_boundaries.csv` | Table: dose level × escalation rule |
| Simulation | `simulation_oc.csv` (PCS, overdose %, N) | Bar chart: % trials selecting each dose as MTD |
| MTD selection | `mtd_summary.json` | Decision tree diagram |
| OC table | `operating_characteristics.csv` | Heat map: DLT scenario × OC metric |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Recommended MTD: 80 mg (PCS = 62% under true DLT = 30% scenario). Expected trial size: 24 patients. Overdose risk (DLT > 33%): 8%. Design meets FDA Oncology Dose Optimization guidance." |
| **Methods** | "BOIN design (Liu & Yuan, 2015). Boundary calibration: λ₁=0.236, λ₂=0.359 for φ=0.30. 1,000-trial simulation with 7 dose-response scenarios." |
| **Report** | `boin_trial_design_report.docx` |

---

### 2.4 — Pharmacogenomics

**Query:** `Run CYP2D6 and CYP2C19 pharmacogenomics genotyping to stratify patients by metabolizer phenotype`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Input file | `.vcf` file with variant calls (can use test VCF with `rs3892097`, `rs4244285`) |
| Gene panel | `CYP2D6, CYP2C19` |
| Drug of interest | `codeine` (CYP2D6), `clopidogrel` (CYP2C19) |

#### Chat stream

- AI: *"I'll genotype CYP2D6 and CYP2C19 star alleles from your VCF using PyPGx, assign diplotypes, and translate to Poor/Intermediate/Normal/Ultrarapid metabolizer phenotypes per CPIC guidelines. For codeine: ultrarapid = toxicity risk; poor = no analgesia."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. VCF Parsing | Extract CYP2D6/2C19 locus genotypes |
| 2. Star Allele Calling | PyPGx or Stargazer diplotype assignment |
| 3. Phenotype Translation | CPIC activity score → phenotype |
| 4. Drug Recommendation | CPIC guideline lookup per phenotype + drug |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Genotypes | `pgx_genotypes.csv` (sample, locus, GT) | Table |
| Star alleles | `star_alleles.csv` (sample, diplotype) | — |
| Phenotypes | `phenotypes.csv` (sample, gene, phenotype) | Pie: phenotype distribution across cohort |
| Recommendations | `drug_recommendations.csv` | Traffic-light table: drug × phenotype → action |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Patient 001: CYP2D6 *1/*2 (Normal metabolizer) — standard codeine dosing. CYP2C19 *2/*2 (Poor metabolizer) — avoid clopidogrel (no activation); switch to prasugrel or ticagrelor." |
| **Methods** | "CYP2D6 diplotyping: PyPGx 0.17. CYP2C19 star alleles per PharmVar 6.1. CPIC guideline lookup v4.1." |
| **Report** | `pharmacogenomics_report.docx` |

---

### 2.5 — Clinical Genomics (Somatic Variant Calling)

**Query:** `Run clinical somatic variant calling on a tumor sample with GATK4 — annotate against ClinVar and ACMG criteria`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Tumor BAM/FASTQ | Upload tumor FASTQ pair (or use S3 path) |
| Normal BAM/FASTQ | Upload matched normal (germline) |
| Reference genome | `GRCh38` |
| Panel of normals | Optional (default PON from TCGA) |

#### Chat stream

- AI: *"I'll run GATK4 Mutect2 in tumor-normal mode to call somatic SNVs and indels, then annotate with ClinVar (pathogenicity) and apply ACMG variant classification. TMB (tumor mutational burden) will be calculated."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Preprocessing | BWA-MEM alignment, BQSR, MarkDuplicates |
| 2. Somatic Calling | Mutect2 tumor-normal mode, FilterMutectCalls |
| 3. Annotation | Funcotator/VEP: gene, consequence, ClinVar pathogenicity |
| 4. ACMG Classification | PVS1/PS1/PM/PP criteria scoring per variant |
| 5. TMB Calculation | Somatic SNV burden per Mb |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Preprocessing | `tumor.bam`, `normal.bam`, QC metrics | Read depth histogram |
| Somatic calls | `somatic.vcf.gz` (PASS variants) | Lollipop plot: coding mutations on protein |
| Annotation | `annotated.maf` (HUGO_Symbol, Variant_Class, ClinVar) | Oncoprint (if cohort) or mutation summary table |
| ACMG | `acmg_classified.tsv` (variant, class 1–5) | Tier table (pathogenic/likely path/VUS) |
| TMB | `tmb.json` (TMB-H if >10 mut/Mb) | Single number badge |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "12 somatic PASS variants detected. 2 pathogenic (ClinVar): TP53 p.R248W (class 5), KRAS p.G12D (class 5). TMB = 8.4 mut/Mb (TMB-Low). 1 VUS in ATM — clinical significance uncertain." |
| **Methods** | "GATK4 Mutect2 v4.4.0, tumor-normal mode. Filtering: PASS only, AF > 0.05, depth > 20×. Annotation: Funcotator with gnomAD and ClinVar 2024-01." |
| **Report** | `somatic_variant_report.docx` |

---

### 2.6 — Real-World Evidence (Survival Analysis)

**Query:** `Run survival analysis on a retrospective cancer cohort — Kaplan-Meier curves, Cox proportional hazards model, biomarker discovery`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Clinical data CSV | Columns: `patient_id, time_to_event, event (0/1), age, stage, biomarker_X, treatment_arm` |
| Time-to-event endpoint | `OS` (overall survival) or `PFS` |
| Grouping variable | `treatment_arm` (for KM) |
| Covariates for Cox | `age, stage, biomarker_X` |

#### Chat stream

- AI: *"I'll run Kaplan-Meier survival curves stratified by treatment arm with log-rank test, then multivariable Cox proportional hazards regression to identify independent prognostic biomarkers. I'll also test PH assumption and output forest plot."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Data QC | Missing data, censoring summary |
| 2. Kaplan-Meier | KM curves per group, log-rank p-value |
| 3. Cox PH Model | Univariable + multivariable Cox, PH test |
| 4. Biomarker Discovery | Continuous biomarker cut-point optimization (Youden) |
| 5. Forest Plot | HR + 95% CI per covariate |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Data QC | `cohort_summary.csv` | Table: N, events, median follow-up |
| KM | `km_curves.png` | KM plot with confidence bands, log-rank p |
| Cox | `cox_results.csv` (HR, 95% CI, p) | Forest plot |
| Biomarker cut-point | `optimal_cutpoint.json` | ROC + KM at optimal cut |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Treatment A vs B: HR = 0.64 (95% CI: 0.48–0.85, log-rank p = 0.002). Biomarker_X (cut = 2.4 ng/mL) independently prognostic: HR = 1.9 per SD increase after adjustment for age and stage." |
| **Methods** | "Kaplan-Meier + log-rank (survminer R package). Cox PH: survival::coxph with Schoenfeld residuals for PH assumption. Optimal cut-point: maxstat R package." |
| **Report** | `survival_analysis_report.docx` |

---

## Section 3: Genomics & Multi-Omics

---

### 3.1 — WGS / Variant Calling (nf-core/sarek)

**Query:** `Run whole-genome sequencing variant calling using nf-core/sarek with GATK HaplotypeCaller — generate VCF and annotate with VEP`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Input samplesheet | CSV: `patient,sample,lane,fastq_1,fastq_2,status` (status: 0=normal, 1=tumor) |
| Reference genome | `GRCh38` |
| Tools | `haplotypecaller` (germline) — default |
| Annotation | `vep` (default) |

AWS Batch required for this pipeline (full WGS). On dev, use a small test FASTQ pair (<50 MB).

#### Chat stream

- AI: *"Running nf-core/sarek v3.4 for germline WGS variant calling. BWA-MEM2 alignment → GATK MarkDuplicates → BQSR → HaplotypeCaller gVCF mode → GenotypeGVCFs → VEP annotation. Time estimate: 2–6 hours for 30× WGS on AWS Batch."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Preprocessing | BWA-MEM2, MarkDuplicates, BQSR |
| 2. Variant Calling | HaplotypeCaller gVCF, GenotypeGVCFs |
| 3. VQSR Filtering | SNP and INDEL VQSR tranches |
| 4. Annotation | VEP: consequence, gnomAD AF, ClinVar |
| 5. QC Report | MultiQC: coverage, duplicate rate, Ti/Tv |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Preprocessing | `sample.bam`, `mark_dup_metrics.txt` | Coverage depth plot |
| Variant calling | `sample.g.vcf.gz`, `genotyped.vcf.gz` | Variant count summary |
| Filtering | `filtered.vcf.gz` (VQSR PASS) | Ts/Tv ratio chart |
| Annotation | `annotated.vcf.gz` / `.maf` | SNV class pie chart (missense/synonymous/etc.) |
| QC | `multiqc_report.html` | Interactive MultiQC HTML |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "4.2M germline variants called (3.8M PASS after VQSR). Ti/Tv = 2.07 (expected 2.0–2.1 for WGS). 32 rare (AF < 0.01) predicted-damaging variants in cancer predisposition genes." |
| **Methods** | "nf-core/sarek v3.4.3, hg38. BWA-MEM2 2.2.1. GATK 4.5.0. VEP 111 with CADD, gnomAD v4.0 annotations." |
| **Report** | `wgs_variant_report.docx` |

---

### 3.2 — Transcriptomics (RNA-seq + DESeq2)

**Query:** `Run bulk RNA-seq differential expression analysis comparing treated vs control samples with DESeq2`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Input | Count matrix CSV (genes × samples) OR FASTQ samplesheet |
| Sample metadata | `condition: treated/control` (column in metadata CSV) |
| Organism | `human` (GRCh38) |
| Reference | `ensembl` gene IDs in count matrix |

If starting from FASTQ: nf-core/rnaseq runs first, then DESeq2.  
If starting from count matrix: directly enters DESeq2 chain.

#### Chat stream

- AI asks: *"Do you have a count matrix or raw FASTQ files?"*
- If count matrix: *"Running DESeq2 DE analysis directly from your count matrix. Size factor normalization → negative binomial model → Wald test for treated vs. control. Volcano plot, MA plot, pathway enrichment with clusterProfiler."*
- Workflow chip: `bulk_rnaseq_de_analysis` (chain)

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Count QC | Library size distribution, PCA, sample-sample correlation |
| 2. DESeq2 DE | Size factor normalization, negative binomial model, Wald test |
| 3. Result Filtering | Padj < 0.05, |log2FC| > 1 |
| 4. Visualization | Volcano plot, MA plot, heatmap (top 50 DE genes) |
| 5. Pathway Enrichment | clusterProfiler: GO-BP and KEGG over-representation |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Count QC | `qc_report.html` | PCA plot, boxplot of library sizes |
| DESeq2 | `de_results.csv` (gene, log2FC, padj) | Volcano plot, MA plot |
| Filtering | `de_significant.csv` | Count of up/down genes |
| Heatmap | `heatmap_top50.png` | Heatmap with sample/gene dendrograms |
| Pathway | `go_enrichment.csv`, `kegg_enrichment.csv` | Dot plot (GeneRatio × BgRatio, color = padj) |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "1,243 significantly DE genes (padj < 0.05, |log2FC| > 1): 712 upregulated, 531 downregulated in treated vs. control. Top pathway: 'Interferon-gamma response' (GO:0034341, padj = 1.2×10⁻¹⁵, 87 genes)." |
| **Methods** | "DESeq2 1.42.0 (Love et al., 2014). Size factors estimated by median-of-ratios. Shrinkage estimator: apeglm. Pathway enrichment: clusterProfiler 4.10.0, GO-BP, Hs.eg.db." |
| **Report** | `rnaseq_de_report.docx` |

---

### 3.3 — Epigenomics (ATAC-seq)

**Query:** `Run ATAC-seq chromatin accessibility analysis using nf-core/atacseq — call peaks with MACS3`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| FASTQ samplesheet | CSV: `sample,fastq_1,fastq_2,replicate,condition` |
| Reference genome | `GRCh38` |
| Spike-in normalization | `false` (default) |
| Peak caller | `macs3` (default) |

#### Chat stream

- AI: *"Running nf-core/atacseq v2.1.2. Trim Galore → BWA-MEM alignment → picard MarkDuplicates → mito-read removal → MACS3 peak calling (narrow) → DiffBind differential accessibility → motif enrichment with HOMER."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. QC & Trimming | FastQC, Trim Galore, MultiQC pre-trim |
| 2. Alignment | BWA-MEM, sort, index |
| 3. Filtering | Dedup, mito removal, shift reads (+4/−5 bp) |
| 4. Peak Calling | MACS3 narrow peaks per sample, consensus peaks |
| 5. Differential | DiffBind: DA regions between conditions |
| 6. Motif Analysis | HOMER findMotifsGenome.pl on DA peaks |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| QC | `multiqc_report.html` | FastQC HTML, insert size distribution |
| Alignment | `sample.bam` | FRiP score bar chart |
| Peaks | `sample_peaks.narrowPeak`, `consensus_peaks.bed` | Peak count per sample table |
| Differential | `diffbind_results.csv` (region, log2FC, FDR) | MA plot, PCA of peak matrix |
| Motifs | `known_motifs.html`, `top_motifs.tsv` | Motif logo table (top 10) |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "32,145 consensus peaks identified (FRiP median = 0.41). 1,892 differentially accessible regions (FDR < 0.05). Top enriched motif: CTCF (p = 10⁻¹²³) in control; AP-1/FOS (p = 10⁻⁸⁷) in treated." |
| **Methods** | "nf-core/atacseq 2.1.2. MACS3 peak calling with q < 0.05. DiffBind v3.12 on consensus peak matrix. HOMER v4.11 de novo and known motif enrichment." |
| **Report** | `atacseq_report.docx` |

---

### 3.4 — Proteomics (DIA-NN)

**Query:** `Run label-free proteomics DIA quantification with DIA-NN from mzML files`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| mzML files | Upload `*.mzML` (or `*.raw` if on Windows) |
| FASTA library | Human proteome `UP000005640_9606.fasta` (auto-fetched from UniProt if not provided) |
| Experiment type | `DIA` |
| Quantification mode | `protein-level` |

#### Chat stream

- AI: *"Running DIA-NN v2.0 in library-free mode: in silico spectral library from human FASTA → neural network peak scoring → MaxLFQ-based protein quantification. I'll output a protein matrix and run differential expression with DEqMS."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Library Generation | DIA-NN in silico library from FASTA |
| 2. DIA Search | Peptide detection and scoring per run |
| 3. Protein Rollup | MaxLFQ normalization, protein FDR 1% |
| 4. QC | CV distribution, protein coverage |
| 5. Differential | DEqMS (variance weighting for MS data) |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Library | `spectral_library.tsv` | — |
| DIA search | `report.tsv` (peptide-level) | Score histogram |
| Protein matrix | `protein_matrix.csv` (protein × sample) | Density: LFQ intensity distribution |
| QC | `qc_metrics.csv` | CV box plots, # proteins per sample |
| DE | `deqms_results.csv` (protein, log2FC, sca.p) | Volcano plot |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "6,342 proteins quantified at 1% FDR (coverage: median 28 peptides/protein). 412 significantly DE proteins (DEqMS FDR < 0.05). Top up-regulated: ACSL4 (log2FC = 2.3, involved in ferroptosis)." |
| **Methods** | "DIA-NN 2.0.1, precursor FDR 1%. MaxLFQ via DIA-NN built-in algorithm. Differential: DEqMS 1.18 (R/Bioconductor)." |
| **Report** | `proteomics_dia_report.docx` |

---

### 3.5 — Metabolomics (XCMS)

**Query:** `Run untargeted LC-MS metabolomics with XCMS — peak detection, alignment, annotation`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| mzML/mzXML files | Upload `*.mzML` from positive + negative mode |
| Sample metadata | CSV: `filename, sample_type (QC/sample), condition, batch` |
| Instrument | `QTOF` or `Orbitrap` |
| Ionization | `positive` or `both` |

#### Chat stream

- AI: *"Running XCMS3 in R/Bioconductor: CentWave peak detection → obiwarp retention time alignment → correspondence → CAMERA annotation → MS/MS spectral matching against HMDB/KEGG for metabolite ID."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Peak Detection | CentWave per sample |
| 2. RT Alignment | obiwarp alignment |
| 3. Peak Correspondence | groupChromPeaks (density method) |
| 4. Gap Filling | fillChromPeaks |
| 5. Annotation | CAMERA isotope/adduct grouping; HMDB match |
| 6. Statistical | PCA, univariate tests per feature |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Peak detection | `chrompeaks.csv` | BPC/TIC overlay plot |
| Alignment | `aligned_chrompeaks.csv` | RT deviation heatmap |
| Feature table | `feature_table.csv` (mz × sample intensities) | Missing values heatmap |
| Annotation | `annotated_features.csv` (HMDB ID, name, score) | Metabolite class pie |
| Statistical | `da_features.csv` (m/z, rt, log2FC, p) | Volcano plot |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "4,218 features detected; 1,104 annotated to HMDB (score > 0.7). 87 significantly different features (FDR < 0.05). Top pathway: 'Phosphatidylcholine biosynthesis' (MetaboAnalyst enrichment p = 0.002)." |
| **Methods** | "XCMS 3.24.0 (R/Bioconductor). CentWave: ppm=10, peakwidth=c(5,30). obiwarp alignment. CAMERA 1.56.0 for adduct annotation. HMDB 5.0 spectral matching." |
| **Report** | `metabolomics_report.docx` |

---

### 3.6 — Metagenomics (Kraken2 + MetaPhlAn4)

**Query:** `Run shotgun metagenomics taxonomic profiling with Kraken2 and MetaPhlAn4`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| FASTQ reads | Paired-end `*_R1.fastq.gz`, `*_R2.fastq.gz` per sample |
| Kraken2 database | `standard` (pre-built on AWS) or `silva` for 16S |
| Reference metaphlan db | `mpa_vOct22_CHOCOPhlAnSGB_202212` |
| Host contamination | Human genome `hg38` (for decontam) |

#### Chat stream

- AI: *"Running nf-core/taxprofiler (or direct Kraken2 + MetaPhlAn4). Host decontamination with Bowtie2/hg38 → Kraken2 classify → Bracken abundance re-estimation → MetaPhlAn4 marker-gene profiling → Pavian/Krona interactive visualization."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. QC & Host Removal | FastQC, Trim Galore, Bowtie2 hg38 filter |
| 2. Kraken2 Classification | k-mer based classification against standard DB |
| 3. Bracken Abundance | Re-estimated species-level abundance |
| 4. MetaPhlAn4 | Clade-specific marker gene profiling |
| 5. Diversity Analysis | Alpha diversity (Shannon), Beta diversity (Bray-Curtis) |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| QC | `multiqc_report.html` | Read retention after host removal |
| Kraken2 | `kraken2_report.txt` per sample | Krona interactive wheel chart |
| Bracken | `bracken_species.tsv` (species × sample) | Stacked bar: top 20 species per sample |
| MetaPhlAn4 | `metaphlan_merged.tsv` | Heatmap: clades × samples |
| Diversity | `diversity.csv` (Shannon, Bray-Curtis) | Box plot (alpha) + NMDS (beta) |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Dominant genera: Bacteroides (38%), Faecalibacterium (14%), Prevotella (9%). Shannon diversity: control 3.4 ± 0.3 vs. treated 2.8 ± 0.4 (p = 0.04). Bray-Curtis PERMANOVA: R² = 0.18, p = 0.02 (condition explains 18% of beta-diversity)." |
| **Methods** | "Kraken2 2.1.3, standard DB (2024-01). Bracken 2.8, level S, read threshold 10. MetaPhlAn4.1.0 with mpa_vOct22 DB. vegan 2.6.4 for diversity analysis." |
| **Report** | `metagenomics_report.docx` |

---

### 3.7 — Multi-Omics Integration (MOFA+)

**Query:** `Integrate RNA-seq, proteomics, and metabolomics datasets using MOFA+`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| RNA-seq matrix | Normalized count matrix (genes × samples) |
| Proteomics matrix | Protein intensity matrix (proteins × samples) |
| Metabolomics matrix | Metabolite intensity matrix (features × samples) |
| Sample metadata | CSV: `sample_id, condition, batch` |
| n_factors | `10` (default) |

All three matrices should share the same sample IDs (inner join on columns).

#### Chat stream

- AI: *"Running MOFA+ v2 (Multi-Omics Factor Analysis). I'll train a latent factor model across your 3 omics layers, identify shared and layer-specific factors, correlate factors to sample metadata, and run enrichment on top factor weights."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Data Preprocessing | Normalization, feature variance filter, alignment |
| 2. MOFA Training | Variational inference, factor extraction |
| 3. Factor Correlation | Spearman correlation of factors vs. metadata |
| 4. Weight Analysis | Top weights per factor per omics layer |
| 5. Pathway Enrichment | GSEA on RNA-seq factor weights |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Preprocessing | `mofa_input.hdf5` | Variance explained per feature |
| Training | `mofa_model.hdf5` (MOFA+ object) | Variance explained: stacked bar per factor × omics |
| Factors | `factor_scores.csv` (sample × factor) | Beeswarm: factor scores by condition |
| Weights | `weights_rna.csv`, `weights_prot.csv`, `weights_metab.csv` | Top weight heatmap |
| Pathway | `gsea_factor1.csv` (pathway, NES, padj) | Dot plot |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Factor 1 explains 18% variance across all layers and correlates with treatment (Spearman r = 0.84, p = 10⁻⁶). Top RNA-seq weights: interferon pathway genes. Top metabolomics weights: ceramide species — suggesting coordinated inflammatory response." |
| **Methods** | "MOFA+ v2.1.0. 10 factors, Gaussian likelihood for all views. Convergence: ELBO threshold 10⁻⁶. GSEA via fgsea 1.26 on factor 1 RNA-seq weights (MSigDB Hallmarks)." |
| **Report** | `multiomics_mofa_report.docx` |

---

## Section 4: Structural Biology

---

### 4.1 — Cryo-EM SPA (CryoSPARC)

**Query:** `Run CryoSPARC single particle analysis on cryo-EM micrographs — motion correction, CTF estimation, particle picking, 2D/3D classification, refinement`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Micrographs | `.mrc` files (gain-corrected or raw) |
| Pixel size (Å/px) | `1.05` |
| Accelerating voltage (kV) | `300` |
| Spherical aberration (mm) | `2.7` |
| Amplitude contrast | `0.1` |
| Expected particle diameter (Å) | `150` |

#### Chat stream

- AI: *"Running CryoSPARC v4 SPA pipeline: Patch MotionCor → Patch CTF estimation → Blob picking → 2D classification → Ab-initio 3D → Heterogeneous refinement → Homogeneous refinement → Local CTF refinement → FSC resolution estimation."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Preprocessing | Patch MotionCor (motion correction), CTF estimation |
| 2. Particle Picking | Blob picker → 2D class inspector → Template picker |
| 3. 2D Classification | 50 classes, iterative cleaning |
| 4. Ab-initio 3D | Random initialization, 3 classes |
| 5. 3D Refinement | Homogeneous refinement → Local CTF refinement |
| 6. Validation | FSC curve, Guinier plot, GSFSC resolution |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Motion correction | `corrected_micrographs/*.mrc` | Drift trajectory plot |
| CTF | `ctf_params.csv` (defocus, astigmatism) | CTF fit diagnostic image |
| 2D classes | `classes_2D.mrcs` | 2D class gallery (image grid) |
| Ab-initio | `volume_init.mrc` | 3D density map (MRC viewer) |
| Refinement | `final_volume.mrc`, `particles_refined.cs` | Half-map overlay, FSC curve |
| FSC | `fsc_curve.png` | FSC = 0.143 resolution annotation |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Overall resolution: 3.4 Å (FSC = 0.143). 84,320 particles in final refinement (from 2.1M picks). Local resolution: core 3.1 Å, peripheral loops 4.8 Å. Density map uploaded to CryoSPARC Live viewer." |
| **Methods** | "CryoSPARC v4.4.1. Patch MotionCor (7×5 patches, B-factor 500). Patch CTF (7×5 patches). 2D classification: 50 classes, 40 iterations. Ab-initio 3D: 3 classes × 300 iterations. Non-uniform refinement." |
| **Report** | `cryoem_spa_report.docx` |

---

### 4.2 — Protein Structure Prediction (AlphaFold3)

**Query:** `Predict the 3D structure of a protein sequence using AlphaFold3 — validate the model with MolProbity and identify binding sites`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Protein sequence | FASTA format (single chain, or multi-chain complex) |
| Or UniProt ID | `P04637` (human TP53) |
| Run mode | `monomer` or `multimer` |
| MSA mode | `full` (default) or `single_sequence` (fast) |

#### Chat stream

- AI: *"Running AlphaFold3 structure prediction: MSA construction with jackhmmer/HHblits → template search → structure module → model ranking. After prediction, MolProbity clash score and Ramachandran analysis. fpocket for binding site prediction."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. MSA Construction | jackhmmer (UniRef90), HHblits (BFD/MGnify), template search (PDB) |
| 2. Structure Prediction | Evoformer + structure module, 5 models |
| 3. Model Ranking | pLDDT-based selection |
| 4. Validation | MolProbity (clash score, Rama, rotamer) |
| 5. Binding Site | fpocket cavity detection |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| MSA | `msa.a3m` (depth statistics logged) | MSA depth plot (# sequences vs. position) |
| Prediction | `ranked_0.pdb` through `ranked_4.pdb` | 3D viewer: pLDDT color-coded ribbon |
| pLDDT plot | `plddt.png` | Per-residue confidence score line chart |
| MolProbity | `molprobity_report.txt` (clash < 10, Rama > 98%) | Ramachandran plot |
| Binding sites | `fpocket_pockets.pdb` | Pocket volume visualization |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "TP53 DNA-binding domain (aa 94–292): pLDDT 89.4 (high confidence). Tetramerization domain: pLDDT 72.1 (moderate). MolProbity clash score: 4.2 (good). Ramachandran: 97.8% favored. Top pocket: 812 Å³ volume, hydrophobicity score 3.8." |
| **Methods** | "AlphaFold3 v3.0. MSA: jackhmmer 3.3.2 (UniRef90 2024-01), HHblits 3.3.0 (BFD). Template cutoff: 2020-05-14. MolProbity 4.5.2. fpocket 3.0." |
| **Report** | `protein_structure_report.docx` |

---

### 4.3 — Molecular Dynamics (GROMACS)

**Query:** `Run GPU-accelerated GROMACS molecular dynamics for a protein-ligand complex — equilibration, production MD, trajectory analysis`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Protein PDB | `protein.pdb` OR PDB ID (e.g. `6LU7`) |
| Ligand SDF/MOL2 | `ligand.sdf` (if complex) |
| Force field | `CHARMM36m` (default) or `AMBER99SB-ILDN` |
| Simulation time | `100 ns` |
| Temperature | `310 K` |
| Water model | `TIP3P` |

#### Chat stream

- AI: *"Running GROMACS GPU-accelerated MD: system preparation with CHARMM-GUI → energy minimization → NVT equilibration (310K) → NPT equilibration (1 atm) → 100 ns production MD. RMSD, RMSF, H-bond analysis, binding free energy (MM-PBSA)."*
- Workflow chip: `AMBER pmemd GPU Molecular Dynamics` or `gromacs_md` (after Q20 fix applied in this session)

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. System Preparation | Protonation, CHARMM force field parameters, solvation, ionization |
| 2. Energy Minimization | Steepest descent until Fmax < 1000 kJ/mol/nm |
| 3. NVT Equilibration | 100 ps at 310 K (velocity rescaling thermostat) |
| 4. NPT Equilibration | 100 ps at 1 atm (Parrinello-Rahman barostat) |
| 5. Production MD | 100 ns GPU simulation |
| 6. Analysis | RMSD, RMSF, H-bond, MM-PBSA binding ΔG |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| System prep | `topol.tpr`, `system.gro` | Solvated system 3D preview |
| Energy min | `em.log` (convergence) | Potential energy convergence plot |
| NVT | `nvt.edr` (temperature) | Temperature vs. time chart |
| NPT | `npt.edr` (pressure, density) | Pressure + density equilibration chart |
| Production | `traj.xtc`, `md.tpr` (100 ns, compressed) | — |
| RMSD | `rmsd.xvg` | RMSD vs. time line chart (backbone) |
| RMSF | `rmsf.xvg` | RMSF per residue bar chart |
| MM-PBSA | `mmpbsa_results.csv` | Bar: ΔG components (MM, PB, SA) |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "System equilibrated by 20 ns (RMSD plateau at 2.1 Å). Protein backbone RMSF: flexible loop aa 124–138 (RMSF = 4.2 Å). Ligand binding stable throughout 100 ns (ligand RMSD < 1.5 Å). MM-PBSA ΔG = −32.4 ± 4.1 kJ/mol." |
| **Methods** | "GROMACS 2024.2, GPU-accelerated (NVIDIA A100). CHARMM36m force field. Water: TIP3P, box = 12 Å padding. Ewald PME electrostatics. Time step: 2 fs." |
| **Report** | `md_simulation_report.docx` |

---

### 4.4 — Molecular Docking (AutoDock Vina)

**Query:** `Dock a small molecule ligand into a target protein using AutoDock Vina — score the top poses and visualize`

#### Input

| Parameter | Value for testing |
|-----------|------------------|
| Receptor PDB | PDB ID `1HSG` (HIV protease) or upload `.pdb` |
| Ligand | SMILES `CC(=O)Oc1ccccc1C(=O)O` or SDF |
| Binding box center | x=2, y=5, z=-17 (auto-detected from known ligand if present) |
| Box size (Å) | 20 × 20 × 20 |
| Exhaustiveness | `8` (default) |
| Top N poses | `9` |

#### Chat stream

- AI: *"Docking your ligand against PDB 1HSG using AutoDock Vina 1.2. I'll prepare the receptor (AutoDockTools: add hydrogens, assign Gasteiger charges), generate 3D ligand conformer, define the binding box around the active site, and run exhaustiveness=8. Top 9 poses returned with kcal/mol scores."*

#### Workflow panel

| Phase | Steps |
|-------|-------|
| 1. Receptor Prep | OpenBabel/AutoDockTools: H-add, PDBQT conversion |
| 2. Ligand Prep | 3D conformer (RDKit), PDBQT conversion |
| 3. Grid Definition | Box center + size from user or active site detection |
| 4. Docking | AutoDock Vina: exhaustiveness=8, 9 poses |
| 5. Pose Analysis | Energy decomposition, H-bond contacts, PLIF |

#### Step outputs

| Step | Files | Visualization |
|------|-------|---------------|
| Receptor prep | `receptor.pdbqt` | — |
| Ligand prep | `ligand.pdbqt` | 2D structure image |
| Docking | `docking_results.pdbqt` (9 poses + scores) | 3D viewer: top pose in binding pocket |
| Pose analysis | `vina_scores.csv` (pose, score, RMSD to mode 1) | Bar chart: scores per pose |
| Contacts | `plif_contacts.csv` (residue, interaction type) | 2D PLIF diagram |

#### After-run tabs

| Tab | Content |
|-----|---------|
| **Findings** | "Best pose: −7.2 kcal/mol. Key contacts: ASP25 (H-bond acceptor), VAL82 (hydrophobic), ILE50 (H-bond). Pose 1 RMSD from reference: 1.4 Å (validated against co-crystal). All 9 poses cluster in same binding mode." |
| **Methods** | "AutoDock Vina 1.2.5. Receptor prepared with AutoDockTools 1.5.7 (Gasteiger charges). Ligand 3D: RDKit ETKDG. Box: 20³ Å centered at active site. Exhaustiveness=8." |
| **Report** | `molecular_docking_report.docx` |

---

## Common Testing Checklist

Use this checklist for EVERY use case during manual QA:

### Routing verification
- [ ] Query from "Try it →" link loads correct workflow chip (not a generic/wrong workflow)
- [ ] Chain vs. workflow: bioinformatics pipelines with multiple tools should route to chains where available
- [ ] Workflow name in chip matches expected workflow (see table in doc header)

### Workflow panel states
- [ ] Pre-run: param strip visible; missing required params show "Fix now" alert
- [ ] Run clicked: footer shows "Running…" spinner within 1 s
- [ ] Phase cards transition: pending → running → completed (real-time, via SSE)
- [ ] At least one idle→running→completed transition observed in real time (not mocked)
- [ ] Completion: footer shows "Run again"; overall badge `data-status="completed"`
- [ ] Failure: footer shows "Restart"; phase card and badge show `data-status="failed"`

### After-run tabs
- [ ] "Findings" tab: AI narrative with quantitative results (not generic placeholder text)
- [ ] "Methods" tab: tool names + versions, parameters used, citations
- [ ] "Report" tab: Download button present and functional
- [ ] Downloaded file opens without error and contains all expected sections

### QC gates (ADMET only)
- [ ] Red QC gate alert appears when any ADMET endpoint fails threshold
- [ ] Two-number display: measured value (red) vs. threshold (grey)
- [ ] "Edit" button on gate row opens QC Settings panel
- [ ] Auto-loop suggestion appears for flagged endpoints

### Known routing status (as of 2026-07-01)

| Use case | Expected routing | Status |
|----------|-----------------|--------|
| Q01 Target Discovery | `target_tractability_assessment` chain | ✓ Fixed |
| Q02 Virtual Screening | `virtual_screening_autodock` workflow | Verify |
| Q03 ADMET | `admet_full_panel` or `herg_cardiac_safety_qsar` | Verify (partial) |
| Q04 PBPK | `pbpk_allometric_scaling` workflow | Verify |
| Q05 Pop PK | `population_pk_simulation` workflow | Verify |
| Q06 FAERS | `faers_disproportionality` workflow | ⚠ Check - limited coverage |
| Q07 WGS/sarek | `nf-core/sarek` workflow | Verify |
| Q08 RNA-seq DESeq2 | `bulk_rnaseq_de_analysis` chain | ⚠ LLM arbitration bug tracked |
| Q09 ATAC-seq | `nf-core/atacseq` workflow | Verify |
| Q10 Proteomics DIA | `proteomics_dia_diann` workflow | Verify |
| Q11 Metabolomics XCMS | `lcms_metabolomics_consensus` chain | ✓ Works on dev |
| Q12 Metagenomics | `shotgun_metagenomics_to_mag` chain | ✓ Works on dev |
| Q13 Multi-omics MOFA | `multi_omics_mofa_chain` chain | ✓ Works on dev |
| Q14 BOIN | `boin_dose_escalation_chain` or workflow | Verify |
| Q15 Pharmacogenomics | `cyp2d6_cyp2c19_pgx` workflow | Verify |
| Q16 Somatic variants | Somatic variant calling workflow | ⚠ Coverage gap tracked |
| Q17 Survival analysis | `survival_analysis_cox` workflow | Verify |
| Q18 Cryo-EM SPA | `cryosparc_standard_spa` workflow | Verify |
| Q19 Protein structure | AlphaFold3 workflow | Verify |
| Q20 Molecular Dynamics | GROMACS/AMBER workflow | ✓ Subworkflow filter fixed 2026-07-01 |
| Q21 Molecular Docking | `autodock_vina_docking` workflow | Verify |

---

## Test Data Sources

| Data type | Where to get |
|-----------|-------------|
| SMILES (drug compounds) | PubChem (pubchem.ncbi.nlm.nih.gov) or ChEMBL |
| Protein PDB files | RCSB PDB (rcsb.org) |
| Test FASTQ (RNA-seq) | nf-core `test` profile datasets or ENCODE small datasets |
| Test VCF | GATK bundle (b37/hg38), or generate from 1000G chr22 |
| Clinical PK data | NONMEM example datasets or simulated |
| mzML files | PRIDE Archive test datasets |
| Cryo-EM micrographs | EMPIAR test datasets (empiar-10025: β-galactosidase) |

---

*Document maintained in `docs/20260701_TESTER_GUIDE_21_USE_CASES.md`*  
*Contact: engineering team for questions about expected routing or workflow behavior*
