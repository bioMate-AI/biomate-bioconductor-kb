# Supplementary Note S3: QC Governance Test Suite Documentation
**BioMate QC Governance Stack — Paper 1 Supplementary Material**
**Last updated:** 2026-03-04
**Total tests:** 577 (in core QC suite; excludes billing/Redis-dependent and e2e/playwright tests)

## Overview

The BioMate QC governance stack is covered by two test files:
- `backend/tests/test_qc_edge_cases.py` — 413 test methods in 47 classes
- `backend/tests/test_qc_e2e_domains.py` — 164 test methods in 19 classes

Tests are organised into three tiers:

| Tier | Coverage |
|------|----------|
| **Unit** | Individual parser functions, threshold functions, suggestion generators |
| **Integration** | Full SSE event chain: metric file → parse → threshold → emit |
| **Domain scenario** | Named researcher personas running domain-specific QC workflows end-to-end |

All tests run without a live backend or database — the metric files are written to `tmp_path` and the SSE callback is a lambda that captures events into a list.

---

## test_qc_edge_cases.py — Unit and Integration Tests

### Core Infrastructure

| Class | Tests | Description |
|-------|-------|-------------|
| `TestStatusFiltering` | 6 | FAILED/RUNNING/CANCELLED statuses emit no QC events |
| `TestDuplicateDeduplication` | 4 | Same task:process hash emits only 1 event |
| `TestThresholdBoundaryConditions` | 13 | Exact-at-threshold values do not trigger gates |
| `TestSSECallbackErrors` | 3 | Exceptions in callback do not propagate |
| `TestHashResolution` | 4 | Task hash → work dir resolution with malformed inputs |

### Parser Edge Cases

| Class | Tests | Description |
|-------|-------|-------------|
| `TestParserEdgeCases` | 11 | Empty/malformed log files return None gracefully |
| `TestParserPositiveCases` | 9 | Valid log files parse all expected fields |
| `TestUniversalQCParsers` | 40 | Full coverage of all 12 parsers: motion, CTF, trimming, alignment, feature counting, single-cell, duplication, ATAC, metagenomics, proteomics, FSC, SMILES |

### Suggestion Generator

| Class | Tests | Description |
|-------|-------|-------------|
| `TestSuggesterAlreadyAtRecommended` | 7 | No suggestion when parameter already at recommended value |
| `TestNoneDefaults` | 6 | None-typed defaults do not crash the suggester |
| `TestAbInitioAndRefinement` | 9 | Cryo-EM ab initio and refinement suggestion paths |
| `TestRNASeqSuggester` | 5 | RNA-seq specific suggestion paths |
| `TestConfidenceRange` | 6 | All confidence values in [0.0, 1.0] |
| `TestDictSuggestedValues` | 4 | Dict-type suggested values serialise correctly |
| `TestSuggestionReasonText` | 8 | Reason text is non-empty for all domains |

### SSE Event Schema

| Class | Tests | Description |
|-------|-------|-------------|
| `TestStructuredFailureFormat` | 8 | Failure dicts contain required keys: metric, value, threshold, operator, message |
| `TestSSEEventDataCompleteness` | 9 | qc_gate_triggered events contain process_name, failures, qc_metrics, suggestions |
| `TestPositiveCasesNoTrigger` | 8 | Metrics above threshold → no qc_gate_triggered event emitted |
| `TestMultipleFailures` | 5 | Multiple concurrent failures appear in same event |

### Domain-Specific Gate Logic

| Class | Tests | Description |
|-------|-------|-------------|
| `TestProcessNameVariants` | 12 | All documented process name aliases route to correct domain handler |
| `TestDomainFactory` | 5 | Domain factory selects correct handler class by workflow_domain |
| `TestATACSeqQCDomain` | 15 | ATAC-seq ENCODE4 thresholds: TSS enrichment (GOLD), FRiP (advisory), NRF (GOLD) |

### Regression Tests

| Class | Tests | Description |
|-------|-------|-------------|
| `TestBugRegressions` | 32 | Specific bugs fixed during development; includes CTF defocus boundary, MARKDUPLICATES domain skipping, NRF falsy-value bug |
| `TestCTFDefocusBoundary` | 11 | CTF defocus in-range, out-of-range (below/above), and boundary conditions |
| `TestPickingDuplicateFractionInvariant` | 5 | Particle picking logs do not trigger duplication gate |
| `TestEndToEndFileToSSE` | 24 | Full file-to-event chain for 12 domains |
| `TestUncoveredPaths` | 16 | Previously untested code branches |
| `TestRNASeqMultiFailure` | 9 | Multiple RNA-seq failures appear together in one event |
| `TestAuditFindings` | 8 | First-round expert audit findings (Danev 2016, ENCODE4, GATK) |
| `TestRound2AuditFindings` | 15 | Second-round audit fixes (advisory pattern, metagenomics tiers, WES coverage) |

### QC Override and Profile System

| Class | Tests | Description |
|-------|-------|-------------|
| `TestQCOverrides` | 22 | Per-invocation override system: accepted metrics, Red Line enforcement, GOLD immutability, audit trail |
| `TestNamedProfiles` | 25 | All 31 named profiles validated: description, domain_hint, reference count, override keys |

### Tier 1 & Near-Threshold Features

