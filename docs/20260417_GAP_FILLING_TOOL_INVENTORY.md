# BioMate Gap-Filling Tool Inventory
## All Proposed Workflows with Sample Queries, Inputs, and Outputs

**Date:** 2026-04-17  
**Scope:** Complete specification of 18 new workflows to fill drug development gaps  
**Linked to:** `docs/20260417_DRUG_DEV_GAP_ANALYSIS_AND_FEEDBACK_LOOP.md`  
**Validated against:** `backend/galaxy_ai_tools.db` (12,274 tools, 2,449 workflows)

---

## DB Validation Summary

Each of the 18 workflows has been checked against `galaxy_ai_tools.db`. Status codes:

| Code | Meaning |
|---|---|
| `DB_INSTALLABLE` | Core tool exists in DB as `installable` at priority=100 — wrap into Nextflow workflow, do NOT rebuild the tool |
| `DB_WORKFLOW_EXISTS` | nf-core/Galaxy workflow already in DB and executable — consider extending rather than rebuilding |
| `PARTIAL_EXTEND` | Existing BioMate workflow covers part of this; extend rather than build from scratch |
| `TRULY_NEW` | Not found in DB anywhere — must build end-to-end |

### Validation Results

| ID | Workflow | DB Status | DB Evidence |
|---|---|---|---|
| A1 | immunogenicity_prediction | **DB_INSTALLABLE + DB_WORKFLOW_EXISTS** | NetMHCPan 4.1 (priority=100), NetMHCiiPan 4.1 (priority=100), nf-core/epitopeprediction (id=12700), nf-core/mhcquant (id=12736) |
| A2 | repeated_dose_tox_prediction | TRULY_NEW | ProTox-3.0, rdkit-toxicophore not found in DB |
| A3 | reactive_metabolite_prediction | **DB_INSTALLABLE** | BioTransformer 3.0 (toolshed, priority=100) |
| A4 | cyp_tdi_prediction | PARTIAL_EXTEND | `cyp_ddi_panel` exists (R1+R1gut); TDI/R2 layer not implemented — extend existing |
| A5 | dart_toxicity_prediction | TRULY_NEW | OECD QSAR Toolbox, RepDose not in DB |
| B1 | lnp_formulation_optimization | TRULY_NEW | No LNP/endosomal ML tool in DB |
| B2 | cns_penetration_prediction | TRULY_NEW | CNS MPO / Kpuu model not in DB |
| B3 | oral_absorption_bcs_model | TRULY_NEW | BCS classifier / GI absorption ODE not in DB |
| B4 | nanoparticle_pk_biodistribution | TRULY_NEW | NP PK / EPR / PEG stealth model not in DB |
| B5 | membrane_permeability_prediction | TRULY_NEW | PermPred GCN, P-gp RF not in DB |
| C1 | target_engagement_kinetics | TRULY_NEW | KinScreen, occupancy ODE not in DB |
| C2 | proteome_selectivity_profiling | TRULY_NEW | DeepKinase / full kinome panel not in DB |
| C3 | covalent_warhead_design | TRULY_NEW | GSH reactivity model not in DB |
| D1 | pbpk_pksim | TRULY_NEW | PK-Sim / OSP Suite not in DB |
| D2 | clinical_trial_simulation | TRULY_NEW | mrgsolve/BOIN/simtrial not in DB (BOIN DB hits were false positives — ontology tools, not dose escalation) |
| D3 | transporter_ddi_prediction | TRULY_NEW | TransPred ML, full 8-transporter FDA panel not in DB |
| D4 | allometric_scaling | TRULY_NEW | Power law PK scaling / MABEL / MRSD not in DB |
| D5 | pharmacogenomics_stratification | **DB_INSTALLABLE** | pharmCAT 1.7.0 (toolshed, priority=100) |

### Impact on Build Plan

- **A1 accelerated**: NetMHCPan + NetMHCiiPan are Galaxy-installable at priority=100. Skip Docker build; install via Galaxy ToolShed and wrap in Nextflow process. Also consider using `nf-core/epitopeprediction` directly as base pipeline.
- **A3 accelerated**: BioTransformer 3.0 is Galaxy-installable. Wrap existing tool + add ReactMetPredict SMARTS layer on top.
- **A4 is an extension**: Do NOT build `cyp_tdi_prediction` as a new workflow. Extend `pharmacology/cyp_ddi_panel/main.nf` with a TDI process (kinact/KI estimation + R2 calculation). The docstring already mentions R2 — it just isn't coded yet.
- **D5 accelerated**: PharmCAT 1.7.0 is Galaxy-installable. Use it for VCF → PGx diplotype calling; add PharmGKB API layer for annotations.
- **11 workflows are TRULY_NEW** (B1-B5, C1-C3, D1-D2, D3): these require full build from scratch. They remain the highest-effort items.

---

## Organization

Gaps are grouped by the four key challenges from the source analysis:

| Challenge | Coverage Now | Target | New Workflows |
|---|---|---|---|
| A. Long-term use / chronic safety | 55% | 85% | 5 tools |
| B. Better delivery | 20% | 75% | 5 tools |
| C. On-target engagement | 70% | 90% | 3 tools |
| D. Clinical translatability | 45% | 80% | 5 tools |

---

# SECTION A — Long-Term Use / Chronic Safety

---

## A1. Immunogenicity Prediction

**Category:** `pharmacology/`  
**Workflow name:** `immunogenicity_prediction`  
**Priority:** P1 (critical for biologics — ADCs, bispecifics, gene therapy)  
**DB Status:** `DB_INSTALLABLE + DB_WORKFLOW_EXISTS`  
**DB Evidence:** NetMHCPan 4.1 (`galaxyp/iedb_netmhcpan/netmhcpan`, priority=100), NetMHCiiPan 4.1 (`galaxyp/iedb_netmhcpan/netmhciipan`, priority=100), nf-core/epitopeprediction (id=12700), nf-core/mhcquant (id=12736)  
**Build approach:** Install NetMHCPan/NetMHCiiPan from Galaxy ToolShed. Use `nf-core/epitopeprediction` as the Nextflow base. Add CamSol aggregation layer + deimmunization proposal logic on top. No Docker build needed for the core predictor.

### What it does
Predicts immunogenicity risk for protein therapeutics (mAbs, scFv, ADC payloads, mRNA-encoded proteins). Runs T-cell epitope mapping, HLA-II binding prediction, and aggregation propensity. Returns per-sequence risk tier and deimmunization hotspot map.

### Tools
- **NetMHCpan-4.1** — HLA-I/II binding prediction (state-of-art, Nielsen lab)
- **EpiSweep / IEDB consensus** — T-cell epitope aggregation from multiple predictors
- **CamSol** — aggregation propensity from Cambridge (solubility-reducing patches)
- **Biopython** — sequence parsing, peptide window tiling

