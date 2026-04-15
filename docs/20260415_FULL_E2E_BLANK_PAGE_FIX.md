# Full E2E Blank Page Fix — 2026-04-15

## Problem

All 7 failing tests in `e2e/full-workflow-e2e.e2e.ts` exhibited the same symptom:
**the React app page goes blank** immediately after (or during) `pollRunToCompletion` returning a terminal status.

Confirmed via screenshot evidence:
- Pre-execution screenshots (e.g., `05_terminal_status`, `uc5_workflow_card`): 200-340KB — normal content
- Post-completion screenshots (e.g., `06_completion_banner`, `uc3_after_completion`): exactly **8514 bytes** — completely blank white page

The blank pages all have URL `http://localhost:5000/` — no navigation occurred, but the React component tree was rendering nothing.

## Root Cause

Two bugs in `frontend/client/src/hooks/useUnifiedExecution.ts`, in the polling `setState` updater (the else branch, line ~488):

### Bug 1: Side effect inside setState updater (primary crash cause)

```typescript
// BEFORE (broken)
setState((prev) => {
  if (prev.currentRun && prev.currentRun.id !== runId) return prev;  // wrong guard

  if (['completed', 'failed', 'cancelled'].includes(status.status)) {
    emitUxEvent('workflow.status_changed', {
      runId,
      workflowId: prev.currentRun!.execution.galaxyWorkflowId,   // ← CRASH if null
      invocationId: prev.currentRun!.execution.galaxyInvocationId, // ← CRASH if null
      status: status.status,
    });
  }

  if (!prev.currentRun) return prev;  // too late — already crashed above
  ...
```

`emitUxEvent` calls `fetch` (a side effect) inside a React setState updater, violating React's purity constraint. More critically, the guard `prev.currentRun && prev.currentRun.id !== runId` passes through when `prev.currentRun` is null (because `null && X` is falsy, not a return), then `prev.currentRun!.execution` throws `TypeError: Cannot read properties of null`. React has no error boundary → entire component tree unmounts → blank page.

### Bug 2: Wrong null guard

The original guard `if (prev.currentRun && prev.currentRun.id !== runId) return prev` only returns early if there's a DIFFERENT run; it doesn't protect against null currentRun.

## Fix Applied

**File:** `frontend/client/src/hooks/useUnifiedExecution.ts`

```typescript
// AFTER (fixed)
} else {
  // Emit status-change telemetry OUTSIDE the updater (side effects don't belong in setState)
  if (['completed', 'failed', 'cancelled'].includes(status.status) && currentRunRef.current) {
    emitUxEvent('workflow.status_changed', {
      runId,
      workflowId: currentRunRef.current.execution.galaxyWorkflowId,  // safe via ref
      invocationId: currentRunRef.current.execution.galaxyInvocationId,
      status: status.status,
    });
  }

  setState((prev) => {
    // Guard: skip if no current run OR if it's a different run
    if (!prev.currentRun || prev.currentRun.id !== runId) return prev;

    return {
      ...prev,
      currentRun: {
        ...prev.currentRun,
        execution: { ...prev.currentRun.execution, status: status.status, ... }
        ...
      },
    };
  });
}
```

Changes:
1. Moved `emitUxEvent` **outside** the setState updater — called using the safe `currentRunRef.current` ref
2. Changed guard from `prev.currentRun && prev.currentRun.id !== runId` to `!prev.currentRun || prev.currentRun.id !== runId` — now correctly handles null case

## Test Results After Fix (Run 3, 2026-04-15 ~13:00)

| Test | Before Fix | After Fix |
|------|-----------|-----------|
| ADMET Full Execution Flow | FAIL (blank) | FAIL (banner not visible — different issue) |
| AWAITING REVIEW UX | FAIL (blank) | FAIL (execute API error — different issue) |
| UC-3: Per-step output | FAIL (blank) | FAIL (blank — partial fix) |
| UC-4: Checkpoint visibility | PASS ✓ | PASS ✓ |
| UC-5: Interactive tool launcher | FAIL (blank) | **PASS ✓** (phase cards=4) |
| UC-6: Detach/Reconnect | in progress | in progress |
| UC-7: Download Commands | in progress | in progress |
| UC-2: Pilot Run | in progress | in progress |

Key improvement: **UC-5 now passes** — `uc5_after_completion.png` is 313KB (was 8514 blank).

## Remaining Issues

### UC-3 still blank after fix

`uc3_after_completion.png` is still 8514 bytes (blank) despite the same fix that makes UC-5 pass. Both tests run the same ADMET query. Potential cause: test execution order — UC-3 runs right after UC-2 which failed mid-execution. Possible React/browser state contamination from the previous test failing.

### ADMET banner not showing

Even when the page doesn't crash, `currentRun.execution.status` is not updating to 'completed' in the React state. The PostRunMicroSurvey doesn't fire (no "feedback modals" detected), confirming React never sees 'completed'. This means the else-branch setState guard `!prev.currentRun` is returning early — `prev.currentRun` IS actually null at the moment the poll fires with terminal status. The root cause of *why* `prev.currentRun` is null when `currentRunRef.current` is non-null is still under investigation.

### AWAITING REVIEW UX execute error

Test 2 fails at `clickConfirmAndCaptureRunId` — the execute API returns non-200. This may be a backend issue (e.g., duplicate execution attempt, AWS Batch quota).

## Files Modified

- `frontend/client/src/hooks/useUnifiedExecution.ts` — polling null guard + side effect cleanup

## Next Steps

1. Determine why `prev.currentRun` is null inside the else-branch setState when `currentRunRef.current` is non-null
2. Add a fallback: if the else-branch update is skipped (null guard hit), still ensure `stopPolling` doesn't permanently halt status updates
3. Fix AWAITING REVIEW UX execute failure (backend)
4. Re-run full E2E suite after additional fixes
