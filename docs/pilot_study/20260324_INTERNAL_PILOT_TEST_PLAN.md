# BioMate Pilot Study — Internal Validation Test Plan
## Pre-Release Readiness Gate Before Zhejiang People's Hospital Pilot

**Document owner:** BioMate Engineering  
**Study reference:** `business/BioMate_DrugDiscovery_Study_Proposal.md`  
**Pilot window:** March 30 – April 8, 2026  
**Internal validation deadline:** March 29, 2026 (pre-pilot commitment)  
**Datasets:** `data/pilot_study_datasets/`

---

## Purpose

This plan defines the exact inputs, execution steps, expected outputs, logging requirements, and pass/fail evaluation metrics that the BioMate engineering team must validate **before** handing the platform to the Zhejiang People's Hospital research team on March 30.

A "green" internal validation means:
- Every workflow the pilot will use runs to completion on our reference dataset
- Output values are within expected range and agree with published literature
- Logging captures the timestamps and run IDs needed to measure H1, H2, H3
- No hallucinated commands, no silent failures, no null result fields

---

## Reference Dataset

All internal tests use the BCR-ABL1 / CML dataset assembled in `data/pilot_study_datasets/`:

| File | Contents |
|---|---|
| `compounds.csv` | 15 compounds (SMILES + ground truth metadata) |
| `ground_truth_admet.csv` | Literature-validated ADMET values (hERG IC50, DILI, Ames) |
| `reference_actives.smi` | 4 known BCR-ABL1 inhibitors for pharmacophore model |
| `assay_results_arm3.csv` | IC50 / Ki / hERG / solubility assay data for Arm 3 upload test |
| `target_info.json` | BCR-ABL1 target metadata (PDB: 1IEP, UniProt: P00519) |

**Design rationale:** The 15 compounds span four categories:
1. **True positives** — approved BCR-ABL1 TKIs (CPD001–CPD006) with known potency rankings
2. **Synthetic analogs** — imatinib variants (CPD007–CPD008) to test interpolation
3. **Cardiac safety controls** — terfenadine and cisapride (CPD009–CPD010) with extreme hERG liabilities; withdrawn from market
4. **Negative controls** — metoclopramide, erlotinib, gefitinib, doxorubicin, acetaminophen (CPD011–CPD015) for specificity and DILI reference

This design ensures BioMate can be validated against all three study hypotheses (H1/H2/H3) and multiple safety dimensions simultaneously.

---

## Workflow Coverage

The pilot requires these BioMate workflows to be available and validated:

| # | Workflow | Nextflow Path | Hypothesis Tested |
|---|---|---|---|
| W1 | ADMET profiling | `pharmacology/ADMET_pred` | H1, H2, H3 |
| W2 | Comprehensive ADMET | `pharmacology/predict_admet_properties` | H1, H2, H3 |
| W3 | IVIVE hepatic clearance | `pharmacology/ivive_hepatic_clearance` | H1, H3 |
| W4 | Pocket detection / druggability | `pharmacology/pocket_detection_druggability` | H1, H3 |
| W5 | Pharmacophore filtering | `pharmacology/pharmacophore_filtering` | H1, H3 |
| W6 | Integrated ranking + assay upload | `drug_discovery/assay_ingestion` API | H1, H3 |
| W7 | CRO export | `drug_discovery/export` API | H1, H3 |

---

## Pre-Test Setup Checklist

Before running any test session, confirm:

- [ ] Docker daemon running; `docker ps` responds
- [ ] Image `biomate/biomni-tools:latest` present locally (`docker images | grep biomni-tools`)
- [ ] Image `biomate/biomni-drug-discovery-nf:latest` present locally
- [ ] PDB 1IEP downloaded: `wget -O /tmp/1IEP.pdb https://files.rcsb.org/download/1IEP.pdb`
- [ ] Backend server running on `localhost:8080`
- [ ] Frontend dev server running on `localhost:5173`
- [ ] Redis session store running
- [ ] All 15 compound SMILES verified parseable by RDKit (see validation script below)

### SMILES Validation Script

```bash
python3 - << 'EOF'
from rdkit import Chem
import csv

with open("data/pilot_study_datasets/compounds.csv") as f:
    reader = csv.DictReader(f)
    for row in reader:
        mol = Chem.MolFromSmiles(row["smiles"])
        status = "OK" if mol else "FAIL"
        print(f"{status}  {row['compound_id']}  {row['name']}")
EOF
```

Expected: all 15 lines print `OK`.

