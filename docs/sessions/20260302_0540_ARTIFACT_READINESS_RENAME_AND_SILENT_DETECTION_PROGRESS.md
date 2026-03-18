# Artifact Readiness Rename + Silent Detection Progress (2026-03-02 05:40)

## Scope
- Continue implementation by replacing ambiguous `usefulness` naming with `artifactReadiness`.
- Keep detection silent (no user-facing prompt), as requested.
- Add deterministic E2E coverage for silent artifact-readiness telemetry behavior.

## Changes Implemented

### 1) Renamed status contract field
- Backend status response now returns `artifactReadiness` instead of `usefulness`.
- File:
  - `frontend/server/routes.ts`

### 2) Client hook/status mapping update
- `useUnifiedExecution` now reads `status.artifactReadiness`.
- Silent telemetry emission uses artifact readiness payload fields.
- File:
  - `frontend/client/src/hooks/useUnifiedExecution.ts`

### 3) Removed user-facing artifact-readiness prompt path
- Removed remaining viewer UI prompt/CTA code so this remains background-only detection.
- File:
  - `frontend/client/src/components/nextflow-workflow-viewer.tsx`

### 4) Updated message/viewer wiring
- Removed stale viewer prop wiring tied to old field.
- File:
  - `frontend/client/src/components/chat-message.tsx`

### 5) Updated strict E2E assertion naming
- `complete-workflow.e2e.ts` now asserts `artifactReadiness.meetsContract`.
- File:
  - `frontend/e2e/complete-workflow.e2e.ts`

### 6) Added deterministic silent-detection E2E
- New test verifies:
  - silent telemetry event is emitted once for `artifact_readiness`
  - no user-facing prompt appears.
- File:
  - `frontend/e2e/ux-artifact-readiness-silent.e2e.ts`

### 7) Schema alignment
- Added `artifactReadiness` to execution run status schema.
- File:
  - `frontend/shared/schema.ts`

## Validation Results

### Build/Lint
- `npm run build`: PASS
- Lints on edited files: PASS

### E2E
- `ux-artifact-readiness-silent.e2e.ts`: PASS (deterministic behavior verified)
- `complete-workflow.e2e.ts`: FAIL (consistent backend runtime issue)
  - Terminal status: failed
  - Error: `No entry workflow specified`
  - This indicates workflow selection/execution picked a non-entry Nextflow artifact (`subworkflow` path), not a regression caused by the rename/silent telemetry slice.

## Current Blocker
- Real-run backend path remains unstable for complete workflow scenario due occasional non-entry Nextflow selection.
- This requires additional selection contract tightening (entry-workflow-only acceptance) in generation/search path.

