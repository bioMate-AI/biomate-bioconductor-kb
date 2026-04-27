# BioMate Drug Development Benchmark Plan

**Date:** 2026-04-27  
**Status:** Planning — implementation starts Week 1

---

## 1. Motivation

BiomniEval1, LABBench, BixBench, and SGI-Bench test **knowledge recall** — they assess whether an LLM can answer biology questions. None of them test what BioMate is actually built to do: take a biological intent, route it to the right workflow, fill parameters, execute on AWS Batch, and produce scientifically valid output.

This document defines a benchmark suite organized by the stages of drug development where BioMate has tool coverage (from the coverage analysis at `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`). Each benchmark is independently runnable and decomposed across the six testable layers of the BioMate pipeline.

---

## 2. The Six Evaluation Layers

Every BioMate workflow interaction traverses six sequential failure points. Each benchmark covers a subset of them.

```
[L1] INTENT CLASSIFICATION    Did BioMate recognize this as a workflow task?
       │
[L2] WORKFLOW ROUTING         Did it select the right workflow from 2,455 options?
       │
[L3] PARAMETER EXTRACTION     Did it fill the correct input values?
       │
[L4] PREREQUISITE DETECTION   Did it identify missing inputs and ask correctly?
       │
[L5] EXECUTION COMPLETION     Did the Nextflow job finish without error?
       │
[L6] OUTPUT VALIDITY          Is the biological output scientifically correct?
```

**Layer coverage by benchmark:**

| Benchmark | L1 | L2 | L3 | L4 | L5 | L6 | AWS cost |
|-----------|----|----|----|----|----|----|----------|
| B1 ADMET  | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  | ~$0.50/run |
| B2 Docking| ✓  | ✓  | ✓  | ✓  | ✓  | ✓  | ~$2/run    |
| B3 PBPK   | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  | ~$0.20/run |
| B4 BOIN   | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  | ~$0.10/run |
| B5 Target | ✓  | ✓  | ✓  | ✓  | ✓  | ✓  | ~$3/run    |

Layers L1–L4 cost only LLM tokens (~$0.003–$0.008/task). L5–L6 require AWS Batch execution.

---

## 3. Coverage Map — Which Drug Dev Stages Are Benchmarked

From the coverage analysis, BioMate has ✅ internal tool coverage at these stages:

| Stage | Coverage | Benchmark | Primary Workflows |
|-------|----------|-----------|-------------------|
| S0 Target Discovery | 75% | **B5** | AlphaFold, AutoSite, MAGeCK |
| S1 Hit Discovery | 80% | **B2** | DiffDock, Vina, DrugCLIP |
| S2 Hit-to-Lead | 90% | **B1** | predict_admet_properties, CYP DDI, IVIVE |
| S3 Lead Optimization | 70% | *(future)* | GROMACS, OpenFE RBFE, REINVENT4 |
| S4 Preclinical | 65% | **B3** | pbpk_simulation, allometric_scaling |
| S5/S6 IND / Phase I | 80% | **B4** | clinical_trial_simulation, BOIN |
| S7/S8 Phase II/III | 45% | *(data boundary)* | clinical_trial_simulation only |
| S10 Post-market | 75% | *(future)* | FAERS, DDinter, CYP DDI |

Stages S7/S8 and S10 require patient-level data or external API connections — not benchmarkable without data partnerships.

---

## 4. Benchmark Specifications

---

### B1 — ADMET Screening (Stage S2: Hit-to-Lead)

**What it tests:** Full chain from SMILES input → ADMET property prediction → QC gate decision.  
**Primary workflow:** `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`  
**Layers covered:** L1–L6

#### 4.1.1 Test Cases

20 compounds with published experimental values from ChEMBL and PharmaBench:

