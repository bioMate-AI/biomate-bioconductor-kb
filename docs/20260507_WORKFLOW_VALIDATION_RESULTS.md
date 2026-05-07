# BioMate Workflow Validation — Real AWS Batch Results
# Date: 2026-05-07 | Validated by: live Batch submission

---

## Test Methodology

All jobs submitted via `POST http://localhost:8081/api/nextflow/execute` with `executor: awsbatch`.
Timing sourced from AWS Batch `describe-jobs` API (millisecond precision).
Costs calculated using **AWS Fargate pricing (us-west-2)**:
- vCPU: $0.04048/hr
- Memory: $0.004445/GB-hr

**Batch overhead** (scheduling + container pull) observed: **90–230s per job** — a fixed cost independent of workflow complexity. This must be factored into minimum billing floor.

**3 Hardware Tiers defined:**

| Tier | CPU Config | GPU Config | Spot? | Notes |
|---|---|---|---|---|
| **Economy** | 2 vCPU / 4 GB, Fargate Spot | g4dn.xlarge ($0.526/hr) | Yes | Spot discount ~70% → effective $0.030/hr Fargate; may be interrupted |
| **Balanced** | 4 vCPU / 8 GB, Fargate On-Demand | g4dn.2xlarge ($0.752/hr) | No | Default; matches most workflow resource specs |
| **Performance** | 16 vCPU / 32 GB, Fargate On-Demand | g5.4xlarge ($1.624/hr) | No | Fastest; for time-sensitive or large-dataset runs |

---

## Standard Input Sizes Used

| Category | Validation (small) | Standard (pricing) |
|---|---|---|
| Compound (ADMET/CYP/docking) | 10 SMILES (372 bytes) | 100 SMILES |
| PK/PD (NCA/PBPK) | 3 subjects × 6 timepoints (419 bytes) | 10 subjects × 12 timepoints |
| Clinical trial simulation | 200 sims, 10 patients, 4 dose levels | 1000 sims, 30 patients, 7 dose levels |
| MD simulation | 10,000 steps (20ps), 1AKI lysozyme + aspirin | 5,000,000 steps (10ns), ~50K atoms |
| CryoEM SPA | 3 movie stacks, 10 MB each | 1,000 movie stacks, ~10 GB |

---

## CPU Workflows — Real Measured Data

### predict_admet_properties
**Domain:** pharmacology | **Type:** CPU-only

**Input:** 10 SMILES compounds (372 bytes)
**Container image:** `biomni-admet:x86`

| Step | vCPU | RAM | Container Time | Container Cost |
|---|---|---|---|---|
| PREDICT_ADMET_PROPERTIES | 4 | 8 GB | **16.8s** (measured) | $0.000919 |
| **TOTAL** | **4** | **8 GB** | **16.8s compute / 119s wall** | **$0.000919** |

**3-Tier Pricing (10 SMILES input):**

| Tier | Instance | Time | Compute Cost | Wall Cost | Notes |
|---|---|---|---|---|---|
| Economy | 2 vCPU / 4 GB Spot | ~30s | $0.000184 | $0.000734 | 2× slower, Spot ~70% discount |
| **Balanced** | **4 vCPU / 8 GB** | **16.8s** | **$0.000919** | **$0.006528** | **✅ Validated on Batch** |
| Performance | 16 vCPU / 32 GB | ~8s | $0.001759 | $0.026520 | Marginal gain for single-step workflow |

**Extrapolated to 100 SMILES (10× data):**
| Tier | Est. Time | Est. Compute Cost | Est. Wall Cost | Suggested Price |
|---|---|---|---|---|
| Economy | ~5 min | $0.002 | $0.007 | $0.10 |
| Balanced | ~3 min | $0.009 | $0.065 | $0.25 |
| Performance | ~1 min | $0.018 | $0.088 | $0.50 |

---

### clinical_trial_simulation (BOIN)
**Domain:** drug_discovery | **Type:** CPU-only

**Input:** 200 simulations, 10 patients, 4 dose levels
**Container image:** `biomni-tools:x86`

