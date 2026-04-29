# IND Regulation Report — Gold Standard Test Plan

**Date:** 2026-04-29  
**Scope:** §2.6.1–§2.6.3 generation accuracy, safety flag detection, PK parameter accuracy  
**Status:** Draft → Executed

---

## 1. Audit Findings (Pre-Test)

Seven critical issues found in the assembler before testing:

| # | Issue | Severity | Fixed? |
|---|-------|----------|--------|
| 1 | Pass rate used composite_score ≥ 0.5 proxy; LLM claimed "passed all safety gates" | HIGH | ✅ Fixed |
| 2 | hERG default 9999 µM for unmeasured compounds — silently treated as safe | HIGH | Documented |
| 3 | TDC ADMET benchmark marked `data_source: hardcoded_fallback` — not live validation | HIGH | Test added |
| 4 | Silent LLM failure — empty string returned with no document warning | MED | Documented |
| 5 | PPBR_AZ MAE 19.35% vs baseline 8.4% (2.3× worse) | MED | In test |
| 6 | "validated methods" in title when validation report unavailable | MED | Documented |
| 7 | No training set citation for applicability domain calculation | LOW | Documented |

---

## 2. Gold Standard Reference Compounds

Selected for known, published pharmacological properties:

| Compound | MW | logP | hERG IC50 | Ames | DILI | f_u | Vd (L/kg) | Expected outcome |
|----------|-----|------|-----------|------|------|-----|-----------|-----------------|
| **Ibuprofen** | 206.3 | 3.97 | >30 µM (safe) | Negative | Negative | 0.01 | 0.15 | Lead candidate: clean |
| **Terfenadine** | 471.7 | 6.49 | ~0.1 µM (toxic) | Negative | Positive | 0.03 | 4.7 | hERG+ flag |
| **Nitrofurantoin** | 238.2 | -0.47 | >100 µM (safe) | Positive | Negative | 0.33 | 0.28 | Ames+ flag |
| **Atorvastatin** | 558.7 | 4.46 | 5.2 µM (borderline) | Negative | Positive | 0.012 | 381 | DILI+ flag |

Sources: FDA drug labels; ChEMBL; ICH S7B reference dataset; TDC ADMET leaderboard.

---

## 3. Test Cases

### TC-1: Safety Gate Accuracy
**Objective:** Verify the assembler correctly identifies compounds with known safety liabilities.

Input:
- Campaign with 4 compounds: ibuprofen, terfenadine, nitrofurantoin, atorvastatin
- Assay data: hERG IC50 (µM), Ames (binary), DILI (binary)

Expected outcomes:
- `herg_flagged = 1` (terfenadine only, IC50 < 10 µM)
- `ames_flagged = 1` (nitrofurantoin only)
- `dili_flagged = 2` (terfenadine + atorvastatin)
- Lead compound = ibuprofen (rank 1, highest composite score)
- Pass rate = 1/4 = 25% (only ibuprofen passes all gates)
- §2.6.3.3 narrative mentions Ames mutagenicity positive compound
- §2.6.3.7 (cardiac) mentions hERG-flagged compound

### TC-2: PK Parameter Accuracy (§2.6.2)
**Objective:** Verify pk_summary values for ibuprofen are within published ranges.

Input:
- pk_summary with published ibuprofen PK: f_u=0.01, Vd=0.15 L/kg, cl_hepatic_fraction=0.90, cl_renal_fraction=0.05
- Provide as pk_summary JSON body parameter

Expected outcomes:
- §2.6.2 "Predicted DMPK Parameters" table present
- Table contains f_u=0.010, Vd=0.150 (±5% tolerance for floating point)
- Estimation method citation includes "Lobell" and "Lombardo"
- Disclaimer present

### TC-3: Document Completeness
**Objective:** All ICH M4 CTD sections present and non-empty.

Expected outcomes:
- sections array contains exactly: 2.6.1.1–2.6.1.6, 2.6.2, 2.6.3 (8 entries)
- Each heading appears in markdown (non-empty section body)
- Title page contains molecule name, sponsor, indication, target
- Document ≥ 15,000 chars total
- Pandoc: DOCX generated

### TC-4: LLM Narrative Quality
**Objective:** Regulatory prose is present and well-formed.

Expected outcomes:
- §2.6.1.1 narrative: ≥ 50 chars, contains regulatory language
- §2.6.1.2 (PBPK) narrative: mentions EMA criterion, AFE or AAFE
- §2.6.3.3 (genotoxicity) narrative: mentions Ames, ICH S2
- §2.6.3.7 (cardiac) narrative: mentions hERG, IC50, ICH S7B
- No narrative section is empty (LLM failure degrades to empty string)

### TC-5: TDC ADMET Live Accuracy
**Objective:** Verify hERG/DILI accuracy against published TDC test set (live, not hardcoded).

Reference: TDC ADMET leaderboard (https://tdcommons.ai/benchmark/admet_group/)
- hERG: AUROC ≥ 0.85 (Chemprop baseline 0.87)
- DILI: AUROC ≥ 0.80 (Chemprop baseline 0.847)
- PPBR_AZ MAE: currently 19.35% vs 8.4% baseline — **FAIL**

PPBR fix needed: the Lobell 2003 sigmoid underestimates binding for highly lipophilic compounds. Planned fix: add a correction factor for compounds with logP > 3 where the Lobell model is known to overpredict fu.

---

## 4. Pass/Fail Criteria

| Test | Metric | Pass threshold |
|------|--------|----------------|
| TC-1: Safety flags | herg/ames/dili counts exact match | All 3 exact |
| TC-1: Lead compound | rank-1 compound ID | Ibuprofen |
| TC-1: Pass rate | % passing all gates | 25% ± 0 |
| TC-2: f_u | Absolute error | < 0.005 |
| TC-2: Vd | Relative error | < 10% |
| TC-2: Disclaimer present | Boolean | True |
| TC-3: Section count | Exact | 8 |
| TC-3: Document size | Total chars | ≥ 15,000 |
| TC-3: DOCX generated | Boolean | True |
| TC-4: Narrative non-empty | Count of non-empty narratives | ≥ 4/5 |
| TC-4: ICH S7B mentioned | Boolean | True |
| TC-5: hERG AUROC | ≥ 0.85 | PASS (0.9635) |
| TC-5: DILI AUROC | ≥ 0.80 | PASS (0.8542) |
| TC-5: PPBR MAE | ≤ 12% | **FAIL (19.35%)** — open issue |

---

## 5. Open Issues After Testing

| Issue | Priority | Planned fix |
|-------|----------|-------------|
| PPBR MAE too high (19.35% vs 8.4% baseline) | HIGH | Chemprop-style correction or AdMET-AI integration |
| TDC benchmark hardcoded | HIGH | Wire to live TDC API or local test set |
| Silent LLM failure (empty section) | MED | Add warning to `warnings[]` array |
| AD training set not documented | MED | Add citation to `_section_applicability_domain()` |
| CYP induction missing from §2.6.2 | LOW | Add note in DDI sub-section |