| Case ID | Compound | SMILES | hERG IC50 (µM) | DILI class | Ames | Ro5 |
|---------|----------|--------|----------------|------------|------|-----|
| ADMET-001 | Aspirin | `CC(=O)Oc1ccccc1C(=O)O` | >100 (safe) | negative | negative | pass |
| ADMET-002 | Cisapride | `CCOC1=CC=C(C=C1)NC(=O)C2=CC(=C(C=C2OC)N)Cl` | 0.14 (toxic) | positive | negative | pass |
| ADMET-003 | Terfenadine | `OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC` | 0.20 (toxic) | positive | negative | pass |
| ADMET-004 | Caffeine | `Cn1cnc2c1c(=O)n(c(=O)n2C)C` | >100 (safe) | negative | negative | pass |
| ADMET-005 | Nitrofurantoin | `O=C1CN(N1C(=O)/C=N/O[N+](=O)[O-])c1ccccc1` | >100 (safe) | positive | positive | pass |
| ADMET-006 | Ibuprofen | `CC(C)Cc1ccc(cc1)C(C)C(=O)O` | >100 (safe) | negative | negative | pass |
| ADMET-007 | Doxorubicin | `OC1C(OC2CC(OC3CC(O)C(O)(Cc4c(O)c5C(=O)c6cccc(O)c6C(=O)c5c(O)c4C3=O)O2)N(C)C)C(C)OC1O` | >10 (moderate) | positive | positive | pass |
| ADMET-008 | Metformin | `CN(C)C(=N)NC(=N)N` | >100 (safe) | negative | negative | pass |
| ADMET-009 | Haloperidol | `OC1(CCc2ccc(Cl)cc2)CCN(CCCC(=O)c2ccc(F)cc2)CC1` | 0.11 (toxic) | positive | negative | pass |
| ADMET-010 | Atorvastatin | `CC(C)c1c(C(=O)Nc2ccccc2F)c(-c2ccccc2)c(-c2ccc(F)cc2)n1CCC(O)CC(O)CC(=O)O` | >10 (moderate) | negative | negative | pass |
| ADMET-011 | Verapamil | `COc1ccc(CCN(C)CCCC(C#N)(c2ccc(OC)c(OC)c2)C(C)C)cc1OC` | 0.43 (toxic) | positive | negative | pass |
| ADMET-012 | Tamoxifen | `CCC(=C(c1ccccc1)c1ccc(OCCN(C)C)cc1)c1ccccc1` | 0.60 (toxic) | positive | negative | pass |
| ADMET-013 | Warfarin | `OC(=O)c1ccccc1OCC(=O)c1ccccc1` | >100 (safe) | negative | negative | pass |
| ADMET-014 | Chlorpromazine | `CN(C)CCCN1c2ccccc2Sc2ccc(Cl)cc21` | 1.40 (moderate) | positive | negative | pass |
| ADMET-015 | Loratadine | `CCOC(=O)N1CCC(=C2c3ccc(Cl)cc3CCc3ccncc32)CC1` | >10 (moderate) | negative | negative | pass |
| ADMET-016 | Sildenafil | `CCCC1=NN(C)C(=C1C(=O)OCC)c1cc(S(=O)(=O)N2CCN(C)CC2)ccc1OCC` | 5.6 (moderate) | negative | negative | pass |
| ADMET-017 | Thalidomide | `O=C1CCC(N2C(=O)c3ccccc3C2=O)C(=O)N1` | >100 (safe) | negative | positive | pass |
| ADMET-018 | Ketoconazole | `CC(=O)N1CCN(CC1)c1ccc(OCC2COC(Cn3ccnc3)(O2)c2ccc(Cl)cc2Cl)cc1` | 0.82 (toxic) | positive | negative | pass |
| ADMET-019 | Methotrexate | `CN(Cc1cnc2nc(N)nc(N)c2n1)c1ccc(cc1)C(=O)NC(CCC(=O)O)C(=O)O` | >100 (safe) | positive | negative | fail (MW>500) |
| ADMET-020 | Clozapine | `CN1CCN(CC1)C1=NC2=CC(Cl)=CC=C2NC2=CC=CC=C12` | 1.10 (moderate) | positive | negative | pass |

**Classification thresholds** (must match workflow defaults):
- hERG: toxic = IC50 < 1 µM; moderate = 1–10 µM; safe = > 10 µM
- DILI: binary (positive/negative)
- Ames: binary (positive/negative)
- Ro5: fail if MW > 500 OR LogP > 5 OR HBD > 5 OR HBA > 10

#### 4.1.2 NL Intent Test Cases

For L1–L4 evaluation, 20 NL query variants per compound (total 400 L1–L4 probes):

```
Type A (complete): "Run ADMET screening on these 3 compounds: {SMILES}"
Type B (incomplete): "I need to check the safety profile of my lead compound"
Type C (ambiguous): "Can you analyze this molecule for me? {SMILES}"
Type D (multi-step): "Run ADMET on {SMILES}, then filter out hERG-toxic compounds"
Type E (wrong domain): "Sequence-align these proteins: {PROTEIN_SEQ}" [negative control]
```

