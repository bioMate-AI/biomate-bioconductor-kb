# Pharmacology Workflow Validation Plan
**Date:** 2026-04-28

## Why Validation Matters

BioMate's pharmacology workflows cite peer-reviewed references but have not yet been
run against independent gold-standard datasets. A pharma client or regulatory reviewer
will ask: "How do you know this is right?" The answer must be empirical, not just
"we used the correct formula."

This document defines three concrete validation tests, the gold-standard data source
for each, and the acceptance criteria. Passing all three moves the workflows from
"Level 2 — referenced but unvalidated" to "Level 1 — independently validated."

---

## Validation Test 1 — `pbpk_disease_state`

### Gold standard: FDA published guidance examples

The FDA renal and hepatic impairment guidance documents contain real clinical study
results that the agency itself uses to illustrate the methodology. Any tool claiming
to implement this guidance must reproduce these numbers.

**Renal impairment (FDA 2010 Guidance, Appendix A examples):**

| Drug | CLr fraction | Normal GFR | Impairment | Observed AUC ratio | Expected from guidance formula |
|------|-------------|------------|------------|-------------------|-------------------------------|
| Gabapentin | ~100% renal | 120 mL/min | Severe (GFR 30) | ~5× | ~5.2× (Nolin power-law) |
| Metformin | ~100% renal | 120 mL/min | Moderate (GFR 45) | ~2× | ~1.8× |
| Atenolol | ~85% renal | 120 mL/min | ESRD (GFR 10) | ~6× | ~5.8× |

**Hepatic impairment (FDA 2003 Guidance, Table 2 examples):**

| Drug | Extraction ratio | Child-Pugh | Observed AUC ratio | Expected |
|------|-----------------|------------|-------------------|----------|
| Midazolam | High (ER~0.95) | B (moderate) | ~2.5× | ~2.4× (flow-limited) |
| Lorazepam | Low (ER~0.03) | C (severe) | ~1.5× | ~1.6× (well-stirred) |
| Lidocaine | High (ER~0.65) | B | ~2.2× | ~2.0× |

**Acceptance criteria:** predicted AUC ratio within ±25% of observed for ≥8 of 10
drug-impairment pairs. This matches FDA's own acceptable range for PBPK model
predictions in their 2018 PBPK reporting guidance.

---

## Validation Test 2 — `biomarker_patient_enrichment`

### Gold standard: BRIM-3 trial (vemurafenib, BRAF V600E, melanoma)

Chapman et al. NEJM 2011 (doi:10.1056/NEJMoa1103782) is the landmark biomarker-
enriched Phase III trial. The Phase II data that justified Phase III enrollment shows:

- BRAF V600E+ patients: ~63% response rate
- BRAF V600E- patients: <5% response rate (essentially non-responders)
- Enrichment ratio: >12×
- The biomarker enabled a 40% reduction in Phase III sample size vs unenriched design

**Validation approach:** Generate synthetic Phase II data matching these proportions
(n=80 patients, 3 biomarkers: BRAF status as true predictive, 2 noise biomarkers),
run `biomarker_patient_enrichment`, and verify:

**Acceptance criteria:**
- BRAF status ranked #1 by enrichment ratio
- Recovered ER ≥ 10 (vs true >12 — some loss expected with n=80)
- Bootstrap-corrected sensitivity > 0.85 at optimal cut-point
- Noise biomarkers have FDR q-value > 0.05 (correctly not selected)
- Phase III sample size reduction ≥ 35% with biomarker enrichment

---

## Validation Test 3 — `polymorph_stability_screening`

### Gold standard: Cambridge Structural Database polymorph counts

The CSD documents crystal forms for thousands of pharmaceutical compounds.
High-polymorph drugs and low-polymorph drugs are well-established from literature:

**High polymorph count (should score HIGH risk):**
- Carbamazepine: 5 known forms (notorious CMC problem)
- Ritonavir: 2 forms (Form II appeared in production, caused a $250M recall)
- Sulfathiazole: 5 forms
- ROY compound: 9 forms (record holder)

**Low polymorph count (should score LOW or MEDIUM risk):**
- Aspirin: 2 forms (known but stable)
- Caffeine: 2 forms (stable Form I dominant)
- Paracetamol (acetaminophen): 3 forms but Form I is dominant and stable
- Ibuprofen: racemic Form I stable

**Acceptance criteria:**
- All 4 high-polymorph compounds score MEDIUM or HIGH (≥ 5 points on 10-point scale)
- Ritonavir and carbamazepine specifically score HIGH (≥ 7.0)
- At least 3 of 4 low-polymorph compounds score LOW or MEDIUM (≤ 5.5)
- No false negatives on the two historical CMC-crisis compounds (ritonavir, carbamazepine)

---

## Implementation

All three tests are implemented in:
`evaluation/runners/run_pharmacology_benchmark.py`

The runner:
1. Calls each workflow's Python logic directly (extracts and executes the embedded
   Python, bypassing Nextflow for speed)
2. Compares results against ground truth
3. Reports pass/fail per case and an overall accuracy score
4. Writes structured results to `evaluation/results/pharmacology_benchmark_v1/`

---

## Relationship to Existing Evaluation Framework

BioMate already has `evaluation/` with runners, adapters, and benchmark datasets for
routing, ADMET, and BiomniEval1. This pharmacology benchmark follows the same pattern.

Running `run_pharmacology_benchmark.py` produces a validation table that can be:
- Included in the Paper A (BioMate-Cryo) supplementary
- Shown to pharma clients as evidence of calibration
- Used as a regression test in CI to catch future breakages
