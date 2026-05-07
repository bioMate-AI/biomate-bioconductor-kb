# BioMate Regulatory LLM Training Data Quality Report

**Date:** 2026-05-06
**Script:** `scripts/data_quality_check.py`
**Total records audited:** 5,588

---

## Executive Summary

| # | File | Records | Issues Found |
|---|------|---------|-------------|
| 1 | `data/regulatory_training/combined_regulatory_training.jsonl` | 2,070 | 6 issue types |
| 2 | `data/regulatory_training/tasks/task1_section_generation.jsonl` | 542 | 3 issue types |
| 3 | `data/regulatory_training/tasks/task2_regulatory_qa.jsonl` | 12 | 1 issue |
| 4 | `data/regulatory_training/tasks/task3_region_adaptation.jsonl` | 317 | CRITICAL: all targets unmodified |
| 5 | `data/glp_study_data/epar_study_tables.jsonl` | 2,281 | 3 structural issues |
| 6 | `data/glp_study_data/fda_pharmar_studies.jsonl` | 366 | 2 minor issues |

**Critical issues requiring immediate action:**
1. **Task 3 (region adaptation): 317/317 targets are verbatim copies of the FDA input** — the adaptation pipeline did not run or did not write outputs. This entire dataset is unusable as-is.
2. **FDA label section headers contaminate openFDA records**: 425 records (85% of openFDA source) start with "13 NONCLINICAL TOXICOLOGY" or similar — section headers were included in the training responses rather than stripped.
3. **EMA_EPAR boilerplate contamination**: ~263–375 EMA records contain cover-page/admin text (CHMP, Assessment report, Procedure No, Committee for Medicinal Products). The EPAR extractor is including preamble text.
4. **Massive near-duplicate cluster**: 82 near-duplicate groups with 320 extra copies — dominated by FDA label "13 NONCLINICAL TOXICOLOGY 13.1 Carcinogenesis…" text repeated 16–23 times each.
5. **EPAR table headers: ~50% are empty or single-char** — PDF table extraction artifacts in 6,573 of 13,177 header cells.

---

## Section 1: Raw Corpus — `combined_regulatory_training.jsonl`

### 1a. Examples per source

| Source | Count |
|--------|-------|
| ICH_Guideline | 1,186 |
| openFDA_FDA_Labels | 500 |
| EMA_EPAR | 375 |
| FDA_NDA_Review | 9 |
| **Total** | **2,070** |

⚠️ **ISSUE: FDA_NDA_Review has only 9 examples** — extremely underrepresented. The most valuable source for IND-style prose has virtually no coverage.

### 1b. Word count distribution per source

| Source | min | p10 | p25 | median | p75 | p90 | max |
|--------|-----|-----|-----|--------|-----|-----|-----|
| ICH_Guideline | 17 | 39 | 60 | 77 | 90 | 100 | 126 |
| EMA_EPAR | 44 | 95 | 208 | 801 | 801 | 801 | 801 |
| openFDA_FDA_Labels | 81 | 138 | 190 | 277 | 456 | 684 | 1,201 |
| FDA_NDA_Review | 68 | 69 | 79 | 105 | 180 | 227 | 240 |

⚠️ **ISSUE: ICH_Guideline responses are very short (median 77 words).** The p10–p25 range (39–60 words) is below the typical 100-word minimum useful for LLM training targets. Many are ToC fragments and document history blocks.

⚠️ **ISSUE: EMA_EPAR has a bimodal distribution.** The p75–max are all 801 words — suggesting a hard text-length cut at 801 words truncating many records at identical lengths. The p25 of 208 suggests ~25% of records are much shorter fragments.

### 1c. Empty / near-empty responses (< 30 words)

**Count: 43** — all from `ICH_Guideline`.

Examples:
```
[ICH_Guideline] (21 words) '6.6. Exceptions................................................................'
[ICH_Guideline] (26 words) 'INTERNATIONAL CONFERENCE ON HARMONISATION OF TECHNICAL REQUIREMENTS...'
[ICH_Guideline] (23 words) '• Brief Summary • Methods of Analysis • Absorption • Distribution...'
[ICH_Guideline] (22 words) 'S1B Document History New First Codification History Date...'
```

