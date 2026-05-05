# ICH Guideline Reference for IND Module 2.6

**Date:** 2026-05-05  
**Purpose:** Reference guide for all ICH and FDA/EMA guidance documents used in BioMate regulatory LLM training. Explains what each guideline is, which §2.6 section it governs, and its training data status.

---

## Quick Map: §2.6 Section → Governing Guidelines

| CTD Section | Content | Primary Guidelines | Status |
|-------------|---------|-------------------|--------|
| **§2.6.1** Nonclinical Pharmacology Overview | PD mechanism, off-target pharmacology | M3(R2), S7A, M4S(R2) | ✓ collected |
| **§2.6.2** Pharmacokinetics Overview | Absorption, distribution, metabolism, excretion | M3(R2), FDA PBPK 2018, EMA PBPK | ✓ collected |
| **§2.6.3.1** General Toxicology | Repeat-dose studies, NOAEL, target organs | M3(R2) | ✓ collected |
| **§2.6.3.2** Reproductive/Developmental Tox | Fertility, embryo-fetal, pre/postnatal | **S5(R3)** | ✗ S5(R3) unavailable |
| **§2.6.3.3** Genotoxicity | Ames, micronucleus, chromosomal aberration | S2(R1) | ✓ collected |
| **§2.6.3.4** Carcinogenicity | 2-year bioassay, transgenic models, dose selection | **S1A, S1B, S1C(R2)** | ✓ collected |
| **§2.6.3.5** Local Tolerance / Special | Route-specific tolerance, impurities | M7(R2), M3(R2) | M7(R2) unavailable |
| **§2.6.3.6** Immunotoxicity | TDAR assay, immunosuppression, hypersensitivity | **S8** | ✓ collected |
| **§2.6.3.7** Cardiac Safety (hERG) | Ion channel assays, in vivo QT | S7B, **S7B(R1)** | S7B ✓; R1 unavailable |
| **§2.6.4** Pharmacology Tabulated Summary | Study-by-study table | M4S(R2) | ✓ format guide |
| **§2.6.5** Pharmacokinetics Tabulated Summary | PK parameter tables by species | M4S(R2) | ✓ format guide |
| **§2.6.6** Toxicology Tabulated Summary | Tox study tables by type | M4S(R2) | ✓ format guide |
| **Multi-region additions** | Ethnic bridging, Japanese/Chinese requirements | E5(R1), E7 | ✓ collected |
| **Biologics-specific §2.6** | Species selection, immunogenicity, homology | **S6(R1)** | ✗ unavailable |

---

## Guidelines in Detail

### ICH M4S(R2) — The CTD Template ★★★★★

**What it is:** Defines the *structure* of Module 2.6 itself — what sections exist, their order, what content belongs where. It is the blueprint that every CTD nonclinical summary follows.

**Why it matters for training:** Every training example must ultimately conform to this structure. The section numbering (§2.6.1 through §2.6.6), the prose style guidelines, and the required content per subsection are all specified here.

**Status:** ✓ Collected. 80 sections, avg 57 words/section.

**Key content:** Section-by-section description of what goes in §2.6.1 (pharmacology overview), §2.6.2 (pharmacokinetics overview), §2.6.3 (toxicology overview), §2.6.4–6 (tabulated summaries). Also defines the written summary vs tabulated summary distinction.

---

### ICH M3(R2) — Master Phase-Gating Guideline ★★★★★

**What it is:** The single most important guideline for IND submissions. Defines exactly which nonclinical studies must be completed before starting Phase I, IIa, IIb, and Phase III. Every IND nonclinical package justification traces back to M3(R2).

**Why it matters for training:** §2.6.1 overview narratives almost always include language like "in accordance with ICH M3(R2), the following studies support initiation of Phase I" or "the nonclinical package described herein is consistent with ICH M3(R2) requirements for a Phase I single-ascending-dose study." The model must learn this framing.

**Status:** ✓ Collected. 80 sections, avg 70 words.

**Key content:** Study requirements table by clinical phase (Phase I/II/III), species requirements, study duration, route of administration requirements, exemptions for oncology drugs, and cross-references to other ICH guidelines (S7A for safety pharm, S2 for geno, S5 for repro).

---

### ICH S7A — Safety Pharmacology Core Battery ★★★★★

**What it is:** Defines the mandatory "core battery" of safety pharmacology studies that must be completed before first-in-human dosing. The core battery is:
- **CNS:** Irwin test (functional observational battery in rodents)
- **Cardiovascular:** hERG in vitro + in vivo QT/QTc in telemetered dog/primate
- **Respiratory:** in vivo respiratory function assessment

