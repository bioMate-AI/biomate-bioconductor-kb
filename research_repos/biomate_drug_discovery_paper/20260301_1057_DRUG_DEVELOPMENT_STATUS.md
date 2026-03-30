# Drug Development — Accurate Status Audit
**Date:** 2026-03-01 10:57
**Purpose:** Correct the Paper 4 overview (dated 2026-02-25) which understated existing implementation.

---

## 1. Nextflow Workflow Layer — Status: ✅ COMPLETE

### Main End-to-End Pipeline
`backend/biomni_workflows/nextflow_nfcore/workflows/drug_discovery/main.nf`

Runs in parallel: physicochemical properties → ADMET prediction → molecular docking (DiffDock) → drug combination safety → FDA recalls + label info. Optional docking branch gated on `target_protein / protein_sequence / pdb_id`.

### 25 Pharmacology Subworkflows (nfcore DSL2)
All at `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/*/main.nf`

| Subworkflow | Category |
|---|---|
| `ADMET_pred`, `predict_admet_properties` | ADMET |
| `calculate_physicochemical_properties` | Physicochemistry |
| `run_diffdock_with_smiles`, `docking_autodock_vina`, `run_autosite` | Molecular docking |
| `predict_binding_affinity_protein_1d_sequence` | Binding affinity |
| `check_drug_combination_safety`, `find_alternative_drugs_ddinter` | Safety |
| `check_fda_drug_recalls`, `get_fda_drug_label_info`, `query_fda_adverse_events` | Regulatory |
| `analyze_fda_safety_signals`, `query_adverse_events`, `query_drug_labels`, `query_drug_recalls` | Surveillance |
| `analyze_interaction_mechanisms`, `query_drug_interactions` | DDI |
| `bi_exp_model`, `sigmoid` | PK/PD ODE models |
| `estimate_alpha_particle_radiotherapy_dosimetry`, `analyze_radiolabeled_antibody_biodistribution` | Dosimetry |
| `analyze_xenograft_tumor_growth_inhibition`, `run_3d_chondrogenic_aggregate_assay` | Preclinical |
| `apply_vcog_grade`, `grade_adverse_events_using_vcog_ctcae` | Toxicity grading |
| `perform_mwas_cyp2c19_metabolizer_status` | Pharmacogenomics |
| `retrieve_topk_repurposing_drugs_from_disease_txgnn` | Drug repurposing |
| `analyze_western_blot` | Protein detection |
| `analyze_accelerated_stability_of_pharmaceutical_formulations` | Formulation |

### DrugCLIP Virtual Screening
`backend/nf-core-workflows/modules/biomate-ai-tools/drugclip/main.nf` — ultra-fast virtual screening against target proteins; outputs ranked compound scores.