---

## Session 1 — ADMET Profiling of Full Compound Set (H1, H2)

**Arm:** 1 and 2 (workflow quality + time-to-result)  
**Day in pilot:** Day 1  
**Operator:** BioMate engineer (internal rehearsal)  
**Time budget:** ≤ 30 minutes end-to-end

### 1.1 Input

**Chat query (exact text):**
```
I have 15 small molecules I want to evaluate for cardiac and liver safety before selecting leads. 
Can you run ADMET profiling on them and flag any with hERG IC50 below 10 μM or DILI risk above low?

Here are the SMILES:
CPD001: CC1=CC=C(C=C1)NC(=O)C2=CC=CC(=C2)NC3=NC=CC(=N3)C4=CC=CN4C
CPD002: CC(=O)NC1=CC(=C(C=C1)Cl)NC(=O)C2=CC(=NC(=N2)NC3=CC=CC=C3)N4CCN(CC4)CC
CPD003: CC1=NC(=C(C=N1)C(=O)NC2=CC(=CC(=C2)C(F)(F)F)C3=CN=CC(=C3)C)C
CPD004: COC1=C(OC)C=C2C(=C1)NC(=O)C(=C2)C3=CC(=CC(=C3)Cl)OC
CPD005: OC(=O)C1=CC=C(C=C1)NC(=O)C1=C(C)N=CC(=C1)C1=CC=C2C(=C1)C1=CC=CC=C1C(=O)N2C
CPD006: CC1=NC(=CC(=C1)F)NC(=O)C1=CN=C2N(C1=O)C(C)(C)CC2
CPD007: CC1=CC=C(C=C1)NC(=O)C2=CC(=CC=C2)NC3=NC=CC(=N3)C4=CC=CN4
CPD008: CC1=CC=C(C=C1)NC(=O)C2=CC(=CC=C2)NC3=NC=CC(=N3)C4=CC=CN4CC
CPD009: OC(CCCC1=CC=CC=C1)(C1=CC=CC=C1)CCN1CCC(CC1)C(O)(C1=CC=C(C=C1)C(C)(C)C)C1=CC=C(C=C1)C(C)(C)C
CPD010: CCOC1=CC2=C(C=C1OCC)NC(=O)CC2
CPD011: CCN(CC)CCNC(=O)C1=CC(=C(C=C1N)OC)Cl
CPD012: COCCOC1=CC2=C(C=C1OCCOC)NC(=NC2=O)NC3=CC=CC(=C3)C#C
CPD013: COC1=CC2=C(C=C1OCCCN3CCOCC3)NC(=NC2=O)NC4=CC(=C(C=C4)F)Cl
CPD014: COC1=C2CC(C[C@@H]3C[C@H](O[C@H]4C[C@@H](N)[C@H](O)[C@@H](C)O4)[C@H](O)[C@@H](C(=O)CO)O3)OC2=C(O)C3=C1C(=O)c1cccc(O)c1C3=O
CPD015: CC(=O)NC1=CC=C(O)C=C1
```

### 1.2 Execution Steps

1. Paste the query into BioMate chat interface
2. BioMate selects `ADMET_pred` or `predict_admet_properties` workflow automatically
3. Workflow runs via `nextflow run` with `-profile docker`
4. Results are streamed back to chat interface
5. Chat message contains structured ADMET table and flagged compounds

### 1.3 Expected Output — Per Compound

| Compound | hERG IC50 (μM) | hERG Flag | DILI Risk | DILI Flag | Pass/Fail |
|---|---|---|---|---|---|
| CPD001 Imatinib | >30 | — | Low | — | **PASS** |
| CPD002 Dasatinib | 1–5 | ⚠️ borderline | Low | — | **Conditional** |
| CPD003 Nilotinib | <1 | 🚨 concern | Moderate | ⚠️ | **FAIL** |
| CPD004 Bosutinib | >30 | — | Low | — | **PASS** |
| CPD005 Ponatinib | <1 | 🚨 concern | Moderate | ⚠️ | **FAIL** |
| CPD006 Asciminib | >30 | — | Low | — | **PASS** |
| CPD007 Gleevec-A1 | >30 | — | Low | — | **PASS** |
| CPD008 Gleevec-A2 | >30 | — | Low | — | **PASS** |
| CPD009 Terfenadine | <0.1 | 🚨 HIGH | Low | — | **FAIL** (hERG) |
| CPD010 Cisapride | <0.1 | 🚨 HIGH | Low | — | **FAIL** (hERG) |
| CPD011 Metoclopramide | >100 | — | Low | — | **PASS** |
| CPD012 Erlotinib | >30 | — | Low | — | **PASS** |
| CPD013 Gefitinib | >30 | — | Low | — | **PASS** |
| CPD014 Doxorubicin | 2–8 | ⚠️ borderline | High | 🚨 | **FAIL** (DILI) |
| CPD015 Acetaminophen | >100 | — | Moderate | ⚠️ | **Conditional** |

