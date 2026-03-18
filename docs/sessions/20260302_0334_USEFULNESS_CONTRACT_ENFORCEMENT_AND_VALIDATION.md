# Usefulness Contract Enforcement and Validation (2026-03-02 03:34)

## Goal
- Continue real-user system testing by enforcing that "completed" must also be useful to users (visualizable + downloadable outputs), not just technically finished.

## Changes Implemented

### 1) Status endpoint: usefulness contract signal
- File: `frontend/server/routes.ts`
- Endpoint: `GET /api/workflows/runs/:id/status`
- Added `usefulness` block in response for completed runs:
  - `hasOutputs`
  - `visualizableCount`
  - `downloadableCount`
  - `totalOutputs`
  - `meetsContract`

### 2) Best-effort output hydration
- For completed runs with empty persisted outputs:
  - attempts to fetch history contents from Galaxy
  - stores discovered outputs in invocation output storage
  - recomputes usefulness

### 3) Nextflow fallback artifact extraction
- For Nextflow runs where invocation outputs are not materialized yet:
  - derive artifacts from `nextflowStatus` (`outputs`, `results`, `output_files`, `outdir`, and parsed file paths in `log_tail`)
  - compute usefulness from these artifacts so status reflects real generated outputs

### 4) E2E contract assertion
- File: `frontend/e2e/complete-workflow.e2e.ts`
- Added status assertion:
  - `statusPayload.usefulness.meetsContract === true`
- Added bounded polling window (~90s) for usefulness convergence after terminal completion.

## Real-User Validation Results

### A) Initial strict check (before fallback parsing) — expected fail
- `complete-workflow.e2e.ts` failed with:
  - `Run completed without useful outputs`
  - `usefulness={"hasOutputs":false,"visualizableCount":0,"downloadableCount":0,"totalOutputs":0,"meetsContract":false}`
- This confirmed prior "completed" status could hide user-value gaps.

### B) After Nextflow fallback parsing
- `complete-workflow.e2e.ts`: **PASS**
  - backend run id captured
  - terminal state reached
  - usefulness contract passed
  - frontend output visualization/download checks passed

### C) Regression check
- `pm-user-stories-comprehensive.e2e.ts`: **PASS (3/3)**

## Key Audit Conclusion
- The system now exposes and validates a concrete usefulness contract in status polling.
- Real-user E2E can fail explicitly when completion lacks usable outputs.
- With fallback artifact extraction for Nextflow, status/usefulness now better reflects actual execution products in the current architecture.

