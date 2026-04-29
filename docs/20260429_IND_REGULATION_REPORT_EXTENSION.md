# IND Regulation Report — §2.6.2 Pharmacokinetics + §2.6.3 Toxicology

**Date:** 2026-04-29  
**Branch:** integration/next-phase  
**Commit:** aa4030927

---

## What Was Built

Extended the BioMate IND section assembler from §2.6.1 (Pharmacology) to cover the complete ICH M4 CTD
nonclinical written summaries required for IND submission.

### New sections

**§2.6.2 Nonclinical Overview: Pharmacokinetics** (`_section_pk_overview()`)

Sub-sections:
- 2.6.2.1 Methods of Analysis — PBPK platform description
- 2.6.2.2 Absorption — in silico solubility/permeability, Lipinski Ro5
- 2.6.2.3 Distribution — Rodgers & Rowland tissue distribution
- 2.6.2.4 Metabolism — CYP pathway modelling, well-stirred liver model
- 2.6.2.5 Excretion — renal filtration, biliary excretion pathway
- 2.6.2.6 Pharmacokinetic Drug Interactions — CYP inhibition summary
- 2.6.2.7 Other PK Studies — P-gp/transporter caveat

LLM narrative calls: `pk_overview` (PBPK qualification interpretation), `pk_adme` (ADME profile)

**§2.6.3 Nonclinical Overview: Toxicology** (`_section_toxicology_overview()`)

Sub-sections:
- 2.6.3.1 Single-Dose Toxicity — in vivo gap acknowledgement
- 2.6.3.2 Repeat-Dose Toxicity — in vivo gap acknowledgement
- 2.6.3.3 Genotoxicity — Ames prediction + ICH S2(R1) note
- 2.6.3.4 Carcinogenicity — structural alert evaluation
- 2.6.3.5 Reproductive/Developmental Toxicity — Phase I scope note
- 2.6.3.6 Local Tolerance — route-dependent note
- 2.6.3.7 Safety Pharmacology — hERG/cardiac (ICH S7B)

LLM narrative calls: `tox_overview`, `tox_genotox`, `tox_cardiac`

### New data loader

`_load_safety_profile(campaign_id)` — queries `campaign_assay_results` and aggregates:
- Per-compound assay dict (hERG IC50, DILI flag, Ames flag, ClinTox, solubility, permeability)
- Campaign-level flag rates (herg_flagged, dili_flagged, ames_flagged, clintox_flagged)
- Lead compound (rank 1) safety endpoints

---

## Document Size

| Version | Chars | Sections |
|---------|-------|----------|
| §2.6.1 only (before) | ~10,600 | 6 sub-sections |
| §2.6.1–§2.6.3 (after) | ~19,200 | 8 sections |

---

## API Changes

`POST /{campaign_id}/ind-assembly` response now includes `sections` array with 8 entries:
```json
["2.6.1.1", "2.6.1.2", "2.6.1.3", "2.6.1.4", "2.6.1.5", "2.6.1.6", "2.6.2", "2.6.3"]
```

Title page updated: "CTD Module 2.6 — Nonclinical Written Summaries"  
Sections header: "§2.6.1 Pharmacology · §2.6.2 Pharmacokinetics · §2.6.3 Toxicology"

---

## Frontend Changes

`drug-discovery-ind-assembly.tsx`:
- `SECTION_TITLES` extended with `"2.6.2"` and `"2.6.3"` entries
- Header badges updated: "ICH M4 — CTD §2.6.1–§2.6.3" + "Pharmacology · Pharmacokinetics · Toxicology"
- Contents preview badge: "8 sections · §2.6.1–§2.6.3"

`drug-discovery-cro-demo.tsx`:
- Tour tip updated to mention all three ICH sections
- Checklist updated to reference §2.6.1–§2.6.3

---

## Tests Updated

`drug-discovery-cro-compliance.e2e.ts` (DD-CRO-5):
- `expectedSections` extended to include `'2.6.2'` and `'2.6.3'`
- New assertions: PK section contains "Pharmacokinetics|PBPK|absorption|distribution|metabolism"
- New assertions: Tox section contains "Toxicology|hERG|genotoxicity|Ames|cardiac"
- All assertions: **PASS** (19,239 chars, pandoc: true, DOCX: true)

`demo-11-ind-assembly.demo.ts`:
- Updated section count assertion from 6 → 8
- Added quality checks for §2.6.2 and §2.6.3 content keywords

---

## ICH M4 Coverage After This Session

| CTD Section | Status |
|------------|--------|
| §2.6.1 Nonclinical Overview: Pharmacology | ✅ Complete (6 sub-sections + LLM narrative) |
| §2.6.2 Nonclinical Overview: Pharmacokinetics | ✅ Complete (7 sub-sections + LLM narrative) |
| §2.6.3 Nonclinical Overview: Toxicology | ✅ Complete (7 sub-sections + LLM narrative) |
| §2.6.4 Pharmacology Written Summary | ⬜ Not yet (requires tabulated study data) |
| §2.6.5 Pharmacokinetics Written Summary | ⬜ Not yet (requires in vitro DMPK data) |
| §2.6.6 Toxicology Written Summary | ⬜ Not yet (requires GLP tox study data) |
| §2.6.7 Tabulated Summaries | ⬜ Not yet (requires study-by-study tables) |

Sections §2.6.4–§2.6.7 require actual in vitro/in vivo experimental data that is not available
from in silico computation alone. These are not suitable for purely computational generation
and should be added when BioMate has integration points with LIMS/ELN for wet lab data.