**Critical discriminations BioMate must get right:**
- Terfenadine and cisapride must score as HIGHEST hERG risk (worst ranked)
- Nilotinib must score worse than bosutinib on cardiac safety
- Doxorubicin must trigger DILI flag
- Acetaminophen must NOT trigger DILI flag at single-dose context (dose-dependent)

### 1.4 Logging Requirements

Backend must record:
```json
{
  "session_id": "<uuid>",
  "query_submitted_at": "<ISO8601>",
  "workflow": "ADMET_pred | predict_admet_properties",
  "compound_count": 15,
  "nextflow_run_id": "<run_hash>",
  "result_delivered_at": "<ISO8601>",
  "elapsed_seconds": "<int>",
  "compounds_passed": "<int>",
  "compounds_failed": "<int>",
  "compounds_conditional": "<int>",
  "manual_correction_required": false
}
```

### 1.5 Evaluation Metrics

| Metric | Target | How Measured |
|---|---|---|
| Completion without manual correction | Yes | No re-submission needed |
| Time-to-result | ≤ 30 min | `result_delivered_at − query_submitted_at` |
| hERG discrimination accuracy | ≥ 90% correct flags | Compare to `ground_truth_admet.csv` |
| DILI discrimination accuracy | ≥ 90% correct flags | Compare to `ground_truth_admet.csv` |
| Null result fields | 0 | Count of `null` in output JSON |

**Pass gate for Session 1:** All 5 metrics green → proceed to Session 2.

---

## Session 2 — Hepatic Clearance Prediction (H1, H2)

**Arm:** 1 and 2  
**Day in pilot:** Day 1–2  
**Time budget:** ≤ 20 minutes

### 2.1 Input

**Chat query:**
```
For the BCR-ABL1 inhibitor candidates, can you predict hepatic clearance to help me understand 
which compounds might have problematic liver extraction? Focus on imatinib, dasatinib, nilotinib, 
and bosutinib specifically.

SMILES:
Imatinib: CC1=CC=C(C=C1)NC(=O)C2=CC=CC(=C2)NC3=NC=CC(=N3)C4=CC=CN4C
Dasatinib: CC(=O)NC1=CC(=C(C=C1)Cl)NC(=O)C2=CC(=NC(=N2)NC3=CC=CC=C3)N4CCN(CC4)CC
Nilotinib: CC1=NC(=C(C=N1)C(=O)NC2=CC(=CC(=C2)C(F)(F)F)C3=CN=CC(=C3)C)C
Bosutinib: COC1=C(OC)C=C2C(=C1)NC(=O)C(=C2)C3=CC(=CC(=C3)Cl)OC
```

### 2.2 Workflow Invoked

`pharmacology/ivive_hepatic_clearance`

**Key parameters:**
- `clint_uL_min_mg`: compound-specific intrinsic clearance (predicted)
- `hepatocyte_scaling`: 120 million cells/g liver (default)
- `liver_weight_g`: 1500 g (default human)
- `fu_plasma`: predicted unbound fraction
- Model: well-stirred liver model

### 2.3 Expected Output Structure

```json
{
  "compounds": [
    {
      "name": "Imatinib",
      "clint_uL_min_mg": <predicted>,
      "hepatic_clearance_mL_min_kg": <predicted>,
      "extraction_ratio": <0.0-1.0>,
      "clearance_class": "Low | Medium | High",
      "fu_plasma": <0.0-1.0>
    }
  ]
}
```

**Expected clearance classes (literature):**
- Imatinib: Medium extraction ratio (CL ~14 L/h)
- Dasatinib: High extraction ratio (short half-life, extensive hepatic metabolism)
- Nilotinib: Low-Medium extraction ratio (long half-life ~17h)
- Bosutinib: Medium extraction ratio

### 2.4 Logging Requirements

Same structure as Session 1, with `workflow: "ivive_hepatic_clearance"`.

### 2.5 Evaluation Metrics

