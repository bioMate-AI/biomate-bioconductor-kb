# Session Audit — PK/PD QC Gates, Ames Alerts, IVIVE + Handoff Notes
**Date:** 2026-03-03 18:21
**Branch:** `connection_formal`
**Author:** Claude (backend QC track)

---

## What Was Completed This Session

### 1. `import json` Missing from `qc_trace_monitor.py`

**Root cause:** The new parser methods added for PK/PD gates called `json.loads()` and
`json.JSONDecodeError` but the file had never had `import json` at the top.

**Fix:** Added `import json` to the module imports (line 8).

---

### 2. Population PK QC Gates (nlmixr2)

Reads `nlmixr2_results.json` from the workflow work directory.

| Metric | Threshold | Gate |
|---|---|---|
| `convergence_status` | `!= "converged"` | **GOLD blocking** |
| `max_eta_shrinkage_pct` | `> 30%` | SILVER advisory |
| `condition_number` | `> 1000` | BRONZE advisory |

Process name routing: `NLMIXR2_POPULATION_PK`, `POPULATION_PK`, `POP_PK`, `POPPK`, `POPK`.

---

### 3. NCA QC Gates (PKNCA)

Reads `nca_results.json`.

| Metric | Threshold | Gate |
|---|---|---|
| `auc_extrap_pct_max` | `> 20%` | SILVER advisory |
| `subjects_with_no_terminal_slope / n_subjects` | `> 30%` | BRONZE advisory |

Process name routing: `NCA_PKNCA`, `NCA_ANALYSIS`, `NONCOMPARTMENTAL`, `PKNCA`.

---

### 4. IVIVE (In Vitro to In Vivo Extrapolation) Workflow + QC Gate

**New workflow:** `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ivive_hepatic_clearance/main.nf`

Implements well-stirred, parallel tube, and dispersion models with species constants
(human, rat, mouse, dog; Davies & Morris 1993, Barter 2007). Outputs `ivive_results.json`.

**QC gate** reads `ivive_results.json`:

| Metric | Threshold | Gate |
|---|---|---|
| `clh_fraction_of_qh` | `> 0.90` | BRONZE advisory ("near maximum hepatic blood flow — consider fu_plasma refinement") |
| `clh_fraction_of_qh` | `< 0.30` | BRONZE advisory ("low extraction — transporter involvement likely") |

Process name routing: `IVIVE`, `HEPATIC_CLEARANCE`, `IVIVE_HEPATIC`, `CLEARANCE_SCALING`.

---

### 5. Ames Structural Alerts Added to Both ADMET Workflows

Added `compute_ames_alerts()` (Kazius 2005, 13 SMARTS patterns) to:
- `pharmacology/ADMET_pred/main.nf`
- `pharmacology/predict_admet_properties/main.nf`

Both workflows now write `ames_positive`, `ames_probability`, `ames_structural_alerts`, and
`ames_method` fields into `toxicity_report.json["toxicity"]`.

The existing Ames gate in `qc_trace_monitor.py` (line 3293) reads these fields and fires a
**SILVER advisory** when `ames_positive=True` or `ames_probability >= 0.70`.

---

### 6. Regression Tests

**File:** `backend/tests/test_qc_e2e_domains.py`

Added:
- `TestPopulationPKQCGates` — 13 tests (nlmixr2 convergence, ETA shrinkage, condition number; NCA AUC extrapolation, no-slope subjects; IVIVE high/low extraction, process name routing)
- `TestAmesStructuralAlerts` — 4 tests (positive fires advisory, negative clean, below threshold, coexists with hERG gate)

**Test suite result:** 512 / 512 passing, 32 skipped (billing / Redis tests).

**Commit:** `777aa0613` on `connection_formal`.

---

## Open Items for UX Colleague

### A. Missing QC Gate Modal Display Names (Low-effort, ~5 min)

**File:** `frontend/client/src/components/qc-gate-modal.tsx`
**Object:** `PROCESS_DISPLAY_NAMES` (line 27)

