# BioMate Drug Development Capabilities
**Date:** 2026-03-01
**Audience:** Academic and industry collaborators — structural biologists, medicinal chemists, DMPK scientists
**Document type:** Platform capability overview for collaboration discussions and Paper 4 context

---

## 1. Executive Summary

BioMate is an AI-powered drug development platform that executes reproducible, containerized Nextflow (nf-core DSL2) workflows covering the full drug development pipeline — from structural target identification and virtual screening through lead optimization, preclinical in vivo studies, formulation science, and regulatory-grade clinical pharmacokinetic analysis. Every stage is governed by an evidence-graded QC layer (GOLD / SILVER / BRONZE) that blocks or flags poor-quality data before it can propagate to expensive downstream analyses, directly addressing the silent QC failure modes that are responsible for a large fraction of late-stage attrition in drug discovery programs. BioMate integrates 25 pharmacology Nextflow subworkflows, a 15-module cryo-EM single-particle analysis pipeline, MaxQuant/DIA-NN proteomics parsers, compound SMILES validation, pharmacogenomics coverage gating, and newly added population PK/PD via nlmixr2 and non-compartmental analysis via PKNCA — all deployable on local infrastructure, SLURM clusters, or AWS Batch. The platform is accessible through a conversational AI interface that generates and executes Nextflow workflows in response to natural-language research questions.

---

## 2. Coverage by Drug Development Phase

The table below maps each standard drug development phase to BioMate's specific capabilities. Audience notation: **SB** = structural biologist, **DD** = drug developer (medicinal chemist / DMPK scientist), **Both** = relevant to both audiences.