⚠️ **ISSUE: 43 ICH_Guideline records are table-of-contents rows, document history blocks, or section title strings** — not training-quality regulatory prose. These should be filtered out.

### 1d. Duplicate detection

- **Exact duplicates:** 52 unique texts duplicated, 72 extra copies
- **Near-duplicates (same first 100 chars):** 82 groups, 320 extra copies

⚠️ **ISSUE: Largest near-duplicate cluster is "13 NONCLINICAL TOXICOLOGY 13.1 Carcinogenesis…" appearing 16–23 times each across multiple variants.** This is the openFDA section header — the extractor pulled the same boilerplate from many different drug labels.

Top duplicated previews:
```
count=23  '13 NONCLINICAL TOXICOLOGY 13.1 Carcinogenesis, Mutagenesis, Impairment of Fertil…'
count=21  '13 NONCLINICAL TOXICOLOGY 13.1 Carcinogenesis, Mutagenesis, Impairment of Fertil…'
count=5   '12.3 Pharmacokinetics Systemic plasma levels of bupivacaine following administra…'
```

### 1e. Boilerplate contamination (admin/cover-page keywords)

| Keyword | Total Hits | Source |
|---------|-----------|--------|
| CHMP | 283 | 259 EMA_EPAR, 24 ICH |
| Assessment report | 263 | 263 EMA_EPAR |
| Procedure No | 213 | 213 EMA_EPAR |
| Table of Contents | 234 | 209 EMA_EPAR, 25 ICH |
| European Medicines Agency | 204 | 201 EMA_EPAR, 3 ICH |
| Committee for Medicinal Products | 197 | 196 EMA_EPAR, 1 ICH |

⚠️ **ISSUE: 1,394 boilerplate keyword hits total.** The EMA_EPAR extractor is including assessment report cover pages and CHMP committee preambles instead of filtering to the nonclinical pharmacology section text. These records will teach the model to generate administrative boilerplate rather than regulatory prose.

### 1f. FDA label header contamination

**Count: 425** — all from `openFDA_FDA_Labels`.

Examples:
```
[openFDA_FDA_Labels] '13 NONCLINICAL TOXICOLOGY 13.1 Carcinogenesis, Mutagenesis, Impairment of Fertility…'
[openFDA_FDA_Labels] '12.3 Pharmacokinetics Systemic plasma levels of bupivacaine…'
```

⚠️ **ISSUE: 425 records (85% of the 500 openFDA records) include the FDA label section header string.** The extractor should strip the section title and return only the prose body. Training on this teaches the model to prefix its output with section headers.

### 1g. Non-ASCII / encoding issues

**Count: 0** — clean.

### 1h. Language check (possible non-English)

**Count: 31** — all from `ICH_Guideline`, but inspection shows these are actually English records that failed the heuristic due to heavy use of abbreviations, dotted table-of-contents lines, and bullet-list formats with minimal common English words. Not a real language issue, but confirms these are low-quality ToC/abbreviation fragments that should be filtered (overlaps with issue 1c).

---

## Section 2: Training Pairs — `task1_section_generation.jsonl`

### 2a. Count and word-count distribution per section_type

| section_type | n | min | p10 | median | p90 | max |
|-------------|---|-----|-----|--------|-----|-----|
| admet | 193 | 121 | 143 | 276 | 495 | 500 |
| tox_genotox | 143 | 137 | 169 | 267 | 500 | 500 |
| tox_overview | 72 | 131 | 168 | 284 | 500 | 500 |
| pk_overview | 70 | 123 | 144 | 470 | 500 | 500 |
| overview | 62 | 120 | 138 | 263 | 500 | 500 |
| pbpk | 2 | 120 | — | 123 | — | 126 |

⚠️ **ISSUE: `pbpk` has only 2 examples.** This is one of BioMate's core capabilities — heavily underrepresented in the training set.

⚠️ **ISSUE: Many targets hit the 500-word ceiling** (visible in p90=500 across multiple sections) — the generation prompt appears to cap output at 500 words but many training targets are truncated at that limit, suggesting some targets are incomplete.

### 2b. Citation injection rate per section_type

