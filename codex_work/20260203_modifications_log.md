# Modifications Log - 2026-02-03

## Scope
- Workflow status/output desync in BioMate UI due to invocation ID mismatch.

## Changes

### 1) `frontend/server/workflow-sse.ts`
- Updated SSE handlers (`workflow_state`, `step_state`, `workflow_completed`) to resolve BioMate invocation records by `galaxyInvocationId` first, then fall back to direct `invocation_id`.
- This ensures SSE updates target the correct `WorkflowInvocation` record created by `/api/workflows/execute`, which uses a different UUID than Galaxy’s invocation ID.

## Rationale
- The unified execution flow creates a new `WorkflowInvocation.id` while Galaxy emits SSE events keyed by its own invocation ID.
- Previously, SSE updates attempted to update `storage` using the Galaxy ID directly, leading to stale status/progress and missing outputs in the UI.
- Resolving by `galaxyInvocationId` fixes the desync without changing API response shapes.

## Plan Update
- Added an explicit note in the plan to ensure SSE updates map to BioMate invocation records using `galaxyInvocationId`.

