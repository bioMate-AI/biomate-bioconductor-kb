# BioMate Drug Development: Gap Analysis, Coverage Map & Wet-Lab Feedback Loop

**Date:** 2026-04-17  
**Source image:** `/home/yzhang/Desktop/business/drug_development.jpg`  
**Scope:** Drug development challenge survey · BioMate coverage · gap plan · wet-lab→model loop documentation

---

## Part 1 — Source: Drug Development Key Challenges

The image (a Chinese pharma commentary post) makes a pointed observation that the industry's attention has shifted away from "finding new targets" toward four harder operational problems:

| # | Challenge (Chinese) | Translation |
|---|---|---|
| 1 | 能不能长期用 | **Long-term use** — chronic safety, immunogenicity, drug tolerance |
| 2 | 能不能更好地送达 | **Better delivery** — bioavailability, delivery systems, tissue selectivity |
| 3 | 能不能真正作用到目标位置 | **On-target engagement** — target occupancy, tissue distribution, selectivity |
| 4 | 能不能在真实临床中走通 | **Clinical translatability** — preclinical→clinical translation, real-world populations |

The author's conclusion: these four issues determine whether a drug development direction can succeed long-term, more than target novelty alone.

---

## Part 2 — BioMate Current Capability Map

### Full Workflow Inventory

BioMate currently has **52 drug-development–relevant workflows** across three categories:

#### Drug Discovery (24 Nextflow workflows)
`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/`

| Workflow | What it does |
|---|---|
| alphafold_db_search | Structural/sequence homolog search via Foldseek + MMseqs2 |
| structure_prediction_docking | AlphaFold3 + DiffDock + Vina parallel docking |
| schrodinger_glide_docking | Schrodinger SP/XP/HTVS docking with GlideScore |
| moe_covalent_docking | Covalent inhibitor / FBDD docking |
| pocket_detection_druggability | fpocket binding site detection |
| pharmacophore_filtering | RECAP pharmacophore model + library screening |
| drugclip_virtual_screening | CLIP-based ultra-fast virtual screening (10M× faster than docking) |
| openfe_rbfe | Alchemical relative binding free energy (OpenFE) |
| amber_pmemd_md | AMBER MD + MM-GBSA binding free energy, GPU-accelerated |
| gromacs_protein_md | GROMACS MD + gmx_MMPBSA, equilibration + production |
| reinvent4_lead_design | REINVENT4 generative RL: de novo / scaffold decoration / linker / hopping |
| scaffold_hopping | RECAP fragmentation + MMP analysis |
| scfv_antibody_design | ProteinMPNN + AlphaFold2 scFv intrabody design |
| syncraft_synthesizability | LLM (Gemini-2.5-Pro) atom-level synthesizability optimization |
| aizynthfinder_retrosynthesis | AiZynthFinder retrosynthesis (≤4 steps, ranked routes) |
| nca_pknca | Non-Compartmental Analysis (NCA parameters: AUC, Cmax, t½, CL/F, Vd/F) |
| p0_pkpd_semaglutide | 2-compartment PK + GLP-1R Emax PD, validated vs SUSTAIN-1 trial |
| drug_moa_rnaseq | DESeq2 + GSEA + LINCS L1000 MoA characterization |
| p0_mrna_validation | mRNA codon optimization + 2-proline stabilization |
| cyp_ddi_panel | CYP450 DDI panel (5 isoforms, IVIVE hepatic clearance, FDA DDI flags) |
| assay_ingestion_and_ranking | Multi-assay ingestion → composite safety-potency scoring |
| cro_submission_export | CRO order formatting (WuXi/Pharmaron/Enamine) |
| p0_docking_validation | Phase 0: docking vs crystal structure (Mpro + nirmatrelvir) |
| p0_pharmacophore_validation | Phase 0: pharmacophore enrichment vs GLP-1R actives |

#### Pharmacology (28 Nextflow workflows)
`backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/`