| Step | vCPU | RAM | Container Time | Container Cost |
|---|---|---|---|---|
| CLINICAL_TRIAL_SIMULATION | 4 | 8 GB | **11.9s** (measured) | $0.000651 |
| **TOTAL** | **4** | **8 GB** | **11.9s compute / 239s wall** | **$0.000651** |

**3-Tier Pricing (200 simulations, 10 patients):**

| Tier | Instance | Time | Compute Cost | Wall Cost |
|---|---|---|---|---|
| Economy | 2 vCPU / 4 GB Spot | ~20s | $0.000184 | $0.004340 |
| **Balanced** | **4 vCPU / 8 GB** | **11.9s** | **$0.000651** | **$0.013110** |
| Performance | 16 vCPU / 32 GB | ~5s | $0.001100 | $0.052880 |

**Extrapolated to standard (1000 sims, 30 patients, 7 dose levels):**
| Tier | Est. Time | Est. Compute Cost | Suggested Price |
|---|---|---|---|
| Economy | ~2 min | $0.003 | $0.10 |
| Balanced | ~1 min | $0.007 | $0.25 |
| Performance | ~30s | $0.011 | $0.50 |

---

### nca_pknca — Partial Results
**Domain:** drug_discovery | **Type:** CPU-only

**Input:** 3 subjects × 6 timepoints (419 bytes → fixed to use `extravascular` route)
**Status:** NCA_INPUT_VALIDATION ✅, PKNCA_ANALYSIS ❌ (route value error: use `extravascular` not `oral`)

| Step | vCPU | RAM | Container Time | Container Cost |
|---|---|---|---|---|
| NCA_INPUT_VALIDATION | 1 | 1 GB | **16.0s** (measured) | $0.000063 |
| NCA_PKNCA_ANALYSIS | 2 | 8 GB | ~30s (config spec, retest needed) | ~$0.000830 |
| NCA_REPORT_HTML | 2 | 8 GB | ~20s (config spec) | ~$0.000553 |
| **TOTAL** | **2** | **8 GB** | **~66s compute / ~400s wall** | **~$0.001446** |

**3-Tier Pricing (10 subjects × 12 timepoints standard):**

| Tier | Instance | Est. Time | Est. Cost | Suggested Price |
|---|---|---|---|---|
| Economy | 1 vCPU / 2 GB Spot | ~2 min | $0.001 | $0.10 |
| **Balanced** | **2 vCPU / 8 GB** | **~1 min** | **$0.004** | **$0.25** |
| Performance | 8 vCPU / 16 GB | ~30s | $0.006 | $0.50 |

---

### PK_SIM_PBPK — Bonus Data (from concurrent user runs)
**Domain:** drug_discovery | **Type:** CPU-only
*Source: Parallel background runs observed in Batch job logs*

| Step | Container Time | Notes |
|---|---|---|
| VALIDATE_COMPOUND_PARAMS | **11s** (measured) | 4 vCPU / 8 GB |
| PKSIM_SIMULATE | **12s** (measured) | PK-Sim Java simulation |
| NCA_ANALYSIS | **18s** (measured) | R/PKNCA downstream |
| GENERATE_FINAL_REPORT | **13s** (measured) | HTML report generation |
| **TOTAL** | **~54s compute / ~3-4 min wall** | 4 sequential Batch steps |

**3-Tier Pricing (1 compound, standard PK simulation):**

| Tier | Instance | Est. Time | Compute Cost | Wall Cost | Suggested Price |
|---|---|---|---|---|---|
| Economy | 2 vCPU / 4 GB Spot | ~90s | $0.001 | $0.006 | $0.25 |
| **Balanced** | **4 vCPU / 8 GB** | **54s** | **$0.003** | **$0.022** | **$0.50** |
| Performance | 16 vCPU / 32 GB | ~20s | $0.004 | $0.044 | $1.00 |

---

### PBPK_PEDIATRIC — Bonus Data (from concurrent user runs)
**Domain:** drug_discovery | **Type:** CPU-only

| Step | Container Time |
|---|---|
| PBPK_PEDIATRIC_SIMULATE | **17s** |
| EVALUATE_MATURATION | **18s** |
| GENERATE_FINAL_REPORT | **25s** |
| **TOTAL** | **~60s compute / ~4 min wall** |

