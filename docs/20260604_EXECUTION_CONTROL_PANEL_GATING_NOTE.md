# `ExecutionControlPanel` is dead code in production today

**Date:** 2026-06-04
**Status:** Active — until somebody flips `useUnifiedExecution={true}`

## TL;DR

`frontend/client/src/components/execution-control-panel.tsx` (762 lines, the
"Unified Execution Control Panel" — sandbox/production mode toggle, tunable
data scope, inline param edit, QC overrides) exists in the codebase, gets
imported by `workflow-artifact.tsx`, but never renders to a user.

It is gated by `useUnifiedExecution={true}`. That prop defaults to `false`
at `workflow-artifact.tsx:160`. No caller anywhere in `frontend/client/src/`
overrides it. The conditional render at `workflow-artifact.tsx:1625`:

```tsx
{(showUnifiedExecution || currentExecutionRun) && useUnifiedExecution && (
  <ExecutionControlPanel ... />
)}
```

…is therefore always `... && false && (...)`. esbuild's dead-code
elimination removes the entire JSX subtree from the production bundle.
Verified empirically: the build output has 0 hits for `qc-settings-section`,
`"Pause at QC"`, `"Threshold Overrides"`, `renderQcSettings` — all the
literal strings + symbol names that are only referenced from inside the
panel. (Other `data-testid` strings unrelated to the panel are preserved,
so this is not a generic build-tool stripping issue.)

## What actually renders in production

The execution UI a user sees today is in
`frontend/client/src/components/nextflow-workflow-viewer.tsx`:

- Phase cards (one per workflow process)
- Per-phase QC blocks (`className="qc-block"`,
  `data-testid="qc-edit-toggle-${group.key}"`)
- Event-driven `qc-gate-inline` alert when a gate fires mid-run
- `qc-report-panel` summary

These render once the run starts and a phase with QC thresholds enters
the `running` state. They do NOT render at the "params panel visible"
moment before the user clicks Run — there is no static "QC settings"
configuration UI in the current production flow.

## Why this matters

1. **Tests written against `ExecutionControlPanel` testids will fail
   no matter what testids you add to the source.** The source survives
   in git; the bundle does not. Specifically the HT-1 assertion
   `frontend/e2e/hts-workflows-ux-e2e.e2e.ts:351` (originally written
   against `[data-testid="qc-settings-section"]`) cannot pass under
   the current build. Commit `7e5d392cd` retargets it to accept either
   the unified-panel OR the phase-QC block, so it gives honest telemetry
   instead of a stuck red.

2. **Design docs that describe the right panel as containing
   `ExecutionControlPanel` are aspirational.** Two docs flagged with
   status banners (commit pending):
   - `docs/20260310_WORKFLOW_UX_SIMPLIFICATION.md`
   - `docs/20260310_TEAM_SHARE_CHAT_QUEUE_AND_TASK_ORCHESTRATION.md`

3. **`useUnifiedExecution.ts` (the hook) is unrelated and IS live.** It
   powers the polling state for `currentExecutionRun` regardless of
   whether the panel renders. Docs that reference the hook are
   correct.

## To enable the panel

Find every render of `<WorkflowArtifact>` inside the chat-with-artifacts
tree and pass `useUnifiedExecution={true}`. Then:

- Validate the panel actually works against today's backend (the design
  predates several executor changes; some props may need updating).
- Check that the old "Pilot Run" button branch (`workflow-artifact.tsx:763`,
  `1222`) doesn't conflict — the two flows currently coexist behind the
  same conditional.
- Run the full E2E suite — the HT-1 assertion will start logging
  `"unified-panel"` in its note instead of `"phase-qc-block"` or `"neither
  unified panel nor phase QC block rendered"`.

## Git references

- `99946bd86` (2026-01-16) — `ExecutionControlPanel` added
- `324297d45` (2026-03-01) — major UI enhancements
- `f6bce7011` (2026-06-03) — testid added to the (still-dead) component
  by an investigation that didn't yet realize the gating
- `7e5d392cd` (2026-06-04) — HT-1 assertion retargeted to accept the
  actually-rendered UI
- `frontend/e2e/hts-workflows-ux-e2e.e2e.ts:350-385` — inline history
  block in the test explains the gating chain
