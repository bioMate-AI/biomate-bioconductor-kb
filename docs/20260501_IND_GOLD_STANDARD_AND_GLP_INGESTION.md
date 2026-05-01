# IND Gold Standard Expansion + GLP Report Ingestion Pipeline

**Date:** 2026-05-01  
**Session focus:** Expand validation set from 10 to 27 reference compounds using public GLP data sources

---

## What Changed

### Gold Standard: 10 → 27 Reference Compounds

`evaluation/datasets/ind_gold_standard/reference_compounds_v2.yaml`

| Category | Count | Compounds |
|----------|-------|-----------|
| hERG safe (≥10 µM) | 18 | Ibuprofen, Sildenafil, Metformin, Metoprolol, Omeprazole, Clarithromycin, Atorvastatin, Warfarin, Midazolam, Caffeine, Propranolol, and 7 others |
| hERG positive (<10 µM) | 9 | Terfenadine (0.1), Cisapride (0.007), Dofetilide (0.012), Verapamil (0.3), Amiodarone (0.3), Haloperidol (0.5), Quinidine (0.8), Astemizole (0.00009), Clozapine (1.5) |
| DILI positive | 16 | Terfenadine, Cisapride, Verapamil, Amiodarone, Haloperidol, Quinidine, Astemizole, Clarithromycin, Troglitazone, Ketoconazole, Isoniazid, Acetaminophen, Valproic_Acid, Clozapine, Nitrofurantoin, Mitomycin_C |
| Ames positive | 3 | Isoniazid, Nitrofurantoin, Mitomycin_C |

All expected_flags are internally consistent with measured values. All ChEMBL IDs verified by name lookup (corrected 12 incorrect IDs from initial dataset).

### Data Sources Integrated

1. **Redfern 2003** (Cardiovasc Res) — hERG IC50 category classification (Cat 1-4)
2. **DILIrank v1** (Chen et al. Drug Discov Today 2016) — vMDILI/wMDILI/nMDILI
3. **Hansen 2009** (Chem Res Toxicol) — Ames mutagenicity data
4. **ChEMBL REST API** — Measured IC50 for hERG (target: CHEMBL240/KCNH2); provides independent verification for 5 compounds
5. **NTP Technical Report TR-341** (Nitrofurantoin, 226-page GLP study) — Ames+, CA+ correctly extracted
6. **FDA drug labels** (NDA numbers: 21-374, 20-895, 18-654, 20-702, 9-218) — PK parameters

### Key Correction: Clarithromycin hERG

- Previous value: 5.0 µM (single Guo 2005 paper)
- ChEMBL consensus (n=5 assays): **58.9 µM**
- Impact: Clarithromycin correctly remains in expected_flags=[] (not hERG-flagged)
- Note: 5 µM value may reflect assay conditions with CYP3A4 auto-inhibition artifact

---

## GLP Report Ingestion Pipeline

### WetLabReportIngester — New Methods

**`ingest_ntp_report(drug_name, ntp_url, cache_dir)`**
- Downloads NTP GLP Technical Report PDFs (public, no auth)
- Extracts Ames result, chromosomal aberration, NOAEL via updated NTP-format regex
- Test result: Nitrofurantoin TR-341 → Ames=**positive** ✓, CA=**positive** ✓

**`ingest_fda_nda(drug_name, nda_url, cache_dir)`**
- Downloads FDA NDA nonclinical review PDFs
- Extracts PK (fu_plasma, t½, Vd, CL, F%) and safety (hERG, Ames, NOAEL)
- Note: some older FDA NDA URLs have changed (pre-1998 PDFs not always accessible)

**`ingest_chembl_reference(drug_name, chembl_id)`**
- Pulls measured hERG IC50 and PPB from ChEMBL REST API
- Returns MeasuredValue with `confidence="MEDIUM"` (assay variability across labs)
- Tested: Verapamil 0.20 µM ✓, Terfenadine 0.20 µM ✓, Cisapride 0.040 µM ✓

### Updated Safety Pattern Matching

Added NTP Technical Report-specific regex patterns for:
- Ames: `"was (mutagenic|not mutagenic) in Salmonella typhimurium"` 
- Chromosomal aberration: `"induced increased numbers of ... chromosomal aberrations"` (NTP implied positive)
- Negative: `"no chromosomal aberrations were observed"`
- Binary result extractor now handles patterns without capture groups (implied results)

---

## Collection Script

`evaluation/runners/collect_gold_standard.py`

```bash
# Full collection (ChEMBL + FDA NDA download + NTP download):
python evaluation/runners/collect_gold_standard.py --all

# ChEMBL only (fast, no PDF downloads):
python evaluation/runners/collect_gold_standard.py --chembl-only --no-download

# NDA downloads only:
python evaluation/runners/collect_gold_standard.py --nda-only
```

Outputs:
- `reference_compounds_v2.yaml` — curated + ChEMBL-augmented gold standard
- `chembl_measured_raw.json` — raw ChEMBL IC50 measurements per compound
- `fda_nda_extracts/` — downloaded NDA PDFs + extracted text (when run with --all)
- `ntp_extracts/` — downloaded NTP GLP report PDFs + extracted text

---

## Competitive Comparison Strategy (documented separately)

`docs/20260501_COMPETITIVE_COMPARISON_STRATEGY.md`

- For the manuscript: **cite and comment** competitors (Certara CoAuthor, AutoIND, Schrödinger, Yseop)
- Direct head-to-head requires commercial access to tools with unreleased code
- The valid quality comparison is a **blinded expert user study** (5 compounds, 2 FDA-experienced reviewers, ICH M4 rubric) — planned as future work
- Manuscript §4.1 now includes Table 5: feature-coverage comparison across 8 tools

---

## Open Items

- Caffeine NTP TR-067: Ames result not found (PDF text may need different page range)
- FDA NDA URL for Ibuprofen returns 404 (URL format changed since 2002)
- Target: expand to 40+ compounds for paper publication (add 13 more: Rosuvastatin, Tamoxifen, Diclofenac, Rifampicin, Methotrexate, Nifedipine, Erythromycin, Digoxin, Simvastatin, Fluoxetine, Ketorolac, Phenytoin, Carbamazepine)
- Run full ADMET-AI prediction pipeline on all 27 SMILES and compare predicted vs measured for all endpoints