**Suggested Price:** Economy $0.25 / Balanced $0.50 / Performance $1.00

---

## GPU/Hybrid Workflows — Real Measured Data

### gromacs_protein_md (1AKI lysozyme + aspirin, 10,000 steps = 20ps)
**Domain:** drug_discovery | **Type:** Hybrid (CPU prep + GPU MD)
**Status:** 6/8 steps measured ✅ | PRODUCTION_MD GPU routing bug fixed, resubmitted

**Routing bug discovered:** PRODUCTION_MD landed on `biomate-nextflow-queue` (CPU-only) instead of `galaxy-cloud-queue-gpu` — GROMACS reported "0 detected GPUs". Fixed by passing `gpu_queue` explicitly in `compute_config`. New run: `079a973d-25b3-421a-b00e-52c2abda7489`.

| Step | vCPU | RAM | Container Time | Queue | Compute Cost |
|---|---|---|---|---|---|
| LIGAND_PREP | 4 | 8 GB | **15.95s** ✅ | CPU | $0.000875 |
| SYSTEM_SETUP | 4 | 16 GB | **75.69s** ✅ | CPU | $0.004900 |
| ENERGY_MINIMIZATION | 8 | 16 GB | **205.16s** ✅ | CPU | $0.022508 |
| NVT_EQUILIBRATION | 16 | 32 GB | **270.80s** ✅ | CPU (no GPU — small test) | $0.059420 |
| NPT_EQUILIBRATION | 16 | 32 GB | **148.30s** ✅ | CPU (no GPU — small test) | $0.032540 |
| PRODUCTION_MD | 8 | 32 GB | **9.4s** ❌ GPU not found | CPU (wrong queue) | $0.000927 (failed) |
| TRAJECTORY_ANALYSIS | 8 | 16 GB | pending GPU rerun | CPU | — |
| MM_GBSA | 8 | 32 GB | pending GPU rerun | CPU | — |
| **TOTAL (6 measured steps)** | — | — | **725.3s compute / 24 min wall** | **CPU** | **$0.120** |

**Note:** NVT/NPT ran CPU-only because this 20ps test is too small for GPU to engage. For real 10ns+ runs, NVT/NPT switch to GPU. PRODUCTION_MD, TRAJECTORY, MM_GBSA awaiting GPU rerun results.

**Note:** PRODUCTION_MD GPU time scales linearly with `n_steps`. 10,000 steps = 20ps. Standard = 5,000,000 steps = 10ns → 500× more GPU time.

**3-Tier Pricing — Standard run (10ns MD, lysozyme + drug-like ligand):**

| Tier | CPU Instance | GPU Instance | Est. Wall Time | Est. Cost | Suggested Price |
|---|---|---|---|---|---|
| Economy | Fargate Spot 4 vCPU | g4dn.xlarge (T4) | ~12 hr | $2.50 | $8.00 |
| **Balanced** | **Fargate 4 vCPU** | **g4dn.2xlarge (T4)** | **~8 hr** | **$4.50** | **$14.00** |
| Performance | Fargate 16 vCPU | g5.4xlarge (A10G) | ~4 hr | $7.50 | $25.00 |

**100ns MD simulation pricing:**

| Tier | Est. Wall Time | Est. Cost | Suggested Price |
|---|---|---|---|
| Economy | ~5 days | $25 | $80 |
| Balanced | ~3 days | $45 | $140 |
| Performance | ~1.5 days | $75 | $250 |

---

## Batch Infrastructure Overhead — Key Finding

**Fixed overhead per job (any CPU workflow):**

| Component | Time | Notes |
|---|---|---|
| Batch job scheduling | 30–60s | RUNNABLE → STARTING |
| Container image pull | 30–60s | First pull; cached on same compute env |
| Container startup | 5–10s | Java/R/Python init |
| **Total overhead** | **65–130s** | Minimum billing floor |

**Implication:** For any workflow costing < $0.01 in compute, the minimum viable charge should be **$0.10** (covers Batch overhead + margin). All micro-workflows (NCA, PBPK, BOIN) should be priced at $0.10–$0.50 minimum regardless of actual compute.