| # | Phase | BioMate Capability | Specific Workflows / Tools | Audience | Output |
|---|---|---|---|---|---|
| 1 | **Target Identification & Validation** | Binding site prediction; binding affinity from sequence; drug repurposing via disease network; chemoproteomics pulldown QC; SMILES structure validation before any prediction | `run_autosite`, `predict_binding_affinity_protein_1d_sequence`, `retrieve_topk_repurposing_drugs_from_disease_txgnn` (TxGNN); MaxQuant / DIA-NN / pulldown QC parsers; `_parse_smiles_metrics()` | Both | Ranked binding sites; affinity scores; top-K repurposing candidates with TxGNN score; proteomics QC report; compound validity report |
| 2 | **Virtual Screening / Hit Identification** | Ultra-fast virtual screening (10M× faster than Vina); diffusion-based docking; AutoDock Vina; physicochemical property calculation | `DrugCLIP` (fast screening), `run_diffdock_with_smiles` (DiffSBDD diffusion docking), `docking_autodock_vina`, `calculate_physicochemical_properties` | Both | Ranked compound list with docking scores; binding pose PDB files; MW / logP / HBD / HBA / TPSA |
| 3 | **Hit-to-Lead (SAR)** | SMILES structure QC gates before ADMET (blocks invalid structures at GOLD level); ADMET profiling for SAR series; physicochemical space monitoring | `_parse_smiles_metrics()` (GOLD: invalid SMILES blocked; SILVER: salts, stereocenters), `ADMET_pred`, `predict_admet_properties`, `calculate_physicochemical_properties`; named profiles: `compound_druglike`, `compound_natural_product`, `compound_peptidomimetic` | DD | Clean compound registry; ADMET heatmap across SAR series; Lipinski Ro5 flags |
| 4 | **Lead Optimization (ADMET, Safety Triage)** | Full ADMET panel (12 endpoints); hERG cardiotoxicity gate; DILI risk gate; Ames mutagenicity gate; ClinTox gate; drug combination safety; DDI alternative finding | `predict_admet_properties` (DeepPurpose MPNN/CNN/Morgan — solubility, Caco-2, HIA, BBB, PPBR, CYP2C19/2D6/3A4/1A2/2C9, ClinTox, lipophilicity, t½, clearance); hERG IC50 gate (GOLD < 1 μM blocking; SILVER 1–10 μM advisory); DILI gate (DILIrank GOLD blocking); Ames gate (SILVER advisory); ClinTox > 0.8 (SILVER advisory); `check_drug_combination_safety`, `find_alternative_drugs_ddinter` | DD | ADMET profile table; safety flag report; DDI alternatives list; QC gate pass/fail with evidence level |
| 5 | **Preclinical — In Vitro Studies** | In vitro drug release kinetics (4 kinetic models); formulation stability; compound QC before assay; pulldown enrichment QC | `analyze_in_vitro_drug_release_kinetics` (zero-order, first-order, Higuchi, Korsmeyer-Peppas); `analyze_accelerated_stability_of_pharmaceutical_formulations` (ICH Q1A/Q1B); `run_3d_chondrogenic_aggregate_assay`; chemoproteomics pulldown QC: enrichment ratio SILVER ≥ 3× | DD | Kinetic model fit parameters (k, n, R²); ICH stability report; enrichment ratio + QC verdict |
| 6 | **Preclinical — In Vivo Studies** | Xenograft tumor growth inhibition analysis; 1-compartment / 2-compartment PK ODE simulation; thyroid hormone PK simulation | `analyze_xenograft_tumor_growth_inhibition`; `pk_ode_system` (1-compartment oral, ka/ke/Vd); `bi_exp_model` (2-compartment IV/oral, bi-exponential A·e^{−αt} + B·e^{−βt}); `simulate_thyroid_hormone_pharmacokinetics` | DD | TGI % and tumor growth curves; simulated PK time-concentration profiles; AUC estimates |
| 7 | **Preclinical Safety / Toxicology** | hERG IC50 gate; DILI gate; Ames mutagenicity gate; ClinTox probability gate; VCOG-CTCAE adverse event grading; FDA adverse event signal analysis; xenograft safety readouts | hERG gate (GOLD < 1 μM blocking; SILVER 1–10 μM); DILI gate (DILIrank "Most-DILI-Concern" = GOLD blocking; "Less-DILI-Concern" = SILVER advisory); Ames gate (positive = SILVER advisory); ClinTox > 0.8 = SILVER advisory; `grade_adverse_events_using_vcog_ctcae`, `apply_vcog_grade`; `analyze_fda_safety_signals` | DD | Structured toxicity flag report; VCOG-CTCAE grade assignments; FDA FAERS signal summary |
| 8 | **Formulation & CMC** | In vitro drug release kinetics; accelerated stability (ICH Q1A/Q1B); kinetic model selection (zero/first/Higuchi/Korsmeyer-Peppas); ODE whole-cell models | `analyze_in_vitro_drug_release_kinetics`, `analyze_accelerated_stability_of_pharmaceutical_formulations`, `zero_order`, `first_order`, `higuchi`, `korsmeyer_peppas`, `exp_decay`; `simulate_whole_cell_ode_model`, `default_whole_cell_model` | DD | Shelf-life estimates; release mechanism classification (erosion vs. diffusion vs. swelling); stability prediction plots |
| 9 | **Clinical PK — Phase I NCA** | Non-compartmental analysis (regulatory-grade); AUC₀₋∞, Cmax, Tmax, t½, CL/F, Vz/F; QC gate on sparse-sampling adequacy | `nca_pknca` — PKNCA R package; regulatory-grade NCA output table; QC gates on minimum number of measurable concentrations | DD | NCA parameter table (AUC, Cmax, Tmax, t½, CL/F, Vz/F) per subject and summary statistics; QC-flagged subjects |
| 10 | **Clinical PK/PD — Population PK (Phase I/II)** | Population PK fitting with between-subject variability (BSV); SAEM algorithm (FDA-recognized NONMEM alternative); 1/2-compartment model fitting; Sigmoid Emax PD model; QC gates on convergence and ETA shrinkage | `nlmixr2_population_pk` (nlmixr2 R package, SAEM/FOCE+); convergence GOLD gate; ETA shrinkage < 30% SILVER gate; condition number < 1000 BRONZE gate; `sigmoid` (Emax PD model) | DD | Population PK parameter estimates (CL, Vd, ka, IIV); VPC plots; OFV; ETA shrinkage report; model convergence QC report |
| 11 | **Pharmacogenomics (PGx) — Precision Dosing** | Per-gene CYP coverage QC gate; CYP2C19 metabolizer status from MWAS; WGS-based star allele call quality gating | PGx CYP gene coverage gate: CYP2D6/2C19/3A4/DPYD/TPMT — GOLD ≥ 30× (CPIC-compliant); `pgx_clinical` profile; `pgx_research` profile (15× advisory); `perform_mwas_cyp2c19_metabolizer_status` | DD | Per-gene coverage report; metabolizer phenotype (EM/IM/PM/UM); dosing recommendation flags; CPIC-compliant QC verdict |
| 12 | **Post-market Safety Surveillance** | FDA FAERS adverse event querying; drug interaction signal mining; drug label retrieval; drug recall checking; safety signal analysis | `query_fda_adverse_events`, `query_drug_interactions`, `query_drug_labels`, `query_drug_recalls`, `analyze_fda_safety_signals`, `check_fda_drug_recalls`, `get_fda_drug_label_info`; end-to-end pipeline includes recall check as final stage | Both | FAERS signal table; PRR / ROR statistics; label change history; active recall list |

---

## 3. Structural Biologist's View

### What BioMate Offers a Structural Biologist

A structural biologist working in a drug discovery context faces two intersecting challenges: determining the three-dimensional structure of a drug target at sufficient resolution to enable rational design, and then using that structure to guide compound selection or predict binding modes for hit series. BioMate addresses both challenges through an integrated cryo-EM single-particle analysis pipeline and a set of molecular docking and binding affinity prediction workflows, all executed as reproducible Nextflow pipelines deployable on GPU-equipped infrastructure.

#### Cryo-EM SPA Pipeline (15 Modules)

The cryo-EM pipeline covers the complete SPA workflow from raw micrograph import to sharpened, post-processed maps, with four levels of Nextflow parallelism for high throughput:

- **`IMPORT_MOVIES`** — Imports raw movie stacks; validates file integrity before any GPU compute is consumed
- **`MOTION_CORRECTION`** — MotionCor2 motion correction with QC gates: total motion drift GOLD < 50 Å (blocking), advisory warnings at 40–50 Å; per-frame drift advisory > 3 Å/frame
- **`CTF_ESTIMATION`** — CTFFIND4 / gCTF with QC gates: fit quality GOLD < 0.7 (blocking); astigmatism advisory > 1000 Å (BRONZE); ice thickness advisory > 50% (from `ctf_diagnostics.json`); phase plate support with phase shift gate (advisory if < 0.2 rad depleted or > 1.5 rad over-charged)
- **`MICROGRAPH_CURATION`** — Automated selection of micrographs passing CTF and motion thresholds
- **`PARTICLE_PICKING`** — Topaz (neural network), crYOLO, or blob-based picking; particle count advisory gate
- **`PARTICLE_EXTRACTION`** — Configurable box size; particle stack assembly
- **`CLASSIFY_2D`** — 2D classification with junk fraction QC gate: GOLD blocking > 70% junk; SILVER advisory 50–70% junk
- **`CLASS_SELECTION`** — Automated and manual class selection
- **`AB_INITIO`** — Initial 3D volume generation
- **`HOMOGENEOUS_REFINEMENT`** — High-resolution refinement; orientation anisotropy QC gate: GOLD blocking > 10× ratio, advisory 5–10× ratio
- **`HETEROGENEOUS_REFINEMENT`** — Conformational heterogeneity analysis
- **`NON_UNIFORM_REFINEMENT`** — Non-uniform regularization for improved resolution
- **`CTF_REFINEMENT`** — Per-particle CTF refinement
- **`SHARPENING`** — B-factor sharpening with gate: advisory if B-factor > 0 Å² (over-sharpened) or < −300 Å² (over-blurred); local resolution spread advisory if σ > 3.0 Å

**Full pipeline:** `spa_full_pipeline/main.nf` runs all 15 stages with intra-stage parallelism (multiple micrograph batches processed simultaneously) and inter-stage parallelism (independent downstream branches run concurrently).

**Deployment profiles:** `standard`, `docker`, `local_gpu`, `multi_gpu`, `slurm`, `singularity`, `aws`, `test`. The `opensource` profile maps every process to open-source containers — RELION (19 of 20 SPA steps), CTFFIND4, Topaz, Phenix — removing any CryoSPARC license dependency.

#### Molecular Docking and Virtual Screening

Once a structure is available, BioMate provides three docking approaches at different speed/accuracy trade-offs:

- **`DrugCLIP`** — Contrastive learning-based virtual screening, approximately 10 million times faster than AutoDock Vina for large-scale screening. Accepts a target protein structure and a compound library; outputs ranked compound scores. Suitable for screening millions of compounds before docking.
- **`run_diffdock_with_smiles`** — Diffusion-based molecular docking (DiffDock). Takes a SMILES string and a protein PDB; generates an ensemble of binding poses using a generative diffusion model. Highest accuracy for individual compound docking, particularly for flexible binding sites.
- **`docking_autodock_vina`** — Classical AutoDock Vina docking. Standard reference method; reproducible, widely cited.
- **`run_autosite`** — Binding site prediction before docking. Identifies druggable pockets on the protein surface; outputs ranked site coordinates and volume estimates.

#### Binding Affinity Prediction

- **`predict_binding_affinity_protein_1d_sequence`** — Predicts binding affinity directly from protein amino acid sequence (no 3D structure required). Useful for target validation before structure determination, or for targets that are disordered.

#### Compound Quality Gates Before Docking

Before any docking or affinity calculation is run, BioMate enforces the SMILES structure QC layer:

- GOLD gate: RDKit SMILES validity — invalid SMILES are rejected before any GPU compute is consumed
- SILVER advisory: salt stripping (auto-stripped with transformation logged), undefined stereocenters flagged
- BRONZE advisory: molecular weight outside drug space (> 900 Da)

Named profiles for compound input: `compound_druglike` (Lipinski Ro5: MW < 500, logP < 5), `compound_natural_product` (relaxed MW < 1000 Da), `compound_peptidomimetic` (MW < 900 Da, relaxed HBD/HBA).

#### Chemoproteomics Target ID

For identifying drug binding partners in a cellular context, BioMate's chemoproteomics pulldown QC parser (`_parse_pulldown_metrics()`) ensures that affinity proteomics data meets minimum quality before downstream target interpretation:

- SILVER blocking gate: enrichment ratio ≥ 3× (bait-to-control)
- SILVER advisory: bait peptides detected
- BRONZE advisory: CRAPome contamination fraction

Named profile: `proteomics_chemoproteomics` — enforces the enrichment ratio gate with stricter background contamination monitoring.

#### Drug Repurposing from Disease Network

- **`retrieve_topk_repurposing_drugs_from_disease_txgnn`** — TxGNN (Therapeutic Target Guided Neural Network) graph-based drug repurposing. Queries a pre-trained disease–gene–drug network to identify existing approved drugs likely to modulate a target of interest. Useful for prioritizing compounds to dock against a newly solved structure.

#### Representative Nextflow Command — Structural Biologist