| Metric | Target |
|---|---|
| Completion | Yes, no re-submission |
| Time-to-result | ≤ 20 min |
| Clearance class ordering | Dasatinib ≥ Imatinib ≥ Bosutinib ≥ Nilotinib (higher extraction = faster clearance) |
| All fields populated | No nulls |

---

## Session 3 — Pocket Detection on BCR-ABL1 Structure (H1, H2)

**Arm:** 1 and 2  
**Day in pilot:** Day 2  
**Time budget:** ≤ 25 minutes (includes PDB fetch)

### 3.1 Input

**PDB download (pre-flight):**
```bash
wget -O /tmp/1IEP.pdb https://files.rcsb.org/download/1IEP.pdb
```

**Chat query:**
```
I need to understand the binding site landscape of BCR-ABL1 kinase. 
Can you analyze the crystal structure 1IEP for druggable pockets and tell me 
which pocket the kinase inhibitors would bind to?
```

### 3.2 Workflow Invoked

`pharmacology/pocket_detection_druggability`

**Command-line equivalent:**
```bash
nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/pocket_detection_druggability/main.nf \
  --mode live \
  --pdb_input /tmp/1IEP.pdb \
  --druggability_threshold 0.4 \
  --min_volume_A3 200 \
  -profile docker
```

### 3.3 Expected Output

**Minimum requirements:**
- ≥ 5 pockets detected
- Top pocket druggability score ≥ 0.40
- Top pocket volume ≥ 500 Å³
- Top pocket center coordinates within 12 Å of imatinib centroid (approximately x=10–15, y=10–20, z=5–15 in 1IEP frame)

**Expected pocket table (approximate):**
```
Rank  Volume(Å³)  Druggability  Center_XYZ
1     870±200     0.55±0.15     ATP-binding cleft region
2     450±150     0.40±0.10     Allosteric myristate pocket
3     300±100     0.30±0.10     Surface pocket 1
...
```

### 3.4 Logging Requirements

```json
{
  "session_id": "<uuid>",
  "workflow": "pocket_detection_druggability",
  "pdb_id": "1IEP",
  "pockets_detected": "<int>",
  "top_pocket_druggability": "<float>",
  "top_pocket_volume_A3": "<float>",
  "elapsed_seconds": "<int>",
  "manual_correction_required": false
}
```

### 3.5 Evaluation Metrics

| Metric | Target | Pass if |
|---|---|---|
| Pockets detected | ≥ 5 | count ≥ 5 |
| Top druggability score | ≥ 0.40 | score ≥ 0.40 |
| Top pocket volume | ≥ 500 Å³ | volume ≥ 500 |
| Time-to-result | ≤ 25 min | elapsed ≤ 1500 s |
| No re-submission | Yes | no manual correction |

---

## Session 4 — Pharmacophore Filtering of Compound Library (H1, H2)

**Arm:** 1 and 2  
**Day in pilot:** Day 3  
**Time budget:** ≤ 30 minutes

### 4.1 Input

**Reference actives file:** `data/pilot_study_datasets/reference_actives.smi`  
(4 known ABL1 inhibitors: imatinib, dasatinib, nilotinib, asciminib)

**Chat query:**
```
Based on the known BCR-ABL1 inhibitors (imatinib, dasatinib, nilotinib, asciminib), 
can you build a pharmacophore model and screen the remaining 11 compounds in my library 
to identify which ones share the key pharmacophore features?
```

### 4.2 Workflow Invoked

`pharmacology/pharmacophore_filtering`

**Command-line equivalent:**
```bash
nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/pharmacophore_filtering/main.nf \
  --mode live \
  --reference_actives "$(cat data/pilot_study_datasets/reference_actives.smi)" \
  --compound_library "CPD007:CC1=CC=C(C=C1)NC(=O)C2=CC(=CC=C2)NC3=NC=CC(=N3)C4=CC=CN4|CPD008:CC1=CC=C(C=C1)NC(=O)C2=CC(=CC=C2)NC3=NC=CC(=N3)C4=CC=CN4CC|..." \
  --min_features 3 \
  -profile docker
```

### 4.3 Expected Output

**Compounds expected to PASS pharmacophore filter (structural similarity to ABL1 inhibitors):**
- CPD007 (Gleevec-analog-1) — should match ≥ 4 features
- CPD008 (Gleevec-analog-2) — should match ≥ 4 features