| section_type | n | With Citation | Rate |
|-------------|---|--------------|------|
| tox_overview | 72 | 37 | 51.4% |
| tox_genotox | 143 | 65 | 45.5% |
| pk_overview | 70 | 6 | 8.6% |
| admet | 193 | 5 | 2.6% |
| overview | 62 | 1 | 1.6% |
| pbpk | 2 | 0 | 0.0% |

⚠️ **ISSUE: `admet`, `overview`, and `pbpk` have very low citation rates (0–2.6%).** If the goal is to train the model to cite ICH guidelines, these sections will receive no signal for doing so. The system prompt instructs citation but most targets lack it.

### 2c. Prompt-target alignment: tox_genotox misclassification

**0 misclassified** — all 143 tox_genotox targets contain at least one genotoxicity keyword. Clean.

### 2d. Boilerplate leak in assistant targets

**Count: 1** — one `idelalisib` target starts with "DEPARTMENT OF HEALTH AND HUMAN SERVICES PUBLIC HEALTH SERVICE FOOD AND DRUG ADMINISTRATION CENTER FO…"

⚠️ **ISSUE: 1 FDA cover page leaked into the assistant target for idelalisib.** Remove this record.

### 2e. Duplicate assistant targets

- **51 unique texts duplicated, 74 extra copies**

⚠️ **ISSUE: The same text chunks from FDA drug labels appear as targets for multiple different drugs/sections.** Top duplicated:
```
count=5  '2-year study was performed in rats to evaluate the carcinogenic potential of nap…'
count=5  '12.3 Pharmacokinetics Systemic plasma levels of bupivacaine…'
count=4  'tumorigenicity when clopidogrel was administered for 78 weeks…'
```
These are verbatim excerpts from FDA labels being used as "generated" targets — the model is learning to memorize specific drug data rather than generalize regulatory writing patterns.

---

## Section 3: QA Pairs — `task2_regulatory_qa.jsonl`

All 12 question-answer pairs listed:

| # | Question (first 80 chars) | Answer words | Status |
|---|--------------------------|--------------|--------|
| 01 | Answer the following regulatory question... (EMA PBPK criterion) | 42 | ⚠️ Short |
| 02 | Answer the following regulatory question... (PBPK qualification report) | 57 | OK |
| 03 | Answer the following regulatory question... (EMA PBPK failed model) | 59 | OK |
| 04 | Answer the following regulatory question... (Redfern hERG categories) | 62 | OK |
| 05 | Answer the following regulatory question... (ICH S7B in silico hERG) | 62 | OK |
| 06 | Answer the following regulatory question... (ICH S2(R1) Ames positive) | 62 | OK |
| 07 | Answer the following regulatory question... (EMA DILI Reflection Paper) | 74 | OK |
| 08 | Answer the following regulatory question... (NMPA/CDE guidelines) | 77 | OK |
| 09 | Answer the following regulatory question... (ICH E5 bridging) | 78 | OK |
| 10 | Answer the following regulatory question... (21 CFR Part 11) | 81 | OK |
| 11 | Answer the following regulatory question... (ICH M4S QSAR validation) | 93 | OK |
| 12 | Answer the following regulatory question... (FDA/EMA AI practice) | 96 | OK |

⚠️ **ISSUE: QA pair #1 answer is only 42 words** — below the 50-word threshold for adequate coverage. The answer covers the EMA 67% within-2-fold criterion but is very terse.

**Note: QA pair #12 cites "FDA/EMA Joint Guidance on Good AI Practice in Drug Development (January 2026)"** — no such guidance existed as of the knowledge cutoff. This may be a hallucinated citation that will teach the model to invent regulatory references.

---

## Section 4: Region Adaptation Pairs — `task3_region_adaptation.jsonl`

### 4a. Count per target region

| Target Region | Count |
|--------------|-------|
| EMA | 180 |
| NMPA | 82 |
| PMDA | 55 |

Section types: admet (178), pk_overview (110), overview (27), pbpk (2).
All source region: FDA.

### 4b. Do targets differ from the FDA input?

**CRITICAL ISSUE — 317/317 (100%) targets are verbatim copies of the FDA input text.**