### Sample Chat Queries
```
"Predict the immunogenicity risk of this antibody sequence: [FASTA]"
"My anti-CD20 scFv has been failing in clinical due to ADA formation. Can you map the T-cell epitope hotspots and suggest deimmunization mutations?"
"Compare the immunogenicity risk of these two bispecific antibody designs. Which one is likely to produce fewer anti-drug antibodies?"
"Run HLA-II epitope prediction for our IL-6R mAb candidate using the top 10 most common HLA alleles in the Asian population."
```

### Expected Input
```
FASTA protein sequence (VH+VL or full IgG)
Optional:
  - HLA allele panel (default: 9 most common HLA-DRB1)
  - Peptide window size (default: 9-mer for MHC-I, 15-mer for MHC-II)
  - Binding threshold IC50 (default: <500 nM = binder)
  - Population: global | Asian | European | African
```

### Expected Output
```
immunogenicity_report.html      — per-residue heat map, hotspot annotations
epitope_table.csv               — peptide sequence | HLA allele | IC50 (nM) | rank %
aggregation_patches.pdb         — structure colored by CamSol score (if PDB provided)
deimmunization_proposals.json   — top-5 point mutations to reduce top epitopes
summary.json:
  {
    "risk_tier": "HIGH | MEDIUM | LOW",
    "top_epitope_count": 7,
    "hla_coverage_pct": 82.3,
    "aggregation_hotspots": ["K97", "F100"],
    "recommended_action": "Deimmunize positions 94-101 before advancing to IND"
  }
```

---

## A2. Repeated-Dose Toxicity Prediction