| Workflow | What it does |
|---|---|
| ADMET_pred | hERG IC50 + DILI risk screening (Aronov + Lammert models) |
| predict_admet_properties | ADMET via RDKit + optional DeepPurpose MPNN; ClinTox, solubility |
| calculate_physicochemical_properties | MW, LogP, TPSA, HBD/HBA, Lipinski |
| predict_binding_affinity_protein_1d_sequence | MPNN-CNN binding affinity from SMILES + protein 1D sequence |
| qsar_rf_model | QSAR with Random Forest + 5-fold CV; cv_R2 < 0.5 → SILVER block |
| nlmixr2_population_pk | PopPK/PD (nlmixr2 SAEM/FOCE+): 1-/2-compartment, VPC, GOF, covariates |
| ivive_hepatic_clearance | In vitro → in vivo hepatic clearance extrapolation (well-stirred model) |
| bi_exp_model | Biexponential PK model |
| sigmoid | Sigmoid / Emax PD model |
| check_drug_combination_safety | DDI mechanism and management analysis |
| check_fda_drug_recalls | FDA recall lookup |
| find_alternative_drugs_ddinter | Alternative drug recommendation to avoid DDIs |
| analyze_interaction_mechanisms | DDI mechanism + clinical significance scoring |
| get_fda_drug_label_info | FDA label retrieval |
| grade_adverse_events_using_vcog_ctcae | VCOG-CTCAE grading |
| apply_vcog_grade | VCOG adverse event grading application |
| analyze_radiolabeled_antibody_biodistribution | %IA/g biodistribution over time across tissues (antibody PK) |
| estimate_alpha_particle_radiotherapy_dosimetry | Ac-225 dosimetry for alpha-particle radiotherapy |
| analyze_accelerated_stability | ICH accelerated stability → degradation kinetics + shelf-life |
| run_3d_chondrogenic_aggregate_assay | 3D chondrogenesis compound evaluation |
| analyze_xenograft_tumor_growth_inhibition | Xenograft TGI statistical analysis |
| analyze_western_blot | Densitometric Western blot quantification |
| run_autosite | AutoSite pocket detection |
| docking_autodock_vina | AutoDock Vina pipeline |
| run_diffdock_with_smiles | DiffDock from SMILES |
| retrieve_topk_repurposing_drugs_from_disease_txgnn | TxGNN drug repurposing |
| perform_mwas_cyp2c19_metabolizer_status | MWAS for CYP2C19 metabolizer biomarker |

#### Physiology (3 PK/PD)
| Workflow | What it does |
|---|---|
| pk_ode_system | Oral absorption ODE (ka, ke, Vd) |
| simulate_thyroid_hormone_pharmacokinetics | Multi-compartment tissue PK with binding kinetics |
| mono_exp_model | Monoexponential elimination |

---

## Part 3 — Coverage vs. The Four Key Challenges

### Challenge 1: Long-Term Use (慢性安全 / 耐受性)

**Coverage: 55% — Moderate**

| Covered | Gap |
|---|---|
| hERG IC50 (cardiac safety) | Repeated-dose toxicity prediction |
| DILI risk prediction (Lammert) | Carcinogenicity / genotoxicity (Ames, micronucleus) |
| ADMET + ClinTox screening | Immunogenicity: T-cell epitope / HLA binding |
| Drug combination safety + DDI | Anti-drug antibody (ADA) risk for biologics |
| FDA adverse event + recall lookup | Time-dependent enzyme inhibition (TDI) |
| Formulation ICH stability | Reactive metabolite prediction (GSH trap) |
| VCOG-CTCAE adverse event grading | Reproductive / developmental toxicity (DART) |

Key missing piece: **immunogenicity prediction for biologics**. No T-cell epitope prediction, no HLA binding prediction, no ADA risk model. This is increasingly critical as the field shifts toward ADCs, bispecifics, and gene therapies.

---

### Challenge 2: Better Delivery (递送优化)

**Coverage: 20% — Weak**

| Covered | Gap |
|---|---|
| Lipinski / physicochemical properties | Nanoparticle / LNP formulation design |
| LogP, TPSA (passive permeability proxies) | PEGylation and conjugation optimization |
| IVIVE hepatic clearance | Oral formulation: dissolution, absorption modeling |
| ICH accelerated stability | Controlled / sustained release kinetics |
| Radiolabeled antibody biodistribution | Small-molecule tissue penetration prediction |

This is the single largest gap relative to industry relevance. LNP delivery for RNA therapeutics, targeted delivery for oncology (ADC linker/payload design), CNS penetration (P-gp efflux / BBB permeability) — none of these are covered.

---

### Challenge 3: On-Target Engagement (靶点覆盖 / 选择性)

