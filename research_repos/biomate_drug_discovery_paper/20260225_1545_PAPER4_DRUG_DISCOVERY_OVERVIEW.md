# Paper 4: Drug Discovery QC Governance — Nature Chemical Biology
**Date:** 2026-02-25 15:45
**Target journal:** Nature Chemical Biology (IF ~14) or Molecular & Cellular Proteomics (IF ~7)
**Target submission:** Month 30 (~August 2028)
**Status:** Workflows exist; QC governance layer not yet built; co-authors needed

---

## Core Claim

Evidence-graded QC governance reduces false-positive drug discovery hits and improves ADMET prediction reliability by gating on input data quality before expensive downstream computation. Three concrete domains: proteomics (LC-MS/MS), compound structure (SMILES QC), and pharmacogenomics (WGS → drug response).

---

## Domain 1: Proteomics (LC-MS/MS) — BUILD THIS FIRST

### Why proteomics, not metabolomics

Proteomics has the most mature, unambiguous QC standards in all of mass spectrometry:
- PSM/protein FDR 1% is **universally accepted** (Elias & Gygi 2007, Nature Methods)
- HUPO-PSI published **mzQC** format (Bittremieux et al. 2023, MCP) — 100+ community QC metrics
- nf-core/diaproteomics pipeline already exists and produces standardized outputs
- BioMate already lists diaproteomics in workflow catalog

Metabolomics by contrast: < 30% of features get confident IDs, no universal QC standard, highly fragmented.

### Three proteomics use cases for drug discovery

**Use Case A: Target Identification (Affinity Proteomics)**
- Pulldown + LC-MS/MS to identify what a drug actually binds
- Thermal Proteome Profiling (TPP), chemoproteomics, CETSA
- Silent QC failure: low protein FDR → false-positive target identifications → wrong MOA hypothesis → failed validation

**Use Case B: Mechanism of Action (Phosphoproteomics)**
- Kinase inhibitor treatment → measure phosphorylation changes across proteome
- Standard at Cellzome (GSK), Pfizer chemoproteomics platform
- Silent QC failure: poor phosphopeptide enrichment → missed key signaling events → incomplete MOA

**Use Case C: Plasma Biomarker Discovery (Drug Response)**
- Plasma proteomics before/after drug treatment
- FDA-cleared protein biomarkers all go through LC-MS validation
- Silent QC failure: quantification CV > 20% → false biomarker candidates → failed clinical validation

### Proteomics QC Governance Layer (to build)

Governance schema based on **mzQC** (HUPO-PSI standard). BioMate adopts mzQC metric IDs.

| Metric | Evidence Level | Threshold | Source | Tool Output |
|---|---|---|---|---|
| PSM FDR | **GOLD** | < 1% | Elias & Gygi 2007, Nat Methods | MaxQuant `msms.txt` |
| Protein FDR | **GOLD** | < 1% | Same | MaxQuant `proteinGroups.txt` |
| Mass accuracy | **GOLD** | < 5 ppm | Instrument standard | MaxQuant `summary.txt` |
| Missed cleavages | **SILVER** | < 20% | nf-core/proteomics; EuBIC 2018 | MaxQuant `peptides.txt` |
| Phosphosite localization | **SILVER** | score > 0.75 | Beausoleil et al. 2006, Nat Biotech | MaxQuant `Phospho(STY)Sites.txt` |
| Label-free quant CV | **SILVER** | < 20% (technical reps) | EuBIC 2018 community standards | MaxQuant `proteinGroups.txt` |
| Oxidized Met fraction | **BRONZE** | < 30% | Sample handling heuristic | MaxQuant `peptides.txt` |
| RT drift across runs | **BRONZE** | < 2 min | PTXQC community heuristic | MaxQuant `summary.txt` |

**DIA-NN specific (for DIA proteomics):**
| Metric | Evidence Level | Threshold | Source |
|---|---|---|---|
| Precursor FDR | **GOLD** | < 1% | Universal |
| Peptide CV | **SILVER** | < 15% across replicates | DIA community practice |
| Library coverage | **SILVER** | > 60% of spectral library detected | Spectronaut/DIA-NN best practices |

**Named profiles (3):**
- `proteomics_standard` — DDA, label-free, standard cell lysate
- `proteomics_phospho` — phosphoproteomics enrichment (lower PSM count acceptable, higher localization requirement)
- `proteomics_plasma_biomarker` — depleted plasma, stricter CV (< 15%), lower library coverage acceptable

**Implementation effort:** ~5 days backend
- `_parse_maxquant_metrics()` — 1 day
- `_parse_diann_metrics()` — 1 day
- `_check_qc_thresholds()` proteomics branch — 1 day
- Named profiles — 0.5 day
- Tests — 1 day

---

## Domain 2: Compound Structure QC (ADMET Gateway)

