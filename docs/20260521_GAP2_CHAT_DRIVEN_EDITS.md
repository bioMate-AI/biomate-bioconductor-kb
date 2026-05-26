# Gap 2 — Chat-Driven Param / Step Edits Write Back to Panel

**Status:** Open
**Owner:** unassigned
**Opened:** 2026-05-21
**Related:** Gap 1, Gap 3

## Problem

Users naturally type things in chat like "change pH to 7.4" or "add a docking step after rnaseq". Today:

- **Param changes via chat don't reach the panel.** `onParameterChange` (frontend/client/src/components/nextflow-workflow-viewer.tsx:1267) bubbles panel-side edits up to `chat-with-artifacts.tsx`, but the reverse path — chat message → mutate panel artifact — is not wired. The user has to find the field in the panel and edit it by hand.
- **Step additions are not supported at all.** The workflow object is immutable after generation. `pipeline-list-view.tsx:482` shows aspirational hint text ("Chat to edit: 'add GSEA after step 3'") but there is no `onAddStep` handler and no splice path in the panel. The only way to change structure is to regenerate the workflow from scratch.

## Goal

Natural-language edits in chat update the open workflow artifact in place. Param edits apply automatically; structural edits (add/remove/reorder steps) require a one-click confirm.

## Approach

**Structured edit ops emitted by the assistant, applied by a reducer on the workflow artifact.**

The LLM, after composing its text reply, runs a second short structured-output pass to emit a list of `WorkflowEdit` ops if the user's last message implied any. The frontend applies them via a pure reducer, producing a new artifact object that the panel re-renders from.

## Steps

1. **Define the edit-op schema** in `shared/schema.ts`:
   ```ts
   type WorkflowEdit =
     | { op: 'set_param'; stepId: string; paramName: string; value: unknown }
     | { op: 'add_step'; afterStepId: string | null; workflowPath: string; params?: Record<string, unknown> }
     | { op: 'remove_step'; stepId: string }
     | { op: 'reorder'; stepId: string; beforeStepId: string }
   ```
   Attach to assistant messages as `message.metadata.workflowEdits: WorkflowEdit[]` and `editsTargetMessageId: string` (which prior workflow artifact they apply to).

2. **Backend extraction.** In `backend/lib/galaxy/ai/ai_assistant.py`, after the main LLM reply, run a Haiku call with the current workflow JSON + last user message: "Return any edit ops implied by the user, else `[]`." Validate each op against the workflow schema in `backend/database/galaxy_ai_tools.db` (step exists, param exists, value in allowed_values). Drop invalid ops with a logged warning.

3. **Frontend reducer.** Add `applyWorkflowEdits(workflow, edits): Workflow` in `frontend/client/src/lib/workflow-edits.ts`. Pure function, no side effects. For `add_step`, look up `required_params` from the workflow DB via `/api/ai_assistant/workflow_meta?path=...` so the user doesn't have to specify them in chat.

4. **Apply on message arrival.** In `chat-with-artifacts.tsx`, when a new assistant message lands carrying `workflowEdits` and a matching `editsTargetMessageId`, run the reducer and `setPanelWorkflow(newArtifact)`. The panel re-renders.

5. **Confirm-before-apply for structural ops.** `set_param` auto-applies. `add_step` / `remove_step` / `reorder` render a chip in chat ("Add VINA_DOCK after rnaseq? [Apply] [Discard]"). On apply, mutate the artifact; on discard, drop the op.

6. **Show a diff card.** After any apply, render a small chip near the next progress line: "+ Added VINA_DOCK after step 3" / "pH: 7.0 → 7.4". One-deep undo restores the prior artifact.

7. **E2E.** New test `frontend/e2e/chat-edits-panel.e2e.ts`:
   - Open a docking workflow in the panel
   - Send "change exhaustiveness to 16" → assert the panel input now shows 16, no new workflow card emitted, one diff chip shown
   - Send "add a docking step" → assert a confirm chip appears, click Apply, assert step list grows by one

## Files Touched

| File | Change |
|---|---|
| `shared/schema.ts` | Add `WorkflowEdit` type + message metadata fields |
| `backend/lib/galaxy/ai/ai_assistant.py` | Add edit-extraction Haiku pass + schema validation |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | New endpoint `/api/ai_assistant/workflow_meta` for params lookup |
| `frontend/server/routes.ts` | Pass `workflowEdits` through unchanged |
| `frontend/client/src/lib/workflow-edits.ts` | New reducer file |
| `frontend/client/src/components/chat-with-artifacts.tsx` | Apply reducer on message arrival; render confirm/diff chips |
| `frontend/e2e/chat-edits-panel.e2e.ts` | New test |

## Risks

- **LLM hallucinates ops on innocuous messages.** ("Thanks!" → `set_param`?) Mitigation: the extractor prompt explicitly requires the op to be unambiguously implied by an imperative; return `[]` otherwise. Validate against schema before applying.
- **Race with a running execution.** User edits params while the workflow is running. Mitigation: if `currentRun?.status === 'running'`, reject `set_param` ops with a chat message ("Run is in progress — edits will apply after restart").
- **Add_step needs upstream/downstream wiring.** The new step likely consumes the previous step's output. Mitigation: `applyWorkflowEdits` infers `usesStepId` from `afterStepId` for now; do not try to auto-rewire complex DAGs in v1.

## Out of Scope (v1)

- Multi-step compound edits in one chat turn (do it sequentially)
- DAG reordering beyond linear
- Undo stack deeper than 1

## Done When

- [ ] Schema + types committed
- [ ] Backend extractor returns valid ops on a 10-case fixture
- [ ] Reducer unit tests pass (12+ cases)
- [ ] `set_param` round-trip works in dev
- [ ] `add_step` confirm chip works in dev
- [ ] E2E green