**Coverage: 70% — Strong**

| Covered | Gap |
|---|---|
| Binding free energy: OpenFE RBFE, AMBER MM-GBSA, GROMACS | Kinetic target engagement (koff/kon/residence time) |
| Docking: Glide, Vina, DiffDock, MOE covalent | Proteome-wide selectivity profiling (chemoproteomic) |
| AlphaFold3 structure prediction | Covalent warhead reactivity (GSH reactivity) |
| Pharmacophore filtering + DrugCLIP | Target occupancy modeling over time |
| MoA characterization (RNA-seq + LINCS) | Cell target engagement: CETSA / DARTS protocol |
| Biodistribution (antibodies) | — |

This is BioMate's strongest area. The main gaps are kinetics (residence time) and orthogonal wet-lab target engagement assay protocols.

---

### Challenge 4: Clinical Translatability (临床转化)

**Coverage: 45% — Partial**

| Covered | Gap |
|---|---|
| NCA PK parameters (AUC, Cmax, t½, CL/F) | PBPK with organ-specific parameterization |
| Population PK/PD (nlmixr2 SAEM/FOCE+) | Clinical trial design simulation |
| GLP-1R semaglutide PK/PD validated vs SUSTAIN-1 | Dose escalation safety simulation (oncology 3+3 / BOIN) |
| IVIVE hepatic clearance | DDI transporter prediction (OATP, P-gp, BCRP) |
| CYP DDI panel + FDA risk flags | Heterogeneous patient population modeling |
| CYP2C19 metabolizer MWAS | Comprehensive pharmacogenomics stratification |
| Xenograft tumor growth inhibition | Species scaling (allometric) |
| Drug label retrieval (FDA labeling) | QSP/systems pharmacology models |

---

## Part 4 — Gap Prioritization Plan

Ordered by impact × feasibility:

### Priority 1: Immunogenicity Prediction (Long-term use)
**Rationale:** Biologics pipeline (ADCs, bispecifics, gene therapy) is the dominant new drug class. ADA formation is the #1 clinical failure mode for biologics. T-cell epitope and HLA binding prediction are established in silico tools (EpiVax, NetMHCpan, IEDB).

**Plan:**
- Workflow: `pharmacology/immunogenicity_prediction`
- Tools: NetMHCpan-4.1 (HLA-I/II binding), EpiSweep / IEDB consensus (T-cell epitopes), aggregation propensity (CamSol)
- Output: per-residue immunogenicity risk score, deimmunization site proposals, ADA risk tier (low/medium/high)
- Integration: add to ADMET screening pipeline as optional module for biologics

### Priority 2: PBPK Modeling (Clinical translatability)
**Rationale:** FDA increasingly requires PBPK models for DDI submissions and pediatric extrapolation. Population PK (nlmixr2) is already present; PBPK is the missing organ-level layer.

**Plan:**
- Workflow: `drug_discovery/pbpk_pksim`
- Tools: PK-Sim (Open Systems Pharmacology, OSP Suite) — open source, Docker-able
- Capabilities: tissue distribution, first-pass extraction, renal clearance, transporter-mediated DDI (OATP1B1/3, P-gp, BCRP)
- Use case: pediatric/elderly dose prediction, organ impairment dosing, DDI regulatory submissions

### Priority 3: LNP / Delivery System Optimizer (Better delivery)
**Rationale:** mRNA vaccines, siRNA, ASO, gene therapy all depend on delivery. No tool currently in BioMate addresses formulation-level delivery.

**Plan:**
- Workflow: `drug_discovery/lnp_formulation_optimization`
- Tools: RDKit physicochemical + custom ML model for endosomal escape prediction; pKa of ionizable lipid vs pH
- Capabilities: LNP component ratio optimization (lipid:PEG:cholesterol:cargo), tissue targeting score, stability predictor
- Stretch goal: integrate with Bayesian optimizer for iterative LNP design (mirrors the DMTA loop)

### Priority 4: Clinical Trial Design Simulator (Clinical translatability)
**Rationale:** In silico trial simulation (MAST framework, virtual patient populations) is now used by FDA for approval supplement evidence.