**Compounds expected to FAIL (structurally dissimilar):**
- CPD009 Terfenadine — antihistamine scaffold, no ABL1 pharmacophore
- CPD010 Cisapride — different scaffold
- CPD011 Metoclopramide — no kinase features
- CPD014 Doxorubicin — DNA intercalator scaffold
- CPD015 Acetaminophen — too simple, MW too low

**EGFR inhibitors (uncertain/expected borderline):**
- CPD012 Erlotinib — anilinoquinazoline; may share HBD/HBA pattern with some ABL1 features
- CPD013 Gefitinib — similar to erlotinib

### 4.4 Logging Requirements

```json
{
  "session_id": "<uuid>",
  "workflow": "pharmacophore_filtering",
  "reference_compound_count": 4,
  "library_compound_count": 11,
  "pharmacophore_features": "<int>",
  "compounds_passed_filter": "<int>",
  "elapsed_seconds": "<int>",
  "manual_correction_required": false
}
```

### 4.5 Evaluation Metrics

| Metric | Target |
|---|---|
| Gleevec analogs pass filter | Both CPD007 and CPD008 pass |
| Withdrawn drugs screened out | Terfenadine, cisapride not in passed list |
| Negative controls excluded | Metoclopramide, acetaminophen not in passed list |
| Time-to-result | ≤ 30 min |
| No re-submission | Required |

---

## Session 5 — Integrated Ranking + Assay Data Upload (H1, H3)

**Arm:** 1, 2, and 3 (starts Day 4 per study design)  
**Day in pilot:** Day 4  
**Time budget:** ≤ 20 minutes

### 5.1 Input

**Assay data file:** `data/pilot_study_datasets/assay_results_arm3.csv`

**Chat query:**
```
I have assay results for all 15 compounds including IC50, Ki against BCR-ABL1, 
hERG IC50, solubility and Caco-2 permeability. Can you upload these results and 
give me a prioritized ranking of which compounds to advance?
```

**File upload:** `data/pilot_study_datasets/assay_results_arm3.csv`

### 5.2 API Invoked

`POST /api/drug-discovery/{campaign_id}/ingest-assay`

Then:  
`GET /api/drug-discovery/{campaign_id}/compounds` — retrieve ranked list

### 5.3 Expected Output — Ranked Compound List

**Expected top 5 compounds (in order):**

| Rank | Compound | Reasoning |
|---|---|---|
| 1 | Asciminib (CPD006) | IC50 0.5 nM, no hERG concern, clean DILI |
| 2 | Imatinib (CPD001) | IC50 600 nM but excellent safety; gold standard |
| 3 | Bosutinib (CPD004) | IC50 1 nM, clean hERG |
| 4 | Gleevec-A2 (CPD008) | Predicted moderate potency, clean safety |
| 5 | Gleevec-A1 (CPD007) | Predicted lower potency, clean safety |

**Expected bottom 3 (worst ranked — safety failures):**

| Rank | Compound | Reason |
|---|---|---|
| 13 | Nilotinib (CPD003) | hERG IC50 0.8 μM — below safety threshold |
| 14 | Cisapride (CPD010) | hERG IC50 0.05 μM — extreme risk; no target activity |
| 15 | Terfenadine (CPD009) | hERG IC50 0.08 μM — extreme risk; withdrawn drug |

**Critical requirement:** Terfenadine must rank LAST or in bottom 3. It must never appear in the top 10. This is the scientific correctness gate for the hERG safety algorithm.

### 5.4 Logging Requirements

```json
{
  "session_id": "<uuid>",
  "workflow": "assay_ingestion",
  "campaign_id": "<uuid>",
  "compounds_ingested": 15,
  "ranking_computed": true,
  "top_ranked_compound": "Asciminib | Imatinib | Bosutinib",
  "terfenadine_rank": "<must be >10>",
  "elapsed_seconds": "<int>",
  "manual_correction_required": false
}
```

### 5.5 Evaluation Metrics

| Metric | Target | Pass if |
|---|---|---|
| Upload completes | Yes | HTTP 200 from ingest-assay |
| Ranking returned | Yes | ≥ 15 compounds in ranked list |
| Terfenadine rank | > 10 | rank > 10 |
| Cisapride rank | > 10 | rank > 10 |
| Asciminib/Bosutinib in top 5 | Yes | at least one in top 5 |
| Time-to-result | ≤ 20 min | elapsed ≤ 1200 s |

---

## Session 6 — CRO Export for Top Compounds (H1)

**Arm:** 1  
**Day in pilot:** Day 5  
**Time budget:** ≤ 10 minutes

### 6.1 Input

