# Regulatory LLM v9+ — Modality Coverage Roadmap

**Date:** 2026-05-16
**Purpose:** Document the scenarios v6/v7 *do not* cover, with prioritized fill order.
**Current state:** v6 covers small-molecule oral Phase I–III standard ICH M3(R2) pathway.

---

## Why this doc exists

The v6 evaluation showed 4/5 checkers above target on the synthetic test split. But that test split is calibrated to the **small-molecule oral standard path**. Real customer programs span modalities and contexts that the current checker stack does not see. This doc enumerates the gaps and prioritizes them by market impact and engineering cost.

---

## Coverage matrix

| Dimension | Covered (v6) | Partial | Not covered |
|---|---|---|---|
| **Modality** | small molecule | — | biologics, gene therapy, cell therapy, mRNA, peptides, ADC, combination |
| **Indication class** | non-oncology | oncology (excluded from MRSD task) | — |
| **Population** | adult healthy, adult patient, WOCBP | — | pediatric, geriatric, pregnant |
| **Submission type** | initial IND §2.6.1–2.6.6 | — | IND amendment, pre-IND briefing, BLA, 505(b)(2) bridging, compassionate use |
| **Region** | FDA + EMA citations | NMPA via region_adaptation | full NMPA prose, PMDA, TGA, Swissmedic, ANVISA |
| **Sponsor type** | industry implicit | — | academic, virtual sponsor |
| **Data source** | structured pipeline outputs | PDF single-study GLP reports | multi-study NDA reviews, Benchling exports, sponsor data warehouse APIs |

---

## Tier 1 — highest-leverage gaps (first 10 customers)

These are the three modalities/scenarios most likely to be in the first paying customer's pipeline.

### T1A. Biologics (ICH S6(R1))

**Why it matters:** Any large pharma running ADMET also runs antibody programs. Biologics are >50% of new IND submissions by some counts.

**Key technical differences vs M3(R2):**

| Concept | M3(R2) small molecule | S6(R1) biologic |
|---|---|---|
| FIH dose derivation | NOAEL / BSA → HED ÷ 10 = MRSD | **MABEL** from receptor occupancy or EC50, with safety factor |
| Species count | 2 (rodent + non-rodent) typically | **1 may suffice** if pharmacologically relevant |
| Genotox battery | required (Ames + mammalian + in vivo) | **not typically required** |
| Standard carcinogenicity | required for chronic Phase III | **rarely required**; weight-of-evidence |
| Safety pharm core battery | separate ICH S7A studies | **incorporated into repeat-dose tox** |
| New assessment | — | **immunogenicity / ADA monitoring** required |

**New checker:** `biologics_mabel.py` — verifies that MABEL is correctly derived from receptor occupancy (10-20% RO target) or in vitro EC20/EC50 with a documented safety factor.

**New SFT task:** task10 MABEL computation (parametric over target type, RO threshold, EC50 value, safety factor).

**Existing module changes:**
- `phase_gating.py` needs a `modality` parameter that switches to S6(R1) requirements
- `structural_validator.py` §2.6.6 subsection structure is largely the same; immunogenicity gets a new subsection inside "Other Toxicity Studies"

**Effort:** ~1 week (new checker + generator + phase_gating modality branch + 500 SFT examples)

### T1B. Oncology positive path (ICH S9)

**Why it matters:** Oncology is a large fraction of clinical-stage assets. Today the MRSD task **excludes** oncology, which means the model silently fails on the most common indication category.

**Key technical differences:**

| Concept | Standard M3(R2) | ICH S9 oncology |
|---|---|---|
| FIH dose derivation | NOAEL / BSA → ÷10 | **STD10** (severely toxic dose in 10% of rodents) **÷ 10**, OR **HNSTD** (highest non-severely-toxic dose) **÷ 6** for non-rodent |
| Genotox | full battery before Phase I | **Ames only** before Phase I; full battery before marketing |
| Reproductive tox | per Phase | **only embryo-fetal**, often deferred to Phase III |
| Safety pharm | separate ICH S7A | **integrated into repeat-dose** |

**New checker:** `oncology_std10.py` — verifies STD10/HNSTD arithmetic + 1/10 (rodent) or 1/6 (non-rodent) rule.

**New SFT task:** task11 STD10/HNSTD computation.

**Existing module changes:**
- `mrsd_verifier.py` could be folded together with `oncology_std10.py` under a single `fih_dose_verifier.py` with a modality switch
- `phase_gating.py` modality branch already proposed for biologics — extend for oncology

