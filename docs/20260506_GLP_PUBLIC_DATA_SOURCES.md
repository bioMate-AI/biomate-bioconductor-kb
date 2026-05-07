# Public GLP Nonclinical Study Data — Sources and Collection Plan

**Date:** 2026-05-06  
**Purpose:** Document public sources of GLP study data for PDF ingestion model training

---

## What We Need

To train the PDF extraction model (Track A of the IND product plan), we need nonclinical
study documents containing structured data: species, dose groups, NOAEL, route, duration,
key findings. These map to the §2.6.3 subsections of an IND.

The common assumption that this data is entirely proprietary is **wrong**. Three public
sources exist with high-quality, pharmaceutical-context nonclinical study data.

---

## Source 1 — FDA Pharmacology/Toxicology Reviews ⭐ PRIMARY

**What it is:** When FDA approves a drug, it publishes the reviewer's summary of the sponsor's
Module 4 (nonclinical study reports). This is an FDA scientist's structured extraction of the
GLP study results submitted by the sponsor — the same data we want to learn to extract.

**URL pattern:**
```
https://www.accessdata.fda.gov/drugsatfda_docs/nda/[YEAR]/[NDA]Orig1s000PharmR.pdf
```

**How to discover available URLs:**
1. Query Drugs@FDA API for NDAs with TOC review documents:
   `https://api.fda.gov/drug/drugsfda.json?search=submissions.submission_type:NDA`
2. The API returns `TOC.html` URLs — substitute `TOC.html` → `PharmR.pdf`
3. HEAD request to confirm the file exists before downloading

**Verified working examples:**
| Drug | NDA | Year | Size | Content |
|------|-----|------|------|---------|
| Otezla (apremilast) | 205437 | 2014 | 34.6 MB | 390 pages, 22 study tables, NOAEL data |
| Entresto (sacubitril/valsartan) | 207986 | 2015 | 9.4 MB | Cardiac safety tables |
| Brilinta (ticagrelor) | 200327 | 2010 | 0.4 MB | Tox summary |
| Imbruvica (ibrutinib) | 204824 | 2013 | 3.4 MB | Oncology nonclinical |

**Scale:** ~3,000+ NDA applications with PharmR documents publicly available.

**Content quality:** HIGH. Contains:
- NOAEL with species, route, duration, dose groups, sex
- Genotoxicity battery results (Ames, micronucleus, chromosomal aberration)
- hERG IC50 values and cardiac safety pharmacology
- PK parameters (Cmax, AUC, t½, protein binding)
- Safety margins vs human exposure (AUC ratio at NOAEL)
- Specific toxicological findings at each dose level

**Caveat:** `(b)(4)` redactions appear where trade-secret data was withheld.
These are usually proprietary formulation details or specific assay parameters,
not the NOAEL values or primary study conclusions.

**Recency matters — use 2020+ for current ICH guideline alignment:**

| Year range | ICH guidelines reflected |
|-----------|------------------------|
| pre-2012 | Pre-ICH S2(R1) — old genotoxicity battery |
| 2012–2021 | S2(R1), S7B 2005, M3(R2) |
| 2022–2023 | + S5(R3) reproductive tox, M7(R2) mutagenic impurities |
| 2024–2025 | + S7B(R1) in silico hERG formalised, most current |

**Recommended filter:** `--year-min 2020` for training data that matches current regulatory
language and citation patterns. PharmR PDFs from 2020–2025 will cite the same guidelines
our model is trained to produce.

---

## Source 2 — NTP Technical Reports

**What it is:** National Toxicology Program (US NIEHS) publishes full technical reports
of GLP carcinogenesis and toxicology studies conducted on ~2,000 chemical compounds.
These are among the most rigorously structured public nonclinical study reports available.

**URL pattern:**
```
https://ntp.niehs.nih.gov/ntp/htdocs/lt_rpts/tr[NNN].pdf
```
Report numbers: TR-50 to TR-620+. All public, no authentication.

**Content quality:** VERY HIGH structure.
- Standardised format across all reports (same FDA/NIH contractor format for 40 years)
- Always contains: NOAEL, LOAEL, species/strain, route, dose groups, duration
- Carcinogenesis findings by organ/tissue/sex
- Haematology and clinical chemistry data

**Limitation:** Mostly industrial chemicals and environmental contaminants, not
pharmaceutical drug candidates. The study format is identical to pharma GLP studies,
but the compounds are different. Useful for training the extraction model's understanding
of study report structure; less useful for regulatory prose style.

**Scale:** 620+ reports, all downloadable.

---

## Source 3 — EMA EPAR Nonclinical Study Tables (Already Have PDFs)