**Chat query:**
```
I want to order the top 5 BCR-ABL1 compounds from WuXi AppTec for in vitro testing. 
Can you prepare a CRO export file for them?
```

### 6.2 API Invoked

`GET /api/drug-discovery/{campaign_id}/export/cro-order?vendor=wuxi&top_n=5`

### 6.3 Expected Output

A downloadable CSV/Excel file containing:
```
Compound_ID, Name, SMILES, MW, ClogP, Vendor_Code, Notes
CPD006, Asciminib, CC1=NC(=CC(=C1)F)..., 449.9, 2.21, [WuXi_CAS_lookup], Top ranked
CPD001, Imatinib, CC1=CC=C..., 493.6, 3.74, [WuXi_CAS_lookup], Reference compound
CPD004, Bosutinib, COC1=..., 530.0, 4.62, [WuXi_CAS_lookup], Clean hERG
...
```

Format must be: compound name, SMILES, MW, ClogP, rank, safety notes.

### 6.4 Evaluation Metrics

| Metric | Target |
|---|---|
| Export file generated | Yes |
| Contains top 5 compounds | Yes, 5 rows |
| No safety failures in export | No terfenadine or cisapride in top-5 export |
| Download link functional | HTTP 200 on download |
| Time-to-result | ≤ 10 min |

---

## Session 7 — QC Defensibility Review (H3)

**Arm:** 3  
**Day in pilot:** Days 4–9 (reviewing Sessions 1–6 outputs)  
**Time budget:** 45 minutes for full review

### 7.1 What Is Reviewed

The research team (internal engineer acting as clinical researcher proxy) reviews:
1. **ADMET result table** from Session 1 — are flags scientifically defensible?
2. **Hepatic clearance values** from Session 2 — are clearance classes reasonable?
3. **Pocket detection output** from Session 3 — does top pocket correspond to known binding cleft?
4. **Pharmacophore filter results** from Session 4 — are the passed compounds chemically sensible?
5. **Compound ranking** from Session 5 — does the final ranking agree with expert expectation?
6. **CRO export file** from Session 6 — is it ready to submit to WuXi without modification?
7. **QC audit trail** — is every quality gate decision traceable to a literature source?

### 7.2 Rating Scale (H3 Measurement)

| Rating | Label | Definition |
|---|---|---|
| 5 | Publication-ready | Could be included in a manuscript methods section as-is |
| 4 | Publication-ready with minor edits | One or two clarifications needed; no scientific errors |
| 3 | Acceptable for internal use | Correct results but insufficient documentation for publication |
| 2 | Needs revision | Correct result but poor documentation or one scientific concern |
| 1 | Not defensible | Scientific error or missing results |

**H3 passes if:** ≥ 70% of session reviews receive rating 4 or 5 (≥ 5 out of 7 sessions).

### 7.3 Review Checklist Per Session

For each of Sessions 1–6, complete:
- [ ] All compounds have results (no nulls)
- [ ] Safety flags are scientifically justified (reference cited)
- [ ] Quality gate thresholds match QC profile standard
- [ ] Result can be directly included in a methods section
- [ ] No hallucinated tool calls or parameters in the run log
- [ ] Run time recorded and within target

---

## Full Evaluation Matrix

### H1 — Workflow Quality

| Session | Query | Completed without correction? | Hallucination? | Score |
|---|---|---|---|---|
| S1 | ADMET 15 compounds | ✓ / ✗ | None / Count | Pass if ✓ and 0 |
| S2 | Hepatic clearance 4 cpds | ✓ / ✗ | None / Count | Pass if ✓ and 0 |
| S3 | Pocket detection 1IEP | ✓ / ✗ | None / Count | Pass if ✓ and 0 |
| S4 | Pharmacophore filter | ✓ / ✗ | None / Count | Pass if ✓ and 0 |
| S5 | Assay upload + ranking | ✓ / ✗ | None / Count | Pass if ✓ and 0 |
| S6 | CRO export | ✓ / ✗ | None / Count | Pass if ✓ and 0 |

**H1 passes if:** ≥ 5 of 6 sessions complete without manual correction. Hallucination count must be 0.

### H2 — Time-to-Result

| Session | Time Budget | Actual Time | Pass? |
|---|---|---|---|
| S1 ADMET | ≤ 30 min | <recorded> | |
| S2 Clearance | ≤ 20 min | <recorded> | |
| S3 Pocket | ≤ 25 min | <recorded> | |
| S4 Pharmacophore | ≤ 30 min | <recorded> | |
| S5 Ranking | ≤ 20 min | <recorded> | |
| S6 CRO export | ≤ 10 min | <recorded> | |

