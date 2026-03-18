# Run Manager Panel Implementation and Gap Analysis

Timestamp: 2026-03-01 12:36

## User question addressed

Question:
- If Galaxy-Nextflow already supports multi-workflow execution, why was a Run Manager not already visible in BioMate UI?
- What exactly was missing?

Answer summary:
- Multi-run capability existed in backend and orchestration layers.
- Main chat UI remained single-active-run oriented (`currentRun` focus).
- Missing piece was UI wiring for discoverability + quick run-context switching.

## What existed before this change

### 1) Backend / orchestration readiness (already present)

- Nextflow executor can launch and track multiple background runs.
- BioMate server tracks multiple execution runs via `/api/workflows/runs`.
- Poller/SSE infra supports concurrent invocation polling.
- Execution APIs already include listing and loading runs.

### 2) Frontend state model gap

- Main chat flow (`chat-with-artifacts`) primarily tracks one `currentRun`.
- No visible run queue/list in primary chat surface.
- Users had no quick “switch to another run context” action.
- Result: backend concurrency existed, but UX did not surface it as a first-class multitask experience.

## Implementation delivered

### File changed

- `frontend/client/src/components/chat-with-artifacts.tsx`

### New Run Manager UI

Added header actions:
- `Run Manager` toggle button (`data-testid="button-toggle-run-manager"`)
- refresh button (`data-testid="button-refresh-run-manager"`)

Added panel:
- `data-testid="run-manager-panel"`
- 4 grouped buckets:
  - `running`
  - `queued`
  - `failed`
  - `completed`
- each run card:
  - workflow name
  - status
  - updated/created time
  - click to switch (`loadRun(run.id)` from unified execution hook)

### Data and refresh behavior

- Uses `/api/workflows/runs?limit=50`.
- Refreshes every 10 seconds + manual refresh button.
- Displays fetch errors inline in panel.

### Quick switch behavior

- Clicking a run triggers `loadRun(runId)`.
- Emits telemetry event `workflow.run_switched`.
- Updates active run context used by execution status surfaces.

## Why this was not already visible “just because Galaxy has it”

Galaxy internals and BioMate UX are separate layers:

1. Galaxy/Nextflow provides execution and state primitives.
2. BioMate server proxies and tracks execution records.
3. UI must explicitly implement multitask affordances.

Previously layer (3) was incomplete in the main chat flow.

## Validation

### Lint

- No linter errors in updated file.

### Build

- `npm run build` passed.

### E2E regression

- `ux-autofix-gate.e2e.ts` PASS
- `feedback-real-ui-strict.e2e.ts` PASS
- `pm-user-stories-comprehensive.e2e.ts` PASS
- matrix result: SUCCESS
- artifact:
  - `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_123158.txt`

## Remaining gaps (important)

1. Run list is user/project scoped by existing API behavior, but chat-session-specific mapping remains weak (`chatSessionId` not fully persisted for run creation in current storage path).
2. “What can I do while this runs?” proactive assistant prompt is still not implemented.
3. No dedicated E2E yet for run switching interaction itself (only regression coverage currently).

## Recommended next step

1. Persist and use `chatSessionId` in execution runs for tighter run-context filtering.
2. Add proactive background-assist prompt when long-running execution detected.
3. Add deterministic `ux-run-manager-switch.e2e.ts`.

