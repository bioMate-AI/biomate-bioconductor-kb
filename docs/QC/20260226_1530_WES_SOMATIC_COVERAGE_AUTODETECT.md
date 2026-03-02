# WES Somatic 150X Coverage Auto-Detect — Implementation Complete
**Date:** 2026-02-26 15:30
**Status:** Implemented, tested, 533/533 passing
**Context:** Last remaining P0 item from Paper 1 plan (`research_repos/biomate_qc_governance_paper/20260225_1545_PAPER1_OVERVIEW.md`)

---

## Problem

The MOSDEPTH coverage gate used a two-tier threshold:
- Standard WES (domain in `wes`, `whole_exome`, etc.): 80X
- WGS / everything else: 30X

Somatic variant calling on WES data requires significantly higher depth:
- Tumor-normal: ≥ 150X on tumor sample (GATK Mutect2 Best Practices 2023)
- Tumor-only: ≥ 200X (no germline comparator; artifacts harder to filter)

Without the somatic tier, a 130X tumor WES run would pass the gate (130X ≥ 80X) when it should fail.

---

## Fix: Three-Tier Coverage Detection

### New `_wes_somatic_domains` tuple in `_check_qc_thresholds()` and `_check_qc_warnings()`

```python
_wes_somatic_domains = ("wes_somatic", "wes_tumor", "wes_tumor_normal",
                        "somatic_exome", "somatic_targeted", "targeted_somatic",
                        "exome_somatic")
```

### Threshold selection logic

| Domain match | Threshold | Label |
|---|---|---|
| `_wes_somatic_domains` | 150X | "WES somatic" |
| `_wes_domains` | 80X | "WES germline" |
| Everything else | 30X | "WGS germline" |

### Gate message

```
"Low genome coverage: {cov:.1f}X (threshold: {_cov_t:.0f}X for {_label}).
GATK Best Practices: ≥ 30X WGS, ≥ 80X WES germline, ≥ 150X WES somatic."
```

### Near-threshold warning

Same three-tier logic in `_check_qc_warnings()`: just-above the somatic threshold (e.g., 152X when somatic)
emits `qc_warning` event instead of a gate.

---

## New Named Profiles

| Profile | mean_coverage | duplicate_pct | Rationale |
|---------|--------------|--------------|-----------|
| `wes_somatic_tumor_normal` | 150X | (unchanged, 40%) | GATK Mutect2 matched tumor-normal, VAF ≥ 5% |
| `wes_somatic_tumor_only` | 200X | 50% | GATK tumor-only mode; FFPE/archival higher dup expected |

---

## Files Modified

| File | Change |
|------|--------|
| `backend/lib/galaxy/jobs/qc_trace_monitor.py` | +`wes_somatic_tumor_normal` and `wes_somatic_tumor_only` named profiles; +three-tier coverage gate in MOSDEPTH block; +three-tier near-threshold in `_check_qc_warnings()` |
| `backend/tests/test_qc_edge_cases.py` | +`TestWESSomaticCoverageAutoDetect` (8 regression tests) |

---

## Test Results

```
533 passed, 116 warnings
(up from 525 before this session)
```

8 new tests in `TestWESSomaticCoverageAutoDetect`:
- somatic domain 130X fires gate at 150X
- somatic domain 155X no gate
- wes_tumor_normal alias also uses 150X
- standard WES 90X passes (80X threshold unaffected)
- standard WES 60X fires gate at 80X (not 150X)
- somatic 152X → near-threshold warning only (not gate)
- `wes_somatic_tumor_normal` profile override = 150X
- `wes_somatic_tumor_only` profile override = 200X + dup=50%

---

## Paper 1 P0 Checklist — COMPLETE

| Fix | Status |
|-----|--------|
| Hi-C false-positive duplication gate | ✅ DONE |
| WES somatic 150X auto-detect | ✅ DONE |
| Sequencing saturation (CellRanger) | ✅ DONE |
| FSC 0.143 gate (cryo-EM) | ✅ DONE (implemented in earlier session) |
| Near-threshold warnings: coverage, TSS, NRF | ✅ DONE |
