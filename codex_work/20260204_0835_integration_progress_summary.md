## Summary of Work and Findings

### Scope and intent
- Continued the sandbox integration work for Nextflow execution and template reuse in `biomate_nextflow_sandbox`.
- Focused on making template-reuse workflows importable into Galaxy and on diagnosing why invocations remain stuck in `new`/`queued`.

### Changes applied in sandbox backend
- Preserved full template steps during template reuse (including `data_input`) instead of collapsing to tool-only steps.
- Dropped unsupported `data_output` steps during template reuse to avoid Galaxy import assertion errors.
- Ensured `parameter_input` steps include a `tool_state` with:
  - `parameter_type` inferred from input descriptions (boolean when description mentions boolean).
  - `optional` defaulted to `true`.
  - `default` set to `false` for boolean parameters.
- Normalized `tool_state` to JSON string for Galaxy import (Galaxy expects string-encoded `tool_state`).

### Test workflow used
- `FASTQ_TRIM_FASTP_FASTQC` (template reuse from nf-core subworkflow).

### Test results
- Template reuse now produces `data_input`, `parameter_input`, and `tool` steps (no `data_output`).
- Galaxy workflow import succeeds after:
  - `data_output` removal,
  - `parameter_input` `tool_state` defaults,
  - `tool_state` JSON string normalization.
- Tool ID mapping required for installed tools:
  - `Repository_Actions_FastQC` -> `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy1`
  - `Repository_Actions_fastp` -> `toolshed.g2.bx.psu.edu/repos/iuc/fastp/fastp/1.0.1+galaxy3`
- Invocation still remains in Galaxy state `new` with `steps: []` (no step materialization).
- Frontend shows `queued` continuously because Galaxy invocation never progresses.
- Frontend `/api/invocations/:id/nextflow/status` returns `Unexpected token <` due to 404 HTML response from Galaxy (no such endpoint).

### Key error evidence (Galaxy backend)
- Earlier: `KeyError: 'parameter_type'` for `parameter_input` (fixed by tool_state defaults).
- Then: `AssertionError: Unexpected workflow step type [data_output]` (fixed by removing `data_output`).
- Current: invocations create successfully but stay `new` with `steps: []` even for Galaxy engine.

### Files modified
- `backend/lib/galaxy/ai/ai_assistant.py`

### Open issues confirmed
- Galaxy invocation does not materialize steps (`state: new`, empty `steps`).
- Nextflow status polling endpoint is missing in Galaxy (`/api/workflows/:id/nextflow/status` 404).
- Frontend continues to parse HTML error as JSON for Nextflow status.

### New findings after scheduler debugging
- Workflow scheduler was not running because `workflow_schedulers_conf.xml` had:
  - Wrong root element, and
  - Handler ID that did not match `server_name` (`main.1`).
- After updating the scheduler config and matching handler ID, the workflow scheduler began scheduling pending invocations.
- A minimal FastQC workflow now advances to `state: scheduled` with steps populated.
- Nextflow run now schedules but fails with `output_not_found`:
  - Missing output `reads` from step 7 when step 8 depends on it.
  - Galaxy invocation messages show `output_not_found` as the failure reason.
- Root cause of scheduling stall: workflow scheduler handler ID mismatch.
  - `server_name` is `main.1`, but handler config used `_default_` → `is_handler=False`.
  - After setting handler ID to `main.1`, the workflow scheduler processed queued invocations.
- AI assistant now initialized with `galaxy_app` so toolbox-based fixes can run.
- Postprocessing now resolves `Repository_Actions_*` tool IDs and fixes output connections (e.g. `reads` → `out1` for fastp).
- FASTQ_TRIM_FASTP_FASTQC now transitions to `running` without immediate `output_not_found`.
- Frontend now uses sandbox Galaxy (`http://localhost:8101`) and fallback Nextflow status from `/api/invocations/:id`.
  - Added fallback to return `state` from Galaxy invocation when Nextflow endpoint is missing.
  - Verified fallback returns `new` and later `scheduled` for a new invocation.
- Switched job execution to Docker for tools but mapped `upload1` to local to avoid missing Galaxy module inside container.
- New blocker: tool containers are linux/amd64 while host is linux/arm64/v8.
  - FastQC job fails with `exec format error` due to container architecture mismatch.
  - This prevents end-to-end completion in sandbox until an arm64 tool image is used.
  - Resolved by adding `config/container_resolvers.yml` mapping fastqc/fastp to `biomate/biotools:arm64-v5` and wiring `container_resolvers_config_file` in `config/galaxy.yml`.
  - Verified `fastqc` and `fastp` run to completion using the arm64 image.
- End-to-end run (FASTQ_TRIM_FASTP_FASTQC) now executes and produces outputs (`fastp` + `fastqc`) successfully in Galaxy history.
- Remaining desync: Galaxy invocation state/steps remain `scheduled` even though datasets are `ok`.
- Frontend dev server (MemoryStore) can crash (exit 137), losing run state; after restart `/api/workflows/runs/:id/status` 404s.
- Added Nextflow status fallback to compute status from Galaxy history contents when invocation state stays `scheduled` (returns `ok` when all datasets are `ok`).
- Updated GalaxyStatePoller to use the same history-based completion logic, so `/api/workflows/runs/:id/status` now reaches `ok` with 100% progress even when invocation state remains `scheduled`.
- Switched frontend storage to DB-backed persistence (workflow invocations, outputs, execution runs).
  - Added `workflow_invocations` and `output_datasets` tables plus `execution_engine` column on `execution_runs`.
  - Added DB bootstrap in `frontend/server/db.ts` to create missing tables/columns.
  - Verified run status persists across frontend restart (`/api/workflows/runs/:id/status` returns `ok`).
- Added migration `frontend/migrations/0003_db_storage_persistence.sql` and updated journal to document DB-backed storage tables.

## Detailed TODOs (Next Actions)

### 1) Diagnose Galaxy invocation stuck at `new`
- Confirm workflow scheduler stays active after restart and monitor thread remains running.
- Verify `workflow_schedulers_conf.xml` handler ID matches `server_name` (`main.1`).

### 2) Add a Nextflow status endpoint or update frontend polling
- Option A: Implement Galaxy backend endpoint `/api/workflows/{invocation_id}/nextflow/status`.
- Option B: Update frontend Nextflow polling to use `GET /api/invocations/{invocation_id}` (Galaxy invocation state) when Nextflow endpoint is missing.
- Ensure response payload matches frontend expectations.
- Status fallback implemented in `frontend/server/routes.ts`; keep monitoring for edge cases.

### 3) Wire `parameter_input` defaults into invocation parameters
- In `frontend/server/routes.ts`, detect `parameter_input` steps and pass defaults into `invokeWorkflow` parameters.
- Confirm `tool_state` is serialized correctly for Galaxy.

### 4) Verify end-to-end execution with installed tools
- Pick a minimal workflow with installed tools and valid outputs (e.g. single FastQC).
- Validate input upload, invocation scheduling, step progression, outputs, and download.

### 5) Fix `output_not_found` in FASTQ_TRIM_FASTP_FASTQC
- Inspect step 7 output names and confirm expected output `reads`.
- Ensure parameter inputs (skip flags) and tool defaults are compatible.
- Consider updating workflow connections or tool_state defaults to produce `reads`.
  - Partially addressed by mapping to `out1`; monitor for completion and final outputs.

### 6) Fix container architecture mismatch
- Use an arm64-compatible tool image for FastQC/Fastp (e.g., update container resolver or override tool containers).
- Alternatively, install tools locally (non-container) or enable multi-arch emulation.