#### 4.1.3 Metrics

**Layer 1–2: Routing accuracy**
- Metric: `routing_accuracy = correct_workflow / n_queries`
- Correct workflow: any of `predict_admet_properties`, `ADMET_pred`, `drug_discovery` (full pipeline)
- Target: ≥ 90%

**Layer 3: Parameter extraction F1**
- Metric: F1 over `{smiles_list, ADMET_model_type}` keys
- Semantic equivalence: `smiles_list` accepts JSON array or comma-separated
- `ADMET_model_type` in {MPNN, GNN, RF} (default MPNN if unspecified)
- Penalty: −0.2 for each hallucinated parameter not in NL query
- Target: F1 ≥ 0.80

**Layer 4: Prereq detection**
- Metric: for Type B/C queries (SMILES missing), BioMate asks clarifying question within 1 turn
- Score: binary per case — `1.0` if clarifying question asked, `0.0` if workflow launched with empty SMILES
- Target: ≥ 95%

**Layer 5: Execution completion**
- Metric: `completion_rate = jobs_exit_0 / jobs_submitted`
- Jobs: 20 compounds × 1 job each = 20 AWS Batch jobs
- Timeout: 10 minutes per job (ADMET is CPU-only, ~2–5 min actual)
- Target: ≥ 95%

**Layer 6: Output validity**

Sub-metric 6a — **Classification accuracy** (primary):
```
accuracy_per_property = exact_match(predicted_class, reference_class)
overall_accuracy = mean(hERG_acc, DILI_acc, Ames_acc, Ro5_acc)
```
Target: overall_accuracy ≥ 0.80 (matches PharmaBench published baseline)

Sub-metric 6b — **Rank correlation** (secondary, for continuous predictions):
```
spearman_rho = spearman(predicted_hERG_IC50_ranking, experimental_hERG_ranking)
```
Target: ρ ≥ 0.65 across the 20-compound set

Sub-metric 6c — **Output completeness**:
- All 4 ADMET properties present in output JSON/CSV
- All 20 compounds processed (no silent failures)
- Target: 100%

**Composite score:**
```
B1_score = 0.20 × routing_accuracy
         + 0.15 × param_f1
         + 0.10 × prereq_rate
         + 0.20 × completion_rate
         + 0.35 × output_accuracy
```

**Published baseline:** PharmaBench (arXiv:2602.05016) overall ADMET accuracy: 0.76 on held-out ChEMBL set.

---

### B2 — Docking Triage (Stage S1: Hit Discovery)

**What it tests:** SMILES → docking → ranked hit list.  
**Primary workflow:** `docking` / `diffdock_docking` / `autodock_vina`  
**Layers covered:** L1–L6  
**Dataset:** 15 PDB systems already in `evaluation/datasets/drug_discovery_e2e/pdb_systems.yaml`

#### 4.2.1 Test Cases

15 protein-ligand systems × 3 ligands each = 45 docking predictions. Systems span:
- 5 kinases (CDK2, EGFR, p38 MAPK, Aurora A, BTK)
- 3 GPCRs (β2-AR, D2R, A2aR)
- 3 proteases (BACE-1, thrombin, cathepsin B)
- 2 nuclear receptors (ERα, PPARγ)
- 2 other (HSP90, HDAC1)

All have: crystal structure in PDB + experimental Kd (nM) for rank ordering.

#### 4.2.2 Metrics

**Layer 6: Output validity**

Sub-metric 6a — **Rank correlation (primary)**:
```
per_system_rho = spearman(predicted_docking_score_rank, experimental_Kd_rank)
overall_rho = mean(per_system_rho) over 15 systems
```
Target: ≥ 0.65 (vs AutoDock Vina standalone ~0.45; Mozi reported 0.71)

Sub-metric 6b — **Top-1 hit identification**:
```
top1_accuracy = fraction of systems where tightest experimental binder has best predicted score
```
Target: ≥ 0.60

Sub-metric 6c — **Pose validity**:
- Docked pose RMSD vs crystal structure ≤ 2.0 Å for known crystal ligands (where available)
- Target: ≥ 50% poses within 2 Å

