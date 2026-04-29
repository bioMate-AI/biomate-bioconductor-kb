# IND Regulatory Skills DB, OSP Benchmark Wiring, and Multi-Region Audit

**Date:** 2026-04-29  
**Session:** IND §2.6 implementation continuation  
**Status:** All changes implemented and verified (37/37 gold standard passing)

---

## Summary of Changes This Session

### 1. Regulatory Skills DB (`regulatory_skills_db.py`)

SQLite-backed knowledge store for patterns learned from EMA-accepted OSP Qualification Reports.

**Schema:**
- `documents` — one row per source document with SHA256 hash
- `skills` — extracted PBPK metrics (GMFE, within-2-fold values)
- `pbpk_benchmarks` — structured benchmark records per drug pair
- `narrative_patterns` — regulatory sentences and criterion statements

**6 authoritative sources (all GPL-licensed, EMA-accepted):**
| Source ID | Report | Key compounds |
|-----------|--------|---------------|
| OSP_CYP3A4_DDI | CYP3A4 DDI v2.2 | Midazolam, Rifampicin, Clarithromycin |
| OSP_CYP2C19_DDI | CYP2C19 DDI v2.0 | Omeprazole, Fluvoxamine |
| OSP_CYP1A2_DDI | CYP1A2 DDI | Fluvoxamine, Theophylline, Caffeine |
| OSP_PGP_DDI | P-gp DDI | Digoxin, Rifampicin, Itraconazole |
| OSP_PEDIATRIC_CYP3A4 | Pediatric CYP3A4 | Midazolam, Alfentanil |
| OSP_CKD | CKD special population | Gabapentin, Atenolol |

**First ingestion results (all 6 sources fresh):**
- 194 skills extracted
- 5 PBPK benchmarks (all PASS, within-2-fold: 87.5%–100%)
- 133 narrative patterns
- OSP-approved PBPK range: within-2-fold 50–100%, GMFE AUC 1.0–1.76

**Source validation guard:** All guideline IDs are validated against `regulatory_knowledge.yaml` before ingestion. Non-current or unofficial sources are rejected.

### 2. OSP Benchmark Check in RegulatoryAuditor

New `_check_osp_benchmarks()` method added to `RegulatoryAuditor.audit()`:

- Reads `validation_report.within_2fold_fraction`, `.afe`, `.aafe` from assembly context
- Calls `RegulatorySkillsDB.compare_metrics()` to compare against OSP approved range
- Emits:
  - `MAJOR OSP-BENCH-001` if below EMA 67% criterion
  - `INFO OSP-BENCH-002` if passes EMA but outside OSP range (87.5%–100%)
  - `INFO OSP-BENCH-PASS` if passes and within OSP range
- Silently no-ops if skills DB has not been ingested yet

**Test on BioMate metrics (within-2-fold=73.3%):**
```
[INFO] OSP-BENCH-PASS: BioMate PBPK within-2-fold (73.3%) meets EMA criterion 
       and is within OSP-approved range. OSP approved range: 50.0–100.0%
```

### 3. New API Endpoints

All under `/api/drug-discovery/`:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/regulatory-skills/summary` | DB state: document/skill/benchmark counts |
| `POST` | `/regulatory-skills/ingest` | Download and ingest all 6 OSP reports |
| `GET` | `/regulatory-skills/pbpk-benchmarks` | All PBPK benchmark records from approved reports |
| `GET` | `/regulatory-skills/narratives` | Regulatory narrative patterns (filterable by section/type) |
| `GET` | `/regulatory-skills/compare-metrics` | Compare PBPK metrics against EMA criterion + OSP range |

**Sample `compare-metrics` response:**
```json
{
  "biomate_metrics": {"afe": 0.95, "aafe": 1.3, "within_2fold": 0.733},
  "ema_criterion": {"threshold": 0.67, "passes": true, "margin": 0.063},
  "osp_benchmark": {
    "n_reports": 5,
    "within_2fold_range_pct": [50.0, 100.0],
    "gmfe_auc_range": [1.0, 1.76],
    "biomate_within_osp_range": true
  },
  "verdict": "PASS",
  "note": "BioMate within-2-fold (73.3%) exceeds EMA criterion (67%). OSP approved range: 50.0–100.0%"
}
```

### 4. Ingestion Runner (`evaluation/runners/ingest_regulatory_skills.py`)

CLI for managing the skills DB:
```bash
# Ingest all sources (idempotent)
python evaluation/runners/ingest_regulatory_skills.py