```bash
# Run full cryo-EM SPA pipeline on a directory of raw movie stacks,
# using the open-source (RELION/CTFFIND4/Topaz) profile on a SLURM cluster.
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/spa_full_pipeline/main.nf \
  -profile opensource,slurm \
  --input_dir /data/raw_movies/ \
  --pixel_size 0.83 \
  --voltage 300 \
  --cs 2.7 \
  --outdir /results/spa_run_20260301/ \
  --phase_plate false \
  -resume

# After structure is obtained, run virtual screening + docking pipeline
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/workflows/drug_discovery/main.nf \
  -profile docker \
  --smiles_file /data/compounds/hit_series.csv \
  --pdb_id 8XYZ \
  --run_docking true \
  --docking_method diffdock \
  --qc_profile compound_druglike \
  --outdir /results/docking_20260301/
```

The BioMate AI assistant will generate these commands automatically from natural-language input such as: *"Run the CryoSPARC SPA pipeline on my micrographs, then dock our top 50 DrugCLIP hits against the resulting structure using DiffDock."*

---

## 4. Drug Developer's View

### What BioMate Offers a Medicinal Chemist / DMPK Scientist

A medicinal chemist or DMPK scientist working in lead optimization and preclinical development needs reliable, reproducible tools that match pharmaceutical industry standards: ADMET profiling with interpretable confidence, safety triage before expensive in vivo experiments, regulatory-compatible PK analysis, and FDA surveillance for competitive intelligence and safety signals. BioMate provides all of these through governed Nextflow workflows with evidence-graded QC gates that flag data quality issues before they reach decision-makers.

#### ADMET Profiling (12 Endpoints, DeepPurpose Models)

The `predict_admet_properties` workflow applies three model architectures (MPNN, CNN, Morgan fingerprint) per endpoint, providing ensemble confidence alongside point estimates:

| Endpoint | Model | Relevance |
|---|---|---|
| Aqueous solubility | MPNN | Formulation and bioavailability |
| Caco-2 permeability | CNN | GI absorption prediction |
| Human intestinal absorption (HIA) | MPNN | Oral bioavailability |
| Blood-brain barrier (BBB) | MPNN | CNS compound triage |
| Plasma protein binding ratio (PPBR) | CNN | Free fraction estimation |
| CYP2C19 inhibition | Morgan | DDI risk, metabolizer interaction |
| CYP2D6 inhibition | Morgan | DDI risk, CYP2D6 substrate triage |
| CYP3A4 inhibition | Morgan | Major metabolic pathway |
| CYP1A2 inhibition | Morgan | DDI risk |
| CYP2C9 inhibition | Morgan | DDI risk |
| Clinical toxicity (ClinTox) | MPNN | Failed IND/NDA flag |
| Lipophilicity (logD) | CNN | Distribution and membrane permeability |
| Half-life | MPNN | Dosing interval planning |
| Clearance | CNN | Dose calculation input |

`ADMET_pred` provides the same panel via the ADMET-AI ensemble (a complementary model package). Both workflows accept SMILES input directly or from the compound QC pipeline output.

#### Safety Triage Gates

BioMate enforces four safety QC gates between ADMET profiling and any progression decision:

**hERG Cardiotoxicity Gate** (Sanguinetti & Tristani-Firouzi 2006, Nature 440:463-469)
- GOLD blocking: hERG IC50 < 1 μM — compound flagged as high cardiotoxicity risk; workflow halts
- SILVER advisory: hERG IC50 1–10 μM — advisory warning logged, progression requires documented override

**DILI Gate** (Chen et al. 2016, Drug Metab Dispos 44:1581-1591)
- GOLD blocking: DILIrank "Most-DILI-Concern" classification — known hepatotoxin; workflow halts
- SILVER advisory: DILIrank "Less-DILI-Concern" — advisory flag; proceed with caution note

**Ames Mutagenicity Gate** (ICH S2(R1) guideline)
- SILVER advisory: positive Ames prediction from ADMET output — genotoxicity advisory before IND

**ClinTox Gate** (Clinical Trials database-trained classifier)
- SILVER advisory: ClinTox probability > 0.8 — clinical failure flag before Phase I commitment

These four gates are enforced in sequence in the end-to-end `drug_discovery/main.nf` pipeline. Any GOLD-level failure stops the run and emits a structured QC failure event via SSE to the BioMate frontend.

#### Drug Combination Safety and DDI

- **`check_drug_combination_safety`** — Screens a combination of drug SMILES/names against a DDI database; returns interaction severity classification
- **`find_alternative_drugs_ddinter`** — Given a drug with known DDI, finds mechanistically similar alternatives with fewer interactions via DDInter
- **`query_drug_interactions`** — FDA-sourced drug interaction signal query

#### PK Modeling — Simulation (Preclinical)

Three ODE-based PK simulation modules for preclinical dose projection:

**`pk_ode_system`** — 1-compartment oral PK model:
- Parameters: ka (absorption rate constant), ke (elimination rate constant), Vd (volume of distribution), dose
- Output: time-concentration profile at user-specified sampling times
- Use case: First-in-animal dose range estimation from in vitro ADMET CL/Vd estimates

**`bi_exp_model`** — 2-compartment IV/oral PK model (bi-exponential):
- Parameters: A, alpha, B, beta (disposition coefficients and hybrid rate constants)
- Output: bi-exponential concentration decay curve
- Use case: IV bolus PK with distribution phase (most small molecules in rodent PK studies)