**Composite score:**
```
B2_score = 0.15 × routing_accuracy
         + 0.10 × param_f1
         + 0.15 × completion_rate
         + 0.40 × rank_rho
         + 0.20 × top1_accuracy
```

**Published baseline:** AutoDock Vina Spearman ρ ≈ 0.45; Gnina ρ ≈ 0.58; Mozi ρ = 0.71.

---

### B3 — PBPK Simulation (Stage S4: Preclinical / S5: IND)

**What it tests:** Compound physicochemical properties → human PK predictions (Cmax, AUC, t½, Vd).  
**Primary workflow:** `nextflow_nfcore/subworkflows/drug_discovery/pbpk_simulation/main.nf`  
**Layers covered:** L1–L6

#### 4.3.1 Test Cases

15 reference compounds with published human IV/oral PK from FDA drug labels and published literature:

| Case | Compound | Route | Published Cmax (µM) | Published t½ (h) | Published AUC (µM·h) |
|------|----------|-------|---------------------|------------------|----------------------|
| PK-001 | Aspirin (oral 500mg) | oral | 0.54 | 0.33 | 0.21 |
| PK-002 | Caffeine (oral 200mg) | oral | 4.8 | 5.0 | 33.6 |
| PK-003 | Ibuprofen (oral 400mg) | oral | 37.4 | 2.1 | 94.5 |
| PK-004 | Metformin (oral 500mg) | oral | 1.8 | 6.2 | 14.0 |
| PK-005 | Warfarin (oral 10mg) | oral | 0.42 | 40.0 | 24.8 |
| PK-006 | Midazolam (IV 0.05 mg/kg) | IV | 0.34 | 2.3 | 1.28 |
| PK-007 | Verapamil (oral 120mg) | oral | 0.28 | 6.0 | 1.68 |
| PK-008 | Atorvastatin (oral 80mg) | oral | 0.048 | 14.0 | 0.29 |
| PK-009 | Sildenafil (oral 100mg) | oral | 0.49 | 4.0 | 1.77 |
| PK-010 | Loratadine (oral 10mg) | oral | 0.019 | 8.4 | 0.30 |
| PK-011 | Propranolol (oral 80mg) | oral | 0.19 | 4.5 | 1.28 |
| PK-012 | Diazepam (oral 10mg) | oral | 0.21 | 43.0 | 13.1 |
| PK-013 | Ketoconazole (oral 200mg) | oral | 3.63 | 8.0 | 17.2 |
| PK-014 | Theophylline (oral 300mg) | oral | 8.3 | 9.0 | 83.7 |
| PK-015 | Methotrexate (IV 50mg/m²) | IV | 7.2 | 7.5 | 23.4 |

For each case: provide SMILES + physicochemical params (MW, logP, pKa, fu_plasma, CLint, renal_CL) from published sources. The model must predict Cmax, AUC, t½ that match FDA-label human PK.

#### 4.3.2 Metrics

**Layer 6: Output validity**

Sub-metric 6a — **2-fold accuracy (primary)**:
```
within_2fold(predicted, observed) = 0.5 × observed ≤ predicted ≤ 2 × observed
accuracy_2fold_Cmax = fraction of 15 cases within 2-fold for Cmax
accuracy_2fold_AUC  = fraction of 15 cases within 2-fold for AUC
accuracy_2fold_t½   = fraction of 15 cases within 2-fold for t½
overall_2fold = mean(accuracy_2fold_Cmax, accuracy_2fold_AUC, accuracy_2fold_t½)
```
Target: ≥ 0.70 (FDA PBPK guidance accepts 2-fold as acceptable prediction)

Sub-metric 6b — **MAFE (Mean Absolute Fold Error)**:
```
MAFE = mean(|log2(predicted/observed)|) over all 15 cases × 3 PK parameters
```
Target: MAFE ≤ 1.0 (i.e., mean fold error ≤ 2×)

Sub-metric 6c — **Direction accuracy** (Cmax comparison across dose levels):
- For cases with multiple doses: higher dose → higher Cmax (linearity check)
- Target: 100% directionally correct

**Composite score:**
```
B3_score = 0.20 × routing_accuracy
         + 0.15 × param_f1
         + 0.20 × completion_rate
         + 0.35 × overall_2fold
         + 0.10 × (1 - MAFE/2)   # normalized
```

**Published baseline:** Simcyp/GastroPlus PBPK: 2-fold accuracy ~75–85% for top 200 drugs. Open-source PBPK models: 60–70%.

