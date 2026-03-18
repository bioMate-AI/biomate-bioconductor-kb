# Explicit Low-Confidence Override Flow Implementation (2026-03-01 07:17)

## Objective

Continue from dual-confidence gate and add an explicit, auditable user action path:

- default: block low-confidence workflow execution,
- optional: user deliberately confirms override to proceed.

## Implemented changes

### 1) Shared execution config now supports explicit override flag

File:
- `frontend/shared/schema.ts`

Change:
- Added `allowLowConfidence?: boolean` to `executionConfigSchema`.

Purpose:
- keep override contract typed and explicit.

### 2) UI now exposes "Confirm and Run Anyway" only when blocked

File:
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`

Changes:
- Existing block warning remains visible when execution is blocked.
- Added explicit button:
  - `data-testid="button-confirm-low-confidence-run"`
  - label: `Confirm and Run Anyway`
- Clicking button sends execution override payload:
  - `__executionOverrides.allowLowConfidence = true`
  - `__executionOverrides.overrideReason = <block reason>`
- Emits telemetry event:
  - `workflow.low_confidence_override_clicked`

### 3) Chat message run handoff carries both assessment and override

File:
- `frontend/client/src/components/chat-message.tsx`

Changes:
- Execution block reason now considers:
  - domain guard block reason, OR
  - low-confidence feedback prompt (`needsUserFeedback`).
- Run callback payload includes:
  - `__generationAssessment`
  - `__executionOverrides` from viewer action.

### 4) Run request now forwards explicit override to backend gate

File:
- `frontend/client/src/components/chat-with-artifacts.tsx`

Changes:
- Reads `workflow.__executionOverrides?.allowLowConfidence`.
- Sets `executionConfig.allowLowConfidence`.
- Adds `userConfirmedLowConfidence` into `generationAssessment`.

### 5) Backend gate now logs accepted overrides for auditability

File:
- `frontend/server/routes.ts`

Changes:
- Existing confidence gate stays enforced.
- If `allowLowConfidence === true`, server logs warning with contextual fields:
  - user, workflow name, scientific/technical gate flags.

## Validation

- Lints on edited files: no errors.
- UI test:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/domain-case-performance.e2e.ts --project chromium`
  - Result: `1 passed`.

## Resulting behavior

- Low-confidence workflows are blocked by default.
- User can still proceed only via explicit confirmation action.
- Override intent is now visible in telemetry + server logs for audit trail.