# Force re-download
python evaluation/runners/ingest_regulatory_skills.py --force

# Print DB summary
python evaluation/runners/ingest_regulatory_skills.py --summary

# Compare specific PBPK metrics
python evaluation/runners/ingest_regulatory_skills.py --compare \
  --afe 0.95 --aafe 1.3 --within2fold 0.733 --region EMA
```

---

## Architecture: IND §2.6 Data Flow

```
ADMET Nextflow workflow
    → pk_summary.json
        → POST /{campaign_id}/pk-summary (stored in SQLite)
            → INDSectionAssembler._load_stored_pk_summary()
                → §2.6.2 Pharmacokinetics section
                → §2.6.3.7 Cardiac Safety section

CRO assay CSV upload
    → campaign_assay_results table
        → INDSectionAssembler._load_safety_profile()
            → §2.6.1.3 ADMET Results (hERG/DILI/Ames flags)
            → §2.6.3 Toxicology overview

PBPK Validation (ModelValidationService)
    → validation_report (within_2fold, AFE, AAFE, R², n_points)
        → §2.6.1.2 PBPK Model Qualification
        → RegulatoryAuditor._check_osp_benchmarks()
            → RegulatorySkillsDB.compare_metrics()
                → EMA criterion + OSP benchmark range
```

---

## Gold Standard Test Results

### v2 Test Suite (37/37 PASS)
9 reference compounds: Ibuprofen, Terfenadine, Nitrofurantoin, Atorvastatin, Cisapride, Troglitazone, Warfarin, Midazolam, Caffeine

| Test Category | Tests | Pass |
|---------------|-------|------|
| TC-1: Safety flags | 8 | 8 |
| TC-2: PK accuracy | 5 | 5 |
| TC-3: Completeness | 7 | 7 |
| TC-4: Narrative quality | 12 | 12 |
| TC-5: Known compound | 5 | 5 |

### TDC Benchmark Scores
| Assay | BioMate | Chemprop Baseline | Gap |
|-------|---------|-------------------|-----|
| hERG AUROC | **0.9635** | 0.87 | +0.0935 ✓ |
| DILI AUROC | **0.8542** | 0.847 | +0.007 ✓ |
| PPBR MAE (%) | 19.35 | 8.4 | -10.95 ✗ (open) |

**PPBR gap root cause:** Lobell 2003 sigmoid formula overestimates PPB for logP > 3 compounds.  
**Proposed fix:** Replace with ADMET-AI Chemprop-RDKit model (MAE ~8.6%).

---

## Multi-Region Compliance Coverage

| Region | Checks implemented | Status |
|--------|-------------------|--------|
| FDA | PBPK Assumptions & Limitations table, ICH S9 oncology note | ✓ audit check (Sprint 1 open: generate content) |
| EMA | PBPK 67% criterion, DILI mechanistic tier, OSP benchmark range | ✓ full |
| NMPA | GLP declaration, ethnic bridging statement | ✓ audit checks |
| PMDA | Japanese ethnic sensitivity (ICH E5/E7) | ✓ audit check |

---

## Open Items (Sprint 1, ~5 hours)

1. **FDA: Model Assumptions & Limitations content** — Audit check exists; `_section_pbpk_assumptions()` template needs to be wired into document generation
2. **NMPA: GLP declaration field** — `glp_facility` and `glp_recognition` params exist in `INDAssemblyRequest`; need template text in §2.6.1 overview 
3. **NMPA/PMDA: Ethnic bridging statement** — Add `ethnic_bridging_note` field; generate template per ICH E5
4. **PPBR fix** — Replace Lobell 2003 with ADMET-AI model in `predict_admet_properties.nf`

## Open Items (Sprint 2, ~8 hours)

5. **EMA DILI mechanistic tier** — Reactive metabolite structural alert evaluation (RDKit SMARTS or Derek Nexus)
6. **within-3-fold PBPK metric** — Add to `_section_pbpk()` table (MINOR audit finding currently)

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/drug_discovery/regulatory_skills_db.py` | **NEW** — SQLite skills DB with OSP ingestion |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_auditor.py` | Added `_check_osp_benchmarks()`, logging import |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | 5 new `/regulatory-skills/` endpoints |
| `evaluation/runners/ingest_regulatory_skills.py` | **NEW** — CLI runner for skills ingestion |
| `backend/database/regulatory_skills.db` | **NEW** — Populated with 6 OSP reports, 194 skills |