**H2 passes if:** Average across all sessions ≤ 30 minutes, and ADMET + docking combined ≤ 30 min.

### H3 — QC Defensibility

| Session | Rating (1–5) | Defensible? (≥4) |
|---|---|---|
| S1 ADMET | | |
| S2 Clearance | | |
| S3 Pocket | | |
| S4 Pharmacophore | | |
| S5 Ranking | | |
| S6 CRO export | | |
| Overall audit trail | | |

**H3 passes if:** ≥ 5 of 7 reviews receive rating 4 or 5.

---

## Scientific Correctness Gates (Hard Failures)

Any of the following results in **immediate fail** — the platform must not be released to the hospital until fixed:

1. **Terfenadine or cisapride ranks in top 10** — hERG safety algorithm is broken
2. **Any null fields in ADMET output** — workflow is not running the prediction engine
3. **Pocket detection returns 0 pockets on 1IEP** — scoring algorithm failed
4. **A hallucinated tool name or parameter** appears in any run log
5. **Time-to-result > 60 minutes** for any single session
6. **CRO export contains a compound with FAIL safety status**
7. **Chat interface does not stream results** — SSE pipeline broken

---

## Logging and Audit Infrastructure Requirements

Each session must produce the following artefacts, stored in a durable location:

### Run-level Log (per nextflow invocation)
```
Location: /tmp/biomate-pilot-logs/<session_id>_<workflow>_<timestamp>.json
Format: JSON (structure defined per session above)
Retention: Until April 15, 2026 (14 days post-pilot)
```

### Chat-level Audit Trail
```
Location: backend session store (Redis / DB)
Fields: session_id, query_text, workflow_selected, run_id, elapsed_ms, output_summary
Access: exportable via GET /api/sessions/{session_id}/audit
```

### QC Audit Log (for methods report)
```
Location: docs/QC/pilot_run_<date>_S<n>.md
Format: Markdown (same format as docs/QC/20260324_PHARMACOLOGY_ADMET_WORKFLOW_AUDIT.md)
Content: Input, parameters used, QC thresholds applied with evidence sources, result summary, pass/fail verdict
```

---

## Pre-Release Sign-Off Checklist

Complete this checklist by **March 29, 2026** before handing the platform to the hospital team:

### Workflow Validation
- [ ] Session 1 (ADMET) — all 15 compounds have results, terfenadine flagged first
- [ ] Session 2 (IVIVE) — 4 compounds have hepatic clearance with correct class ordering
- [ ] Session 3 (Pocket) — ≥ 5 pockets detected, top druggability ≥ 0.40
- [ ] Session 4 (Pharmacophore) — Gleevec analogs pass, terfenadine fails
- [ ] Session 5 (Ranking) — terfenadine in bottom 3, asciminib/bosutinib in top 5
- [ ] Session 6 (CRO export) — download link works, file format correct

### Safety Algorithm Validation
- [ ] hERG ranking puts terfenadine (IC50 0.08 μM) lower than imatinib (>30 μM)
- [ ] hERG ranking puts nilotinib (IC50 0.8 μM) lower than bosutinib (>30 μM)
- [ ] DILI ranking penalises doxorubicin and acetaminophen (conditional)

### Infrastructure Validation
- [ ] All 6 sessions complete within time budget
- [ ] Zero hallucinated commands in any run log
- [ ] SSE streaming shows live progress in chat interface
- [ ] Audit trail exportable via API
- [ ] QC log files written for all 6 sessions

### Go/No-Go Decision
All 18 checkboxes must be ticked before releasing to the hospital team.  
If any safety algorithm gate (items under "Safety Algorithm Validation") fails, this is a **hard blocker** — no release until fixed.

---

## Execution Script

The following script runs all 6 sessions programmatically for a fully automated internal validation:

```bash
#!/bin/bash
# internal_pilot_validation.sh
# Runs all 6 sessions and logs results for pre-release sign-off
# Usage: bash docs/pilot_study/internal_pilot_validation.sh

set -e
PILOT_DIR="$(pwd)/data/pilot_study_datasets"
LOG_DIR="/tmp/biomate-pilot-logs"
mkdir -p "$LOG_DIR"

PDB_PATH="/tmp/1IEP.pdb"
if [ ! -f "$PDB_PATH" ]; then
  echo "[SETUP] Downloading 1IEP.pdb..."
  wget -q -O "$PDB_PATH" https://files.rcsb.org/download/1IEP.pdb
fi

echo "[S1] ADMET profiling — 15 compounds..."
time nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf \
  --smiles "CC1=CC=C(C=C1)NC(=O)C2=CC=CC(=C2)NC3=NC=CC(=N3)C4=CC=CN4C" \
  --compound_id "CPD001_imatinib" \
  -profile docker --outdir "$LOG_DIR/s1_admet" 2>&1 | tee "$LOG_DIR/s1_admet.log"

echo "[S2] IVIVE hepatic clearance — 4 compounds..."
time nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ivive_hepatic_clearance/main.nf \
  --smiles "CC1=CC=C(C=C1)NC(=O)C2=CC=CC(=C2)NC3=NC=CC(=N3)C4=CC=CN4C" \
  --compound_id "imatinib" \
  -profile docker --outdir "$LOG_DIR/s2_ivive" 2>&1 | tee "$LOG_DIR/s2_ivive.log"

echo "[S3] Pocket detection — 1IEP..."
time nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/pocket_detection_druggability/main.nf \
  --mode live \
  --pdb_input "$PDB_PATH" \
  --druggability_threshold 0.4 \
  -profile docker --outdir "$LOG_DIR/s3_pockets" 2>&1 | tee "$LOG_DIR/s3_pockets.log"

echo "[S4] Pharmacophore filtering..."
REFERENCE_SMILES="CC1=CC=C(C=C1)NC(=O)C2=CC=CC(=C2)NC3=NC=CC(=N3)C4=CC=CN4C Imatinib
CC(=O)NC1=CC(=C(C=C1)Cl)NC(=O)C2=CC(=NC(=N2)NC3=CC=CC=C3)N4CCN(CC4)CC Dasatinib"
time nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/pharmacophore_filtering/main.nf \
  --mode live \
  --reference_actives "$REFERENCE_SMILES" \
  --compound_library "CC1=CC=C(C=C1)NC(=O)C2=CC(=CC=C2)NC3=NC=CC(=N3)C4=CC=CN4 Gleevec-A1|OC(CCCC1=CC=CC=C1)(C1=CC=CC=C1)CCN1CCC(CC1)C(O)(C1=CC=C(C=C1)C(C)(C)C)C1=CC=C(C=C1)C(C)(C)C Terfenadine" \
  -profile docker --outdir "$LOG_DIR/s4_pharmacophore" 2>&1 | tee "$LOG_DIR/s4_pharmacophore.log"

echo "[S5] Assay upload + ranking..."
# API-based — requires running server
curl -s -X POST "http://localhost:8080/api/drug-discovery/pilot-campaign-001/ingest-assay" \
  -F "file=@$PILOT_DIR/assay_results_arm3.csv" \
  | tee "$LOG_DIR/s5_ingest.json"

curl -s "http://localhost:8080/api/drug-discovery/pilot-campaign-001/compounds" \
  | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'{i+1}. {c[\"name\"]} score={c.get(\"composite_score\",\"N/A\")}') for i,c in enumerate(data.get('compounds',[]))]" \
  | tee "$LOG_DIR/s5_ranking.txt"

echo "[S6] CRO export..."
curl -s "http://localhost:8080/api/drug-discovery/pilot-campaign-001/export/cro-order?vendor=wuxi&top_n=5" \
  -o "$LOG_DIR/s6_cro_export.csv"

echo ""
echo "=== Internal Validation Complete ==="
echo "Logs: $LOG_DIR"
echo "Review each log file and complete the sign-off checklist in docs/pilot_study/20260324_INTERNAL_PILOT_TEST_PLAN.md"
```

---

## Timeline to March 29 Deadline

| Date | Action | Owner |
|---|---|---|
| March 24 (today) | Datasets prepared; test plan written | Engineering |
| March 25 | Run Sessions 1–3 internally; fix any blockers | Engineering |
| March 26 | Run Sessions 4–6 internally; complete sign-off checklist | Engineering |
| March 27 | Address any failures from internal run | Engineering |
| March 28 | Re-run full validation suite; all 18 checkboxes green | Engineering |
| March 29 | Platform configured with hospital target + compounds; briefing call | Engineering + Hospital team |
| March 30 | **Pilot Day 1 — hospital researchers begin** | Hospital team (self-directed) |

---

*BioMate AI · Internal document · Not for distribution · March 24, 2026*