**Plan:**
- Workflow: `drug_discovery/clinical_trial_simulation`
- Tools: nlmixr2 (already present) + mrgsolve + NONMEM-compatible virtual patient library
- Capabilities: dose escalation (3+3, BOIN, mTPI-2), exposure-response simulation, PK variability from PopPK → responder rate prediction
- Input: PopPK parameters from nlmixr2 run; output: recommended dose range, probability of toxicity/efficacy

### Priority 5: Transporter DDI (Clinical translatability)
**Rationale:** OATP1B1/3, P-gp, BCRP substrate/inhibitor prediction is mandatory in FDA DDI guidance (2020). Currently only CYP-based DDI is covered.

**Plan:**
- Workflow: `pharmacology/transporter_ddi_prediction`
- Tools: MolML transporter models or ChemDES features + RF classifiers; FDA static DDI modeling equations
- Output: OATP1B1/3 substrate probability, P-gp/BCRP inhibitor IC50 estimate, net drug interaction AUC ratio

### Priority 6: BBB / CNS Penetration (Better delivery)
**Rationale:** CNS drug development has the highest attrition rate, largely due to P-gp efflux and poor BBB penetration. Standard physicochemical rules (MW<450, LogP 1-3, TPSA<90) are insufficient.

**Plan:**
- Workflow: `pharmacology/cns_penetration_prediction`
- Tools: Kp,uu,brain predictor (P-gp efflux model + passive permeability), MDCK-MDR1 cell permeability ML model
- Output: BBB permeability class, Kp,uu,brain estimate, P-gp efflux ratio, CNS MPO score

---

## Part 5 — Wet-Lab → Model Feedback Loop: Architecture & Status

### What Is Implemented

BioMate has a **DMTA (Design–Make–Test–Analyse) loop** for drug discovery campaigns. It is implemented and functional but requires manual trigger for each step.

#### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BioMate DMTA Feedback Loop                       │
│                                                                     │
│  DESIGN ──────────────────────────────────────────────────────────  │
│  BayesianOptimizer.propose()                                        │
│    ├── GP surrogates per objective (potency, safety, ADMET)         │
│    ├── Expected Hypervolume Improvement (EHVI) acquisition          │
│    ├── Morgan fingerprint features (RDKit, radius=2, 2048-bit)      │
│    ├── Diversity penalty (Tanimoto-based)                           │
│    └── Output: SMILES list for next synthesis batch                 │
│                     │                                               │
│                     ↓                                               │
│  MAKE ─────────────────────────────────────────────────────────── │
│  CommercialAvailabilityChecker (PubChem batch API)                 │
│  CROOrderExporter (WuXi / Pharmaron / Enamine CSV formats)          │
│  AiZynthFinder retrosynthesis (≤4-step routes)                     │
│  SynCraft synthesizability optimizer (LLM atom-level edits)         │
│                     │                                               │
│                     ↓                                               │
│  TEST ──────────────────────────────────────────────────────────── │
│  [Wet-Lab: IC50, hERG, DILI, ADMET assays]                         │
│                     │                                               │
│                     ↓  ← FEEDBACK ENTRY POINT                      │
│  ANALYSE ──────────────────────────────────────────────────────── │
│  AssayIngestionService                                              │
│    ├── CSV upload (POST /api/drug-discovery/{id}/ingest-assay)      │
│    ├── Multi-assay parsing + unit normalization                     │
│    ├── Composite safety-potency scoring (weighted)                  │
│    └── Updated rankings persisted to SQLite                        │
│  Nextflow: assay_ingestion_and_ranking                              │
│    ├── PARSE_ASSAY_DATA (wide-format pivot)                        │
│    ├── COMPUTE_COMPOSITE_SCORE (log-scaled pIC50 + hERG safety)    │
│    └── RANK_AND_REPORT (CSV + HTML + JSON)                         │
│                     │                                               │
│                     └────────────────────→ DESIGN (next round)     │
└─────────────────────────────────────────────────────────────────────┘
```

#### Component Details

**1. Bayesian Optimizer** — `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py`

- `BayesianOptimizer` class with `fit(dataset: CampaignDataset)` + `propose(n_compounds, candidate_pool)` 
- GP surrogates: `sklearn.gaussian_process.GaussianProcessRegressor` with Matérn 5/2 kernel
- Objectives internally normalized to [0,1] with polarity canonicalization (`maximize` → `minimize` negation)
- Acquisition: Expected Hypervolume Improvement (EHVI) over Pareto front
- Diversity penalty: Tanimoto distance from proposed set to current Pareto front
- Output: `RoundProposal` dataclass with SMILES, per-objective scores, acquisition values, Pareto front
- Persistence: save/load round history via SQLite
- QC guard: requires ≥3 compounds with valid data before fitting

**2. Assay Ingestion Service** — `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py`

- `AssayIngestionService` with `ingest_assay_data(campaign_id, csv_content)` method
- CSV schema validation: `compound_id`, `assay_type`, `value`, `unit` (required columns)
- Unit normalization: converts nM/µM/pM → canonical µM; handles `>`, `<`, `~` operators
- Composite scoring: potency (pIC50 log-scaled, 0.01 nM → 1.0 / 1 µM → 0.5) + safety (hERG log-scaled, 30 µM → 1.0)
- Returns: `{ingested_count, errors, compound_rankings, newly_passed, newly_failed}`
- Persistence: two SQLite tables — `campaign_assay_results` + `campaign_compound_ranks`

**3. REST API** — `backend/lib/galaxy/ai/drug_discovery/api_router.py`

| Endpoint | Method | Description |
|---|---|---|
| `/{campaign_id}/ingest-assay` | POST | Upload wet-lab CSV; returns updated rankings |
| `/{campaign_id}/compounds` | GET | Current compound ranking (SMILES + scores) |
| `/{campaign_id}/export/cro-order?fmt=wuxi` | GET | Generate CRO order CSV |
| `/{campaign_id}/models/register` | POST | Register custom ML model |
| `/{campaign_id}/models/{name}/run` | POST | Execute custom model on current compounds |
| `/availability` | POST | Batch PubChem commercial availability check |

**4. Nextflow Pipeline** — `assay_ingestion_and_ranking/main.nf`

Three-process pipeline for batch/HPC-scale assay ingestion:
1. `PARSE_ASSAY_DATA` — CSV parsing, column normalization, wide-format pivot
2. `COMPUTE_COMPOSITE_SCORE` — pIC50 + hERG log-scaled scoring (customizable weights)
3. `RANK_AND_REPORT` — ranked CSV + HTML report + JSON summary

Parameters: `potency_assay`, `safety_assay`, `potency_weight`, `safety_weight`, `herg_safe_threshold`, `top_n`

**5. Frontend Widget** — `frontend/client/src/components/drug-discovery-action.tsx` (412 lines)

Three React panels:
- **AssayUploadWidget**: file picker + campaign ID → POST to ingest-assay
- **CROExportWidget**: format selector (WuXi/Pharmaron/Enamine/Generic) → download order CSV
- **CampaignDashboardWidget**: live compound ranking table with color-coded tiers

**6. Custom Model Registry** — `backend/lib/galaxy/ai/drug_discovery/custom_model_registry.py` + `custom_model_wrapper.py`

Allows external models to plug in to the DMTA loop:
- Wrapper types: Python function, Docker container, REST endpoint
- Models run against current compound set and scores are stored per campaign
- Enables integration of proprietary in-house QSAR, ML, or physics-based models

---

### What Has NOT Been Automated (Manual Gaps)

```
Current:  DESIGN → [MANUAL: CRO order] → [WET LAB: 4–12 weeks] → [MANUAL: CSV upload] → ANALYSE → DESIGN
Goal:     DESIGN → MAKE → TEST → ANALYSE → DESIGN (fully orchestrated)
```

1. **No automatic round trigger**: After `ingest-assay` returns new rankings, the BO does NOT automatically propose next round. User must manually call `/propose`.
2. **No experiment plan generation**: No workflow selects the top-N most informative compounds to order (active learning / uncertainty sampling).
3. **No LIMS integration**: Assay data must be manually exported from ELN/LIMS and uploaded as CSV.
4. **No retraining signal**: The custom model registry runs models on demand; there is no automated retrain-on-new-data event.
5. **No multi-objective Pareto UI**: The Pareto front from the BO is computed but not visualized in the frontend.

---

### Testing Status

#### Unit Tests — ALL PASSING

**`backend/lib/galaxy/ai/drug_discovery/test_bo.py`** (5 tests)
- `test_fit_and_propose`: 6 random Morgan fingerprint compounds, 3-compound proposals, validates SMILES output
- `test_insufficient_data_guard`: <3 compounds raises ValueError
- `test_save_load_round_trip`: SQLite persistence round-trip with proposal count preservation
- `test_pareto_summary`: Pareto front compound set has non-dominated scores
- `test_multi_round_numbering`: Round counter increments correctly across sessions

**`backend/lib/galaxy/ai/drug_discovery/test_cro_commercial.py`** (13 tests)
- WuXi/Pharmaron/Enamine CSV export format validation
- Scientific summary + QC report JSON structure
- Commercial availability (mock + real PubChem API calls for aspirin, caffeine)
- Mock determinism (same seed → same output)
- Batch error handling for invalid SMILES

**`backend/lib/galaxy/ai/drug_discovery/test_real_e2e.py`** (6 blocks, 50+ assertions)
- 16 real drugs (aspirin, imatinib, erlotinib, etc.) with Morgan fingerprints
- Real Gaussian Process fitting + proposal generation
- Real assay ingestion: 8 BCR-ABL inhibitor IC50 values (imatinib, nilotinib, dasatinib, ponatinib…)
- Full CRO export cycle
- Live PubChem API availability check
- QED drug-likeness scoring via RDKit

#### E2E Tests — STATUS: PASSING (from pilot study)

**`frontend/e2e/drug-discovery-pilot-e2e.e2e.ts`** — 6 sessions

- S1: ADMET screening (pilot compound set)
- S2: IVIVE hepatic clearance  
- S3: Pocket detection  
- S4: Pharmacophore filtering  
- S5: Compound ranking  
- S6: CRO export

All 6 sessions pass. Tests hit live backend with real AI responses. No mocks.

**`frontend/e2e/drug-development-ux-comprehensive.e2e.ts`**  
**`frontend/e2e/drug-development-cmc-stability-gates.e2e.ts`**  
**`frontend/e2e/drug-development-execution-truthfulness.e2e.ts`**

These cover UX comprehensiveness, CMC stability QC gates, and execution truthfulness assertions.

#### NOT YET TESTED

- The full **closed-loop cycle** (BO propose → CRO order → assay ingest → re-propose) has not been tested end-to-end as a single automated flow
- The **custom model registry** REST and Docker wrapper modes have not been E2E tested
- The **Nextflow assay_ingestion_and_ranking** pipeline has not been run on AWS Batch (only local runs)

---

## Part 6 — Summary Coverage Scorecard

| Challenge | Current Score | Priority Gap | Recommended Workflow |
|---|---|---|---|
| Long-term use / safety | 55% | Immunogenicity (ADA/T-cell) | `immunogenicity_prediction` |
| Better delivery | 20% | LNP formulation / BBB | `lnp_formulation_optimization`, `cns_penetration_prediction` |
| On-target engagement | 70% | Kinetic occupancy / CETSA | `target_engagement_kinetics` |
| Clinical translatability | 45% | PBPK / trial simulation | `pbpk_pksim`, `clinical_trial_simulation` |
| **DMTA feedback loop** | **70% implemented** | Closed-loop automation | Orchestration layer (Airflow or event-driven) |

---

## Appendix — File Map

| Component | Path |
|---|---|
| Bayesian optimizer | `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py` |
| Assay ingestion service | `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py` |
| Assay schema validation | `backend/lib/galaxy/ai/drug_discovery/assay_schema.py` |
| REST API router | `backend/lib/galaxy/ai/drug_discovery/api_router.py` |
| CRO order export | `backend/lib/galaxy/ai/drug_discovery/cro_order_export.py` |
| Commercial availability | `backend/lib/galaxy/ai/drug_discovery/commercial_availability.py` |
| Custom model registry | `backend/lib/galaxy/ai/drug_discovery/custom_model_registry.py` |
| Custom model wrapper | `backend/lib/galaxy/ai/drug_discovery/custom_model_wrapper.py` |
| Nextflow pipeline | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/assay_ingestion_and_ranking/main.nf` |
| Frontend widget | `frontend/client/src/components/drug-discovery-action.tsx` |
| Unit tests BO | `backend/lib/galaxy/ai/drug_discovery/test_bo.py` |
| Unit tests CRO | `backend/lib/galaxy/ai/drug_discovery/test_cro_commercial.py` |
| Unit tests real E2E | `backend/lib/galaxy/ai/drug_discovery/test_real_e2e.py` |
| E2E pilot suite | `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts` |