**Why it matters for §2.6.1:** §2.6.1 contains the safety pharmacology narrative. The standard phrasing follows S7A: "Core battery safety pharmacology studies per ICH S7A were conducted. CNS assessment via functional observational battery in Sprague-Dawley rats at doses of X/Y/Z mg/kg showed no adverse effects. Cardiovascular assessment via in vitro hERG and telemetered cardiovascular in [species] demonstrated [findings]."

**Status:** ✓ Collected. 74 sections, avg 72 words.

**Key content:** Core battery definition, supplemental studies (renal/urinary, GI, autonomic), study design requirements, timing relative to FIH, species selection rationale.

---

### ICH S7B + S7B(R1) — hERG and Cardiac Safety ★★★★★

**What it is:** S7B (2005) focuses specifically on cardiac ion channel testing (hERG patch clamp) and integrated risk assessment for QT prolongation. S7B(R1) (November 2024) is the major update that formally recognizes and validates in silico cardiac safety screening.

**S7B(R1) key change:** In silico hERG prediction is now formally accepted as a pre-IND screening tool per S7B(R1) Step 4. The guidance specifies acceptable model performance metrics and when in silico can substitute for earlier (non-GLP) in vitro testing. This is directly relevant to BioMate's ADMET pipeline.

**Why it matters for training:** §2.6.3.7 cardiac safety narrative must cite S7B. The specific Redfern (2003) IC50 category thresholds (≤0.1, 0.1-1, 1-10, >10 µM) and the distinction between in silico screen vs GLP in vitro vs in vivo integration must be correct.

**Status:** ✓ S7B (2005) collected (79 sections). S7B(R1) (2024) — URL not yet available on database.ich.org. Manual download needed from ich.org.

---

### ICH S1A, S1B, S1C(R2) — Carcinogenicity ★★★★☆

**What they are:**
- **S1A** — Decides *when* carcinogenicity studies are needed. Key criteria: intended treatment duration > 6 months, or indication in patients who may take it chronically, or structural alerts for genotoxic carcinogenicity. Also defines exemptions (oncology drugs, drugs used acutely).
- **S1B** — Defines *how* to conduct carcinogenicity studies: 2-year rat bioassay + either 2-year mouse bioassay OR a 6-month transgenic mouse (rasH2 or p53+/-). Species, dose levels, histopathology endpoints.
- **S1C(R2)** — How to select doses for carcinogenicity studies: maximum tolerated dose (MTD), 25× human AUC exposure cap, or maximum feasible dose. The AUC cap is a key regulatory threshold.

**Why it matters for training:** §2.6.3.4 carcinogenicity section is required for most NDAs and many INDs (in justification form). Standard phrasing: "Per ICH S1A, carcinogenicity studies are required given the intended chronic treatment duration. Lifetime rat and 6-month rasH2 transgenic mouse bioassays were conducted per ICH S1B. Doses were selected per ICH S1C(R2) with the high dose set at 25× the human AUC exposure." These were **completely absent** from the v1 training dataset.

**Status:** ✓ S1A (36 sections), S1B (57 sections), S1C(R2) (73 sections) — all collected.

---

### ICH S2(R1) — Genotoxicity ★★★★★

**What it is:** The standard test battery for genetic toxicology:
1. Bacterial reverse mutation (Ames test: TA98, TA100, TA102, TA1535, TA1537 strains)
2. Chromosomal aberration / micronucleus in mammalian cells in vitro
3. In vivo micronucleus or comet assay (if in vitro positive)

S2(R1) also defines the ICH standard battery that must be completed before Phase I.

**Why it matters for training:** §2.6.3.3 genotoxicity section is one of the most standardized sections — the text follows a rigid pattern: "Compound X was evaluated for genotoxic potential in a standard ICH S2(R1) test battery. In the bacterial reverse mutation assay (Ames test, strains TA98, TA100, TA102, TA1535, TA1537 ± S9 activation), no mutagenic activity was observed. In vitro chromosomal aberration testing in Chinese hamster ovary cells was negative. No in vivo genotoxicity testing was required."

**Status:** ✓ Collected. 80 sections, avg 78 words.

---

### ICH S5(R3) — Reproductive and Developmental Toxicology ★★★★☆

**What it is:** Governs three study types:
1. **Fertility and early embryonic development (FEED)** — effects on gonads, mating, fertilization, early embryogenesis
2. **Embryo-fetal development (EFD)** — teratogenicity, NOAEL for maternal and fetal effects
3. **Pre- and postnatal development (PPND)** — lactation, pup development, weaning

