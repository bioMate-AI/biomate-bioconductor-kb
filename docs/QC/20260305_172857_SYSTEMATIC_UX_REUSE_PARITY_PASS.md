# Systematic UX Reuse Parity Pass

**Timestamp:** 2026-03-05 17:28:57 CST  
**Goal:** Reuse existing Galaxy/Galaxy-Nextflow abilities in the active chat UX surface, and verify with automated checks.

---

## Scope and Method (Systematic)

1. Identify the **active renderer path** used by real chat users.
2. Map missing capabilities to existing implementations already present in the repo.
3. Wire those capabilities into the active renderer.
4. Add an automated parity check test so missing surfaces fail quickly.
5. Run real E2E execution test to validate no regression on core flow.

---

## Active Path Confirmation

- Active chat path renders `NextflowWorkflowViewer` (not `WorkflowArtifact`) in:
  - `frontend/client/src/components/chat-message.tsx`
- This explains why controls implemented only inside `WorkflowArtifact` were not visible to users.

---

## Capability Reuse Mapping and Implementation

| Capability | Existing implementation reused | Active UX wiring result |
|---|---|---|
| Pause/Resume/Cancel run actions | `useUnifiedExecution` pause/resume/cancel API methods; `/api/workflows/runs/:id/pause|resume|cancel` routes | Added controls to `NextflowWorkflowViewer`; callbacks wired through `chat-message` → `chat-interface` → `chat-with-artifacts` |
| Restart run action | Existing execute workflow path (`onExecute`) reused for rerun trigger | Added visible restart control in active card (reruns using same execution path) |
| Parameter visibility/editability | Existing workflow parameter payload (`workflowDefinition.parameters` / `inline_parameters`) | Replaced hardcoded placeholder params with dynamic parameter extraction and rendering |
| Autofix status visibility | Existing `currentExecutionRun.execution.nextflowStatus.autofix` propagation | Added explicit `autofix-status-panel` in active card (state/attempts/source/message) |

---

## Files Updated

- `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - Added dynamic parameter extraction from workflow payload.
  - Added run controls (run/pause/resume/restart/cancel).
  - Added explicit auto-fix status panel.
- `frontend/client/src/components/chat-message.tsx`
  - Added `onPauseWorkflow` / `onResumeWorkflow` pass-through.
  - Extended viewer status handling to include `paused`.
- `frontend/client/src/components/chat-interface.tsx`
  - Threaded pause/resume callbacks into message rendering path.
- `frontend/client/src/components/chat-with-artifacts.tsx`
  - Wired pause/resume handlers to `useUnifiedExecution.pauseRun/resumeRun`.
  - Added telemetry events for pause/resume clicks.
- `frontend/e2e/ux-capability-parity.e2e.ts` (new)
  - Deterministic parity test for active viewer controls + parameter keys.

---

## Verification Results

### 1) Capability parity check (deterministic)

Command:

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5421 npx playwright test e2e/ux-capability-parity.e2e.ts --project chromium
```

Result:

- **1 passed**
- Confirms active card renders:
  - run/pause/resume/restart/cancel controls
  - workflow-derived parameters (`Reference Genome`, `Threads`, `Min Particle Diameter`)

### 2) Real execution flow regression check

Command:

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5421 npx playwright test e2e/complete-workflow.e2e.ts --project chromium
```

Result:

- **1 passed**
- Workflow executed to terminal completion with output visualizable/downloadable checks passing.

---

## Remaining Known Gaps

1. Restart currently reuses execute path; deeper engine-native restart lineage can be improved.
2. Pause/resume route semantics currently update execution run state and interaction history; deeper runtime-level pause/resume guarantees may need tighter Nextflow process control semantics.
3. Parameter typing is inferred from current values; richer required/optional/default schema can be surfaced when backend provides explicit contracts.

---

## Outcome

This pass moved missing user-facing controls/parameter visibility from dormant components into the **actual live chat workflow card**, with automated parity checks to reduce silent regression.