**What it is:** We have 375 EMA EPAR assessment report PDFs cached. The CHMP nonclinical
assessment section (pages 30–100 of each report) contains the same structured study tables
as FDA PharmR. These are the EMA reviewer's extraction of Module 4 GLP studies.

**Advantage:** We already have the PDFs. No new downloads needed.

**Content quality:** HIGH — pharmaceutical context, ICH-aligned, includes EMA-specific
criteria (e.g. 67% within-2-fold for PBPK, S5(R3) reproductive endpoints, E5 ethnic bridging).

**What's been collected vs. what's missing:**
- **Done:** Prose extraction for regulatory writing training (§2.6 summaries)
- **Not done:** Structured table extraction (species, dose, NOAEL per study)

Estimated yield: ~5–15 study tables per EPAR × 375 EPARs = 1,875–5,625 study table records.

---

## Extraction Strategy

**Two-pass approach:**

**Pass 1 — Prose extraction (high reliability)**

Every GLP study report has a "Conclusion" or "Results" section in plain prose:
> *"The NOAEL for systemic toxicity in the 28-day repeat-dose rat study was 100 mg/kg/day,
> based on increased liver weight and hepatocellular hypertrophy at 300 mg/kg/day."*

Extract via regex:
```python
re.compile(
    r"(?:NOAEL|no.observed.adverse.effect.level)[^\n]{0,200}?"
    r"(\d+(?:\.\d+)?)\s*(?:mg/kg(?:/day)?|µg/kg|g/kg)",
    re.I
)
```
Reliable on >80% of FDA PharmR and NTP reports. Identifies:
- NOAEL value + units
- Study type from surrounding context (genotox, repeat-dose, reproductive, cardiac)
- Species from surrounding context

**Pass 2 — Table extraction (lower reliability, needs validation)**

Use pdfplumber to find tables where headers contain: `noael`, `dose`, `species`, `duration`.
Issues: merged cells, multi-line rows, no standard column ordering across CROs.

Validation rule: cross-check extracted NOAEL against Pass 1 value from the same document.
If they match → high confidence. If they differ → flag for review.

**LLM-assisted extraction (for Pass 2 failures):**

When table extraction fails, use Gemini (high context window) with a targeted prompt:
```python
prompt = f"""
This is a page from an FDA pharmacology review. Extract the nonclinical study data as JSON:
{{
  "study_type": "...",  # e.g. "28-day repeat dose", "Ames test", "hERG patch clamp"
  "species": "...",
  "route": "...",
  "dose_groups_mgkg": [...],
  "noael_mgkg": ...,
  "key_findings": "..."
}}
Text: {page_text}
"""
```

This is reliable for prose but still requires unit validation (mg/kg vs mg/kg/day vs mg/m²).

---

## Collection Plan

### Immediate — start now

```bash
# EMA EPAR tables (0 downloads needed, we have the PDFs)
python3 scripts/collect_glp_study_data.py \
  --epar-tables \
  --output data/glp_study_data

# FDA PharmR: 2020–2025 approvals (highest regulatory relevance)
python3 scripts/collect_glp_study_data.py \
  --fda --max 200 --year-min 2020 \
  --output data/glp_study_data
```

### Phase 2 — after validating extraction quality

```bash
# Expand FDA to 2018+ (broader coverage, still current guidelines)
python3 scripts/collect_glp_study_data.py \
  --fda --max 500 --year-min 2018 \
  --output data/glp_study_data

# NTP reports for structural training signal
python3 scripts/collect_glp_study_data.py \
  --ntp --max 100 \
  --output data/glp_study_data
```

### Expected yield

| Source | Documents | Study records | Quality |
|--------|-----------|---------------|---------|
| FDA PharmR 2020–2025 | ~200 | ~2,000–4,000 | HIGH |
| EMA EPAR tables | 375 cached | ~2,000–5,000 | HIGH |
| NTP reports | 100 | ~300–600 | MEDIUM (structure only) |
| **Total** | ~675 | **~4,000–10,000** | |

This is sufficient to train and validate a table extraction model covering the main
study types: genotoxicity, cardiac safety, repeat-dose tox, PK parameters.

---

## What This Unlocks

With ~4,000–10,000 extracted study records:

1. **Train the field extractor** — supervised model or validated few-shot LLM prompt that
   reliably converts a study PDF page → `{noael, species, route, dose_groups, study_type}`
2. **Validate against prose** — cross-check table extraction against NOAEL mentioned in
   the conclusion paragraph. Agreement ≥90% = production-ready.
3. **Populate §2.6.3.x sections** — once a sponsor uploads their GLP study PDF,
   extract fields → fill the §2.6.3 template with real data → generate prose narrative
4. **Replace the current computational-only limitation** — with real wet-lab data input,
   BioMate generates §2.6.3 text from actual GLP studies, not predictions