These studies govern §2.6.3.2. The NOAEL values from these studies are used to calculate safety margins for reproductive risk disclosure in the IND.

**Why it matters for training:** §2.6.3.2 reproductive toxicology is a major section present in virtually every IND, but our v1 training data has **zero examples of this section type**. The model has no exposure to standard phrasing like "embryo-fetal development studies in rat and rabbit showed no evidence of teratogenicity at doses up to X mg/kg (Y× human AUC exposure at the MRHD)."

**Status:** ✗ S5(R3) URL not available on database.ich.org. Manual download from ich.org required. This is the **highest-priority manual collection task**.

---

### ICH S6(R1) — Biologics and Biotechnology Products ★★★★☆

**What it is:** Governs preclinical safety evaluation for biotechnology-derived products: monoclonal antibodies, recombinant proteins, gene therapies, cell therapies, antisense oligonucleotides, ADCs.

Key differences from small molecule guidance:
- **Species selection**: must use a pharmacologically relevant species (where the drug binds and is active); rodents are often not appropriate for mAbs
- **Immunogenicity**: anti-drug antibodies (ADA) can confound toxicity — must be measured
- **Homologous protein**: may need to use a surrogate molecule (mouse-specific antibody) for rodent toxicity studies

**Why it matters for training:** ~40% of modern IND filings are for biologics. The nonclinical overview for a mAb looks fundamentally different from a small molecule: no genotoxicity required (per S6(R1)), species justification section required, immunogenicity discussion required. The model currently has no examples of biologic-style nonclinical summaries.

**Status:** ✗ S6(R1) URL not available on database.ich.org. Manual download from ich.org required. **High priority for completeness**.

---

### ICH S8 — Immunotoxicity ★★★☆☆

**What it is:** Defines when dedicated immunotoxicity studies are required beyond what's captured in standard repeat-dose tox studies. Key test: T-cell Dependent Antibody Response (TDAR) assay (KLH or SRBCs immunization challenge). Other tests: NK cell activity, macrophage function, T cell subsets.

S8 triggers: if the drug targets immune cell subsets, if repeat-dose studies show effects in lymphoid organs (spleen, thymus weights, histopathology), if the drug's pharmacology suggests immunomodulation.

**Why it matters for training:** §2.6.3.6 (or integrated into §2.6.3.5) contains an immunotoxicity section when S8 studies are conducted. Many modern INDs require this discussion for immune-modulating drugs (oncology, autoimmune, biologics). Standard phrasing: "Per ICH S8, the potential for immunotoxicity was assessed. The compound's mechanism of action (PD5 inhibition) does not suggest immunomodulatory activity. Standard repeat-dose toxicity studies did not reveal any lymphoid organ weight changes or histopathological findings suggesting immunotoxicity. Dedicated immunotoxicity studies were therefore not performed per ICH S8."

**Status:** ✓ Collected. 80 sections, avg 68 words.

---

### ICH S9 — Anticancer Pharmaceuticals ★★★☆☆

**What it is:** Modified nonclinical package for oncology drugs. Key differences:
- **Genotoxicity**: not required before Phase I for oncology
- **Carcinogenicity**: typically exempt (per S1A, lifetime studies not required if drug is genotoxic)
- **Reproductive toxicity**: may be deferred to Phase III
- **Safety pharmacology**: abbreviated for cytotoxic drugs
- The **S9 exemption table** (Appendix) is frequently cited in oncology INDs

**Why it matters for training:** Oncology INDs are a large proportion of IND filings (FDA ~35% of new IND submissions). The nonclinical narrative for an oncology drug follows a distinctive pattern: "ICH S9 provides the regulatory framework for this oncology IND. In accordance with ICH S9, genotoxicity studies are not required prior to Phase I initiation..."

**Status:** ✓ Collected. 68 sections, avg 73 words.

---

### FDA PBPK Guidance (2018) ★★★★★

**What it is:** FDA's own guidance document on "Physiologically Based Pharmacokinetic Analyses — Format and Content." This is separate from the EMA PBPK guideline and specifies *what FDA reviewers expect* in PBPK submissions (as opposed to EMA's different expectations).

**Key FDA-specific requirements:**
- **Table 2**: Model input parameters with literature sources and justification
- **Table 3**: Sensitivity analysis results for key uncertain parameters
- **Forest plots**: Simulated DDI predictions vs observed (FDA requires this visual)
- **Model verification** vs **Model validation** distinction: FDA explicitly defines these terms differently from EMA

