# Session Restore Bug + Intermediate UI Test Fixes — 2026-05-05

## Problem 1: Workflow panel lost when browser refreshes during active run

### Symptom
User closes or refreshes BioMate while a CryoSPARC pipeline is running on AWS Batch.
After reopening and clicking the session in the sidebar:
- Welcome screen appears (no workflow panel)
- Phase cards not visible
- No polling restarts
- User sees nothing until the run appears in Run Manager

### Root Cause
The workflow panel state (`panelOpen`, `panelWorkflow`, `currentRun`) lives entirely in React memory. No effect re-hydrated it on session load. The session messages stored in localStorage had `invocationId` and `metadata.workflow`, but nothing read these on session change.

### Fix — `frontend/client/src/components/chat-with-artifacts.tsx`

**Effect 1: Session reconciliation** — fires when active chat session changes.
Scans messages newest-first for `invocationId` of a non-terminal run → calls `loadRun()` → `currentRun` restores → `startPolling` restarts.

```typescript
useEffect(() => {
    if (!currentChatSession?.id || currentRun) return;
    const messages = currentChatSession.messages ?? [];
    for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i];
        const invId = msg.invocationId || msg.metadata?.invocationId;
        if (!invId) continue;
        const vStatus = msg.metadata?.workflowViewerStatus;
        if (vStatus === 'completed' || vStatus === 'failed') continue;
        loadRun(invId).catch(...);
        break;
    }
}, [currentChatSession?.id]);
```

**Effect 2: Run restore → panel auto-open** — fires when `currentRun` is set.
When a running run is restored and the panel is closed, auto-opens it using `run.workflowDefinition`.

```typescript
if (isActive && !panelWorkflow && currentRun.workflowDefinition) {
    setPanelWorkflow(currentRun.workflowDefinition)
    setPanelOpen(true)
}
```

**Also fixed: `frontend/client/src/lib/chat-history.ts`**
Backend session API was stripping `metadata` and `invocationId` from messages when mapping them. Added:
```typescript
...(m.metadata ? { metadata: m.metadata } : {}),
...(m.invocation_id ? { invocationId: m.invocation_id } : {}),
```
Note: Galaxy backend currently doesn't store `metadata.type='workflow'` — so the panel auto-open depends on localStorage messages (which DO have metadata).

---

## Problem 2: CS-10 test was passive — no intermediate UI checks

### Symptom
CS-10 test called `pollToTerminal()` which only checked the API status every 5 seconds.
The UI was never inspected during the run. Phase cards could show nothing for 2 hours and the test wouldn't notice.

### Fix — `frontend/e2e/cryoem-stepwise-and-output.e2e.ts`

Replaced `pollToTerminal` with `pollWithLiveUIChecks`. Every 30 seconds it:
1. Counts all `[data-testid^="phase-group-"]` cards
2. Detects if panel has closed (0 cards) and tries to re-open by clicking session in sidebar
3. Logs all visible `phase-card-preview-btn-{filename}` "view" buttons per phase card
4. On FIRST appearance of milestone files, clicks "view" and asserts the correct chart renders:
   - `motion_report_batch_0000.json` → `[data-testid="motion-histogram-chart"]`
   - `ctf_report_batch_0000.json` → `[data-testid="ctf-quality-chart"]`
   - `cs_out_*_class_averages.mrc` → `[data-testid="density-map-viewer"]`
5. Warns when a `completed` phase card has 0 view buttons (data in API but missing from UI)
6. Takes a screenshot every 2 minutes

### Added data-testid to chart components

- `frontend/client/src/components/viewers/motion-histogram-chart.tsx`: `<Card data-testid="motion-histogram-chart">`
- `frontend/client/src/components/viewers/ctf-quality-chart.tsx`: `<Card data-testid="ctf-quality-chart">`
- `density-map-viewer.tsx` already had `data-testid="density-map-viewer"`

---

## Problem 3: Status endpoint missed CryoSPARC runs with only `galaxyInvocationId`

### Symptom
New CryoSPARC runs have `executionEngine='cryosparc'` and `nextflowRunId=None`.
Only `galaxyInvocationId` is set. The status endpoint's `isNextflowRun` condition
was false → no live Galaxy query → `nextflowStatus` returned empty to frontend.

### Fix — `frontend/server/routes.ts`

```typescript
const isNextflowRun =
    getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
    run.execution?.executionEngine === 'nextflow' ||
    !!run.execution?.nextflowRunId ||
    (run.execution?.executionEngine === 'cryosparc' && !!run.execution?.galaxyInvocationId);
```

Also fixed the CryoSPARC poller to use `galaxyInvocationId` as fallback for `nextflowRunId`
when fetching Nextflow status.

---

## Lesson Learned: Never restart the server while a UI test is running

The server restart at 15:10 caused the Playwright browser's React app to reload
(Vite HMR update), which wiped the in-memory panel state. The CS-10 test became
blind — API polls continued but UI checks found 0 phase cards. The panel recovery
fix (`if (phaseCardsRaw === 0) → click session`) now handles this.

---

## Current Pipeline Status (2026-05-05 ~16:00)

| Run | Status | Step |
|---|---|---|
| `07d5bd77` | running | HOMO_REFINEMENT (3 models, k1/k2/k3) |
| `f256cf20` | running | PATCH_CTF_ESTIMATION_BATCH |

Pipeline 07d5bd77 is expected to complete in ~30-60 min (after HOMO_REFINEMENT → NUR → sharpen).
CS-10 test will be re-run once both pipelines complete (to avoid LLM timeout from backend load).