### The problem

15% of ChEMBL compounds have SMILES errors that systematically bias ADMET predictions (Whitehead et al. 2022, J Chem Inf Model). BioMate runs ADMET_pred and predict_admet_properties on SMILES input — no validation gate exists before these expensive calls.

### Governance layer (to build)

| Check | Evidence Level | Action |
|---|---|---|
| SMILES parseable by RDKit | **GOLD** | Hard gate — reject invalid SMILES before any prediction |
| Salt stripped | **SILVER** | Auto-strip salts; log the transformation |
| Stereochemistry complete | **SILVER** | Warn if undefined stereocenters > 0 |
| Molecular weight in drug space | **BRONZE** | Warn if MW > 900 Da (beyond Ro5 space) |
| Tautomer standardized | **BRONZE** | Apply MolVS standardization; log |

**Named profiles:**
- `compound_druglike` — Lipinski Ro5 space (MW < 500, logP < 5, HBD < 5, HBA < 10)
- `compound_natural_product` — relaxed MW gate (< 1000 Da), no logP limit
- `compound_peptidomimetic` — MW < 900, allow more HBD/HBA

**Implementation effort:** ~2 days (uses RDKit, already in the biomate/biomni-tools container)

---

## Domain 3: Pharmacogenomics from WGS

### The problem

CYP2D6, CYP2C19, CYP3A4, DPYD, TPMT variants determine standard-of-care drug dosing (CPIC guidelines). Variant calls in these genes at low coverage (< 8x) produce unreliable star allele assignments → wrong dose recommendations → patient harm in clinical translation.

BioMate's WGS coverage gate (30x genome-wide) is necessary but not sufficient — PGx genes can be covered at 8x even in a 30x library due to GC bias (CYP2D6 is notoriously GC-rich).

### Governance layer (to build)

| Metric | Evidence Level | Threshold | Source |
|---|---|---|---|
| CYP gene min coverage | **GOLD** | ≥ 30x per PGx gene | CPIC guidelines (cpicpgx.org) |
| VQSR PASS rate | **GOLD** | > 95% of called variants | GATK Best Practices |
| Ti/Tv ratio (WGS) | **SILVER** | 2.0–2.1 (WGS), 3.0–3.3 (WES) | GATK documentation |
| Het/Hom ratio | **SILVER** | 1.5–2.5 for unrelated individuals | Population genetics standard |
| CYP2D6 copy number | **BRONZE** | Flag if CNV detected (impacts star allele) | PharmVar guidelines |

**Named profiles:**
- `pgx_clinical` — strict 30x PGx gene coverage; CPIC-compliant
- `pgx_research` — 15x acceptable with lower confidence calls flagged as advisory

**Implementation effort:** ~2 days (parse GATK `.g.vcf` coverage metrics + mosdepth per-gene output)

---

## PK/PD Modeling: Honest Capability Assessment

### What BioMate CAN do today

| Capability | Status | Implementation |
|---|---|---|
| 1-compartment oral PK simulation | ✅ Yes | `pk_ode_system` workflow (ka, ke, Vd parameters) |
| 2-compartment IV/oral PK simulation | ✅ Yes | `bi_exp_model` workflow (A, alpha, B, beta) |
| Thyroid hormone PK simulation | ✅ Yes | `simulate_thyroid_hormone_pharmacokinetics` |
| Sigmoid Emax PD model | ✅ Yes | `sigmoid` workflow |
| Xenograft tumor growth inhibition | ✅ Yes | `analyze_xenograft_tumor_growth_inhibition` |
| VCOG-CTCAE adverse event grading | ✅ Yes | `grade_adverse_events_using_vcog_ctcae` |
| FDA adverse event signal analysis | ✅ Yes | `analyze_fda_safety_signals` |
| Drug combination safety checking | ✅ Yes | `check_drug_combination_safety` |
| Radiotherapy dosimetry (alpha particle) | ✅ Yes | `estimate_alpha_particle_radiotherapy_dosimetry` |
| Biodistribution analysis | ✅ Yes | `analyze_radiolabeled_antibody_biodistribution` |
| CYP2C19 metabolizer phenotyping | ✅ Yes | `perform_mwas_cyp2c19_metabolizer_status` |
| In vitro drug release kinetics | ✅ Yes | `analyze_in_vitro_drug_release_kinetics` |
| Formulation stability (accelerated) | ✅ Yes | `analyze_accelerated_stability_of_pharmaceutical_formulations` |

### What BioMate CANNOT do today (NONMEM/Monolix territory)

