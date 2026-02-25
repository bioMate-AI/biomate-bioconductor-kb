# Proteomics Paper Plan: QC Governance for Drug Discovery LC-MS/MS
**Date:** 2026-02-25 11:38
**Target journal:** Molecular & Cellular Proteomics (IF ~7, home of mzQC/HUPO-PSI) or Journal of Proteome Research (IF ~5)
**Aspirational:** Nature Methods (if benchmark data is strong enough)
**Status:** Workflows exist (52 pharmacology modules, LC-MS agent); QC governance layer not yet built
**Folder:** `research_repos/biomate_proteomics_paper/`

---

## Our Contribution and Innovation — Stated Clearly

### What exists today (the problem)

LC-MS/MS proteomics for drug discovery suffers from three silent failure modes that no current platform addresses:

**Failure 1: No governed QC standard at the pipeline level**
Tools like MaxQuant, DIA-NN, Spectronaut produce QC metrics (FDR, CV, missed cleavages). MultiQC can aggregate them. But no platform:
- Distinguishes GOLD evidence thresholds (PSM FDR 1% — universally agreed, Elias & Gygi 2007) from BRONZE heuristics (oxidized Met fraction < 30% — lab practice)
- Enforces decision points: the pipeline runs to completion regardless of FDR failure
- Produces an audit trail suitable for FDA 21 CFR Part 11

**Failure 2: Protocol blindness**
Phosphoproteomics, plasma biomarker discovery, and affinity proteomics (pulldown) have categorically different QC requirements:
- Phosphoproteomics: lower total PSM count is acceptable; higher localization score required (> 0.75)
- Plasma proteomics: CV < 15% (tighter than cell lysate), lower library coverage acceptable after depletion
- Pulldown/chemoproteomics: enrichment ratio is the key metric, not protein FDR alone

No existing pipeline distinguishes these. A lab running phosphoproteomics through standard DDA thresholds will flag valid experiments as failed and miss genuine quality problems specific to enrichment efficiency.

**Failure 3: No QC at the compound input level**
15% of ChEMBL compounds have SMILES errors that bias ADMET predictions (Whitehead et al. 2022, J Chem Inf Model). No platform validates compound structure quality before running expensive docking/ADMET computations.

### What BioMate adds (the innovation)

**Innovation 1: First platform to implement mzQC (HUPO-PSI community standard) with evidence-graded governance**

The HUPO-PSI published the mzQC format (Bittremieux et al. 2023, MCP) — a community standard for proteomics QC metrics with 100+ controlled vocabulary terms. BioMate is the **first execution platform to implement mzQC metrics with GOLD/SILVER/BRONZE evidence tiers**, mapping community evidence quality to threshold overridability.

This is analogous to what BioMate does for sequencing QC (Paper 1): the innovation is not the metrics themselves but the governed, citation-backed, overridable-by-layer threshold system applied to them.

**Innovation 2: Protocol-aware named profiles for proteomics experiment types**

Three profiles covering the dominant drug discovery use cases:
- `proteomics_standard` — standard DDA, label-free quantification, cell lysate
- `proteomics_phospho` — phosphoenrichment (TiO2/IMAC); relaxed PSM count gate, tightened localization requirement; phosphosite-specific CV gating
- `proteomics_plasma_biomarker` — depleted plasma; stricter CV (< 15%); SIL internal standard required; lower library coverage acceptable after abundant protein depletion

**Innovation 3: Drug discovery workflow integration — QC gates at the decision points that matter**

BioMate gates at the three drug discovery decision points where silent failures are most costly:
1. **Target ID gate (affinity proteomics):** enrichment ratio > 3× input (SILVER); protein FDR < 1% (GOLD); prey/bait specificity score
2. **MOA gate (phosphoproteomics):** phosphopeptide enrichment efficiency > 70% (SILVER); localization score > 0.75 (SILVER); site-level quantification CV < 20% (SILVER)
3. **Biomarker gate (plasma proteomics):** QC sample CV < 15% (SILVER); SIL standard response within 20% of expected (GOLD); missing value fraction < 30% (SILVER)

A failed target ID gate means the pulldown did not work — BioMate surfaces this before the lab spends 2 weeks following up false-positive interactors. No existing platform makes this drug-discovery-specific distinction.

**Innovation 4: SMILES structure QC gate — the first compound quality checkpoint in an automated pipeline**

Before any ADMET prediction, docking, or binding affinity calculation, BioMate validates:
- SMILES parseable (hard gate — RDKit sanitize)
- Salt stripped (auto-correct with audit log)
- Undefined stereocenters flagged (advisory)
- Molecular weight in relevant space (BRONZE, user-configurable)

This prevents the 15% ChEMBL error rate from propagating silently into ADMET results.