**`simulate_thyroid_hormone_pharmacokinetics`** — Specialized thyroid hormone PK ODE system (TSH feedback loop included). Relevant for drugs affecting thyroid function.

**`sigmoid`** — Sigmoid Emax PD model:
- Parameters: Emax, EC50, Hill coefficient (n)
- Use case: Dose-response curve fitting; Hill coefficient estimation for mechanistic understanding

#### PK Modeling — Phase I Clinical (New)

**`nca_pknca`** — Non-compartmental analysis via the PKNCA R package:
- Input: individual subject concentration-time data (CSV)
- Computes: AUC₀₋∞ (linear-log trapezoidal), AUC₀₋t, Cmax, Tmax, t½, CL/F, Vz/F, MRT
- QC gates: minimum measurable concentration count (flags sparse profiles); lambda-z R² gate for reliable terminal slope estimation
- Output: regulatory-grade NCA parameter table (per subject + geometric mean summary); auto-generated plot PDF

**`nlmixr2_population_pk`** — Population PK/PD via nlmixr2 (SAEM algorithm):
- Model library: 1-compartment oral, 2-compartment oral, 2-compartment IV, user-specified ODE
- Between-subject variability (BSV) on CL, Vd, ka with log-normal ETA distributions
- Residual error: proportional, additive, or combined
- QC governance:
  - GOLD gate: convergence status (non-converged run flagged and blocked)
  - SILVER gate: ETA shrinkage < 30% (high shrinkage = parameters poorly estimated)
  - BRONZE gate: condition number < 1000 (numerical stability)
