# QC Governance, Parameter Organization, and Dataset-First UX — Gap Analysis & Implementation

**Date:** 2026-03-17  
**Branch:** `connection_formal`

---

## 1. How QC Profile is Determined at the Backend

### Current state (gap)
The named QC profile is **never auto-selected**. It comes only from `request.executionConfig.qcConfig.qcProfile` in the frontend execute call. Since the QC Settings UI was removed from the panel, the frontend now always sends `{ pauseAtQcFailures: true }` with no profile.

In `backend/lib/galaxy/jobs/qc_trace_monitor.py`, `_start_qc_monitor()` receives `qc_profile=None` → falls back to hardcoded `DEFAULT_THRESHOLDS`. The 31 named profiles (`rnaseq_polya_standard`, `wgs_germline_standard`, `cryoem_spa_phase_plate`, etc.) exist but are never applied.

### Recommended fix (deferred)
In `nextflow_executor.py -> execute_nextflow()`, add domain-keyword -> profile auto-selection:
```python
def _infer_qc_profile(nextflow_path: str) -> str | None:
    path = nextflow_path.lower()
    if "rnaseq" in path: return "rnaseq_polya_standard"
    if "wgs" in path and "germline" in path: return "wgs_germline_standard"
    if "cryosparc" in path or "cryo_em" in path: return "cryoem_spa_standard"
    if "pharmacokinetics" in path or "nca" in path: return "drug_pkpd_standard"
    return None
```

---

## 2. QC as Workflow Step vs. Parallel Monitoring Layer

### Architecture (by design — correct)
QC is a **parallel Python monitoring layer**, NOT a Nextflow process:

- `qc_trace_monitor.py` (`NextflowQCGateHandler`) polls `workflow-trace.txt` every 5 seconds
- Runs as background thread started by `_start_qc_monitor()` in `nextflow_executor.py`
- The Nextflow `.nf` files have **zero QC references** — all steps are pure computation
- QC emits SSE events (`qc_gate_triggered`, `qc_warning`) but does not halt Nextflow itself
- `pauseAtQcFailures=true` controls only the frontend UI reaction (show modal)

**Implication for users:** "Workflow Configuration" parameters set Nextflow process inputs (quality thresholds for STAR, GATK, etc.). The QC governance thresholds are a separate layer that monitors process output quality.

This architecture is clean and should not be changed.

---

## 3. Parameter Organization — Current State & Fix

### Gap
All parameters shown in a single flat "Workflow Configuration" accordion with no per-step grouping. For a 14-step WGS GATK workflow, users cannot tell which parameters control FastQC vs. BWA vs. GATK vs. VQSR.

### Fix implemented (2026-03-17)
Added `buildStepGroupedParameters()` in `nextflow-workflow-viewer.tsx`:
- Uses `workflowDefinition.steps[].parameters` keys to assign parameters to steps
- Each step gets its own collapsible `ParameterGroup` accordion
- Unassigned parameters fall to "General Settings"
- Falls back to single "Workflow Configuration" group when step structure is sparse

### Remaining gap
Backend `parameter_metadata` has no `step` field. Full per-step grouping requires `ai_assistant.py -> _parse_nextflow_params()` to classify params by step:
```json
{ "star_index": { "type": "file", "level": "required", "step": "STAR Alignment" } }
```

---

## 4. Dataset-First Check — Gap & Fix

### Problem
BioMate generated workflows regardless of whether the user specified data. User says "run RNA-seq" -> workflow generated with `input: ""`.

### Root cause
In `galaxy-assistant.ts processMessage()`, `generateWorkflow()` is called even when `recommendedDatasets = []`.

### Fix implemented (2026-03-17)
Added rule to system prompt in `generateResponse()`:
> When the user requests a workflow but has NOT mentioned any dataset (no file path, S3 URI, SRA/GSE/EMBL/PXD accession), ask what data they have BEFORE generating the workflow. Exception: if the user explicitly requests a "demo", "test", or "mock" workflow, generate without requiring data.

**T8 test result:** AI correctly asked for dataset info (askedForData=true, no workflow panel shown).

---

## 5. E2E Test Coverage

New tests added (2026-03-17) in `frontend/e2e/qc-governance.e2e.ts`:

### T7 — Full execution past "Awaiting Review"
Requests demo RNA-seq in mock mode, clicks "Confirm & Run", verifies running state, waits for terminal state.  
**PASS** — runId=9d17a05e, running indicator found, reached `completed`.

### T8 — Dataset-first check  
Sends workflow request with no dataset info, verifies AI asks before generating.  
**PASS** — AI prompted for data (workflow panel not shown).

---

## All Test Results (2026-03-17)
```
T0  PASS  /api/qc/profiles returns >=30 profiles
T1  PASS  SSE inject endpoint exists  
T2  SKIP  AI workflow timing
T3  PASS  QC Settings absent, Workflow Configuration present
T4  SKIP  Run capture timing
T5  PASS  Sidebar collapses on panel open
T6  PASS  Confirm & Run + AWAITING REVIEW badge
T7  PASS  Full execution to completed
T8  PASS  Dataset-first check
```
8 passed, 1 skipped

---

## Files Changed
| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | Dataset-first check rule in system prompt |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | `buildStepGroupedParameters()` + per-step rendering |
| `frontend/e2e/qc-governance.e2e.ts` | T7 (execution) + T8 (dataset-first) tests |

---

## Open Items
1. QC auto-profile selection based on workflow domain (nextflow_executor.py)
2. Backend `parameter_metadata.step` field for precise step grouping
3. QC threshold params from .nf file not surfaced in Workflow Configuration