| Capability | Status | Why missing | Feasible to add? |
|---|---|---|---|
| Population PK/PD (NONMEM) | ❌ No | Proprietary license ($50K/year); NONMEM requires SAS/FORTRAN runtime | Partial — see nlmixr2 below |
| Population PK/PD (Monolix) | ❌ No | Commercial license; GUI-based; not Nextflow-compatible | Partial — see nlmixr2 below |
| Non-compartmental analysis (NCA) | ❌ No | Not implemented | Yes — PKNCA (R, open source) ~1 week |
| Bioequivalence testing | ❌ No | Requires NCA first | Yes — after NCA |
| PBPK modeling (physiologically-based) | ❌ No | PK-Sim/MoBi (open source but complex) | Medium — PK-Sim has CLI mode |
| Dose-finding design (BOIN, CRM) | ❌ No | Not implemented | Yes — R packages ~1 week |
| Between-subject variability (BSV) estimation | ❌ No | Requires population PK framework | Partial via nlmixr2 |
| FDA regulatory NDA/IND submission format | ❌ No | Requires NONMEM compliance validation | Not near-term |

### The Open-Source NONMEM Alternative: nlmixr2

**nlmixr2** is an R package implementing SAEM (the same algorithm Monolix uses) + FOCE+ (equivalent to NONMEM's FOCE method). It is:
- Open source (GPL-2)
- Nextflow-compatible via an R container
- Validated against NONMEM output in published benchmarks (Fidler et al. 2019, CPT Pharmacometrics Syst Pharmacol)
- Used by FDA reviewers for parallel analysis

**Adding nlmixr2 to BioMate:** ~2 weeks implementation
- `nextflow_nlmixr2_popPK` module: takes individual PK data CSV → fits 1/2-compartment population model → outputs ETA shrinkage, OFV, VPC plots
- QC governance layer: convergence status (GOLD gate), ETA shrinkage < 30% (SILVER), condition number < 1000 (BRONZE)

**This enables the PK/PD claim in Paper 4:** "BioMate provides governed population PK analysis using nlmixr2, an FDA-recognized NONMEM alternative, with QC gates on model convergence quality."

---

## Toxicity: What Exists and What Is Missing

### Implemented ✅
- VCOG-CTCAE adverse event grading (animal studies)
- FDA safety signal analysis (post-market surveillance)
- Xenograft tumor growth inhibition (preclinical in vivo)
- In vitro drug release kinetics + formulation stability

### Not Implemented ❌
| Missing | Priority | Effort to add |
|---|---|---|
| hERG cardiotoxicity prediction gate (before ADMET prediction) | High | 2 days — parse hERG IC50 from ADMET output; gate < 1 μM as high-risk |
| DILI (drug-induced liver injury) risk gate | High | 2 days — DILIrank integration; GOLD gate on known DILI compounds |
| Ames mutagenicity gate | Medium | 1 day — AMES test result from ADMET output |
| In vitro-in vivo correlation (IVIVC) | Medium | 1 week — requires dissolution + PK data |
| PBPK for tissue distribution prediction | Low | 3 weeks — PK-Sim CLI wrapping |

---

## Publication Path Options

**Option A (Recommended):** Nature Chemical Biology
- Best fit for drug discovery + QC governance + proteomics story
- IF ~14, Springer Nature family (same as Nature Methods)
- Requires a clear drug discovery biological claim, not just a methods paper

**Option B:** Journal of Proteome Research (ACS)
- If proteomics domain dominates the story
- Faster review cycle (4–6 weeks typical)
- IF ~5; lower impact but high proteomics community readership

**Option C:** CPT: Pharmacometrics & Systems Pharmacology (Wiley/ACoP)
- If nlmixr2 PK/PD domain is strong enough
- The pharmacometrics community venue; IF ~4
- High adoption by FDA reviewers

**Strategy:** Submit proteomics + ADMET + PGx as Option A. If rejected, split into proteomics → Option B and PK/PD → Option C.

---

## Co-Authors Needed

| Role | Why needed |
|---|---|
| LC-MS proteomics expert | Validates MaxQuant/DIA-NN thresholds; mzQC familiarity |
| Pharma/CRO collaborator | Provides real (de-identified) screening LC-MS data for benchmark |
| Clinical pharmacogenomics researcher | CPIC contributor; validates PGx coverage thresholds |
| Pharmacokineticist / DMPK scientist | Validates PK/PD ODE implementations; nlmixr2 benchmarks |
| Toxicologist | Validates hERG/DILI/Ames governance layer design |

---

## Immediate Next Steps

1. **Build proteomics QC domain** (5 days) — MaxQuant + DIA-NN parsers, GOLD/SILVER/BRONZE governance, 3 named profiles, test suite
2. **Build SMILES structure QC gate** (2 days) — RDKit validation before ADMET workflows
3. **Add nlmixr2 Nextflow module** (2 weeks) — population PK capability with convergence QC gates
4. **Add NCA via PKNCA** (1 week) — non-compartmental analysis as NONMEM-free alternative
5. **Find pharma/CRO collaborator** for real benchmark data (Month 1–2)