**Category:** `pharmacology/`  
**Workflow name:** `repeated_dose_tox_prediction`  
**Priority:** P1 (IND-enabling studies are the #1 cost driver in drug development)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch using rdkit-toxicophore (open-source SMARTS library, pip install) + ProTox-3.0 (REST API call to their public server) + custom RDKit safety margin calculator.

### What it does
Predicts organ-level toxicity from repeated dosing using structural alerts, QSAR, and literature-derived NOAEL/LOAEL estimates. Covers hepatotoxicity, nephrotoxicity, cardiotoxicity (beyond hERG), and bone marrow suppression.

### Tools
- **Derek Nexus / open-source equivalent (SMARTS alert library)** — structural alerts for mutagenicity, hERG, hepatotoxicity
- **ProTox-3.0** — web-accessible multi-organ toxicity predictor
- **rdkit-toxicophore** — open SMARTS library for 166 toxicophore alerts
- **pk-tox integration** — maps predicted Cmax to NOAEL-derived safety margin

### Sample Chat Queries
```
"Run a repeated-dose toxicity screen for this compound [SMILES]. We're planning a 28-day rat study."
"Flag any structural alerts for hepatotoxicity or bone marrow suppression in this library of 200 compounds."
"What is the estimated therapeutic index (TI) for compound X given its IC50 of 5 nM and predicted NOAEL of 30 mg/kg?"
"We need to deprioritize compounds with >2 Class I toxicophores before CRO outsourcing. Run the filter."
```

### Expected Input
```
SMILES (single compound or CSV batch)
Optional:
  - species: rat | dog | human (for NOAEL scaling)
  - dose_route: oral | IV | SC
  - projected_Cmax_nM (for safety margin calculation)
  - alert_severity_threshold: 1 | 2 | 3 (1=most severe)
```

### Expected Output
```
tox_alerts.csv            — compound | alert_name | severity | SMARTS_match | evidence_count
tox_summary.html          — organ heat map (liver/kidney/heart/bone marrow/CNS)
noael_estimates.csv       — compound | organ | estimated_NOAEL_mg/kg | confidence
safety_margins.csv        — compound | projected_TI | recommendation
summary.json:
  {
    "compounds_screened": 200,
    "high_risk_count": 12,
    "top_alert": "quinone_formation",
    "recommended_deprioritize": ["CPD-045", "CPD-112"],
    "proceed_to_in_vivo": ["CPD-007", "CPD-023", "CPD-089"]
  }
```

---

## A3. Reactive Metabolite Prediction

**Category:** `pharmacology/`  
**Workflow name:** `reactive_metabolite_prediction`  
**Priority:** P2 (critical for idiosyncratic liver toxicity — FDA requires for NDA)  
**DB Status:** `DB_INSTALLABLE`  
**DB Evidence:** BioTransformer 3.0 (`recetox/biotransformer/biotransformer/3.0.20230403+galaxy5`, priority=100)  
**Build approach:** Install BioTransformer from Galaxy ToolShed. Write a Nextflow wrapper that runs BioTransformer → parses metabolite SMILES → applies ReactMetPredict SMARTS patterns to flag reactive intermediates → generates SVG metabolic map. Skip building BioTransformer from source.

### What it does
Predicts which metabolic transformations generate electrophilic/reactive intermediates (quinones, Michael acceptors, acylating agents, etc.) that can covalently modify proteins and trigger idiosyncratic toxicity. Maps structural liability sites.

### Tools
- **BioTransformer 3.0** — metabolic transformation prediction (CYP, UGT, SULT, gut microbiome)
- **ReactMetPredict** — reactive metabolite SMARTS pattern matching on BioTransformer outputs
- **GLORYx** — CYP-mediated metabolite prediction with site-of-metabolism

### Sample Chat Queries
```
"Does this compound form reactive metabolites through CYP3A4? Show me the predicted metabolites."
"Screen this library for compounds likely to form quinone-type reactive intermediates."
"Our compound has a furan ring — predict the epoxide/ring-opening metabolites and flag the GSH trap risk."
"Generate the full metabolic tree for [SMILES] and highlight which branches carry reactive intermediate risk."
```

### Expected Input
```
SMILES (parent compound)
Optional:
  - enzymes: CYP1A2 | CYP2C9 | CYP2D6 | CYP3A4 | UGT | all (default: all CYPs)
  - max_metabolite_generations: 2 (default)
  - flag_structural_alerts: true
  - gsh_trap_simulation: true (adds GSH conjugation check)
```

### Expected Output
```
metabolite_tree.json          — parent + all predicted metabolites, transformation type, enzyme
reactive_intermediates.csv    — metabolite_SMILES | reactive_type | enzyme | confidence
metabolic_map.svg             — visual tree with reactive intermediates highlighted in red
risk_summary.json:
  {
    "parent_SMILES": "...",
    "reactive_metabolite_count": 3,
    "highest_risk": "quinone_imine (CYP3A4)",
    "structural_alerts_triggered": ["furan", "aniline"],
    "gsh_trap_prediction": "HIGH",
    "recommendation": "Remove/replace furan ring before preclinical advancement"
  }
```

---

## A4. Time-Dependent CYP Inhibition (TDI)

**Category:** `pharmacology/`  
**Workflow name:** `cyp_tdi_prediction`  
**Priority:** P2 (mechanism-based inhibitors cause clinical DDIs that basic Ki does not predict)  
**DB Status:** `PARTIAL_EXTEND`  
**DB Evidence:** `pharmacology/cyp_ddi_panel/main.nf` already exists and computes R1 (reversible) + R1gut inhibition. The docstring mentions R2 (TDI proxy) but it is NOT yet coded.  
**Build approach:** DO NOT create a new workflow. Extend the existing `cyp_ddi_panel` pipeline: add a `CYP_TDI_PREDICTION` Nextflow process that calls pkCSM TDI ML API or runs a structural MBI alert SMARTS check → computes kinact/KI → calculates R2 per FDA guidance → appends to existing DDI report. Single PR to `cyp_ddi_panel/main.nf`.

### What it does
Predicts mechanism-based (time-dependent / irreversible) CYP inhibition. Estimates KI (inactivation constant), kinact (max inactivation rate), and clinical DDI AUC ratio. Required for FDA CYP DDI guidance beyond reversible inhibition.

### Tools
- **pkCSM** or **SuperCYP** ML models — TDI classification
- **FDA static DDI model** — net AUC ratio from kinact/KI + fu,mic
- Integration with existing `cyp_ddi_panel` workflow output

### Sample Chat Queries
```
"Our compound is a strong CYP3A4 inhibitor at 10 nM but we think it may also be a mechanism-based inhibitor. Run TDI prediction."
"Calculate the projected DDI AUC ratio for [SMILES] as a CYP2D6 mechanism-based inhibitor with projected Cmax of 2 µM."
"Flag all compounds in our library that carry structural alerts for MBI (methylenedioxyphenyl, acetylenic groups, etc.)."
```

### Expected Input
```
SMILES
Projected_Cmax_uM (unbound plasma)
Optional:
  - CYP_isoforms: [CYP3A4, CYP2D6, CYP2C9] (default: all 5)
  - hepatocyte_fu_mic: float (microsomal unbound fraction)
  - dose_mg: float (for systemic exposure estimate)
```

### Expected Output
```
tdi_results.csv:
  compound | CYP | KI_uM | kinact_min-1 | kinact/KI | TDI_class | AUC_ratio_predicted
fda_ddi_flags.json:
  { "CYP3A4": { "TDI": true, "AUC_ratio": 4.2, "FDA_category": "Conduct clinical DDI study" } }
mbi_alerts.csv:
  compound | alert_name | SMARTS | severity
```

---

## A5. DART Toxicity Prediction

**Category:** `pharmacology/`  
**Workflow name:** `dart_toxicity_prediction`  
**Priority:** P3 (required for drugs intended for women of childbearing potential; ICH S5)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch; OECD QSAR Toolbox has an API but requires institutional license — use open SMARTS alert library (rdkit-toxicophore) + physicochemical placental transfer model as open-source substitute.

### What it does
Predicts developmental and reproductive toxicity (DART) risk. Screens for teratogenicity, embryotoxicity, and reproductive harm using QSAR models and structural alerts.

### Tools
- **OECD QSAR Toolbox** structural alerts (open)
- **RepDose** database-derived thresholds
- **RDKit** physicochemical property filters for placental transfer

### Sample Chat Queries
```
"Assess the DART risk for our small molecule. It's intended for women of childbearing age."
"Screen these 50 compounds for teratogenic structural alerts before we run ICH S5 studies."
"Does the molecular weight and LogP of this compound suggest significant placental transfer?"
```

### Expected Input
```
SMILES (single or batch CSV)
Optional:
  - indication_population: all | women_cbp | pediatric
  - run_placental_transfer_model: true
```

### Expected Output
```
dart_alerts.csv         — compound | alert_type | mechanism | confidence
placental_transfer.csv  — compound | MW | LogP | transfer_likelihood | threshold_exceeded
dart_risk_tier.json:
  { "risk": "MEDIUM", "alerts": ["nitroso_reduction", "aromatic_amine"],
    "placental_transfer": "HIGH (MW=287, LogP=2.1)",
    "recommendation": "Run ICH S5(A) fertility + embryo-fetal study before Phase II" }
```

---

# SECTION B — Better Delivery

---

## B1. LNP Formulation Optimizer

**Category:** `drug_discovery/`  
**Workflow name:** `lnp_formulation_optimization`  
**Priority:** P1 (mRNA vaccines, siRNA, ASO, gene therapy all depend on LNP delivery)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build end-to-end. Core models: RDKit pKa + custom endosomal escape ML (train on Semple/Kulkarni literature data). Integrate with existing `BayesianOptimizer` for component ratio search.

### What it does
Optimizes lipid nanoparticle (LNP) formulation for nucleic acid delivery. Predicts ionizable lipid pKa, endosomal escape probability, and tissue targeting score. Optionally uses Bayesian optimization to explore component ratios.

### Tools
- **RDKit** — ionizable lipid pKa prediction, LogP, molecular descriptor calculation
- **OpenBabel** — SMILES → 3D structure for electrostatic surface calculation
- **Custom ML model** — endosomal escape classifier (trained on literature LNP data)
- **BO module** (existing `BayesianOptimizer`) — component ratio search

### Sample Chat Queries
```
"I have a new ionizable lipid [SMILES]. Predict its pKa and estimate endosomal escape efficiency for liver-targeted mRNA delivery."
"Optimize the molar ratio of ionizable lipid:DSPC:cholesterol:PEG-lipid for our siRNA targeting the lung."
"Compare the delivery efficiency of DLin-MC3-DMA vs our novel lipid candidate for hepatic mRNA delivery."
"We need an LNP formulation with <50 nm particle size and >80% encapsulation efficiency. Which lipid ratios should we test first?"
```

### Expected Input
```
ionizable_lipid_SMILES: str
helper_lipid_SMILES: str (e.g., DSPC, DOPE)
cargo_type: mRNA | siRNA | ASO | DNA
target_tissue: liver | lung | spleen | muscle | CNS
Optional:
  - run_bo_optimization: true
  - bo_iterations: 20
  - peg_lipid_fraction: 0.01-0.05 (fixed or optimizable)
  - particle_size_target_nm: 50-150
```

### Expected Output
```
lipid_properties.csv:
  lipid | pKa | LogP | headgroup_charge_pH7 | ionization_at_endosomal_pH
formulation_predictions.csv:
  ratio (IL:helper:chol:PEG) | predicted_encapsulation_pct | predicted_size_nm | tissue_score
bo_optimization_trace.json    — acquisition values per BO round (if enabled)
endosomal_escape_score.json:
  { "score": 0.74, "mechanism": "proton_sponge", "confidence": "MEDIUM" }
recommended_formulation.json:
  { "IL_mol_pct": 50, "DSPC_mol_pct": 10, "cholesterol_mol_pct": 38.5,
    "PEG_mol_pct": 1.5, "predicted_size_nm": 85, "encapsulation_pct": 87 }
```

---

## B2. BBB / CNS Penetration Prediction

**Category:** `pharmacology/`  
**Workflow name:** `cns_penetration_prediction`  
**Priority:** P1 (CNS programs have 40% attrition from insufficient brain penetration)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. CNS MPO (6-descriptor RDKit calculation) is trivial; Kpuu,brain and P-gp ML models require training on curated MDCK-MDR1 / brain PK literature datasets.

### What it does
Predicts blood-brain barrier permeability and CNS drug exposure. Estimates Kp,uu,brain (unbound brain-to-plasma ratio), P-gp efflux ratio, BCRP substrate status, and CNS Multiparameter Optimization (MPO) score.

### Tools
- **RDKit** — CNS MPO descriptors (LogP, TPSA, MW, HBD, pKa, LogD7.4)
- **B3PP** or custom MDCK-MDR1 permeability ML model
- **P-gp efflux classifier** (RF trained on literature P-gp substrate data)
- **Kp,uu,brain** estimator from unbound fraction and P-gp contribution

### Sample Chat Queries
```
"Predict CNS penetration for our Parkinson's target compound. SMILES: [...]"
"Screen our CNS library and flag all compounds with CNS MPO score < 4 — these will fail brain penetration."
"Is this compound likely to be a P-gp substrate? The target is in the striatum and we're seeing no efficacy in our mouse model."
"Estimate Kp,uu,brain for compound X with LogP=2.3, TPSA=67, MW=342 and compare to our reference tool compound."
```

### Expected Input
```
SMILES (single or batch CSV)
Optional:
  - pKa: float (if known)
  - logD74: float (if measured)
  - fu_plasma: float (unbound fraction in plasma, if measured)
  - predict_efflux_ratio: true
```

### Expected Output
```
cns_properties.csv:
  compound | LogP | TPSA | MW | HBD | pKa | LogD74 | CNS_MPO_score
pgp_prediction.csv:
  compound | Pgp_substrate | Pgp_IC50_uM_predicted | BCRP_substrate | efflux_ratio_predicted
brain_penetration.csv:
  compound | Kpuu_brain_predicted | BBB_class (HIGH/MED/LOW) | confidence
summary.json:
  { "CNS_MPO": 4.8, "BBB_class": "HIGH", "Kpuu_brain": 0.42,
    "Pgp_substrate": false, "recommendation": "Favorable CNS profile; advance to brain PK study" }
```

---

## B3. Oral Absorption & Dissolution Modeling

**Category:** `pharmacology/`  
**Workflow name:** `oral_absorption_bcs_model`  
**Priority:** P2 (first-pass and dissolution failures account for ~30% of clinical PK failures)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. ESOL/Ali solubility is a 2-line RDKit call. BCS classification logic and GI absorption ODE model are custom Python. Leverage existing `nlmixr2` container for ODE solving.

### What it does
Classifies compound by Biopharmaceutics Classification System (BCS), predicts in vivo dissolution kinetics under fed/fasted conditions, estimates oral bioavailability (F%), and flags formulation risks.

### Tools
- **RDKit** — solubility (ESOL/Ali model), LogP, pKa
- **PBPK absorption module** — compartmental GI absorption with pH gradient
- **BCS classifier** — permeability (Caco-2 ML) + solubility → BCS class I/II/III/IV

### Sample Chat Queries
```
"What BCS class is this compound? We need to decide between salt form and amorphous dispersion."
"Predict oral bioavailability for compound X with LogP=4.5 and water solubility of 3 µg/mL."
"Model the fed vs fasted dissolution profile for our BCS Class II compound with a projected dose of 20 mg."
"Our compound has poor solubility. Should we use spray-dried dispersion or hot-melt extrusion?"
```

### Expected Input
```
SMILES
dose_mg: float
Optional:
  - pKa: float
  - measured_solubility_ugmL: float
  - measured_Caco2_cm_s: float
  - formulation_type: free_base | HCl_salt | amorphous | nanoparticle
  - fed_fasted: fed | fasted | both
```

### Expected Output
```
bcs_classification.json:
  { "BCS_class": "II", "solubility_mgmL": 0.021, "permeability_class": "HIGH",
    "absorption_limiting_step": "dissolution" }
dissolution_profile.csv:     time_min | dissolved_pct_fasted | dissolved_pct_fed
pk_predictions.csv:          Tmax_h | Cmax_ngmL | AUC_nghmL | F_pct
formulation_recommendation.json:
  { "recommended": "amorphous_spray_dried_dispersion",
    "rationale": "LogP=4.5 + BCS II; ASD predicted to increase Fabs from 22% to 68%",
    "risk": "physical_stability_monitoring_required" }
```

---

## B4. Nanoparticle Pharmacokinetics & Biodistribution

**Category:** `pharmacology/`  
**Workflow name:** `nanoparticle_pk_biodistribution`  
**Priority:** P2 (for oncology NPs, targeted delivery, and long-circulating formulations)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. 3-compartment NP PK ODE (blood/tumor/MPS) is ~100 lines of SciPy. EPR and PEG stealth models parameterized from Arvizo/Wilhelm meta-analysis data.

### What it does
Models the in vivo pharmacokinetics of nanoparticle-formulated drugs. Predicts circulation half-life, tumor EPR accumulation, MPS uptake (liver/spleen), and tissue distribution over time. Builds on the existing radiolabeled antibody biodistribution workflow.

### Tools
- **Physiologically-based NP PK model** — 3-compartment (blood, tumor, MPS organs)
- **PEG brush density model** — steric stabilization effect on opsonization/half-life
- **EPR model** — tumor accumulation as function of tumor vasculature permeability
- **ndlib** or custom ODE solver

### Sample Chat Queries
```
"Model the PK of our 80 nm PEGylated PLGA nanoparticle after IV injection. Predict tumor accumulation at 24h."
"How does particle size (50 nm vs 100 nm vs 200 nm) affect liver uptake and tumor EPR for our drug delivery system?"
"Our LNP formulation has 2 mol% PEG-lipid. Will this provide sufficient stealth to achieve >8h half-life?"
"Generate a biodistribution prediction for our antibody-drug conjugate vs the same payload in a targeted NP."
```

### Expected Input
```
particle_diameter_nm: float
surface_chemistry: PEG | lipid | polymer | bare
PEG_density_chains_per_nm2: float (if PEG coated)
dose_mg/kg: float
tumor_model: none | subcutaneous | orthotopic (affects EPR parameter)
Optional:
  - zeta_potential_mV: float
  - PEG_MW_Da: float
  - tumor_vasculature_permeability: low | medium | high
```

### Expected Output
```
pk_profile.csv:             time_h | blood_ngmL | tumor_%ID/g | liver_%ID/g | spleen_%ID/g
half_life_summary.json:
  { "t_half_h": 9.2, "AUC_blood": 142, "tumor_peak_pct_ID_per_g": 8.3,
    "tumor_peak_time_h": 24, "liver_uptake_24h_pct": 31 }
biodistribution_plot.html  — interactive time-course per tissue
formulation_risk.json:
  { "MPS_clearance_risk": "MEDIUM", "stealth_rating": "ADEQUATE",
    "recommendation": "Increase PEG density to 0.15 chains/nm² for improved circulation" }
```

---

## B5. Permeability Prediction (Caco-2 / PAMPA / P-gp)

**Category:** `pharmacology/`  
**Workflow name:** `membrane_permeability_prediction`  
**Priority:** P2 (replaces in vitro assays early in discovery; enables go/no-go on oral route)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Use GCN or Morgan fingerprint RF models trained on Caco-2/P-gp data from ChEMBL + literature. Models are ~200-500 data-point range, feasible to train in-house.

### What it does
Predicts apparent permeability (Papp) across intestinal (Caco-2) and artificial membranes (PAMPA). Classifies P-gp substrate/inhibitor status. Outputs efflux ratio prediction and BCS permeability class.

### Tools
- **PermPred ML** — Caco-2 Papp A→B and B→A prediction (GCN-based)
- **PAMPA QSAR** — RDKit descriptor-based PAMPA predictor
- **P-gp Random Forest** — trained on >2000 Pgp substrate/inhibitor measurements

### Sample Chat Queries
```
"Predict Caco-2 permeability and P-gp efflux ratio for our oral drug candidate."
"This compound has measured PAMPA Papp of 8×10⁻⁶ cm/s but poor oral absorption in rats. Could P-gp efflux explain the discrepancy?"
"Filter our library to keep only compounds with predicted Caco-2 Papp > 10×10⁻⁶ cm/s and efflux ratio < 2."
```

### Expected Input
```
SMILES (single or batch)
Optional:
  - measured_PAMPA_cm_s: float (to calibrate model)
  - pH_donor: 6.8 | 7.4
  - include_Pgp_prediction: true (default)
```

### Expected Output
```
permeability_results.csv:
  compound | Papp_AB_1e-6_cm_s | Papp_BA_1e-6_cm_s | efflux_ratio | Pgp_substrate | BCS_permeability_class
permeability_summary.json:
  { "high_perm_count": 45, "Pgp_substrate_count": 12,
    "recommended_deprioritize": ["CPD-034 (efflux_ratio=14.2)"] }
```

---

# SECTION C — On-Target Engagement

---

## C1. Target Engagement Kinetics (Residence Time)

**Category:** `drug_discovery/`  
**Workflow name:** `target_engagement_kinetics`  
**Priority:** P2 (drug-target residence time is a better predictor of in vivo efficacy than Kd alone)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. KinScreen ML model or structure-activity descriptor-based koff prediction. Occupancy ODE is a simple 2-equation SciPy system. koff via MD proxy reuses existing GROMACS/AMBER Nextflow processes.

### What it does
Estimates binding kinetic rate constants (kon, koff) and drug-target residence time (RT = 1/koff) from structural and physicochemical properties. Predicts occupancy over time given a PK profile. Particularly relevant for slow-binding covalent or allosteric mechanisms.

### Tools
- **KinScreen** ML model — kon/koff prediction from Morgan fingerprints + protein descriptors
- **ODE occupancy solver** — combines PK (Cp(t) from nlmixr2/NCA) with target binding kinetics
- **MD-derived koff** — short MD simulation proxy for dissociation rate (uses existing GROMACS/AMBER)

### Sample Chat Queries
```
"Predict the target residence time of our BTK inhibitor. How long will it remain bound to BTK after drug washout?"
"Our compound has IC50=2 nM but loses efficacy at 12h post-dose. Is this a fast-koff issue? Estimate the koff."
"Model the receptor occupancy vs time for compound X using its measured PK parameters (t½=6h, Cmax=250 nM)."
"Compare the kinetic selectivity profiles of our compound against the 3 closest off-target kinases."
```

### Expected Input
```
SMILES (ligand)
target_PDB or target_name: str
Optional:
  - measured_Kd_nM or IC50_nM: float
  - pk_params: { t_half_h, Cmax_nM, tmax_h }   (for occupancy model)
  - run_md_koff_proxy: true | false
  - occupancy_threshold_pct: 80 (for duration-of-action estimate)
```

### Expected Output
```
kinetics_prediction.json:
  { "kon_M-1s-1": 1.2e5, "koff_s-1": 6.1e-4, "Kd_nM": 5.1,
    "residence_time_min": 27, "confidence": "MEDIUM" }
occupancy_profile.csv:      time_h | occupancy_pct | Cp_nM
occupancy_plot.html         — interactive receptor occupancy vs time curve
kinetic_selectivity.csv:    target | kon | koff | RT_min | selectivity_index
recommendation.json:
  { "RT_adequate_for_qd_dosing": false,
    "recommendation": "Optimize for slower koff — target RT > 120 min for once-daily dosing" }
```

---

## C2. Proteome-Wide Selectivity Profiling

**Category:** `drug_discovery/`  
**Workflow name:** `proteome_selectivity_profiling`  
**Priority:** P2 (selectivity at proteome scale is required for kinase/GPCR/epigenetic programs)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Use ChEMBL per-target RF models or deploy an existing open-source model (e.g., DeepKinase/PKIDB). Selectivity entropy and Gini index are pure Python calculations.

### What it does
Predicts binding affinity across a panel of structurally related off-targets using pre-built proteome-scale models. For kinases: 468 kinome. For GPCRs: 400 receptors. Returns selectivity entropy and Gini index.

### Tools
- **DeepKinase** / **KinomeSCAN ML** — kinase panel (468 kinases, IC50 prediction)
- **ChEMBL GPCR models** — RF/GBM per GPCR from ChEMBL training data
- **BindingDB** proteome panel — available models for 2000+ targets
- **Selectivity entropy** and **Gini index** calculation

### Sample Chat Queries
```
"Run a kinome-wide selectivity screen for our CDK4/6 inhibitor. Flag any unexpected off-targets with IC50 < 100 nM."
"Our GPCR compound is hitting 5-HT2A. Screen the full GPCR panel to understand the selectivity profile."
"Generate a selectivity dendrogram for our compound vs the approved CDK inhibitors (palbociclib, ribociclib, abemaciclib)."
"What is the kinase selectivity entropy for our compound? Is it a selective or promiscuous binder?"
```

### Expected Input
```
SMILES
target_class: kinase | GPCR | nuclear_receptor | epigenetic | all
Optional:
  - panel_size: full | focused_50 | focused_10
  - IC50_threshold_nM: 100 (flag hits below this)
  - reference_compounds: [SMILES1, SMILES2] (for selectivity comparison)
```

### Expected Output
```
selectivity_panel.csv:
  target | predicted_IC50_nM | selectivity_score | flag_hit
selectivity_dendrogram.html  — kinome tree with hit nodes colored by IC50
selectivity_metrics.json:
  { "selectivity_entropy": 1.24, "Gini_index": 0.87,
    "primary_target_IC50": 3.2, "off_target_hits": ["CDK2: 18 nM", "CDK9: 45 nM"],
    "selectivity_verdict": "SELECTIVE (Gini > 0.8)" }
comparison_heatmap.html      — compound vs reference drugs heatmap
```

---

## C3. Covalent Warhead Reactivity & Selectivity

**Category:** `drug_discovery/`  
**Workflow name:** `covalent_warhead_design`  
**Priority:** P3 (covalent drugs are ~20% of approved kinase inhibitors; warhead reactivity is the key design parameter)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Warhead classification is SMARTS-based (trivial). GSH half-life model requires training on literature thiol reactivity data (~300 measurements available in CovPDB). CovPDB lookup can be done via RDKit substructure matching against a local copy.

### What it does
Evaluates electrophilic warhead reactivity for targeted covalent inhibitors. Predicts half-life with glutathione (GSH t½), thiol selectivity, and likelihood of promiscuous off-target modification.

### Tools
- **RDKit + CovalentDock** — warhead classification (acrylamide, chloroacetamide, vinyl sulfone, etc.)
- **GSH reactivity model** — half-life prediction in glutathione at physiological conditions
- **CovPDB** literature data — known covalent target-warhead pairs
- **WaterMap proxy** — burial of Cys residue accessibility in binding site (if PDB provided)

### Sample Chat Queries
```
"Assess the reactivity of our acrylamide warhead. Is it too reactive (pan-assay interference) or appropriate for targeted covalent inhibition?"
"Compare the GSH half-life of these three warhead variants: acrylamide vs propiolamide vs cyanoacrylamide."
"Our KRASG12C inhibitor carries an acrylamide. Predict its promiscuity risk across non-catalytic cysteines in the kinome."
```

### Expected Input
```
SMILES (covalent inhibitor with warhead)
target_cysteine: residue_ID (e.g., C797 for EGFR) — optional, improves prediction
warhead_type: auto-detect | acrylamide | chloroacetamide | vinyl_sulfone | boronate
Optional:
  - run_GSH_halflife: true
  - run_kinome_cys_selectivity: true
  - target_PDB: str
```

### Expected Output
```
warhead_profile.json:
  { "warhead_type": "acrylamide", "GSH_t_half_h": 3.2,
    "reactivity_class": "MODERATE (suitable for targeted covalent)",
    "promiscuity_risk": "LOW" }
cys_selectivity.csv:         kinase | cysteine | predicted_labeling_efficiency_pct
gsh_reactivity_comparison.csv  (if multiple warheads)
recommendation.json:
  { "verdict": "PROCEED", "note": "GSH t½ = 3.2h is in optimal range (2-5h); proceed to selectivity profiling" }
```

---

# SECTION D — Clinical Translatability

---

## D1. PBPK Modeling (Organ-Level PK)

**Category:** `drug_discovery/`  
**Workflow name:** `pbpk_pksim`  
**Priority:** P1 (FDA increasingly requires PBPK for DDI submissions and pediatric dose extrapolation)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Wrap `ospsuite/pk-sim` Docker image in a Nextflow process. PK-Sim supports batch CLI execution via `pksim-batch` command. Input: PKML parameter file (auto-generated from user-provided physicochemical + clearance params). Output: CSV time-course + NCA summary.

### What it does
Full physiologically-based pharmacokinetic model with organ-specific compartments: gut wall, liver (first-pass), blood, lung, kidney, peripheral tissues. Predicts oral bioavailability with mechanistic absorption, tissue distribution, hepatic/renal clearance, transporter effects.

### Tools
- **PK-Sim** (Open Systems Pharmacology Suite) — gold-standard open-source PBPK
- **MoBi** — systems biology model coupling (for QSP extensions)
- Docker container: `ospsuite/pk-sim:latest`

### Sample Chat Queries
```
"Build a PBPK model for compound X. It has microsomal CLint of 45 µL/min/mg, fu,plasma of 0.08, and is a P-gp substrate."
"Predict how hepatic impairment (Child-Pugh B) will change the exposure of our compound — we need this for our FDA submission."
"Simulate pediatric dosing for ages 2-17 based on our adult PBPK model. What dose adjustment is needed?"
"Model the DDI between our compound (OATP1B1 substrate) and rifampin (OATP1B1 inhibitor) in the clinic."
```

### Expected Input
```
SMILES
physicochemical:
  - MW, LogP/LogD, pKa, fu_plasma, fu_mic (microsomal unbound fraction)
clearance:
  - CLint_uL_min_mg (microsomal or hepatocyte)
  - renal_clearance_mL_min (if applicable)
transporters:
  - OATP1B1_substrate: true | false
  - Pgp_substrate: true | false
  - Pgp_IC50_uM: float
population: healthy_adult | child_2-5 | elderly | hepatic_impairment | renal_impairment
dose_mg, dose_route: oral | IV | SC
Optional:
  - DDI_perpetrator_SMILES + dose (for DDI simulation)
```

### Expected Output
```
pk_profile.csv:             time_h | Cp_plasma_ngmL | Ct_liver_ngmL | Ct_kidney_ngmL | ...
nca_parameters.json:
  { "AUCinf_ngh_mL": 1240, "Cmax_ng_mL": 87, "t_half_h": 9.3, "F_pct": 68,
    "CL_F_L_h": 14.2, "Vd_F_L": 189 }
ddi_fold_change.json:       { "AUC_ratio": 3.4, "Cmax_ratio": 2.1, "clinical_DDI_risk": "MODERATE" }
population_pk.csv:          population | AUCinf | Cmax | dose_adjustment_factor
regulatory_summary.txt:     ICH M12 compliant DDI risk assessment narrative
```

---

## D2. Clinical Trial Simulation

**Category:** `drug_discovery/`  
**Workflow name:** `clinical_trial_simulation`  
**Priority:** P1 (FDA Model-Informed Drug Development; reduces trial-and-error in dose selection)  
**DB Status:** `TRULY_NEW`  
**DB Note:** DB query for "BOIN" returned false positives (ontology/bioinformatics tools, not dose escalation). mrgsolve, simtrial, BOIN R packages not present.  
**Build approach:** Build from scratch. Wrap mrgsolve + BOIN R packages in a Docker container with R. Input: PopPK parameter JSON + trial design config. The `nlmixr2` container already exists in BioMate — reuse it as the base image and add mrgsolve/BOIN packages.

### What it does
Simulates Phase I–II clinical trials using PopPK parameters and exposure-response relationships. Supports adaptive dose escalation designs (3+3, BOIN, mTPI-2) and parallel-group efficacy simulations with virtual patient populations.

### Tools
- **nlmixr2** (already in BioMate) — PopPK/PD model base
- **mrgsolve** — fast ODE-based clinical simulation (R package, Docker)
- **BOIN R package** — Bayesian Optimal Interval dose escalation
- **simtrial** (Merck) — adaptive trial simulation
- Virtual patient library: built from nlmixr2 PopPK + literature variability priors

### Sample Chat Queries
```
"Simulate a Phase I dose escalation for our oncology compound. Start at 10 mg, max 400 mg. Use BOIN design targeting 25% DLT rate."
"We have Phase I PK data from 24 patients. Build a PopPK model and simulate the efficacy response at 100 mg BID in a Phase II population of 200 patients."
"What dose provides >80% target occupancy in 90% of patients? Use the receptor occupancy model from our Phase I data."
"Compare the operating characteristics of 3+3 vs BOIN for our compound. Show probability of correct MTD selection."
```

### Expected Input
```
For Phase I simulation:
  - starting_dose_mg, max_dose_mg, dose_levels (list)
  - DLT_rate_target: 0.25 (typical oncology)
  - design: 3+3 | BOIN | mTPI2
  - n_simulations: 1000
  - pk_params: { CL, Vd, ka } + inter-individual variability (IIV_pct)

For Phase II simulation:
  - popPK_model: (output from nlmixr2 or parameter set)
  - ER_model: { Emax, EC50, E0 } or linear
  - n_patients: int
  - dose_regimen: { dose_mg, frequency }
  - primary_endpoint: { metric, threshold, timepoint }
```

### Expected Output
```
dose_escalation_results.csv:
  dose_level | DLT_rate_simulated | patients_treated | P_dose_selection
BOIN_decision_table.html    — real-time decision rules for clinical team
phase2_simulation.csv:
  dose_mg | response_rate_pct | CI_95 | P_success | expected_sample_size
operating_characteristics.json:
  { "P_correct_MTD_selection": 0.82, "P_underdosing": 0.06, "P_overdosing": 0.12 }
pk_vpc.html                 — visual predictive check for PopPK model
ER_plot.html                — exposure-response curve with confidence band
recommendation.json:
  { "recommended_Phase2_dose": "150 mg QD",
    "rationale": "82% target occupancy in 90% patients; DLT rate 18% at 150 mg",
    "sample_size_Phase2": 120 }
```

---

## D3. Transporter-Mediated DDI Prediction

**Category:** `pharmacology/`  
**Workflow name:** `transporter_ddi_prediction`  
**Priority:** P1 (FDA DDI guidance 2020 requires OATP1B1/3, P-gp, BCRP assessment for all NMEs)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Train RF/GBM models per transporter using ChEMBL + BindingDB curated data. FDA static DDI equations (basic model) are deterministic math — implement in Python. Target: 8 FDA-required transporters (OATP1B1, OATP1B3, P-gp, BCRP, MATE1, MATE2-K, OAT1, OCT2).

### What it does
Predicts substrate and inhibitor status for FDA-mandated drug transporters. Calculates static DDI AUC ratios per FDA guidance equations. Flags which transporters require in vitro mechanistic studies and which require clinical DDI studies.

### Tools
- **TransPred ML models** — trained on ChEMBL/BindingDB transporter data for 8 transporters
- **FDA static DDI equations** — basic model for OATP1B1/3, P-gp, BCRP, MATE1/2, OAT1/3, OCT2
- **RDKit molecular descriptors** — feature input for ML models

### Sample Chat Queries
```
"Is our statin analog an OATP1B1/3 substrate? We're concerned about co-administration with cyclosporine."
"Run the full FDA transporter DDI assessment for our compound to prepare the NDA DDI package."
"Our compound is a BCRP inhibitor at 0.5 µM. Calculate the expected DDI AUC ratio with rosuvastatin."
"Screen our lead series for P-gp inhibitors — any compound that could boost exposure of narrow-index drugs is a risk."
```

### Expected Input
```
SMILES (victim compound)
Projected_Cmax_uM (unbound)
Optional:
  - DDI_victim_SMILES: str (for inhibitor scenario)
  - perpetrator_dose_mg: float
  - transporters_to_assess: [OATP1B1, OATP1B3, Pgp, BCRP, MATE1, MATE2, OAT1, OCT2]
    (default: all 8 FDA-required)
```

### Expected Output
```
transporter_results.csv:
  transporter | substrate_probability | inhibitor_IC50_uM_predicted | FDA_risk_flag
static_ddi_model.csv:
  transporter | victim_SMILES | AUC_ratio | Cmax_ratio | FDA_recommendation
regulatory_summary.json:
  { "requires_in_vitro_study": ["OATP1B1", "Pgp"],
    "requires_clinical_DDI_study": ["OATP1B1 (AUC ratio 2.3)"],
    "no_action_required": ["OAT1", "OCT2"],
    "NDA_labeling_needed": true }
```

---

## D4. Allometric Scaling & Species Translation

**Category:** `pharmacology/`  
**Workflow name:** `allometric_scaling`  
**Priority:** P2 (first human dose prediction requires animal-to-human PK extrapolation)  
**DB Status:** `TRULY_NEW`  
**Build approach:** Build from scratch. Power law regression is pure Python/SciPy (10 lines). Rule of Exponents and MABEL/MRSD dose calculation are deterministic formulas — no ML required. Entire workflow could be a single Python script in a lightweight container.

### What it does
Scales pharmacokinetic parameters from preclinical species (mouse, rat, dog, monkey) to human predictions using allometric regression, correction factors (brain weight, maximum lifespan potential), and fixed exponent methods.

### Tools
- **Custom R/Python allometric regression** — power law scaling (CL, Vd, t½ vs body weight)
- **Rule of Exponents** (Mahmood 2003) — correction with MLP or brain weight
- **IVIVE integration** — hepatic CLint + fu,plasma → in vivo CL
- **First-in-human dose predictor** — toxicokinetic-informed starting dose (MABEL)

### Sample Chat Queries
```
"Scale our compound's PK from rat and dog to human. Rat: CL=12 mL/min/kg, Vd=1.8 L/kg. Dog: CL=6 mL/min/kg, Vd=2.1 L/kg."
"We have rat, mouse, and monkey PK data. Predict human Cmax and AUC at a starting dose of 10 mg."
"What is the MABEL-based maximum recommended starting dose for our compound given the NOEL in rat of 20 mg/kg?"
"Does our compound follow simple allometry or do we need a correction factor for clearance prediction?"
```

### Expected Input
```
species_pk_data:
  - species: mouse | rat | dog | monkey
  - CL_mL_min_kg: float
  - Vd_L_kg: float
  - t_half_h: float (optional, calculated from CL+Vd if not provided)
  - body_weight_kg: float
human_body_weight_kg: 70 (default)
Optional:
  - correction_method: simple | MLP | brain_weight | rule_of_exponents
  - iv_or_oral: IV | oral
  - fu_plasma_rat: float (for IVIVE cross-check)
  - toxicokinetic_NOEL_mg_kg: float (for MRSD calculation)
```

### Expected Output
```
allometric_regression.csv:   species | BW_kg | CL | Vd | t_half
allometric_plot.html         — log-log regression with human extrapolation
human_pk_prediction.json:
  { "CL_mL_min_kg_human": 4.2, "Vd_L_kg_human": 1.1, "t_half_h_human": 8.9,
    "prediction_method": "simple_allometry",
    "goodness_of_fit_R2": 0.97 }
fih_dose_recommendation.json:
  { "MRSD_mg_human": 3, "MABEL_dose_mg": 1.5,
    "basis": "1/10 NOEL × HED conversion factor",
    "regulatory_basis": "FDA Guidance 2005 Estimating Maximum Safe Starting Dose" }
```

---

## D5. Pharmacogenomics-Informed Patient Stratification

**Category:** `pharmacology/`  
**Workflow name:** `pharmacogenomics_stratification`  
**Priority:** P2 (companion diagnostics and enrichment strategies now required in many oncology trials)  
**DB Status:** `DB_INSTALLABLE`  
**DB Evidence:** pharmCAT 1.7.0 (`bgruening/pharmcat/pharmcat/1.7.0+galaxy0`, priority=100)  
**Build approach:** Install pharmCAT from Galaxy ToolShed for VCF → PGx diplotype calling. Add PharmGKB REST API layer for gene-drug annotations. Biomarker discovery path reuses existing `drug_moa_rnaseq` DESeq2 workflow via Nextflow `includeConfig`. No Docker build needed for the core PGx caller.

### What it does
Integrates patient genomic data with drug response predictions. Predicts PK variability from CYP/transporter genotypes. Suggests trial enrichment biomarkers. Extends the existing CYP2C19 MWAS workflow to a full PGx panel.

### Tools
- **PharmGKB API** — gene-drug associations, variant annotations
- **PharmCAT** — PGx diplotype calling from VCF → actionable PharmGKB annotations
- **DESeq2** — biomarker discovery from responder/non-responder RNA-seq (uses existing drug_moa_rnaseq)
- **Logistic regression** — genomic feature → response classifier

### Sample Chat Queries
```
"Our compound is metabolized primarily by CYP2D6. What fraction of the European population are poor metabolizers and how much will their exposure increase?"
"Identify predictive biomarkers for response to our KRAS inhibitor from this RNA-seq dataset of 80 responders vs 40 non-responders."
"Which HER2 mutation subtypes are predicted to respond to our compound based on structural binding models?"
"We're planning a Phase II enrichment design. Based on PGx, should we exclude CYP2C9 poor metabolizers?"
```

### Expected Input
```
For PK stratification:
  - SMILES (metabolized by CYP/transporter)
  - primary_metabolizing_enzyme: CYP2D6 | CYP2C9 | CYP2C19 | CYP3A4 | UGT1A1
  - population: European | Asian | African | global
  - fm (fraction metabolized by primary enzyme): float

For biomarker discovery:
  - rnaseq_matrix_csv (gene × sample)
  - sample_metadata_csv (sample | response: responder/non-responder | dose | timepoint)

For genotype-phenotype:
  - vcf_file: patient VCF (SNP calls)
```

### Expected Output
```
pgx_stratification.json:
  { "CYP2D6_PM_prevalence_European_pct": 7.2,
    "fold_increase_PM_vs_EM": 4.8,
    "dose_adjustment_PM": "reduce by 75%",
    "PharmGKB_annotation": "Pharmacogenomics Clinical Annotation Level 1A" }
biomarker_candidates.csv:    gene | logFC | padj | biomarker_type | predictive_AUC
enrichment_recommendation.json:
  { "recommended_inclusion_biomarker": "KRAS_G12C",
    "expected_enrichment_factor": 3.2,
    "predicted_response_rate_enriched": 0.62,
    "predicted_response_rate_unselected": 0.19 }
```

---

# Summary Table

| ID | Tool Name | Category | Challenge | Priority | DB Status | Key Technologies |
|---|---|---|---|---|---|---|
| A1 | immunogenicity_prediction | pharmacology | Long-term use | P1 | DB_INSTALLABLE + DB_WORKFLOW_EXISTS | NetMHCPan-4.1 (ToolShed), nf-core/epitopeprediction (id=12700), CamSol |
| A2 | repeated_dose_tox_prediction | pharmacology | Long-term use | P1 | TRULY_NEW | ProTox-3.0, SMARTS alerts, rdkit-toxicophore |
| A3 | reactive_metabolite_prediction | pharmacology | Long-term use | P2 | DB_INSTALLABLE | BioTransformer 3.0 (ToolShed), ReactMetPredict SMARTS |
| A4 | cyp_tdi_prediction | pharmacology | Long-term use | P2 | PARTIAL_EXTEND | Extend `cyp_ddi_panel`: add TDI process + R2 (kinact/KI) |
| A5 | dart_toxicity_prediction | pharmacology | Long-term use | P3 | TRULY_NEW | OECD QSAR Toolbox alerts, RepDose, RDKit |
| B1 | lnp_formulation_optimization | drug_discovery | Delivery | P1 | TRULY_NEW | RDKit pKa, BO (existing), custom endosomal ML |
| B2 | cns_penetration_prediction | pharmacology | Delivery | P1 | TRULY_NEW | CNS MPO (RDKit), Kp,uu,brain ML, P-gp/BCRP ML |
| B3 | oral_absorption_bcs_model | pharmacology | Delivery | P2 | TRULY_NEW | BCS classifier, GI absorption ODE, ESOL |
| B4 | nanoparticle_pk_biodistribution | pharmacology | Delivery | P2 | TRULY_NEW | NP PK ODE, EPR model, PEG stealth model |
| B5 | membrane_permeability_prediction | pharmacology | Delivery | P2 | TRULY_NEW | Caco-2 GCN/RF, PAMPA QSAR, P-gp RF |
| C1 | target_engagement_kinetics | drug_discovery | Target engagement | P2 | TRULY_NEW | KinScreen ML, ODE occupancy solver, GROMACS reuse |
| C2 | proteome_selectivity_profiling | drug_discovery | Target engagement | P2 | TRULY_NEW | DeepKinase/PKIDB, ChEMBL GPCR models |
| C3 | covalent_warhead_design | drug_discovery | Target engagement | P3 | TRULY_NEW | GSH reactivity RF, CovPDB, warhead SMARTS |
| D1 | pbpk_pksim | drug_discovery | Clinical translation | P1 | TRULY_NEW | PK-Sim CLI (ospsuite Docker), PKML input generator |
| D2 | clinical_trial_simulation | drug_discovery | Clinical translation | P1 | TRULY_NEW | mrgsolve + BOIN R pkg (extend nlmixr2 container) |
| D3 | transporter_ddi_prediction | pharmacology | Clinical translation | P1 | TRULY_NEW | 8-transporter RF/GBM, FDA static DDI equations |
| D4 | allometric_scaling | pharmacology | Clinical translation | P2 | TRULY_NEW | Power law SciPy, MABEL, MRSD (deterministic) |
| D5 | pharmacogenomics_stratification | pharmacology | Clinical translation | P2 | DB_INSTALLABLE | pharmCAT 1.7.0 (ToolShed), PharmGKB API, DESeq2 reuse |

**Total new workflows: 18**

**By DB status:**
- `DB_INSTALLABLE` (wrap existing tool): A1, A3, D5 → fast to build, tool already works
- `PARTIAL_EXTEND` (extend existing workflow): A4 → single PR to `cyp_ddi_panel/main.nf`
- `TRULY_NEW` (build end-to-end): A2, A5, B1–B5, C1–C3, D1–D4 → 13 workflows

**Build priority (revised with DB findings):**
- **Sprint 1 — Quick wins** (DB_INSTALLABLE or PARTIAL_EXTEND): A1, A3, A4, D5 — these can be done in days because core tools are already installable
- **Sprint 2 — P1 TRULY_NEW**: B1, B2, D1, D2, D3 — highest business value, highest effort
- **Sprint 3 — P2 TRULY_NEW**: A2, B3, B4, B5, C1, C2, D4 — build after Sprint 2 validates pipeline
- **Sprint 4 — P3**: A5, C3