---

### B4 — Clinical Trial Design (Stage S5/S6: IND / Phase I)

**What it tests:** Phase I dose escalation design → MTD recommendation.  
**Primary workflow:** `nextflow_nfcore/subworkflows/drug_discovery/clinical_trial_simulation/main.nf`  
**Layers covered:** L1–L6

#### 4.4.1 Test Cases

20 Phase I scenarios with known "correct" MTD from published BOIN operating characteristics or historical trials:

| Case | Scenario | True DLT rate at MTD | Starting dose (mg) | Dose levels | Target toxicity | Expected MTD level |
|------|----------|---------------------|-------------------|-------------|-----------------|-------------------|
| CT-001 | Oncology (myelosuppression) | 0.22 | 10 | [10,20,40,80,150,300] | 0.25 | 150 mg |
| CT-002 | Oncology (GI toxicity) | 0.28 | 5 | [5,10,20,40,80] | 0.25 | 40 mg |
| CT-003 | Conservative (elderly) | 0.15 | 5 | [5,10,20,40,80,150] | 0.20 | 40 mg |
| CT-004 | Rapid escalation (well-known class) | 0.30 | 50 | [50,100,200,400,800] | 0.30 | 400 mg |
| CT-005 | Flat DLT curve | 0.05 | 10 | [10,20,40,80] | 0.25 | 80 mg (no MTD found) |
| CT-006 | Steep DLT curve | 0.40 | 10 | [10,20,40] | 0.25 | 10 mg |
| CT-007 | Standard oncology (3+3 comparison) | 0.25 | 25 | [25,50,100,200,400] | 0.25 | 200 mg |
| CT-008 | Pediatric (weight-adjusted) | 0.20 | 1 mg/kg | [1,2,4,8,12 mg/kg] | 0.25 | 8 mg/kg |
| CT-009 | Bimodal DLT profile | 0.22 at level 3, 0.35 at level 5 | 10 | [10,20,50,100,200,400] | 0.25 | 100 mg |
| CT-010 | Phase I/II seamless | 0.25 | 20 | [20,40,80,160,320] | 0.25 | 160 mg |
| CT-011–020 | Variants of CT-001–010 with modified PK/PD params | varies | varies | varies | varies | varies |

Each scenario specifies: starting_dose_mg, dose_levels_json, DLT_rate_target, pk_CL_L_h, pk_Vd_L, ER_model, ER_EC50_nM. Ground truth MTD is the dose level where true DLT rate is closest to target without exceeding it (per published BOIN operating characteristic tables).

#### 4.4.2 Metrics

**Layer 6: Output validity**

Sub-metric 6a — **MTD accuracy (primary)**:
```
mtd_exact = predicted_MTD_level == true_MTD_level
mtd_adjacent = |predicted_MTD_level - true_MTD_level| ≤ 1 dose level
```
Target: mtd_exact ≥ 0.70; mtd_adjacent ≥ 0.90

Sub-metric 6b — **Operating characteristics**:
- Simulated DLT rate at recommended dose within [target × 0.7, target × 1.3]
- Target: ≥ 90% of simulations within this band

Sub-metric 6c — **Safety flag accuracy**:
- If true DLT rate ≥ 0.33 at starting dose: BioMate must flag "starting dose too high"
- If no MTD found in dose range: BioMate must report "MTD not reached"
- Target: 100% correct safety flags

**Composite score:**
```
B4_score = 0.20 × routing_accuracy
         + 0.15 × param_f1
         + 0.20 × completion_rate
         + 0.30 × mtd_exact
         + 0.15 × safety_flag_accuracy
```

**Published baseline:** BOIN design MTD accuracy vs 3+3: BOIN 70–80% exact, 90–95% adjacent (Yuan et al. 2016, Clin Cancer Res). 3+3: ~50% exact MTD.

---

### B5 — Target Structure Analysis (Stage S0: Target Discovery)

**What it tests:** Protein sequence → structure prediction → druggable pocket identification.  
**Primary workflows:** `boltz2_structure_prediction` or `alphafold_structure_prediction` → `autosite_pocket_detection`  
**Layers covered:** L1–L6

#### 4.5.1 Test Cases

10 protein targets with published crystal structures and known druggable pockets:

| Case | Target | UniProt | Crystal PDB | Known pocket | pLDDT (published) |
|------|--------|---------|------------|--------------|-------------------|
| TS-001 | CDK2 | P24941 | 1HCL | ATP binding cleft | ≥90 |
| TS-002 | EGFR kinase | P00533 | 1IEP | Kinase active site | ≥90 |
| TS-003 | p38 MAPK | Q16539 | 1A9U | DFG pocket | ≥85 |
| TS-004 | BACE-1 | P56817 | 2B8V | Active site flap | ≥80 |
| TS-005 | HDAC1 | Q13547 | 4BKX | Zinc-binding tunnel | ≥85 |
| TS-006 | HSP90α | P07900 | 1YES | N-terminal ADP pocket | ≥90 |
| TS-007 | PPARγ LBD | P37231 | 2PRG | Large hydrophobic LBD | ≥85 |
| TS-008 | Thrombin | P00734 | 1PPB | S1/S2/S3 subsites | ≥80 |
| TS-009 | MDM2 | Q00987 | 1YCR | p53 interaction surface | ≥75 |
| TS-010 | BCL-2 | P10415 | 2W3L | BH3 binding groove | ≥75 |

Input to BioMate: UniProt ID or FASTA sequence + intent NL.

#### 4.5.2 Metrics

**Layer 6: Output validity**

Sub-metric 6a — **Structure quality (pLDDT)**:
```
pLDDT_pass = predicted_pLDDT ≥ published_pLDDT_target
```
Target: ≥ 80% of residues at pLDDT ≥ 70 (AlphaFold threshold for reliable structure)

Sub-metric 6b — **Pocket detection accuracy**:
```
pocket_detected = IoU(predicted_pocket_residues, known_pocket_residues) ≥ 0.5
detection_rate = fraction of 10 targets with pocket_detected
```
Target: detection_rate ≥ 0.80

Sub-metric 6c — **Druggability classification**:
- Known drugged targets should be classified "druggable" (not "undruggable")
- All 10 targets have approved drugs → should all be classified druggable
- Target: 100% correctly classified as druggable

**Composite score:**
```
B5_score = 0.15 × routing_accuracy
         + 0.10 × param_f1
         + 0.15 × completion_rate
         + 0.30 × pLDDT_pass_rate
         + 0.30 × pocket_detection_rate
```

**Published baseline:** AlphaFold2 pLDDT ≥ 90 for 58% of human proteome; AutoSite pocket detection: ~78% IoU ≥ 0.5 on PDB benchmark set.

---

## 5. Evaluation Dimensions per Benchmark

Each benchmark is scored across all six dimensions from the four-dimension framework:

| Dimension | Measurement | Tool |
|-----------|-------------|------|
| **Performance** | B1–B5 composite score (see above) | Scoring functions in adapter |
| **Time/task** | Wall-clock end-to-end: NL query → output available | Adapter `latency_sec` |
| **Cost/task** | LLM tokens (Claude API) + AWS Batch vCPU-hours + S3 | `cost_usd` in DB + Lago billing events |
| **Stability** | 20% sample × 3 repeats: consistency_rate, flip_rate, Cohen's κ | `run_stability.py` |
| **Hallucination** | LLM-as-judge on final report/interpretation text | `hallucination_detector.py` |

**Cost tracking for execution benchmarks** (L5–L6):  
Unlike knowledge benchmarks, B1–B5 incur AWS costs. These are tracked via:
- `biomate-batch-billing` Lambda → Lago `job_started` / `job_completed` events
- `cost_usd` in eval DB = LLM tokens + (vCPU-hours × $0.048 + memory-hours × $0.006)
- B1 ADMET expected: ~$0.02 compute + $0.005 LLM = $0.025/task
- B3 PBPK expected: ~$0.005 compute + $0.005 LLM = $0.010/task
- B4 BOIN expected: ~$0.003 compute + $0.005 LLM = $0.008/task

---

## 6. Scoring Function Specifications

### 6.1 ADMET Output Parser (`parse_admet_output`)

