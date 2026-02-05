---
name: Merge Nextflow Into BioMate
overview: Plan to merge Galaxy Nextflow execution, AutoFix, and invocation management into BioMate, including adapting the corresponding UI, while supporting multiple execution targets (local, Slurm, AWS Batch).
todos:
  - id: inventory-map
    content: Map Nextflow runners/converters and BioMate execution stack
    status: completed
  - id: merge-backend
    content: Port Nextflow execution + AutoFix into BioMate backend
    status: completed
  - id: merge-frontend
    content: Adapt Express routes + React UI for Nextflow state/AutoFix
    status: in_progress
  - id: verify
    content: Run minimal E2E checks for Nextflow execution
    status: pending
isProject: false
---

# Merge Plan: BioMate + Galaxy Nextflow

## Goals

- Bring Nextflow execution + monitoring + AutoFix + invocation management from `galaxy_nextflow` into BioMate.
- Adapt the corresponding UI into BioMate’s React client and Express server.
- Support multiple executors (local, Slurm, AWS Batch) via config.
- Preserve Galaxy data management, uploads, and visualization by keeping outputs synced to Galaxy histories, with a soft fallback on history resolution.

## Key Integration Points

- **Execution engine & monitoring**: Nextflow runner, monitor, converters, scheduler.
- **AutoFix pipeline**: Enhanced AutoFix and fixers + API endpoints.
- **Invocation management**: create/poll/cancel/resume semantics + status streaming.
- **UI parity**: surface Nextflow run state, logs, AutoFix actions, and import workflows in BioMate UI.

## Architecture Alignment

- BioMate’s execution flow is centered on `frontend/server/routes.ts`, `frontend/server/galaxy-api-proxy.ts`, and `frontend/server/galaxy-state-poller.ts` (see `/home/yzhang/biomate/docs/01-architecture/INFORMATION_FLOW.md`).
- Galaxy Nextflow uses runner/monitor/scheduler in `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/jobs/runners/` and converters in `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/workflow/converters/`.
- AutoFix is defined in `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/ai/workflow_ops/autofix/` and exposed via `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py`.

## Plan

### 0) Nextflow-first workflow generation (NEW)

- **Goal**: When execution mode is Nextflow, search/generate **Nextflow workflows**, not Galaxy `.ga` workflows.
- **Selection strategy** (default): search-first with confidence threshold.
  - Use `UnifiedWorkflowSearch` with `format="nextflow"` and `source="nfcore"` first.
  - If score < threshold or no match, generate Nextflow via **module composition** (nf-core modules/subworkflows).
- **Generation modes**:
  1) **Reuse existing nf-core workflow** (preferred).
  2) **Compose from nf-core modules/subworkflows** using metadata constraints.
  3) **Galaxy → Nextflow conversion** fallback when no nf-core coverage.
- **Indexing depth**:
  - Index `nextflow_schema.json`, `main.nf`, `README.md`, `modules/`, `subworkflows/`.
  - Store metadata in `workflows` table; optionally add a `workflow_resources` table for full-text.

### 1) Inventory & Mapping (code-level)

- Map Nextflow execution stack to BioMate backend:
  - Runners/monitor: `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/jobs/runners/nextflow_workflow_runner.py`, `nextflow_monitor.py`, `nextflow_remote_executor.py`, `nextflow_s3_manager.py`.
  - Scheduler: `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/workflow/schedulers/nextflow.py`.
  - Converters: `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/workflow/converters/galaxy_to_nextflow_converter.py`, `nextflow_to_galaxy_converter.py`, `nextflow_pipeline_importer.py`.
- Map BioMate execution and polling surfaces:
  - API routes: `/home/yzhang/biomate/frontend/server/routes.ts`.
  - Poller/SSE: `/home/yzhang/biomate/frontend/server/galaxy-state-poller.ts`, `/home/yzhang/biomate/frontend/server/workflow-sse.ts`.
  - Client hook/panels: `/home/yzhang/biomate/frontend/client/src/hooks/useUnifiedExecution.ts`, `workflow-history-panel.tsx`, `chat-with-artifacts.tsx`.

### 2) Backend merge: Nextflow execution & invocation management

- Port Nextflow runner + scheduler into BioMate backend (`/home/yzhang/biomate/backend/lib/galaxy/...`).
- Expose unified invocation lifecycle endpoints (create/poll/cancel/retry):
  - Extend `/home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` or create dedicated API module for Nextflow invocation management.
