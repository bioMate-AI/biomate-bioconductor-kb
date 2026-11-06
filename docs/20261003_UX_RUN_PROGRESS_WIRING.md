# UX: Wire live run-progress into the workflow run panel (Thread A)

**Date:** 2026-10-03
**Scope:** `frontend/client/src/components/nextflow-workflow-viewer.tsx` (+ new hook)
**Gaps closed:** `docs/20260310_EXECUTION_TRACING_UX_GAPS.md` Gaps 3 & 4 (and partial 1).
**Plan:** `docs/20261003_PARALLEL_WORKSTREAM_PLAN.md` Thread A.

## Problem

The backend endpoint `/api/workflows/{invocationId}/realtime/status` already exists
(Node proxy at `frontend/server/routes.ts:4426` → Galaxy
`autofix3.get_workflow_realtime_status`, which reads `nextflow_monitor`'s
`latest.json` plus in-memory AutoFix sessions). **No frontend code called it.**
The run panel showed only per-step status (per-step polling of
`/api/workflow/step/:id/status`), with no aggregate progress, no elapsed time,
no recent logs, and no AI autofix/issue visibility. The top progress bar had been
removed in the 2026-06-19 UX review.

## What changed

### New file — `frontend/client/src/components/useRealtimeRunStatus.ts`
A small polling hook:
- Polls `/api/workflows/<invocationId>/realtime/status` **only while a run is
  active** and an `invocationId` is present.
- Fires once immediately, then every **5 s** (`intervalMs` default).
- **Stops** (clears the interval) the moment `active` flips false — the caller
  passes `active = false` on terminal states (completed/failed/idle), so polling
  halts automatically on terminal state.
- **Degrades gracefully**: a 404 / network error / malformed body never throws
  and never clobbers previously-good data with `null`. Normalizes the payload
  (`issues`, `autofix`, `restart_info`, optional future `recent_logs`,
  `has_data`) with defensive type guards.

### `nextflow-workflow-viewer.tsx`
- Import the hook; compute `runActive = status === 'running' || status === 'paused'`
  and call `useRealtimeRunStatus(invocationId, runActive)` at top level
  (unconditional — hook-safe).
- **Elapsed clock**: a `runStartRef` + 1 s `nowTick` ticker that starts from
  `nextflowStatus.started_at` (unix seconds) when available, else wall-clock at
  first running; frozen and reset when not active.
- **Live-progress block** rendered at the top of the **Phases** tab (active runs
  only, `runActive && groupedPhases.length > 0`):
  1. **Overall progress** — reuses the existing `.run-bar/.progress/.fill` CSS; shows
     `completed/total` steps (derived from `updatedPhases`) and `%`
     (`completedSteps/totalSteps`, falling back to `effectiveProgress`).
  2. **Current phase/step** — the first `updatedPhases` entry with status `running`.
  3. **Elapsed time** — `formatDuration()` (new module-level helper).
  4. **Collapsible details** (`progressDetailsOpen`) — recent log lines
     (prefers backend `recent_logs` if present, else the SSE `log_tail` the panel
     already holds in `logs`, last 40) **+ AI autofix state** (fixes-applied /
     active chip, detected-issues list with severity + auto-fixable flag, and a
     restart chip when the run was restarted with a new invocation id).
- A new module-level `formatDuration(ms)` helper.
- New `data-testid` hooks (additive): `live-run-progress` (carries its own
  `data-status` + `data-progress-pct`), `live-progress-pct`,
  `live-progress-steps`, `live-progress-current`, `live-progress-elapsed`,
  `live-progress-autofix-chip`, `live-progress-issues-chip`,
  `live-progress-restart-chip`, `live-progress-details-toggle`,
  `live-progress-details`, `live-progress-log`.

### `styles/workflow-panel.css`
Added a themeable `.live-progress*` block (reuses existing CSS custom properties;
light/dark safe).

### `locales/en/common.json`, `locales/zh/common.json`
Additive only: a `panel.live.*` sub-tree and a `workflow.status.paused` key
(EN + idiomatic ZH). No existing keys changed.

## Constraints honoured
- **Did NOT edit `frontend/server/routes.ts`** — proxy already existed (owned by Thread B).
- **No `sync_to_dev.sh`**, **no Batch/cloud run dispatched**.
- Preserved the existing `data-status` test hooks (overall badge, phase cards) and
  the 3-tab structure — the live block is purely additive.
- No Artifact tool used; doc lives under `docs/`.
- Committed with an explicit file list (no `git add -A`).

## Verification
- `cd frontend && npx tsc --noEmit -p .` → **exit 0** (clean).
- `cd frontend && npx vitest run` → **1630 passed, 17 skipped, 4 failed**.
  - The viewer's own suite `nextflow-workflow-viewer.test.tsx` → **all 31 pass**.
  - The 4 failures are **pre-existing and unrelated** to this change:
    `cold-start-dashboard.test.tsx` (lane-label copy), `design-generate/DesignGenerate.test.tsx`
    (fabrication-message copy), `server/cold-refresh-recovery.test.ts` and
    `server/ltm-session-bridge.test.ts` (both regex-grep server source files —
    `routes.ts` / chat-stream — not touched here). Verified none of the 4 test
    files reference any file modified by this change, and the locale edits are
    additive keys that cannot alter existing lookups.

## Notes / follow-ups
- The backend `realtime/status` payload currently carries `status`, `issues`,
  `autofix`, `restart_info` — **not** raw log lines. The "recent logs" shown come
  from the SSE `log_tail` the panel already receives; the hook reads a
  `recent_logs` field **if** the backend adds one later (Gap 1 proper streaming),
  with zero frontend change required.
- Live Batch verification of the progress transitions is compute-gated and
  deferred to the owner per the parallel-workstream plan.