```python
def parse_admet_output(output_dir: str) -> dict:
    """
    Parse ADMET workflow output into standardised dict.
    Looks for: results.csv, admet_predictions.json, output.json
    Returns: {smiles: {herg_class, dili_class, ames_class, ro5_pass, herg_ic50_uM}}
    """

def score_admet_case(predicted: dict, reference: dict) -> dict:
    """
    Returns:
        herg_accuracy: fraction of correct hERG class predictions (toxic/moderate/safe)
        dili_accuracy: fraction of correct DILI binary predictions  
        ames_accuracy: fraction of correct Ames binary predictions
        ro5_accuracy: fraction of correct Ro5 pass/fail predictions
        overall_accuracy: mean of above 4
        spearman_rho: rank correlation on hERG IC50 (continuous)
        completeness: fraction of compounds with all 4 properties present
    """
```

### 6.2 PBPK Output Parser (`parse_pbpk_output`)

```python
def parse_pbpk_output(output_dir: str) -> dict:
    """
    Looks for: pk_summary.csv, simulation_results.json, pk_parameters.csv
    Returns: {Cmax_uM, AUC_uM_h, t_half_h, Vd_L, CL_L_h, Tmax_h}
    """

def score_pbpk_case(predicted: dict, reference: dict) -> dict:
    """
    Returns:
        cmax_within_2fold: bool
        auc_within_2fold: bool
        t_half_within_2fold: bool
        overall_2fold: mean of above 3
        mafe: mean absolute fold error (log2 scale)
    """
```

### 6.3 BOIN Output Parser (`parse_boin_output`)

```python
def parse_boin_output(output_dir: str) -> dict:
    """
    Looks for: mtd_recommendation.json, dose_escalation_report.csv, simulation_summary.json
    Returns: {recommended_MTD_mg, recommended_MTD_level, DLT_rate_at_MTD, 
              safety_flags: [str], operating_characteristics: dict}
    """

def score_boin_case(predicted: dict, reference: dict) -> dict:
    """
    Returns:
        mtd_exact: bool (predicted level == true level)
        mtd_adjacent: bool (within 1 level)
        safety_flags_correct: bool
        dlt_rate_in_band: bool (within [target×0.7, target×1.3])
    """
```

### 6.4 Routing Accuracy (shared across all benchmarks)

```python
def score_routing(agent_response: str, correct_workflows: list[str]) -> float:
    """
    Extract workflow name from agent response.
    Returns 1.0 if any correct_workflow is mentioned or triggered.
    Returns 0.5 if a related but suboptimal workflow is chosen.
    Returns 0.0 if wrong domain workflow or no workflow.
    """
```

### 6.5 Parameter Extraction F1 (shared across all benchmarks)

```python
def score_param_extraction(generated_params: dict, expected_params: dict, 
                           must_not_fill: list[str]) -> float:
    """
    F1 = harmonic mean of precision and recall over correctly-filled params.
    Semantic equivalence handled via GENOME_ALIASES and STRAND_ALIASES.
    Penalty: -0.2 per must_not_fill key incorrectly populated.
    """
```
*(Reuses `ParamPrefillAdapter._compute_score()` — same logic)*

---

## 7. Datasets to Build

| Benchmark | Dataset file | Status | Cases needed |
|-----------|-------------|--------|-------------|
| B1 ADMET | `datasets/admet_benchmark/cases.yaml` | ❌ Create | 20 compounds + 100 NL queries |
| B2 Docking | `datasets/drug_discovery_e2e/pdb_systems.yaml` | ✅ Exists (15 systems) | 20 NL queries |
| B3 PBPK | `datasets/pbpk_benchmark/cases.yaml` | ❌ Create | 15 compounds + 75 NL queries |
| B4 BOIN | `datasets/boin_benchmark/cases.yaml` | ❌ Create | 20 scenarios + 60 NL queries |
| B5 Target | `datasets/target_structure_benchmark/cases.yaml` | ❌ Create | 10 targets + 30 NL queries |

---

## 8. Adapter Architecture

Each benchmark gets an adapter in `evaluation/adapters/`:

```
evaluation/
  adapters/
    admet_benchmark_adapter.py      # B1
    docking_benchmark_adapter.py    # B2 (extends drug_discovery_e2e)
    pbpk_benchmark_adapter.py       # B3
    boin_benchmark_adapter.py       # B4
    target_structure_adapter.py     # B5
  datasets/
    admet_benchmark/cases.yaml
    pbpk_benchmark/cases.yaml
    boin_benchmark/cases.yaml
    target_structure_benchmark/cases.yaml
  scorers/
    admet_scorer.py                 # parse_admet_output + score_admet_case
    pbpk_scorer.py                  # parse_pbpk_output + score_pbpk_case
    boin_scorer.py                  # parse_boin_output + score_boin_case
    structure_scorer.py             # parse_pdb_output + score_pLDDT
```