---

## QC Governance Layer: Full Specification

### Tier 1: MaxQuant DDA Proteomics

**Parseable outputs:** `summary.txt`, `msms.txt`, `peptides.txt`, `proteinGroups.txt`, `Phospho(STY)Sites.txt`

| Metric | Evidence Level | Threshold | Source |
|---|---|---|---|
| PSM FDR | **GOLD** | < 1% | Elias & Gygi 2007, Nature Methods (8,000+ citations) |
| Protein FDR | **GOLD** | < 1% | Same |
| Mass accuracy (median) | **GOLD** | < 5 ppm (Orbitrap); < 20 ppm (ion trap) | Instrument specification |
| Missed cleavage rate | **SILVER** | < 20% | nf-core/proteomics; EuBIC 2018 community standards |
| Phosphosite localization score | **SILVER** | > 0.75 | Beausoleil et al. 2006, Nature Biotechnology |
| Label-free quant CV (technical) | **SILVER** | < 20% | EuBIC 2018 proteomics QC guidelines |
| Sequence coverage (median) | **SILVER** | > 20% for cell lysate | Community practice |
| Oxidized Met fraction | **BRONZE** | < 30% | Sample handling heuristic |
| RT drift across runs | **BRONZE** | < 2 min | PTXQC community heuristic (Bielow et al. 2016, JPR) |

**Named profiles:**
- `proteomics_standard` — all defaults above
- `proteomics_phospho` — FDR same; localization > 0.75 (enforced not advisory); CV < 25% acceptable (phospho enrichment adds variance); missed cleavage < 30% acceptable (phosphopeptides resist digestion)
- `proteomics_plasma_biomarker` — FDR same; CV < 15% (tighter); RT drift < 1 min (tighter); missing value fraction < 30% (SILVER)

### Tier 2: DIA-NN / Spectronaut DIA Proteomics

**Parseable outputs:** `report.tsv`, `report.stats.tsv` (DIA-NN); Spectronaut `_Report.xls`

| Metric | Evidence Level | Threshold | Source |
|---|---|---|---|
| Precursor FDR | **GOLD** | < 1% | Universal; DIA-NN documentation |
| Protein FDR | **GOLD** | < 1% | Universal |
| Peptide CV (across replicates) | **SILVER** | < 15% | DIA community standards; Stenbratt et al. 2021 |
| Library coverage | **SILVER** | > 60% of spectral library detected | Spectronaut best practices |
| MS1 mass accuracy | **SILVER** | < 5 ppm | Instrument standard |
| Missing values fraction | **BRONZE** | < 30% | Community heuristic |

### Tier 3: SMILES / Compound Structure QC

| Check | Evidence Level | Action |
|---|---|---|
| SMILES parseable (RDKit sanitize) | **GOLD** | Hard gate — reject before ADMET/docking |
| Salt stripped | **SILVER** | Auto-strip + audit log |
| Stereochemistry defined | **SILVER** | Advisory if undefined stereocenters > 0 |
| MW in drug-like space | **BRONZE** | Advisory if MW > 900 Da |
| Tautomer standardized | **BRONZE** | Apply MolVS; log transformation |

---

## Benchmark Design

### Benchmark 1: Standard cell lysate DDA (true negative)
- **Dataset:** ProteomeXchange PXD000001 (EBI PRIDE, Nagaraj et al. 2011 MCP — the "deep proteome" paper, 10,000+ proteins from HeLa)
- **Role:** Show BioMate passes all gates on excellent data; no false-positive halts
- **Expected:** All GOLD/SILVER gates pass; minor BRONZE flags for typical oxidation rates

### Benchmark 2: Phosphoproteomics (profile validation)
- **Dataset:** PXD003452 (Sharma et al. 2014 Nature Methods — the deep phosphoproteome of mouse brain, 50,000+ phosphosites)
- **Role:** Default `proteomics_standard` profile flags low PSM counts as warning; `proteomics_phospho` profile correctly passes
- **Expected:** Protocol-mismatch causes false positive; phospho profile eliminates it

### Benchmark 3: Plasma biomarker (protocol-awareness)
- **Dataset:** PXD010154 (Geyer et al. 2017 Cell Systems — plasma proteome profiling with DIA, the landmark plasma proteomics paper)
- **Role:** Show `proteomics_plasma_biomarker` profile applies appropriate CV and missing value thresholds for depleted plasma
- **Expected:** Standard profile may over-flag; plasma profile correctly calibrated

### Benchmark 4: SMILES QC on ChEMBL subset
- **Dataset:** ChEMBL 1,000-compound random sample (public)
- **Role:** Show BioMate catches known SMILES errors; quantify what fraction would reach ADMET with invalid inputs
- **Expected:** ~15% flagged per Whitehead 2022; demonstrate specific error types caught