Example (target=NMPA, section=overview):
- FDA input: `"demonstrated no tumorigenic potential in mice at oral doses up to 1,000 mcg/kg…"`
- NMPA output: `"demonstrated no tumorigenic potential in mice at oral doses up to 1,000 mcg/kg…"` (identical)

Example (target=EMA, section=admet):
- FDA input: `"dosed with levetiracetam in the diet for 104 weeks at doses of 50, 300 and 1,800 mg/kg/day…"`
- EMA output: `"dosed with levetiracetam in the diet for 104 weeks at doses of 50, 300 and 1,800 mg/kg/day…"` (identical)

⚠️ **ISSUE (CRITICAL): The region-adaptation generation pipeline ran and wrote the FDA input text unchanged as the "adapted" output for all 317 records. This entire dataset is invalid as training data** — it teaches the model that FDA→NMPA and FDA→EMA adaptation is a no-op. This dataset must be regenerated with a working adaptation pipeline before it can be used.

---

## Section 5: EPAR Study Tables — `epar_study_tables.jsonl`

### 5a. Records with empty headers

**Count: 45** — 2.0% of records have completely empty `headers` arrays.

⚠️ **ISSUE: 45 tables cannot be meaningfully used without column context.**

### 5b. NOAEL/dose-related headers

**529 records (23.2%)** have NOAEL or dose-related headers — these are the high-value records for GLP study training.

### 5c. Row count distribution

| min | p10 | p25 | median | p75 | p90 | max | mean |
|-----|-----|-----|--------|-----|-----|-----|------|
| 3 | 4 | 6 | 7 | 7 | 7 | 7 | 6.2 |

⚠️ **ISSUE: Row counts are capped at 7 for p75–max** — suggesting a hard 7-row extraction limit was applied during PDF parsing. Many tables likely have more rows that were truncated.

### 5d. Top 10 drugs by table count

| Drug | Tables |
|------|--------|
| nustendi | 58 |
| nilemdo | 56 |
| vyloy | 54 |
| ezmekly | 35 |
| teizeild | 34 |
| loqtorzi | 34 |
| rezurock | 31 |
| tepkinly | 30 |
| cibinqo | 28 |
| mcombriax | 28 |

Coverage is heavily concentrated in a small set of drugs, with the top 10 representing ~20% of all table records.

### 5e. Empty or single-char headers

- **Total header cells:** 13,177
- **Empty / single-char headers:** 6,573 (**49.9%**)

⚠️ **ISSUE: Nearly half of all header cells are empty strings or single characters.** This is a strong indicator of multi-column merged PDF cells being split across empty columns during camelot/pdfplumber extraction. The table structure is largely lost for these records.

### 5f. Merged/garbled headers (newlines or >80 chars)

**Count: 580** garbled headers containing embedded newlines or exceeding 80 characters.

Examples:
```
[pluvicto] 'Calculated absorbed dose for 6 x 7 400 MBq (44 400 MBq cumulative activity) (Gy)a'
[pluvicto] 'Title: Trial PSMA_617-01 VISION: An international, prospective, open label, multicenter, randomized…'
```

⚠️ **ISSUE: 580 headers contain entire table titles or multi-line merged cells** — the PDF extractor is placing row-span content into the header row.

---

## Section 6: FDA PharmR Records — `fda_pharmar_studies.jsonl`

### 6a. Records by source type

| Source Type | Count |
|------------|-------|
| prose | 248 |
| table | 118 |

### 6b. NOAEL value distribution

- **Records with numeric NOAEL:** 248 / 366 (prose records only; table records have no `noael_value` field)
- **Range:** 0 – 2,000 mg/kg
- **Distribution:** min=0, p10=0, p25=2, median=24, p75=90, p90=372, max=2,000

⚠️ **ISSUE: 1 record with suspicious NOAEL value:**
```
[NDA217202, rat] NOAEL=0.0
```
A NOAEL of 0.0 means toxicity was observed at all doses including the lowest — this may be legitimate but warrants manual verification.

⚠️ **NOTE: p10=0 means at least 10% of prose records have NOAEL=0.** A zero NOAEL is uncommon and may indicate extraction failures where no dose was found but a default of 0 was substituted.

