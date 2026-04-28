# ADMET Auto-Loop Architecture

**Date:** 2026-04-17  
**Scope:** `backend/experiments/admet_autoloop/`

## Summary

Built and validated 24/24 unit tests for a drug discovery ADMET safety screening auto-loop.  Architecture mirrors `cryo_em_autoloop` — same orchestrator pattern, same audit logger, same `QCAction`/`QCLevel` types — with only domain-specific modules swapped.

## Design Principle: Start from What BioMate Has

All gate thresholds and metric schemas derive from existing BioMate infrastructure:

| Source file | What it contributes |
|---|---|
| `assay_ingestion.py:25` | `_HERG_SAFETY_THRESHOLD_uM = 10.0` (ICH S7B empirical) |
| `assay_ingestion.py:29` | `_SAFETY_FLAG_TYPES = {"DILI", "Ames", "ClinTox"}` |
| `ADMET_pred/main.nf` | `toxicity_report.json` schema (hERG IC50, DILI risk/prob, Ames) |
| `qc_trace_monitor.py:1033` | ADMET toxicity gate entry point (ADMET_TOXICITY, HERG_SCREEN, DILI_SCREEN, ADMET_PRED) |

## Package Structure

```
backend/experiments/admet_autoloop/
├── __init__.py
├── params.py          — ADMETParams (17 fields) + PHASE_PARAM_OWNERS map
├── qc_evaluator.py    — ADMETQCEvaluator; 3 profiles; 7 gates
├── simulation.py      — SimulatedADMETJob + 6 pre-canned scenarios
├── param_tuner.py     — ADMETParamTuner; 4 HALT handlers
├── orchestrator.py    — ADMETAutoLoop; PHASES list (1-line swap vs CryoEM)
├── audit_logger.py    — AuditLogger (identical logic, ADMET imports)
└── tests/
    └── test_admet_loop.py — 24 tests (AL-1 to AL-24), all passing
```

## Key Modules

### `params.py` — `ADMETParams`

17 tunable parameters across 5 phases:

| Param | Default | Source |
|---|---|---|
| `herg_ic50_threshold_uM` | 10.0 µM | `assay_ingestion.py` line 25 |
| `dili_probability_max` | 0.5 | Lammert 2010 Toxicol Sci |
| `dili_risk_level_max` | "medium" | `assay_ingestion.py` flag logic |
| `ames_probability_max` | 0.5 | Kazius structural alerts |
| `logp_max` | 5.0 | Lipinski Rule of Five |
| `mw_max_da` | 500.0 | Lipinski Rule of Five |
| `num_candidates` | 50 | screening funnel |

### `qc_evaluator.py` — `ADMETQCEvaluator`

3 QC profiles:

| Profile | hERG threshold | DILI prob max | Notes |
|---|---|---|---|
| `admet_standard` | 10 µM | 0.50 | Default; matches assay_ingestion.py |
| `admet_cns` | 10 µM | 0.40 | CNS: TPSA ≤ 90 Å², logP ≤ 4.0 |
| `admet_oncology` | 5 µM | 0.60 | Higher toxicity tolerance; stricter hERG |

7 gates per full ADMET evaluation (`evaluate_phase_2`):
1. `herg_ic50` — HALT if IC50 < threshold
2. `dili_probability` — HALT if prob > max
3. `dili_risk_level` — HALT if risk > allowed level (high > medium > low)
4. `ames_mutagenicity` — HALT if ames_positive OR prob > max
5. `logp` — ADVISORY only
6. `molecular_weight` — ADVISORY only

### `param_tuner.py` — `ADMETParamTuner`

4 HALT handlers:

| Gate | Remediation | Scientific basis |
|---|---|---|
| `herg_ic50` | logp_max −0.5, mw_max_da −10% | Aronov 2008: log10(IC50)≈1.4−0.30×logP |
| `dili_probability` | logp_max→4.0, mw_max_da→400 | Lammert 2010: logP>4 AND MW>400 = high risk |
| `dili_risk_level` | logp_max→4.0 | Lammert boundary |
| `ames_mutagenicity` | ames_strict=True, num_candidates−10 | Kazius 2005: 29 alerts cover 89% positives |

### `orchestrator.py` — `ADMETAutoLoop`

Phase execution order:
```
phase_2_admet_prediction → phase_3_herg_screen → phase_4_dili_ames
```

Single-line difference from `CryoEMAutoLoop`:
```python
# CryoEM:
PHASES = ["phase_A", "phase_B", "phase_C", "phase_D", "phase_E"]

# ADMET:
PHASES = ["phase_2_admet_prediction", "phase_3_herg_screen", "phase_4_dili_ames"]
```

All orchestration logic (retry loop, escalation, audit logging) is identical.

### `simulation.py` — Pre-canned Scenarios

6 scenarios for deterministic testing:

| Scenario | Gate that fires | Resolution |
|---|---|---|
| `SCENARIO_HERG_THEN_PASS` | hERG IC50=3.5µM | passes at attempt 2 (18.0µM) |
| `SCENARIO_DILI_THEN_PASS` | DILI risk=high, prob=0.78 | passes at attempt 2 |
| `SCENARIO_AMES_THEN_PASS` | Ames positive | passes at attempt 2 |
| `SCENARIO_MULTI_GATE` | hERG+DILI both | resolves across 3 attempts |
| `SCENARIO_PERSISTENT_FAIL` | all 3 gates | never passes → escalation path |
| `SCENARIO_CLEAN_PASS` | none | passes on first attempt |

## Test Results

```
24 passed in 0.05s
```

| Range | Coverage |
|---|---|
| AL-1 to AL-6 | QC evaluator gate logic (per gate) |
| AL-7 to AL-10 | ParamTuner remediation rules (per gate) |
| AL-11 to AL-14 | Orchestrator retry/escalation |
| AL-15 to AL-17 | AuditLogger JSONL + summary report |
| AL-18 to AL-20 | Scenario runner integration (hERG, DILI, Ames) |
| AL-21 to AL-23 | Profile variants (cns, oncology, unknown) |
| AL-24 | Multi-gate persistent failure escalation |

## Generalizability

The orchestrator (`ADMETAutoLoop`) is 100% generic except the `PHASES` list.  
The `AuditLogger` is 100% reusable across domains.  
Adding a new domain (e.g. genomics variant QC) requires only:

1. New `params.py` dataclass
2. New `qc_evaluator.py` with domain gates
3. New `param_tuner.py` with remediation handlers
4. One-line PHASES list in a new `orchestrator.py`
5. Test scenarios in `simulation.py`

## Production Wiring Point

When ready to wire into the live BioMate pipeline:

1. `qc_trace_monitor.py` already has ADMET gate detection at lines 1033-1036
2. Add `drug_discovery` QC profile to `qc_trace_monitor.py` using `ADMETQCEvaluator.QC_PROFILES`
3. Wire `ADMETAutoLoop.run()` into the except block where `qc_trace_monitor` fires a toxicity halt

## How to Run

```bash
cd backend
python -m pytest experiments/admet_autoloop/tests/test_admet_loop.py -v
# 24 passed in 0.05s
```