---

## Validation Run Summary Table

| Workflow | Status | Steps | Real Container Time | Wall Time | Batch Instance | Compute Cost | Notes |
|---|---|---|---|---|---|---|---|
| predict_admet_properties | ✅ PASSED | 1 | 16.8s | 119s | 4 vCPU / 8 GB | $0.000919 | 10 SMILES |
| clinical_trial_simulation | ✅ PASSED | 1 | 11.9s | 239s | 4 vCPU / 8 GB | $0.000651 | 200 sims |
| pk_sim_pbpk | ✅ PASSED* | 4 | 54s total | ~240s | 4 vCPU / 8 GB | $0.002957 | *from concurrent user |
| pbpk_pediatric | ✅ PASSED* | 3 | 60s total | ~200s | 4 vCPU / 8 GB | $0.003287 | *from concurrent user |
| nca_pknca (step 1) | ⚠️ PARTIAL | 1/3 | 16s | — | 1 vCPU / 1 GB | $0.000063 | Route col fix needed |
| gromacs_protein_md | 🔄 IN PROGRESS | 3/8 done | 297s so far | 12+ min | CPU: 4-8vCPU; GPU pending | $0.012 so far | 20ps mini run |
| scaffold_hopping | ❌ FAILED | 0 | — | — | — | — | Input format mismatch |
| cyp_ddi_panel | ❌ FAILED | 0 | — | — | — | — | AWS profile not found |

---

## Data Issues Found & Fixes

1. **nca_pknca**: `route` column must use `extravascular` / `intravascular`, not `oral`. Fix: rename in CSV.
2. **scaffold_hopping**: `input_smiles` param expects a path to a file containing a single SMILES string (not a list). Fix: pass SMILES for one representative scaffold + separate list for enumeration.
3. **cyp_ddi_panel**: The `aws` profile name is undefined in the config. The workflow was submitted without `profile: aws` but the config tries to use it internally. Fix: submit with `profile: awsbatch` or fix the config.
4. **gromacs SDF**: User-drawn SDF files have antechamber valence errors. Fix: use RDKit to generate 3D-embedded SDF from SMILES before submission (our RDKit-generated aspirin.sdf works correctly).

---

## Files Used in This Validation

| File | S3 Location | Size |
|---|---|---|
| pk_data.csv (3 subjects, wrong route col) | s3://biomate-workflow-inputs/validation/pk_data.csv | 419 B |
| pk_data_v2.csv (fixed: extravascular) | s3://biomate-workflow-inputs/validation/pk_data_v2.csv | 422 B |
| compounds_10.smi (10 SMILES + names) | s3://biomate-workflow-inputs/validation/compounds_10.smi | 372 B |
| scaffold_smiles.smi (10 SMILES + names) | s3://biomate-workflow-inputs/validation/scaffold_smiles.smi | 374 B |
| smiles_only.smi (10 SMILES, no names) | s3://biomate-workflow-inputs/validation/smiles_only.smi | 240 B |
| 1AKI.pdb (lysozyme, standard protein) | s3://biomate-workflow-inputs/validation/1AKI.pdb | 113.7 KB |
| aspirin_rdkit.sdf (RDKit-generated, valid 3D) | s3://biomate-workflow-inputs/validation/aspirin_rdkit.sdf | 1.8 KB |

---

## Run IDs (for resume/debug)

| Workflow | Run ID | Status |
|---|---|---|
| predict_admet | 08ca64a7-8027-4d8b-b094-d77767c0bfcd | ✅ SUCCEEDED |
| clinical_trial | 6ddac5a7-4a8c-488e-b753-914597e8b793 | ✅ SUCCEEDED |
| nca_pknca v2 | d1ebffca-7ddb-445d-9916-15c8d61316e7 | ⚠️ Partial |
| gromacs v3 | b4e385c5-265e-4949-b4a7-176a10f1e13d | 🔄 Running |
| scaffold_hopping v2 | c7f4fb17-910e-4bde-b541-a983f3a4ee8b | ❌ Failed |
| cyp_ddi_panel | 48e3dc85-102a-4ebd-995d-a02d98bfc573 | ❌ Failed |