### Bioengineering / Drug Release Kinetics
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioengineering/` — 13 subworkflows including `analyze_in_vitro_drug_release_kinetics`, zero/first/Higuchi/Korsmeyer-Peppas kinetic models, and ODE whole-cell models.

---

## 2. QC Governance Layer — Status: ✅ SUBSTANTIALLY COMPLETE (not "to build")

The Paper 4 overview (2026-02-25) stated "QC governance layer not yet built." **This is wrong.** It was built during the QC governance sprint:

### 2a. MaxQuant Parser — ✅ DONE
`qc_trace_monitor.py` `_parse_maxquant_metrics()` (~line 1623)

Parses: `summary.txt` (mass accuracy), `msms.txt` (PSM FDR), `proteinGroups.txt` (protein FDR, LFQ CV), `peptides.txt` (missed cleavage rate, oxidized Met fraction), `evidence.txt` (RT drift).

| Metric | Level | Threshold | Status |
|---|---|---|---|
| PSM FDR | **GOLD** | < 1% | ✅ gate live |
| Protein FDR | **GOLD** | < 1% | ✅ gate live |
| Mass accuracy (ppm) | **GOLD** | < 5 ppm | ✅ gate live |
| Missed cleavage rate | **SILVER** | < 20% | ✅ gate live |
| LFQ CV (tech reps) | **SILVER** | < 20% | ✅ gate live |
| Oxidized Met fraction | **BRONZE** | < 30% | ✅ advisory live |
| RT drift across runs | **BRONZE** | < 2 min | ✅ advisory live |

Test class: `TestGraceProteomicsMaxQuant` (in `test_qc_e2e_domains.py`)

### 2b. DIA-NN / Spectronaut Parser — ✅ DONE
`qc_trace_monitor.py` `_parse_diann_metrics()` (~line 1729)

Parses `report.tsv` and `report.stats.tsv`.

| Metric | Level | Threshold | Status |
|---|---|---|---|
| Protein FDR | **GOLD** | < 1% | ✅ gate live |
| Precursor FDR | **GOLD** | < 1% | ✅ gate live |
| Peptide CV across replicates | **SILVER** | < 15% | ✅ gate live |
| Library coverage | **SILVER** | > 60% | ✅ gate live |

Test class: `TestHenryDIANNPlasma`

### 2c. Chemoproteomics / Pulldown QC — ✅ DONE
`qc_trace_monitor.py` `_parse_pulldown_metrics()` (~line 1822)

| Metric | Level | Threshold | Status |
|---|---|---|---|
| Enrichment ratio | **SILVER** | ≥ 3× | ✅ blocking gate |
| Bait detection | **SILVER** | bait peptides > 0 | ✅ advisory |
| Background contamination | **BRONZE** | contaminant % | ✅ advisory |

Test class: `TestIsobelPulldown`

### 2d. SMILES / Compound Structure QC — ✅ DONE
`qc_trace_monitor.py` `_parse_smiles_metrics()` (~line 1899)

| Metric | Level | Threshold | Status |
|---|---|---|---|
| SMILES parseable (RDKit) | **GOLD** | 0 invalid | ✅ hard gate |
| Salt-stripped | **SILVER** | auto-strip flag | ✅ advisory |
| Stereocenters defined | **SILVER** | undefined = 0 | ✅ advisory |

Test class: `TestJamesSMILESCompoundQC`

### 2e. Named Profiles — ✅ 4 DONE
All in `QC_NAMED_PROFILES` constant:

| Profile | Domain | Key adjustments |
|---|---|---|
| `proteomics_standard` | DDA label-free lysate | Default thresholds |
| `proteomics_phospho` | Phosphoproteomics | Lower PSM count acceptable; phosphosite localization ≥ 0.75 required |
| `proteomics_plasma_biomarker` | Depleted plasma DIA/DDA | Stricter CV < 15%; lower library coverage acceptable |
| `proteomics_chemoproteomics` | Affinity pulldown / ABPP | Enrichment ratio gate enforced |

---

## 3. LC-MS Agent — Status: ✅ COMPLETE (standalone, not yet integrated)

**Location:** `/home/yzhang/biomate/LC-MS-agent/`

A fully independent platform (separate git repo, Docker microservices, Streamlit frontend):
- **5 AI agents** (methodology design, troubleshooting, workflow, report generation, parameter optimization)
- **RAG knowledge base** (Milvus vector DB, multi-source: vendor docs, PubMed, forums)
- **Vendor auto-login** (Playwright — Thermo, Agilent, Waters, Sciex, Bruker, Shimadzu)
- **Tool integrations:** ProteoWizard, OpenMS, MZmine 3, XCMS, MetaboAnalyst, PubChem/HMDB/GNPS compound search
- **FastAPI backend** + **Streamlit frontend** (Upload → Results → Downloads)

**Not yet integrated** with BioMate's main Galaxy/Nextflow platform. Agent endpoints are at `localhost:8000/api/agents/*`, not behind BioMate's `routes.ts` proxy.

---

## 4. What Is GENUINELY MISSING for Paper 4

| Gap | Priority | Effort | Notes |
|---|---|---|---|
| **hERG cardiotoxicity gate** | High | ~2 days | Parse hERG IC50 from ADMET output; gate < 1 μM |
| **DILI risk gate** | High | ~2 days | DILIrank compound lookup; GOLD gate on known hepatotoxins |
| **Ames mutagenicity gate** | Medium | 1 day | Parse from ADMET output |
| **PGx CYP gene coverage gate** | High | ~2 days | Per-gene mosdepth coverage for CYP2D6/2C19/3A4/DPYD/TPMT; CPIC GOLD gate 30x |
| **Compound profiles** | Medium | 0.5 day | `compound_druglike`, `compound_natural_product`, `compound_peptidomimetic` in QC_NAMED_PROFILES |
| **PGx profiles** | Medium | 0.5 day | `pgx_clinical` (30x), `pgx_research` (15x advisory) |
| **nlmixr2 population PK module** | Medium | 2 weeks | Nextflow R container; SAEM convergence QC gates |
| **NCA via PKNCA** | Medium | 1 week | Non-compartmental analysis; AUC/Cmax/t½ output |
| **LC-MS Agent → BioMate integration** | Low | 1 week | Wire `/api/agents/*` endpoints through `routes.ts` |
| **Paper repo content** | High | — | `manuscript/`, `figures/`, `supplementary/` are empty |
| **Benchmark data** | High | — | Need real (de-identified) MaxQuant/DIA-NN dataset; CRO collaborator |

---

## 5. Updated Paper 4 Status Line

**Corrected status** (replacing the 2026-02-25 overview):

> Nextflow workflow layer COMPLETE (25 subworkflows + full pipeline + DrugCLIP); QC governance SUBSTANTIALLY COMPLETE (MaxQuant, DIA-NN, pulldown, SMILES parsers + 4 named profiles); LC-MS Agent complete but not integrated; missing: hERG/DILI/Ames gates, PGx coverage gate, compound profiles, nlmixr2, NCA, benchmark data, co-authors

---

## 6. Priority Order for Today

1. **hERG + DILI toxicity gates** — high-value, 2–3 days, fills the most critical gap in drug safety QC
2. **PGx CYP gene coverage gate** — the clearest novel claim vs. existing tools
3. **Compound profiles** — 0.5 day, completes the SMILES QC governance stack
4. **Update Paper 4 overview** with accurate status