### 6c. Study type distribution

| Study Type | Count |
|-----------|-------|
| general toxicology | 145 |
| **unknown** | **118** |
| fertility | 30 |
| reproductive | 17 |
| embryo-fetal | 12 |
| 28-day | 10 |
| repeat-dose | 8 |
| 26-week | 7 |
| single-dose | 7 |
| single dose | 5 (duplicate label variant) |
| 13-week | 3 |
| hERG | 2 |
| micronucleus | 1 |
| repeat dose | 1 (duplicate label variant) |

⚠️ **ISSUE: 118 records have `study_type = "unknown"` — all are table-source records** that lack study type metadata. Also, "single-dose" and "single dose" are duplicate labels for the same concept, as are "repeat-dose" and "repeat dose" — these should be normalized.

### 6d. Species distribution

| Species | Count |
|---------|-------|
| **unknown** | **268 (73%)** |
| rat | 42 |
| rabbit | 20 |
| dog | 11 |
| monkey | 9 |
| mice | 8 |
| mouse | 7 (duplicate label) |
| hamster | 1 |

⚠️ **ISSUE: 268 records (73%) have no species.** These are all table-source records — the table extractor does not parse species from rows. Also, "mice" and "mouse" are duplicate labels.

### 6e. Missing key_findings text

**Count: 0** — all prose records have non-empty `noael_context`. All table records have at least some rows. Clean.

---

## Prioritized Fix List

### P0 — Must fix before any fine-tuning run

| # | Issue | File | Records Affected |
|---|-------|------|-----------------|
| 1 | **Region adaptation pipeline never ran** — all 317 targets are copies of FDA input | task3_region_adaptation.jsonl | 317 (100%) |
| 2 | **FDA label section header contamination** — "13 NONCLINICAL…" headers in responses | combined_regulatory_training.jsonl | 425 (openFDA) |
| 3 | **EMA_EPAR cover-page boilerplate** — CHMP/Assessment report text in responses | combined_regulatory_training.jsonl | ~263–375 (EMA) |

### P1 — Fix before scaling the dataset

| # | Issue | File | Records Affected |
|---|-------|------|-----------------|
| 4 | Near-duplicate cluster: "13 NONCLINICAL TOXICOLOGY…" repeated 16–23× | combined_regulatory_training.jsonl | ~320 extra copies |
| 5 | ICH_Guideline ToC / document history fragments (< 30 words) | combined_regulatory_training.jsonl | 43 |
| 6 | Duplicate assistant targets in task1 (74 extra copies) | task1_section_generation.jsonl | 74 |
| 7 | EPAR table headers ~50% empty/single-char | epar_study_tables.jsonl | 6,573 cells |
| 8 | FDA_NDA_Review only 9 examples — needs expansion | combined_regulatory_training.jsonl | source gap |

### P2 — Improve for quality

| # | Issue | File | Records Affected |
|---|-------|------|-----------------|
| 9 | ADMET/overview/pbpk citation rate < 3% in task1 | task1_section_generation.jsonl | 257 records |
| 10 | `pbpk` section_type has only 2 training pairs | task1_section_generation.jsonl | 2 |
| 11 | QA pair #1 answer too short (42 words) | task2_regulatory_qa.jsonl | 1 |
| 12 | QA pair #12 cites non-existent "FDA/EMA Joint AI Guidance Jan 2026" | task2_regulatory_qa.jsonl | 1 |
| 13 | FDA PharmR: 118 records with unknown study_type, 268 with unknown species | fda_pharmar_studies.jsonl | 268–386 |
| 14 | Study type label variants ("single-dose" vs "single dose") | fda_pharmar_studies.jsonl | ~6 |
| 15 | EPAR tables capped at 7 rows — truncated table data | epar_study_tables.jsonl | many |
| 16 | EPAR 580 garbled headers (newlines / >80 chars) | epar_study_tables.jsonl | 580 |

---

## Raw Audit Script Output

The full script output is produced by running:

```bash
cd /home/yzhang/biomate
python3 scripts/data_quality_check.py
```

Script location: `/home/yzhang/biomate/scripts/data_quality_check.py`
