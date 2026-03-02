# Phase Plate CTF Gate — Implementation Complete
**Date:** 2026-02-26 13:50
**Status:** Implemented, tested, passing (513/513 tests)
**Context:** P2 item from cryo-EM benchmark paper plan — "Phase plate CTF fitting support"

## Status Note (2026-03-02)
This document is a historical session record. Some implementation claims may not match current `HEAD` due to subsequent branch changes or refactors. Treat this file as audit evidence for the recorded session, not as a guaranteed current-state implementation reference.

---

## What Was Built

Volta Phase Plate (VPP) / fringe-free illumination (FFI) support for the CTF QC gate.
Phase plates enhance contrast for small/flexible complexes but require the per-session
phase shift to remain in the **0.2–1.5 rad** window for optimal signal.

---

## Parser: `_parse_ctf_metrics()` augmentation

After the existing ice-thickness augmentation (`ctf_diagnostics.json`), a new block reads
`ctf_report.json` for:

| Key | Description |
|-----|-------------|
| `avg_phase_shift_rad` | Average per-micrograph phase shift (CryoSPARC JSON) |
| `phase_shift_rad` | Alias without "avg_" prefix |
| `avg_phase_shift_deg` / `phase_shift_deg` | Degrees → converted via `math.radians()` |

Graceful: if no `ctf_report.json` exists, or the file has no phase_shift key, no metric
is added and existing CTF gates are unaffected.

---

## Gate: CTF block in `_check_qc_thresholds()`

Both gates are **advisory (non-blocking)** — some structural information is still present
at either extreme; the operator should reposition the plate before the next session.

| Condition | Evidence | Action |
|-----------|----------|--------|
| `phase_shift_rad < 0.2` | [SILVER] Danev & Baumeister 2016 eLife 5:e13046 | Advisory: "plate depleted, reposition to fresh spot" |
| `phase_shift_rad > 1.5` | [SILVER] Danev & Baumeister 2016 eLife 5:e13046 | Advisory: "over-accumulated charge, verify AmplitudeContrast" |

---

## Near-Threshold Warnings in `_check_qc_warnings()`

| Condition | Near-threshold range | Message |
|-----------|---------------------|---------|
| Approaching depletion | 0.20–0.22 rad (`_near_above(ps, 0.2)`) | "Monitor plate state; prepare to reposition" |
| Approaching over-charge | 1.35–1.50 rad (`_near_below(ps, 1.5)`) | "Consider repositioning soon" |

---

## Named Profile: `cryoem_spa_phase_plate`

Added to `QC_NAMED_PROFILES` (profile #21):

```python
"cryoem_spa_phase_plate": {
    "overrides": {
        "fit_quality": 0.65,   # near-focus VPP collection makes CTF fitting harder
    },
    "references": [
        "[SILVER] Danev R & Baumeister W 2016 eLife 5:e13046",
        "[SILVER] Bharat TAM & Scheres SHW 2015 Curr Op Struct Biol 35:79-86",
    ],
}
```

---

## Mock Pipeline: `cryosparc_standard_spa/main.nf`

Added `params.phase_plate = false` (default: conventional TEM).
When `--phase_plate true`:
- VPP near-focus defocus range: 2,000–8,000 Å (vs 10,000–35,000 Å conventional)
- Per-micrograph `phase_shift_rad` (0.3–1.2 rad, simulating healthy collection)
- `avg_phase_shift_rad` written to `ctf_report.json`

Run VPP simulation with:
```bash
nextflow run main.nf --phase_plate true --mock_mode true --qc_profile cryoem_spa_phase_plate
```

---

## Files Modified

| File | Change |
|------|--------|
| `backend/lib/galaxy/jobs/qc_trace_monitor.py` | +`cryoem_spa_phase_plate` profile; +phase_shift_rad augmentation to `_parse_ctf_metrics()`; +phase shift gate in CTF block; +near-threshold warnings in `_check_qc_warnings()` |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` | Added `params.phase_plate`; PATCH_CTF_ESTIMATION emits `avg_phase_shift_rad` when enabled |
| `backend/tests/test_qc_e2e_domains.py` | +`TestPriyaCryoEM_PhasePlate` (11 tests) |

---

## Test Results

```
513 passed, 116 warnings
(up from 502 before this session)
```

11 new tests in `TestPriyaCryoEM_PhasePlate`:
- 2 × depleted plate advisory (value check + message reposition keyword)
- 2 × over-charged plate advisory (value check + message amplitude contrast)
- 2 × optimal range (0.75 rad no-gate; boundary 0.20 rad no blocking gate)
- 2 × near-threshold warnings (approaching min 0.21; approaching max 1.40)
- 1 × no phase_shift field → no gate (conventional TEM)
- 1 × degrees-to-radians conversion (10° = 0.175 rad → advisory)
- 1 × named profile sets fit_quality=0.65

---

## Remaining Paper Items

| Item | Status | Priority |
|------|--------|----------|
| Benchmark runs on EMPIAR-10061, 10005, 10017, 10028 | requires AWS | paper |
| Comparison to CryoSPARC Live (TRPV1 membrane protein) | requires AWS | paper |
| User study (5–10 sessions) | scheduling | paper |