- Output: population parameter estimates (θ, ω², σ²); individual Bayes post-hoc estimates; VPC (visual predictive check) plots; OFV/AIC/BIC; ETA shrinkage report
- Regulatory note: nlmixr2 implements SAEM (identical to Monolix's algorithm) and FOCE+ (equivalent to NONMEM FOCE); benchmarked against NONMEM in Fidler et al. 2019 (CPT Pharmacometrics Syst Pharmacol 8:731-740)

#### Preclinical In Vivo

**`analyze_xenograft_tumor_growth_inhibition`** — Analyzes tumor growth curves from xenograft studies:
- Computes TGI % at specified time points
- Fits exponential growth models to vehicle and treatment arms
- Statistical comparison of growth rates

**`estimate_alpha_particle_radiotherapy_dosimetry`** — Absorbed dose calculation for targeted alpha therapy
**`analyze_radiolabeled_antibody_biodistribution`** — Tissue distribution analysis for radioconjugates (%ID/g, tumor-to-organ ratios)

#### Formulation and CMC

**`analyze_in_vitro_drug_release_kinetics`** — Fits four kinetic models to dissolution data:
- Zero-order: `Q = Q₀ + k₀t` (erosion-controlled)
- First-order: `ln(Q) = ln(Q₀) - k₁t` (porous matrix)
- Higuchi: `Q = kₕ√t` (diffusion from matrix)
- Korsmeyer-Peppas: `Q/Q∞ = kₚtⁿ` — release exponent n discriminates Fickian (n ≈ 0.43) from anomalous (0.43 < n < 0.85) from Case II transport (n ≈ 0.85)
- Selects best-fit model by R² and AIC; outputs parameters with 95% CI

**`analyze_accelerated_stability_of_pharmaceutical_formulations`** — ICH Q1A(R2)/Q1B-compliant shelf-life estimation:
- Arrhenius-based extrapolation from accelerated conditions (40°C/75%RH) to long-term storage (25°C/60%RH)
- Outputs: predicted shelf life at target storage condition; degradation rate constant k; 95% CI on shelf-life estimate

#### Pharmacogenomics — Precision Dosing

**`perform_mwas_cyp2c19_metabolizer_status`** — CYP2C19 metabolizer phenotype from WGS/genotyping data; outputs EM/IM/PM/UM classification for dosing guidance.

**PGx CYP gene coverage QC gate** — Applied before any PGx interpretation:
- GOLD blocking: coverage < 30× on any of CYP2D6, CYP2C19, CYP3A4, DPYD, TPMT (CPIC guidelines: cpicpgx.org)
- Named profiles: `pgx_clinical` (30× CPIC-compliant), `pgx_research` (15× with advisory flags on low-coverage genes)

#### FDA Post-market Surveillance

The end-to-end pipeline includes FDA surveillance as its final stage. Standalone queries are also available:

- **`analyze_fda_safety_signals`** — Disproportionality analysis (PRR, ROR) on FAERS adverse event data for a drug or drug class
- **`query_fda_adverse_events`** — Direct FAERS query by drug name, reaction term, or MedDRA code
- **`query_drug_interactions`** — FDA-sourced interaction signal mining
- **`query_drug_labels`** — Current prescribing information retrieval
- **`check_fda_drug_recalls`** — Active and historical recall search
- **`get_fda_drug_label_info`** — Structured label section extraction (indications, contraindications, PK data, warnings)

#### Representative Nextflow Command — Drug Developer

```bash
# Lead optimization run: compound SMILES file through full ADMET + safety triage pipeline
# with hERG/DILI gates enforced, using druglike compound profile.
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/workflows/drug_discovery/main.nf \
  -profile docker \
  --smiles_file /data/lead_series/ERK2_inhibitors_v3.csv \
  --run_admet true \
  --run_docking false \
  --qc_profile compound_druglike \
  --outdir /results/lead_opt_20260301/

# Phase I NCA from clinical PK sparse sampling data
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/nca_pknca/main.nf \
  -profile docker \
  --pk_data /data/phase1/cohort1_pk_concentrations.csv \
  --dose 10 \
  --dose_unit mg \
  --weight_normalized true \
  --outdir /results/phase1_nca_20260301/

# Population PK fitting (nlmixr2, SAEM, 2-compartment oral)
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/nlmixr2_population_pk/main.nf \
  -profile docker \
  --pk_data /data/phase1/pooled_pk_all_cohorts.csv \
  --model two_compartment_oral \
  --algorithm saem \
  --bsv_params CL,Vd,ka \
  --qc_profile pgx_clinical \
  --outdir /results/popPK_20260301/
```

The BioMate AI assistant accepts equivalent natural-language input: *"Run ADMET profiling and safety triage on our 48 ERK2 inhibitor SMILES, flag any hERG or DILI concerns, then fit a 2-compartment population PK model to our Phase I data."*

---

## 5. QC Governance Summary

BioMate applies a three-tier evidence-graded QC system across all drug development domains. Evidence levels follow the governance framework defined in the BioMate QC paper (Paper 1, biomate_qc_governance_paper):

- **GOLD**: Universally accepted threshold with multiple independent validations; failure blocks workflow execution
- **SILVER**: Strong evidence from domain-specific standards or major guidelines; failure blocks workflow execution (advisory variant is non-blocking)
- **BRONZE**: Community heuristic or single-source evidence; advisory only (never blocks)

### Complete QC Gate Table

| Domain | Process | Metric | Level | Threshold | Citation |
|---|---|---|---|---|---|
| **Cryo-EM SPA** | Motion correction | Total motion drift | GOLD | < 50 Å | CryoSPARC documentation; MotionCor2 best practices |
| **Cryo-EM SPA** | Motion correction | Per-frame drift | BRONZE advisory | < 3 Å/frame | Community heuristic |
| **Cryo-EM SPA** | CTF estimation | CTF fit quality | GOLD | ≥ 0.7 (Thon ring correlation) | CTFFIND4 documentation; Rohou & Grigorieff 2015, JSB |
| **Cryo-EM SPA** | CTF estimation | Astigmatism | BRONZE advisory | < 1000 Å | No published consensus; fit quality is primary gate |
| **Cryo-EM SPA** | CTF estimation | Ice thickness | BRONZE advisory | < 50% thick | ctf_diagnostics.json heuristic |
| **Cryo-EM SPA** | CTF phase plate | Phase shift (VPP) | SILVER advisory | 0.2–1.5 rad (< 0.2 depleted; > 1.5 over-charged) | Phase plate manufacturer guidelines |
| **Cryo-EM SPA** | 2D classification | Junk fraction | GOLD | < 70% junk classes | CryoSPARC SPA best practices |
| **Cryo-EM SPA** | 2D classification | Junk fraction (advisory) | SILVER advisory | < 50% junk | CryoSPARC SPA recommendations |
| **Cryo-EM SPA** | Refinement | Orientation anisotropy ratio | GOLD | < 10× (best:worst view ratio) | 3DFSC; Tan et al. 2017, Nat Methods |
| **Cryo-EM SPA** | Refinement | Orientation anisotropy (advisory) | SILVER advisory | < 5× | ibid. |
| **Cryo-EM SPA** | Sharpening | B-factor | BRONZE advisory | −300 to 0 Å² | Rosenthal & Henderson 2003, JMB; typical range −100 to −250 Å² |
| **Cryo-EM SPA** | Local resolution | Spread (σ) | BRONZE advisory | < 3.0 Å | cryoSPARC documentation |
| **Proteomics (DDA)** | MaxQuant | PSM FDR | GOLD | < 1% | Elias & Gygi 2007, Nat Methods 4:207-214 |
| **Proteomics (DDA)** | MaxQuant | Protein FDR | GOLD | < 1% | Elias & Gygi 2007, Nat Methods 4:207-214 |
| **Proteomics (DDA)** | MaxQuant | Mass accuracy | GOLD | < 5 ppm | Instrument standard (Orbitrap) |
| **Proteomics (DDA)** | MaxQuant | Missed cleavage rate | SILVER | < 20% | EuBIC 2018 community standards; nf-core/proteomics |
| **Proteomics (DDA)** | MaxQuant | LFQ CV (technical replicates) | SILVER | < 20% | EuBIC 2018 community standards |
| **Proteomics (DDA)** | MaxQuant | Oxidized Met fraction | BRONZE advisory | < 30% | Sample handling heuristic |
| **Proteomics (DDA)** | MaxQuant | RT drift across runs | BRONZE advisory | < 2 min | PTXQC community heuristic |
| **Proteomics (DIA)** | DIA-NN | Protein FDR | GOLD | < 1% | Universal proteomics standard |
| **Proteomics (DIA)** | DIA-NN | Precursor FDR | GOLD | < 1% | Universal proteomics standard |
| **Proteomics (DIA)** | DIA-NN | Peptide CV across replicates | SILVER | < 15% | DIA community best practices (Spectronaut/DIA-NN) |
| **Proteomics (DIA)** | DIA-NN | Library coverage | SILVER | > 60% of spectral library detected | DIA-NN / Spectronaut best practices |
| **Chemoproteomics** | Pulldown | Enrichment ratio (bait:control) | SILVER | ≥ 3× | Cellzome / affinity proteomics community standard |
| **Chemoproteomics** | Pulldown | Bait peptides detected | SILVER advisory | > 0 peptides | Standard QC checkpoint |
| **Chemoproteomics** | Pulldown | CRAPome contamination | BRONZE advisory | < 50% | CRAPome database (Mellacheruvu et al. 2013, Nat Methods) |
| **Compound / SMILES** | Structure validation | RDKit SMILES validity | GOLD | 0 invalid SMILES | Whitehead et al. 2022, J Chem Inf Model (15% ChEMBL error rate) |
| **Compound / SMILES** | Structure validation | Salt stripping | SILVER advisory | Auto-stripped; transform logged | RDKit MolStandardize best practice |
| **Compound / SMILES** | Structure validation | Undefined stereocenters | SILVER advisory | 0 undefined | Cheminformatics best practice |
| **Compound / SMILES** | Structure validation | Molecular weight | BRONZE advisory | < 900 Da (peptidomimetic), < 500 Da (druglike) | Lipinski Ro5 (Lipinski et al. 2001, Adv Drug Deliv Rev) |
| **Drug Safety** | ADMET output | hERG IC50 | GOLD | > 1 μM (blocking if < 1 μM) | Sanguinetti & Tristani-Firouzi 2006, Nature 440:463-469 |
| **Drug Safety** | ADMET output | hERG IC50 (advisory) | SILVER advisory | > 10 μM recommended (1–10 μM = advisory) | ibid. |
| **Drug Safety** | ADMET output | DILI (DILIrank) | GOLD | Not "Most-DILI-Concern" | Chen et al. 2016, Drug Metab Dispos 44:1581-1591 |
| **Drug Safety** | ADMET output | DILI (DILIrank, advisory) | SILVER advisory | Not "Less-DILI-Concern" | ibid. |
| **Drug Safety** | ADMET output | Ames mutagenicity | SILVER advisory | Negative prediction | ICH S2(R1) guideline (EMA/CHMP/ICH/126642/2008) |
| **Drug Safety** | ADMET output | ClinTox probability | SILVER advisory | < 0.8 | Clinical Trials toxicity classifier; Gayvert et al. 2016 |
| **Pharmacogenomics** | WGS / targeted panel | CYP2D6 coverage | GOLD | ≥ 30× per gene | CPIC guidelines (cpicpgx.org); Clinical Pharmacology & Therapeutics |
| **Pharmacogenomics** | WGS / targeted panel | CYP2C19 coverage | GOLD | ≥ 30× per gene | CPIC guidelines |
| **Pharmacogenomics** | WGS / targeted panel | CYP3A4 coverage | GOLD | ≥ 30× per gene | CPIC guidelines |
| **Pharmacogenomics** | WGS / targeted panel | DPYD coverage | GOLD | ≥ 30× per gene | CPIC guidelines (fluoropyrimidine dosing) |
| **Pharmacogenomics** | WGS / targeted panel | TPMT coverage | GOLD | ≥ 30× per gene | CPIC guidelines (thiopurine dosing) |
| **Pharmacogenomics** | WGS / targeted panel | CYP gene coverage (research) | SILVER advisory | ≥ 15× (advisory below 30×) | `pgx_research` profile; CPIC lower bound |
| **Population PK** | nlmixr2 | Model convergence | GOLD | Converged (SAEM/FOCE+ status = SUCCESS) | Fidler et al. 2019, CPT Pharmacometrics Syst Pharmacol 8:731-740 |
| **Population PK** | nlmixr2 | ETA shrinkage | SILVER | < 30% per random effect | Savic & Karlsson 2009, AAPS J 11:558-569 |
| **Population PK** | nlmixr2 | Condition number | BRONZE advisory | < 1000 | nlmixr2 / NONMEM numerical stability standard |
| **Formulation** | Drug release | Korsmeyer-Peppas R² | BRONZE advisory | > 0.95 for model acceptance | Shah et al. 1999, Pharm Res (ICH Q8 context) |
| **Formulation** | Accelerated stability | Shelf-life model R² | SILVER | > 0.98 (Arrhenius fit) | ICH Q1A(R2); Q1E guideline |

### Named QC Profiles

| Profile Name | Domain | Key Adjustments vs. Default |
|---|---|---|
| `proteomics_standard` | DDA label-free lysate | Default DDA thresholds |
| `proteomics_phospho` | Phosphoproteomics enrichment | Lower minimum PSM count; phosphosite localization score ≥ 0.75 required |
| `proteomics_plasma_biomarker` | Depleted plasma DIA/DDA | Stricter CV < 15%; lower library coverage acceptable (plasma complexity) |
| `proteomics_chemoproteomics` | Affinity pulldown / ABPP | Enrichment ratio gate enforced (SILVER); CRAPome contamination monitored |
| `compound_druglike` | ADMET pre-filter | Lipinski Ro5: MW < 500 Da, logP < 5, HBD ≤ 5, HBA ≤ 10 |
| `compound_natural_product` | Natural product screening | Relaxed MW < 1000 Da; no logP limit |
| `compound_peptidomimetic` | Peptide-derived leads | MW < 900 Da; relaxed HBD/HBA limits |
| `pgx_clinical` | Clinical pharmacogenomics | CPIC-compliant 30× coverage on all 5 PGx genes (GOLD blocking) |
| `pgx_research` | Research PGx studies | 15× minimum with SILVER advisory on < 30× genes |

---

## 6. Technology Stack

### Workflow Execution Engine

**Nextflow DSL2 (nf-core standard)** — all BioMate pipelines follow nf-core module conventions: each module is an independent, versioned, containerized process with `meta` channel semantics. Pipelines are composed from modules using nf-core subworkflow patterns, enabling reuse across different end-to-end workflows. Workflow state is checkpointed; interrupted runs resume from the last completed stage (`-resume` flag).

### Container Strategy

- **Docker** — default for local and cloud development; all 25 pharmacology subworkflows have Docker container specifications
- **Singularity** — supported via `-profile singularity`; required for HPC/SLURM environments that do not allow Docker daemon
- **Open-source cryo-EM profile** — maps each process to a specific versioned container (RELION 3.1, CTFFIND4, Topaz, Phenix) instead of a monolithic CryoSPARC container; no commercial license required

### Compute Backends

| Backend | Configuration | Use Case |
|---|---|---|
| Local | `executor = 'local'` (default) | Development and small datasets |
| SLURM | `executor = 'slurm'`; configurable queue, walltime, memory | HPC clusters; cryo-EM GPU jobs |
| AWS Batch | `executor = 'awsbatch'`; S3 work directory | Cloud-scale virtual screening; population PK large datasets |
| AWS GPU | `local_gpu` or `multi_gpu` profile | CryoSPARC-based SPA on g6.2xlarge or multi-GPU instances |

Per-invocation compute configuration overrides are supported from the BioMate settings UI (`Compute` tab): executor type, SLURM queue, AWS S3 bucket, and local output directory can be set globally or overridden per workflow invocation.

### BioMate AI Assistant Layer

The BioMate frontend provides a conversational AI interface (Claude Sonnet / Anthropic API) that:
- Interprets natural-language research questions and maps them to specific Nextflow workflow invocations
- Generates `workflow_artifact` objects with pre-filled parameters, QC profile selection, and compute configuration
- Streams workflow progress and QC gate events to the UI via Server-Sent Events (SSE)
- Enforces QC gate decisions through the QC gate modal (block / override with justification)
- Tracks per-workflow LLM token costs and Batch compute costs through the billing infrastructure (Redis + AWS Lambda)

### Drug-Domain Data Sources

| Source | Integration |
|---|---|
| OpenFDA / FAERS | `query_fda_adverse_events`, `analyze_fda_safety_signals`, `check_fda_drug_recalls` |
| DDInter | `find_alternative_drugs_ddinter`, `query_drug_interactions` |
| TxGNN disease-drug network | `retrieve_topk_repurposing_drugs_from_disease_txgnn` |
| DILIrank (FDA) | DILI QC gate lookup |
| CPIC (cpicpgx.org) | PGx coverage thresholds |
| CRAPome | Chemoproteomics contamination advisory |
| PubChem / HMDB / GNPS | LC-MS Agent compound annotation |
| DeepPurpose model zoo | ADMET prediction (MPNN, CNN, Morgan) |

### LC-MS Agent (Standalone)

A separately deployable LC-MS intelligence platform at `/home/yzhang/biomate/LC-MS-agent/`:
- 5 AI agents: methodology design, troubleshooting, workflow planning, report generation, parameter optimization
- RAG knowledge base: Milvus vector database, sources including vendor documentation (Thermo, Agilent, Waters, Sciex, Bruker, Shimadzu), PubMed, community forums
- Tool integrations: ProteoWizard, OpenMS, MZmine 3, XCMS (R), MetaboAnalyst, PubChem/HMDB/GNPS compound search
- FastAPI backend + Streamlit frontend; integration with BioMate's main platform in progress

---

## Appendix: Workflow Location Reference

All workflows are located under `backend/` in the BioMate repository:

| Workflow Category | Path |
|---|---|
| End-to-end drug discovery | `biomni_workflows/nextflow_nfcore/workflows/drug_discovery/main.nf` |
| Pharmacology subworkflows (25) | `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/*/main.nf` |
| DrugCLIP virtual screening | `nf-core-workflows/modules/biomate-ai-tools/drugclip/main.nf` |
| Bioengineering / drug release (13) | `biomni_workflows/nextflow_nfcore/subworkflows/bioengineering/*/main.nf` |
| Cryo-EM SPA pipeline (15 modules) | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/spa_full_pipeline/main.nf` |
| Cryo-EM individual modules | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/*/main.nf` |
| QC governance layer | `lib/galaxy/jobs/qc_trace_monitor.py` |
| Nextflow executor | `lib/galaxy/webapps/galaxy/api/nextflow_executor_v2.py` |