- Wire config for multi-executor (local/Slurm/AWS Batch) into BioMate config:
  - Extend `/home/yzhang/biomate/backend/config/galaxy.yml.template` with Nextflow executor envs (aligned with `/home/yzhang/biomate/galaxy_nextflow/docs/NEXTFLOW_EXECUTOR_CONFIGURATION.md`).

### 3) Backend merge: AutoFix

- Port `EnhancedAutoFix` and fixers into BioMate backend:
  - `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/ai/workflow_ops/autofix/` → `/home/yzhang/biomate/backend/lib/galaxy/ai/workflow_ops/autofix/`.
- Expose AutoFix endpoints in BioMate Galaxy API:
  - Mirror logic in `/home/yzhang/biomate/galaxy_nextflow/lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py` for `/api/workflows/{invocation_id}/autofix`.

### 4) Frontend server integration (Express) — detailed UI data flow review

- **Current UI data flow to preserve**:
  - `ChatWithArtifacts` uses `/api/workflows/execute` and expects `invocationId` for outputs.
  - `WorkflowHistoryPanel` uses `/api/invocations` with `status`, `completedSteps`, and `outputCount`.
  - `ChatOutputAttachments` uses `/api/invocations/:id/outputs`.
  - SSE uses `/api/galaxy/workflows/sse/:workflowId/:invocationId` (Galaxy invocation ID).
- **Nextflow integration needs**:
  - Add a Nextflow invocation API that still produces a **WorkflowInvocation** record (same shape) so UI stays stable.
  - Expand `GalaxyAPIProxy` (or add a Nextflow API proxy) to fetch Nextflow job state/logs and outputs.
  - Extend `createPoller`/`WorkflowSSEManager` to support a **Nextflow poller** with the same event contract (`workflow_state`, `step_state`, `job_log`, `workflow_completed`).
  - Update `/api/invocations/:id/outputs` to handle Nextflow outputs via Galaxy history, with a soft fallback to re-resolve history ID if missing.
  - Ensure SSE updates map to BioMate invocation records using `galaxyInvocationId` (fixes progress/output desync).

### 5) Client UI adaptation — concrete components

- `**useUnifiedExecution.ts**`: add executionMode (`galaxy` | `nextflow`), expect Nextflow run IDs + map to unified run status.
- `**ChatWithArtifacts**`: allow Nextflow workflow definition to bypass Galaxy `.ga` build; pass `executionConfig` with mode.
- `**WorkflowHistoryPanel**`: display execution engine badge (Galaxy vs Nextflow) and handle Nextflow statuses.
- `**ChatOutputAttachments**`: ensure output datasets can originate from Nextflow artifacts (file links + visualization types).
- **AutoFix UI**: add action buttons and surface AutoFix results for Nextflow runs (likely a new panel or extension of outputs dialog).

### 6) Compatibility & Data Model

- Define a unified execution state model (Galaxy + Nextflow) to keep UI consistent.
- Normalize statuses: queued/running/ok/error + Nextflow-specific states.
- Ensure SSE payload shape includes Nextflow fields (logs, trace, step metrics).

### 7) Shared module reuse (generation + auditing)

- **Overlap identification**:
  - Workflow generation validation/auditing in BioMate (`workflow prerequisites`, `tool validation`).
  - Nextflow pre-run checks / AutoFix in `galaxy_nextflow`.
- **Shared module plan**:
  - Extract shared interfaces for:
    - Tool/param validation
    - Input dataset compatibility
    - Execution readiness checks
  - Create a common module (e.g., `/backend/lib/galaxy/workflow/shared_validation/`) used by both generation and Nextflow execution paths.
- **Goal**: Single source of truth for pre-execution validation logic, minimizing drift.

### 8) Verification

- Minimal E2E checks:
  - Start Nextflow run from UI → verify SSE updates + completion state.
  - Trigger AutoFix → verify response and UI rendering.
  - Execute both Galaxy-native and Nextflow workflows without desync.

## Key Files Likely to Change

- Backend:
  - `/home/yzhang/biomate/backend/lib/galaxy/jobs/runners/`
  - `/home/yzhang/biomate/backend/lib/galaxy/workflow/converters/`
  - `/home/yzhang/biomate/backend/lib/galaxy/workflow/schedulers/`
  - `/home/yzhang/biomate/backend/lib/galaxy/ai/workflow_ops/autofix/`
  - `/home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/`
  - `/home/yzhang/biomate/backend/config/galaxy.yml.template`