**Effort:** ~1 week

### T1C. Real PDF ingestion fully fleshed out

**Why it matters:** Every customer has GLP final reports they want to upload as the source of truth. The current ingester (`study_report_ingester.py`) rejects multi-study FDA NDA reviews — correct behavior — but the positive path for single-study GLP final reports is under-tested.

**Specific gaps:**
1. Customer-uploaded study PDFs are often **scanned + OCR'd**, not native text. Need OCR fallback (`pytesseract` or AWS Textract).
2. Tabular data in PDFs (dose-response tables, individual animal data) needs structured extraction.
3. Benchling exports as CSV + metadata JSON — separate parser.
4. Sponsor data warehouse APIs (REST + auth) — varies per customer; need a pluggable interface.

**Existing module changes:**
- `study_report_ingester.py` — add OCR fallback path, broaden allowed report types, add Benchling CSV reader

**Effort:** ~2 weeks (largest of the three because OCR / table extraction varies per source)

---

## Tier 2 — for the first 50 customers (~3 months out)

### T2A. CTA (EU) + simultaneous multi-region submission

CTA is structurally very similar to IND but Module 2.4 (nonclinical overview) prose conventions differ; some EU-specific guidelines (CHMP/SWP, EMEA/CHMP/QWP) need explicit citation rather than ICH equivalents.

**Effort:** ~3 days. New checker for EU-specific citation patterns + region-stratified prose generators.

### T2B. Pediatric (ICH E11(R1), FDA PREA)

Juvenile animal study requirements depend heavily on indication + drug class. Different starting-dose framework than adult MRSD.

**Effort:** ~1 week.

### T2C. IND amendments (annual reports, protocol amendments)

Different document shape. Annual report has 7 prescribed sections; protocol amendment is just a delta document.

**Effort:** ~1 week.

### T2D. Combination products (ADCs, drug-device)

ADC = small-molecule payload + monoclonal antibody. Both ICH M3(R2) and S6(R1) apply. Each module of the deliverable has to pull from both stacks.

**Effort:** ~1 week assuming T1A (biologics) is done.

---

## Tier 3 — long tail

### T3A. Gene therapy / cell therapy (FDA CTGT)

Biodistribution, persistence, germline integration assessment, vector shedding. Entirely new framework — not a tweak to existing checkers.

**Effort:** ~3-4 weeks. Bigger than any single Tier 1 item.

### T3B. mRNA / LNP

FDA mRNA platform guidance is recent and not yet stable. Defer until guidance stabilizes.

### T3C. Compassionate use / single-patient IND

Different document shape — abbreviated. Custom flow per case.

### T3D. Foreign-GLP recognition statements

Boilerplate text per region. Low effort, low priority until a customer asks.

---

## Out-of-scope (for now)

- BLA, NDA — these are later-stage submissions (post Phase III). Different time horizon.
- Special Protocol Assessment, Orphan Drug Designation — different documents.
- Diagnostic / companion diagnostic — not in BioMate's wheelhouse.

---

## Recommended order

If sequenced for fastest path to product-market fit:

```
Week 1-2:  T1A biologics  (parallel with first-customer onboarding)
Week 2-3:  T1B oncology   (parallel with T1A)
Week 3-5:  T1C PDF ingestion enhancement
Week 5-6:  T2A CTA  (only if a customer signals EU-first submission)
Later:     T2B pediatric, T2C amendments, T2D combination
Long tail: T3A-D as customer demand surfaces
```

**Key principle:** every gap-filling task follows the same checker-first pattern from `docs/20260510_DOCUMENT_GENERATION_APPROACH.md`. New modality = new checker + new SFT generator + new test split. Output passes the existing structural validator with a modality-aware required-subsection list.

---

## How this connects to the customer feedback loop

The feedback infrastructure from Appendix B of `docs/20260504_IND_PRODUCT_UI_REQUIREMENTS.md` already covers the discovery path:

- A customer submits a biologic and the model produces small-molecule prose
- Customer edits paragraphs → captured as DPO pairs
- Customer dismisses "missing hERG" finding (irrelevant for biologic) → captured as rule refinement
- Customer suggests "ICH S6(R1) §3" citation → captured as corpus extension

**The first paying customer tells us which Tier 1 item to fill first.** The feedback loop turns gap signals into prioritized work without us guessing.