**Why it matters for training:** The §2.6.2 PBPK section for an FDA submission must follow FDA format, not EMA format. Our v1 training data had EMA PBPK guidance (EMA_PBPK) but no FDA PBPK guidance — meaning the model had no exposure to FDA's specific format requirements. This was a significant gap since 85% of our section_generation data is FDA-targeted.

**Status:** ✓ Collected (89 KB PDF, 44 sections, avg 69 words). Required browser User-Agent headers to download.

---

### EMA PBPK Guideline (EMA/CHMP/EWP/37498/2011 Rev1) ★★★★★

**What it is:** EMA's guideline on reporting PBPK modeling in EMA submissions. Defines the famous "67% within-2-fold criterion" for model qualification.

**Key requirements:**
- **Qualification dataset**: predict Cmax and AUC for ≥30 reference compounds with known clinical PK
- **67% criterion**: ≥67% of predictions must fall within 2-fold of observed values for both Cmax and AUC
- **AFE/AAFE**: average fold error and absolute average fold error must be reported
- **Model assumptions**: explicit statement of key model assumptions and their uncertainty

**Status:** ✓ Collected. 80 sections, avg 86 words.

---

### ICH E5(R1) — Ethnic Factors in Clinical Data Acceptability ★★★☆☆

**What it is:** Governs when clinical data from one region (e.g., US) can be used to support approval in another region (Japan, China). Defines "ethnic sensitivity" (does PK/PD differ between populations?) and the "bridging study" concept.

**Why it matters for NMPA/PMDA submissions:** §2.6.2 for NMPA or PMDA submissions must include an ethnic bridging assessment. Standard language: "An ethnic sensitivity analysis was conducted per ICH E5. CYP2C19 poor metabolizer prevalence in the Japanese population (18–23%) is higher than in the European population (2–5%), potentially resulting in higher exposure in Japanese subjects. A pharmacokinetic bridging study in Japanese subjects is planned to confirm dose selection."

**Status:** ✓ Collected. 80 sections, avg 75 words.

---

## Gaps Requiring Manual Collection

### S5(R3) — Highest Priority

S5(R3) (Step 4, February 2020) governs §2.6.3.2 reproductive toxicology. The PDF is available on ich.org but the automated download fails on database.ich.org.

**Manual download:** Go to `https://www.ich.org/page/safety-guidelines` → S5 → Step 4 document → download PDF → place at `data/regulatory_training/ich_guidelines/raw/ich/ICH_S5_R3.pdf`

### S6(R1) — High Priority for Biologics Coverage

S6(R1) governs §2.6 for mAbs, gene therapies, ADCs. ~40% of modern INDs.

**Manual download:** Go to `https://www.ich.org/page/safety-guidelines` → S6 → Step 4 document.

### S7B(R1) — Moderate Priority

S7B(R1) (November 2024) formalizes in silico hERG. The original S7B (2005) covers 95% of the same content.

### M7(R2) — Low Priority for §2.6

M7(R2) governs mutagenic impurities (genotoxic impurity thresholds). Relevant mainly for §2.6.3.3 when the drug has known impurities. Lower priority than reproductive/biological safety gaps.

---

## Dataset Impact Summary

| Guideline Added | §2.6 Section Covered | v1 Gap Filled? |
|----------------|---------------------|----------------|
| ICH_S1A | §2.6.3.4 (when carcinogenicity needed) | ✓ Yes |
| ICH_S1B | §2.6.3.4 (how to conduct carcinogenicity) | ✓ Yes |
| ICH_S1C_R2 | §2.6.3.4 (dose selection for carcinogenicity) | ✓ Yes |
| ICH_S7B | §2.6.3.7 (cardiac/hERG) | ✓ Partial (R1 missing) |
| ICH_S8 | §2.6.3.6 (immunotoxicity) | ✓ Yes |
| ICH_S9 | §2.6.3 oncology INDs | ✓ Yes |
| FDA_PBPK_2018 | §2.6.2 (FDA PBPK format) | ✓ Yes |
| EMA_PBPK | §2.6.2 (EMA PBPK criteria) | ✓ Yes |
| ICH_S5(R3) | §2.6.3.2 (reproductive tox) | ✗ Still missing |
| ICH_S6(R1) | §2.6 biologics | ✗ Still missing |

**ICH guideline corpus: 429 examples (v1) → 946 examples (v2), +120% increase**

The most important remaining gap is **§2.6.3.2 reproductive toxicology** (S5(R3)) — present in virtually every IND but still unrepresented in the training data.