| Class | Tests | Description |
|-------|-------|-------------|
| `TestTierOneChanges` | 5 | US-3.2 CTF defocus directional failure; US-3.3 two-tier alignment critical; US-6.3 near-threshold warning events |
| `TestCryoEMNearThresholdWarnings` | 9 | Near-threshold warnings for motion drift (40–50 Å), CTF fit quality (0.70–0.77), particle count (1000–1100), 2D junk (0.45–0.50) |

### Paper 1 P0 Features

| Class | Tests | Description |
|-------|-------|-------------|
| `TestPaper1P0Fixes` | 12 | Hi-C false-positive suppression; CellRanger sequencing saturation advisory; coverage/TSS/NRF near-threshold warnings |
| `TestWESSomaticCoverageAutoDetect` | 8 | WES somatic 150X auto-detect; three-tier gate (somatic/germline/WGS); named profiles wes_somatic_tumor_normal and wes_somatic_tumor_only |

### New Suggester Classes (2026-03-04)

| Class | Tests | Description |
|-------|-------|-------------|
| `TestDrugDiscoverySuggester` | 9 | hERG IC50 tiers, DILI structural alert, Ames filter, pulldown bead/protein suggestions, QSAR estimator |
| `TestCryoEMSharpeningSuggester` | 5 | B-factor guidance (Rosenthal & Henderson 2003), local resolution 3D variability suggestion |
| `TestDomainRoutingProteomics` | 3 | chemoproteomics → ProteomicsParameterSuggester; maxquant/diann routing verified |

---

## test_qc_e2e_domains.py — Domain Scenario Tests

Each class follows a named researcher persona running a complete domain workflow. Tests verify the full pipeline from metric file → SSE event without mocking any intermediate step.

| Class | Domain | Tests | Key scenarios |
|-------|--------|-------|---------------|
| `TestAliceRNASeq` | RNA-seq | 18 | polyA/ribo-depleted/FFPE/snRNA profiles; alignment, trimming, featureCounts gates |
| `TestBobDNASeq` | WGS/WES | 14 | WGS 30X, WES 80X/150X/200X somatic gates; duplication domain skipping |
| `TestCarolSingleCell` | scRNA-seq | 12 | mito fraction (standard/cardiac/neuronal); cells detected; CellRanger parsing |
| `TestDaveChIPSeq` | ChIP-seq | 8 | FRiP advisory; peak count gate; duplication skip |
| `TestEveMetagenomics` | Metagenomics | 8 | Tiered classification rate; soil/marine/clinical profiles |
| `TestFrankCryoEM` | Cryo-EM SPA | 15 | Motion drift; CTF fit quality; defocus range; particle count; named profiles |
| `TestDomainFactory` | All | 6 | Domain factory creates correct handler for each domain string |
| `TestGraceProteomicsMaxQuant` | Proteomics | 14 | MaxQuant peptides.txt parsing; PSM FDR (GOLD); missed cleavage; CV gate |
| `TestHenryDIANNPlasma` | Proteomics | 10 | DIA-NN report parsing; plasma biomarker profile; CV < 15% gate |
| `TestFrankRefinementFSC` | Cryo-EM | 10 | FSC 0.143 gold-standard gate; half-map FSC parsing |
| `TestProteomicsProfiles` | Proteomics | 8 | proteomics_phospho; proteomics_plasma_biomarker; proteomics_chemoproteomics |
| `TestIsobelPulldown` | Proteomics | 12 | Chemoproteomics pulldown enrichment ratio gate |
| `TestJamesSMILESCompoundQC` | Drug Discovery | 19 | SMILES QC gates: invalid SMILES, MW, TPSA, rotatable bonds, Lipinski, PAINS |
| `TestPriyaCryoEM_P1Gates` | Cryo-EM | 26 | P1 cryo-EM gates: motion correction, CTF estimation, particle picking |
| `TestPriyaCryoEM_P2Gates` | Cryo-EM | 15 | P2 cryo-EM gates: ab initio, refinement, FSC gate |
| `TestPriyaCryoEM_PhasePlate` | Cryo-EM | 11 | Volta Phase Plate advisory gates; phase shift parsing; cryoem_spa_phase_plate profile |

---

## Governance Layer Coverage

| Layer | Description | Tests |
|-------|-------------|-------|
| Layer 0 — Red Lines | 4 metrics, hardcoded, never overridable | 6 (in TestQCOverrides) |
| Layer 1 — GOLD thresholds | Community gold standard, ENCODE4/Elias&Gygi | 18 (ATAC TSS, protein FDR, NRF) |
| Layer 2 — SILVER/BRONZE | Literature-supported, user override with audit trail | 180+ across all domain tests |
| Layer 3 — Named profiles | 31 curated protocol-aware sets | 33 (TestNamedProfiles + profile scenario tests) |
| Advisory pattern | Non-blocking gates for ambiguous metrics | 22 (ChIP FRiP, CTF astigmatism, phase plate, saturation) |
| Near-threshold warnings | qc_warning SSE events before failures | 14 (coverage, TSS, NRF, drift, CTF, phase plate) |

---

## Running the Test Suite

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest \
    tests/test_qc_edge_cases.py \
    tests/test_qc_e2e_domains.py \
    tests/test_gap3_complete_integration.py \
    tests/test_gap3_standalone.py \
    -q --tb=short
# Expected: 577 passed (32 skipped = billing/Redis tests)
```

*For the full test source, see `backend/tests/test_qc_edge_cases.py` and `backend/tests/test_qc_e2e_domains.py`.*