The following process names from new PK/PD workflows have **no entry** in the lookup table.
The fallback `humanizeProcessName()` produces readable but imperfect labels (e.g. "Nca Pknca").

Add these entries:

```typescript
// PK/PD — new this session
NCA_PKNCA: "Non-Compartmental Analysis (PKNCA)",
NCA_ANALYSIS: "Non-Compartmental Analysis",
NLMIXR2_POPULATION_PK: "Population PK Modelling (nlmixr2)",
POPULATION_PK: "Population PK Modelling",
IVIVE: "IVIVE Hepatic Clearance",
IVIVE_HEPATIC_CLEARANCE: "IVIVE Hepatic Clearance",
HEPATIC_CLEARANCE: "IVIVE Hepatic Clearance",
CLEARANCE_SCALING: "Clearance Scaling (IVIVE)",
```

Optionally add `TROUBLESHOOTING_STEPS` entries for these processes — useful guidance would be:
- `NCA_PKNCA`: check sampling schedule density near Tmax; add terminal-phase time points
- `NLMIXR2_POPULATION_PK`: check NONMEM/nlmixr2 log for gradient issues; reduce model complexity; widen initial parameter bounds
- `IVIVE`: check fu_plasma assay reliability at low binding; consider uptake transporter scaling

---

### B. TypeScript Errors (7 remaining in `connection_formal`)

These are all in files that appear to have come in from another branch. None are in code written
this session.

**`frontend/client/src/components/chat-message.tsx` line 252**
```
error TS18048: 'message.metadata' is possibly 'undefined'.
```
Fix: change `message.metadata.workflow` → `message.metadata?.workflow`

---

**`frontend/client/src/components/chat-output-attachments.tsx` lines 190, 310, 312, 314**

Four errors. Root cause: call sites pass `onDownload` prop and `invocationId` prop to viewer
components that don't accept them:

```
line 190: InteractiveToolLauncher — 'invocationId' not in InteractiveToolLauncherProps
line 310: VCFViewer            — 'onDownload' not in VCFViewerProps
line 312: SequenceViewer       — 'onDownload' not in SequenceViewerProps
line 314: AnnotationViewer     — 'onDownload' not in AnnotationViewerProps
```

Viewer interfaces are defined in `frontend/client/src/components/viewers/`:
- `vcf-viewer.tsx:40` — `{ output: OutputDataset; className?: string }`
- `sequence-viewer.tsx:34` — same
- `annotation-viewer.tsx:40` — same
- `interactive-tool-launcher.tsx:42` — `{ outputs: OutputDataset[] }`

**Two options:**
1. Remove `onDownload` and `invocationId` from the four call sites in `chat-output-attachments.tsx` ← simplest
2. Add optional `onDownload?` and `invocationId?` to each viewer's Props interface and wire them up

---

**`frontend/server/routes.ts` lines 3795, 3839**
```
error TS2353: 'source' does not exist in type { height?, width?, ... geneCount? }
```
The `metadata` field on `OutputDataset` doesn't include `source` or `localPath`.
These fields are already consumed correctly at lines 97 and 108 (`metadata.source === 'nextflow'`).

Fix: add them to the metadata type in the shared schema:
```typescript
// In shared/schema.ts, OutputDataset.metadata shape:
source?: string
localPath?: string
```

---

## Test Suite Baseline (End of Session)

| Suite | Result |
|---|---|
| QC core (test_qc_e2e_domains + test_qc_edge_cases + test_gap3_*) | **512 / 512 pass**, 32 skipped |
| TypeScript (`npx tsc --noEmit`) | **7 errors** |

---

## Files Changed This Session

**Backend:**
- `lib/galaxy/jobs/qc_trace_monitor.py` — added `import json`; PK/PD + IVIVE parsers and gates
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ivive_hepatic_clearance/main.nf` — new IVIVE workflow
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` — Ames structural alerts integrated
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` — Ames structural alerts integrated
- `tests/test_qc_e2e_domains.py` — 17 new regression tests (TestPopulationPKQCGates + TestAmesStructuralAlerts)
