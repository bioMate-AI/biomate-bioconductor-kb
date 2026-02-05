# UI E2E + S3 Security Updates (2026-02-05 13:37)

## Scope
This document records the UI improvements, E2E test expansion, S3 input/output handling, and encryption‑at‑rest for persisted S3 metadata in the `experiment_front` UI and sandbox frontend. It also lists tests executed and their outcomes.

## High‑level goals
- Expand end‑to‑end UI tests to cover real user flows (generate → run → outputs, history, downloads).
- Wire missing UI behavior so tests reflect real UX rather than placeholders.
- Add S3 input/output UX linked to execution config.
- Keep S3 credentials secure (memory‑only) and encrypt persisted metadata at rest.
- Ensure tests fail on any console/page errors.

## Key UI changes in `experiment_front`
### 1) Workflow Workspace execution visibility
- The workspace now triggers executions and shows progress + outputs.
- The “Run Analysis” button is wired to `useUnifiedExecution`.
- Output attachments render in the workspace when a run completes.

### 2) Workflow parameter editing
- `WorkflowBuilder` now opens `ParameterDialog` when “Edit Parameters” is used.
- Dialog saves parameter changes back to the step and reflects updates in the step card.
- Added validation for required parameters and numeric range limits.
- Schema fetching is guarded: only fetches for toolshed/biomni tool IDs; fallback schema used otherwise.

### 3) Upload → workflow input mapping
- Files attached in chat are converted into dataset configs.
- First workflow step gets those datasets as inputs for display.
- Context sidebar shows attached files for visibility.

### 4) Save and export workflow
- Save button opens `SaveWorkflowDialog`, saves a template in `localStorage`, and shows save status.
- Export button triggers JSON download of the workflow + steps.

### 5) Context sidebar S3 input/output
- Added S3 input/output forms in the Files tab.
- S3 datasets are displayed in the sidebar lists (inputs + outputs).
- S3 validation enforces bucket, key/prefix, access key, and secret key.
- A note clarifies credentials are stored in memory only.

## Security: Encryption‑at‑rest for S3 metadata
### Why
S3 bucket/prefix metadata should not be stored in plaintext in the browser. Credentials must never persist. The UI now encrypts S3 metadata before writing to `localStorage` and decrypts it on load.

### How it works
- An AES‑GCM key is generated per session and stored in `sessionStorage` (not persisted across browser sessions).
- S3 metadata (bucket/prefix/region) is encrypted before saving datasets to `localStorage`.
- On reload, S3 metadata is decrypted in memory and used to display names/prefixes.
- Credentials are stored only in memory (not in `localStorage` or encrypted payloads).
- Dataset IDs are opaque UUIDs (no bucket/prefix leakage in IDs).

### Result
- `localStorage` contains `s3ConfigEncrypted` payload only (no plaintext bucket/prefix, no credentials).
- On refresh within the same browser session, metadata is restored from encrypted payload.
- On new session (fresh key), metadata is not recoverable without re‑entry.

## Execution config alignment
When running a workflow, S3 inputs/outputs are injected into `executionConfig.storage`:
- `executionConfig.storage.inputs`
- `executionConfig.storage.outputs`
Credentials are merged only at the moment of execution and are not persisted.

## E2E test coverage (Playwright)
All tests run under **strict mode**: any `console.error` or `pageerror` fails the test.

### Core flows
- Generate workflow → run → outputs shown.
- History panel shows completed run, open results.
- Download outputs (single and ZIP).

### Error handling and recovery
- Validation for empty generation request.
- Retry after validation success.

### Upload and mapping
- Attached file appears in chat.
- Attached file appears in workflow step inputs.
- Attached file appears in context sidebar.

### Parameter editing
- Parameter dialog updates step parameters and reflects changes.
- Required parameter validation shows errors.

### Save/export
- Save dialog validates required fields and saves template.
- Export triggers JSON download.

### S3 (inputs/outputs)
- S3 input/output included in execution config.
- S3 form validation errors.
- S3 inputs persist across reload.
- S3 credentials never persisted to `localStorage`.
- S3 execution blocked when credentials missing after reload.

### Latest E2E result
- **`npm run e2e` → 21/21 passed**

## Files changed (high‑level)
### UI behavior and security
- `experiment_front/src/App.tsx`
  - Manages input/output datasets.
  - Encrypts persisted S3 metadata.
  - Decrypts S3 metadata on load.
  - Keeps credentials in memory only.
- `experiment_front/src/components/layout/WorkflowWorkspace.tsx`
  - Injects S3 storage into execution config.
  - Blocks execution if credentials missing.
- `experiment_front/src/components/layout/ContextSidebar.tsx`
  - S3 input/output forms and listing.
  - S3 validation and reset logic.
  - "credentials not persisted" hint.
- `experiment_front/src/components/workflow-builder.tsx`
  - Wires parameter dialog.
  - Save/export workflow behavior.
- `experiment_front/src/components/parameter-dialog.tsx`
  - Validation for required and numeric range constraints.

### Tests
- `experiment_front/e2e/ui-workflow.spec.ts`
  - 21 total tests with strict console/page error policy.

## Known limitations
- Encryption key is session‑scoped (stored in `sessionStorage`), so encrypted metadata cannot be decrypted across browser restarts.
- S3 credentials are not stored anywhere persistent; users must re‑enter on new sessions.
- Server‑side secure storage of S3 metadata/credentials is not implemented yet (client‑only for now).

## Next possible improvements
- Backend‑side secure storage with encryption + access control.
- Key rotation and metadata re‑encryption flow.
- Upload → execute with real Galaxy dataset linking for S3 inputs.
- Validate S3 outputs in workflow history/results display.