Each adapter inherits `BenchmarkAdapter` and implements:
- `load_tasks()` → list of `BenchmarkTask`
- `task_prompt(task)` → NL string sent to BioMate
- `score(task, agent_response)` → L1–L4 score (text-based)
- `score_execution(task, run_id)` → L5–L6 score (output file-based)

---

## 9. Implementation Roadmap

### Week 1 — Foundation (no AWS spend)
- [ ] Build `datasets/admet_benchmark/cases.yaml` (20 compounds, 100 queries)
- [ ] Build `datasets/pbpk_benchmark/cases.yaml` (15 compounds, 75 queries)
- [ ] Build `admet_scorer.py` + `pbpk_scorer.py` (output parsers + metrics)
- [ ] Fix `param_prefill` runner bug (5-min fix, unblocks L3 for all benchmarks)
- [ ] Write `admet_benchmark_adapter.py` L1–L4 only (no execution)
- [ ] Run L1–L4 eval: measure routing + param extraction + prereq detection → get baseline

### Week 2 — Execution (AWS spend: ~$15 total)
- [ ] Run B1 ADMET L5–L6: 20 compounds × 1 job = 20 Batch jobs (~$0.50 total)
- [ ] Run B3 PBPK L5–L6: 15 compounds × 1 job = 15 Batch jobs (~$0.30 total)
- [ ] Write output parsers, collect results, compute 2-fold accuracy
- [ ] Build `boin_benchmark_adapter.py` + `datasets/boin_benchmark/cases.yaml`
- [ ] Run B4 BOIN: 20 scenarios (~$0.20 total)

### Week 3 — Docking + Structure (AWS spend: ~$60 total)
- [ ] Run B2 Docking: 15 systems × 3 ligands = 45 jobs (~$2–3/system = ~$35)
- [ ] Run B5 Structure: 10 proteins × 1 job = 10 jobs (~$3/job = ~$30)
- [ ] Compute Spearman ρ for docking; pLDDT + pocket detection for structure

### Week 4 — Report
- [ ] Integrate all five benchmarks into `generate_eval_report.py`
- [ ] Run stability (20% × 3) for B1 and B3
- [ ] Run hallucination audit on all execution benchmark findings text
- [ ] Write full four-dimension results table

---

## 10. Success Criteria (Publication Bar)

| Benchmark | BioMate target | Current published best | Gap |
|-----------|---------------|----------------------|-----|
| B1 ADMET accuracy | ≥ 0.80 | PharmaBench: 0.76 | +0.04 |
| B2 Docking Spearman ρ | ≥ 0.65 | Mozi: 0.71; Vina: 0.45 | competitive |
| B3 PBPK 2-fold accuracy | ≥ 0.70 | Simcyp: 0.80 (commercial) | −0.10 |
| B4 BOIN MTD exact | ≥ 0.70 | BOIN paper: 0.70–0.80 | on par |
| B5 Pocket detection | ≥ 0.80 | AutoSite: 0.78 | +0.02 |
| **Overall chain** | ≥ 0.75 | **No published E2E benchmark exists** | **novel** |

The overall chain metric (intent→output across all 5 domains) has no published comparator. BioMate is the first system to report it.

---

## 11. Open Questions

1. **Reference ADMET values**: Use ChEMBL measured IC50 or PharmaBench QSAR predictions as reference? Recommend ChEMBL measured where available (20 compounds selected above have ChEMBL data).

2. **PBPK input completeness**: Should the L3 benchmark provide all physicochemical params (CLint, fu_plasma, etc.) in the NL query, or should BioMate also be expected to predict them? Recommend: provide in NL (testing PK simulation, not QSAR prediction).

3. **Docking success criterion**: Spearman ρ is sensitive to the number of ligands per system. With only 3 ligands, ρ can be only {−1, 0, +0.5, +1}. Consider increasing to 5 ligands per system or using AUROC instead.

4. **AWS cost governance**: Execution benchmarks should not run automatically on every commit. Recommend: gate behind `--run-execution` flag; default to L1–L4 only.

5. **Stability cost**: Running B1 stability (20% × 3 = 12 runs × 20 compounds = 60 AWS jobs) costs ~$3. Acceptable.