### Comparison
- **Comparator A:** Standard MaxQuant/DIA-NN pipeline with manual QC review
- **Comparator B:** MultiQC proteomics module (post-hoc report only)
- **Comparator C:** PTXQC (dedicated MaxQuant QC tool by Bielow et al.)
- **Key differentiator vs PTXQC:** PTXQC is post-hoc reporting; BioMate halts execution and proposes parameter changes in real time

---

## Implementation Plan

### Phase 1 — QC governance layer (5 days)
1. `_parse_maxquant_metrics()` — parse `summary.txt`, `msms.txt`, `peptides.txt`, `proteinGroups.txt` (2 days)
2. `_parse_diann_metrics()` — parse `report.tsv` and `report.stats.tsv` (1 day)
3. `_check_qc_thresholds()` proteomics branch — GOLD/SILVER/BRONZE logic (1 day)
4. Named profiles: `proteomics_standard`, `proteomics_phospho`, `proteomics_plasma_biomarker` (0.5 day)
5. Tests: `TestProteomicsQCDomain` — 25 tests mirroring RNA-seq test structure (1 day)

### Phase 2 — SMILES QC gate (2 days)
1. `_parse_compound_metrics()` — RDKit SMILES validation
2. SMILES QC branch in `_check_qc_thresholds()`
3. 10 tests covering valid SMILES, salt forms, missing stereo, invalid SMILES

### Phase 3 — Drug discovery workflow integration (1 week)
1. Wire affinity proteomics (pulldown) QC: enrichment ratio gate
2. Wire phosphoproteomics: enrichment efficiency + localization gates
3. Wire plasma biomarker: CV + missing value + SIL standard gates

### Phase 4 — Benchmark runs and paper drafting (Month 3–6)

---

## What a Reviewer Will Ask

1. "How does this compare to PTXQC?" — Our answer: PTXQC is post-hoc; BioMate intercepts execution. Show a time/cost saving experiment.
2. "What is the false positive rate on known-good data?" — Benchmark 1 answers this.
3. "Is the mzQC adoption real or superficial?" — Use mzQC CV terms by name in the API output; cite Bittremieux 2023 prominently.
4. "Why are the BRONZE thresholds not just advisory notes?" — The GOLD/SILVER/BRONZE distinction determines *who can override* and *with what audit trail*. BRONZE can be overridden silently; SILVER requires a justification logged to the audit JSONL.

---

## Co-Authors Needed

| Role | Why |
|---|---|
| LC-MS proteomics expert (drug discovery context) | Validates MaxQuant/DIA-NN threshold choices; provides real pharma benchmark data |
| HUPO-PSI / mzQC contributor | Ideal co-author; directly validates our mzQC implementation; J Proteome Res or MCP credibility |
| Computational chemist (cheminformatics) | Validates SMILES QC design; knows ChEMBL error literature |
| Medicinal chemist / DMPK scientist | Validates drug discovery use case framing; provides pulldown or phosphoproteomics dataset |

---

## Parallel Track with Cryo-EM Paper

Both papers share:
- The same QC governance architecture (GOLD/SILVER/BRONZE layers, named profiles, SSE events, audit JSONL)
- The same `qc_trace_monitor.py` backend (each paper adds a new domain)
- The FSC 0.143 gate (cryo-EM paper) and PSM FDR gate (proteomics paper) are both GOLD — same governance philosophy

**Shared infrastructure work (benefits both papers simultaneously):**
- `qc_trace_monitor.py` extension: new domain branches (PROTEOMICS, CRYOEM_REFINEMENT)
- Named profile system extension: proteomics and cryo-EM profiles added to `QC_NAMED_PROFILES`
- Test suite extension: `TestProteomicsQCDomain` and `TestCryoEMRefinementQCDomain`

**Timeline alignment:**
- Both papers can run off the same QC governance infrastructure built for Paper 1
- Proteomics benchmark data (PXD000001, PXD003452) is faster to download/process than cryo-EM EMPIAR data
- Proteomics paper can submit first (~Month 18) if benchmark data is obtained quickly
- Cryo-EM paper submits ~Month 20 after EMPIAR benchmark runs complete

---

## Immediate Next Steps

1. Build `_parse_maxquant_metrics()` — start with `summary.txt` and `proteinGroups.txt` (highest-priority columns)
2. Download PXD000001 (HeLa deep proteome) from PRIDE — run through MaxQuant to get real output files for parser development
3. Contact a proteomics core facility director about co-authorship + benchmark dataset access
4. Confirm mzQC CV term IDs to use as controlled vocabulary in the QC output schema
