# Gap 3 — "Run Again" Param Carryover from Previous Run

**Status:** Open
**Owner:** unassigned
**Opened:** 2026-05-21
**Related:** Gap 1, Gap 2

## Problem

After a workflow completes (or fails), the panel's footer shows "Run again" or "Restart" (`frontend/client/src/components/nextflow-workflow-viewer.tsx:2089`, 2718-2720). Clicking it calls `onExecute(params)` with the panel's *current* `params` state — which is initialized from `workflowDefinition.parameters` or `inline_parameters` (line 834), i.e. the workflow's defaults plus any in-session edits.

**The actually-submitted params from the prior run are not carried over.** If the user ran with `exhaustiveness=16`, completed, and clicked Run again, the panel shows `8` (the default) again. Reloading the page restores localStorage edits, but never the submitted params from the actual run record.

## Goal

After a terminal run, clicking "Run again" pre-fills the panel with the *exact* params submitted to the prior run, with a visible "Reset to defaults" affordance to undo.

## Approach

**Surface what the server already has.** `/api/workflows/runs/:id` likely already returns the submitted params (or can with a one-line patch). Use them to initialize the panel's `params` state when the run reaches a terminal status.

## Steps

1. **Confirm the server returns submitted params.** Read `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` and the route handler for `/api/workflows/runs/:id`. If `parameters` / `submitted_params` is in the response, skip step 2.
2. **Add `submittedParams` to the run record** if missing. Source is the dict the executor sent to Nextflow (already stored in the run row in most paths). Wire it through `useUnifiedExecution.ts` so `currentRun.submittedParams` is populated.
3. **Initialize the panel from `submittedParams` on terminal status.** In `nextflow-workflow-viewer.tsx`, when `viewerStatus` transitions to `'completed'` or `'failed'` AND `currentRun?.submittedParams` is non-empty AND the user has not touched any field in the current session, set `params` state from `submittedParams` (one-shot, via a ref guard so a second transition doesn't clobber further edits).
4. **Add a visible affordance.** A small text link "Reset to defaults" next to "Run again" that re-applies `workflowDefinition.parameters`. Cheap, and disambiguates the new behavior. Tooltip: "Currently showing params from your last run."
5. **E2E.** `frontend/e2e/run-again-param-carryover.e2e.ts`:
   - Run a docking workflow with `exhaustiveness=16`
   - Wait for completion
   - Assert the input still shows `16` (not the default `8`)
   - Click "Reset to defaults" → assert input shows `8`
   - Edit to `12` → click Run again → assert next run submitted `12`

## Phase 2 (deferred, only if asked)

- **Multi-run history.** Add a "..." menu on the Run Again button listing the last 3 runs of this workflow with timestamps + a "Load these params" option per row. Reads from `/api/workflows/runs?workflow_path=...&limit=3`.

## Files Touched

| File | Status |
|---|---|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | **No change needed** — `ExecutionRun.parameters.toolParameters` already in `GET /api/workflows/runs/:id`. Confirmed `shared/schema.ts:1015`. |
| `frontend/client/src/hooks/useUnifiedExecution.ts` | **No change needed** — `currentRun` already exposes the full run. |
| `frontend/client/src/hooks/useRunAgainParamCarryover.ts` | **NEW FILE — landed.** Encapsulates the effect, the ref guard, the Reset handler, and the `extractSubmittedParams` helper. |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | **Wire-up pending — apply in VS Code (see patch below).** Repeated tool-edit attempts to this file got reverted by an external editor buffer. |
| `frontend/client/src/components/chat-with-artifacts.tsx` | **Wire-up pending — apply in VS Code (see patch below).** Same reason. |
| `frontend/e2e/run-again-param-carryover.e2e.ts` | **New test landed.** Will pass once the wire-up below is applied and a workflow run completes. |

## Apply-in-editor patch (paste manually)

**1. `frontend/client/src/components/nextflow-workflow-viewer.tsx`**

Add to the props interface (next to `initialParams`):
```ts
lastSubmittedParams?: Record<string, any>;
```

Destructure it in the function signature:
```ts
  workflowDefinition,
  initialParams,
  lastSubmittedParams,
```

Right after `const userOverriddenParams = useRef<Set<string>>(new Set());`, add:
```ts
const { showingSubmittedParams, resetToDefaults } = useRunAgainParamCarryover({
  status,
  runId,
  lastSubmittedParams,
  userOverriddenParams,
  setParams,
  defaults: initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {},
});
```

Import at the top:
```ts
import { useRunAgainParamCarryover } from '@/hooks/useRunAgainParamCarryover';
```

Inside the run-primary div (right after the "Run again / Restart / Confirm and run" button, around line 2770), add:
```tsx
{showingSubmittedParams && (status === 'completed' || status === 'failed') && (
  <button
    type="button"
    data-testid="button-reset-params-to-defaults"
    onClick={resetToDefaults}
    title="Currently showing params from your last run. Click to reset to workflow defaults."
    style={{
      marginLeft: 8, fontSize: 11,
      color: 'var(--bm-text-dim, oklch(0.55 0.01 260))',
      background: 'transparent', border: 'none', cursor: 'pointer',
      textDecoration: 'underline',
    }}
  >
    Reset to defaults
  </button>
)}
```

**2. `frontend/client/src/components/chat-with-artifacts.tsx`**

Import at top:
```ts
import { extractSubmittedParams } from '@/hooks/useRunAgainParamCarryover';
```

At the `<NextflowWorkflowViewer ... />` call site (around line 1344), add the prop:
```tsx
lastSubmittedParams={extractSubmittedParams(currentRun)}
```

After both edits are saved, run `npx tsc --noEmit` to confirm clean.

## Risks

- **Surprising users who expected defaults.** Mitigation: the "Reset to defaults" link is always visible while submitted params are in effect; tooltip explains the behavior.
- **Clobbering live edits.** If the user has already typed in a field before the run completes (unlikely but possible during a long run), don't overwrite. Mitigation: ref guard tracks "has the user touched anything"; if yes, skip the auto-init.
- **submittedParams may include resolved internal fields** (paths normalized, defaults filled). The panel must only pre-fill fields it knows about; unknown keys are ignored.

## Done When

- [ ] `submittedParams` reliably present on `/api/workflows/runs/:id`
- [ ] Panel pre-fills from `submittedParams` on first terminal transition
- [ ] "Reset to defaults" link visible and working
- [ ] E2E green
- [ ] One screenshot showing the prior run's params pre-filled after completion