- Frontend server:
  - `/home/yzhang/biomate/frontend/server/routes.ts`
  - `/home/yzhang/biomate/frontend/server/galaxy-api-proxy.ts`
  - `/home/yzhang/biomate/frontend/server/galaxy-state-poller.ts`
  - `/home/yzhang/biomate/frontend/server/workflow-sse.ts`
- Frontend client:
  - `/home/yzhang/biomate/frontend/client/src/hooks/useUnifiedExecution.ts`
  - `/home/yzhang/biomate/frontend/client/src/components/workflow-history-panel.tsx`
  - `/home/yzhang/biomate/frontend/client/src/components/chat-with-artifacts.tsx`
  - `/home/yzhang/biomate/frontend/client/src/components/chat-output-attachments.tsx`

## Assumptions

- BioMate’s Galaxy backend will remain the primary execution orchestrator, with Nextflow integrated as an execution mode.
- We can reuse Galaxy Nextflow AutoFix endpoints and data formats with minimal translation.
- Multi-executor support is configuration-driven and selected per deployment.

## Decisions Needed (Captured)

- Execution target: **multi** (local + Slurm + AWS Batch).

## Detailed Next To-dos (Implementation Level)

### A) Inventory and status alignment
- Record completed Phase 1 backend merge in this plan (per `codex_work/20260203_nextflow_biomate_inventory_mapping.md` and `codex_work/20260203_backend_merge_session_log.md`).
- Record completed Phase 2 frontend routes (Express) in this plan (per inventory mapping).
- Confirm Galaxy API key location and environment usage (frontend `.env`, backend `.env`) and document as assumptions (no code change).

### B) Backend wire-up and gaps closure
- Ensure Nextflow runner and scheduler are registered and reachable from BioMate execution path (not only copied).
- Validate Nextflow converters are used by workflow conversion/import APIs (Galaxy ↔ Nextflow).
- Confirm AutoFix endpoints use BioMate invocation records and models correctly (workflow invocation linkage).
- Verify remaining absolute imports in `backend/lib/galaxy/ai/workflow_ops/**` are normalized to relative imports.
- Decide whether optional dependencies (`pulsar-galaxy-lib`, `aiohttp`) are required for targeted use cases; document gating strategy if not installing.

### C) Frontend server integration (Express)
- Verify new Nextflow AI routes are aligned with Galaxy Nextflow endpoints and return consistent shapes for UI consumption.
- Implement/verify a Nextflow execution endpoint that still writes a BioMate `WorkflowInvocation` record with unified status.
- Implement/verify Nextflow log proxy endpoint for AI ops panels.
- Confirm SSE event mapping uses `galaxyInvocationId` first (per `codex_work/20260203_modifications_log.md`).

### D) Frontend client integration (React)
- Add execution engine badge and status mapping in `frontend/client/src/components/workflow-history-panel.tsx`.
- Extend `frontend/client/src/hooks/useUnifiedExecution.ts` to accept `executionMode` and normalize Nextflow status values.
- In `frontend/client/src/components/chat-with-artifacts.tsx`, allow Nextflow workflows to bypass Galaxy `.ga` generation and pass execution mode.
- In `frontend/client/src/components/chat-output-attachments.tsx`, support Nextflow outputs as artifacts with consistent metadata.
- Add a Nextflow AutoFix affordance in workflow run details or outputs dialog.

### E) UI/Backend parity (Galaxy Nextflow features)
- Map `galaxy_nextflow` UI endpoints to BioMate equivalents and list gaps:
  - `ai/analyze`, `ai/analyze_detailed`, `ai/query`, `ai/apply_fix`, `ai/agent/dispatch`, `ai/analyze_parameters`, `ai/analyze_resources`, `ai/info`.
- Decide minimum parity set for BioMate UI and document which endpoints are supported.

### F) Nextflow-first workflow generation
- Adjust `UnifiedWorkflowSearch` and workflow generator to prefer `format=nextflow` when execution mode is Nextflow.
- Extend nf-core indexing to store `nextflow_schema.json`, `main.nf`, `modules/`, `subworkflows/` metadata.
- Add Galaxy `.ga` → Nextflow DSL2 conversion fallback if no nf-core matches are found.

### G) Verification and tests
- Add minimal integration tests for Nextflow execution, monitoring, and AutoFix endpoints.
- Add UI-level checks for status/output consistency and SSE updates for both Galaxy and Nextflow.
- Re-run isolated Nextflow integration tests and record results in codex_work logs.
 - Verify Nextflow outputs appear in Galaxy histories and visualize correctly; fallback only re-resolves history ID (no filesystem reads unless explicitly required).

