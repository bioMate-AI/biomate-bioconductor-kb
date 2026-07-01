# Interactive Tools E2E: B1/C1 Fix — Session Workflows Persistence

**Date:** 2026-07-01  
**Branch:** integration/next-phase  
**Status:** Fix shipped, pending sync to dev + E2E re-run

---

## Problem

B1 and C1 tests in `frontend/e2e/interactive-tools.e2e.ts` were unconditionally
skipping because `GET /api/sessions/:id` returned `workflows: []` for every
session. The right panel therefore showed no workflow card and no AfterRunReport —
the `[data-testid^="panel-tab-"]` selector never appeared, causing the
12 s `waitForSelector` to time out and the test to skip.

### Root cause

`chat_sessions.workflows` (JSONB, default `'[]'`) was **never written** when a
workflow run completed. Two completion paths existed but neither updated the column:

1. `galaxyPoller.on('workflow_completed', ...)` — updates `execution_runs`, outputs,
   metrics, but never touches `chat_sessions`.
2. `POST /internal/runs/by-invocation/:invId/status` (orphan finalizer) — updates
   `execution_runs.execution.status` but never touches `chat_sessions`.

All the required data was already in `execution_runs` (`chatSessionId`,
`workflowName`, `workflowDefinition`, status). It just wasn't being copied back.

---

## Fix: Three changes in `frontend/server/routes.ts`

### 1. `workflow_completed` handler (line ~506)

After updating `execution_runs` status + progress, if the run has a
`chatSessionId` and the terminal status is `completed`:

```sql
UPDATE chat_sessions
SET workflows = '[{"workflow_id":..., "workflow_name":..., "status":"completed"}]'::jsonb,
    last_activity = NOW()
WHERE session_id = $chatSessionId
```

### 2. Orphan finalizer handler (`POST /internal/runs/by-invocation/:invId/status`)

Same logic after `storage.updateExecutionRun(...)`.

### 3. `GET /api/sessions/:sessionId` — dynamic backfill (line ~13359)

When the stored `workflows` column is empty, the handler now looks up
`execution_runs WHERE chat_session_id = $sessionId AND status IN ('completed','failed','running')`
and synthesises the workflows array on the fly. This makes **all historical runs**
(completed before the persistence fix) immediately visible without a backfill
migration.

```typescript
session.workflows = runRows.rows.map(r => ({
  workflow_id: r.id,
  workflow_name: r.workflow_name || r.workflow_definition?.name || 'Workflow',
  status: r.run_status || 'completed',
}));
```

---

## Architecture note: Interactive tools vs built-in viewers

The user explicitly flagged this:
> "before interactive panel, there are already common visualization tools for
> common data types, interactive panel is not supposed to replace them!!!!!!
> They are just providing an alternative option"

Built-in viewers (`StepOutputPreview`, `AfterRunReport`) are the **primary**
visualization path:
- CSV/TSV → HTML table viewer
- PNG/JPG → `<img>` tag
- FASTA/VCF/text → code block

Interactive tools (Jupyter notebook, RStudio, CellxGene) are **secondary
alternatives** — supplemental buttons shown alongside, not instead of, the
built-in viewers. Any future UX change that hides the built-in viewer in favour
of an "Open in Jupyter" button is a regression.

---

## What B1/C1 must test (after fix)

B1 must verify that after a real workflow run completes, navigating to
`/?session=<chatSessionId>` shows:
1. The right panel renders (panel tabs appear)
2. `AfterRunReport` shows step outputs with built-in viewers (table/image/code)
3. Interactive tool buttons appear as **additional** options (e.g. "Open in Jupyter")
   — present alongside, not replacing, the file preview

---

## Open issues

- [ ] **E2E test still needs a live completed run** — the dynamic backfill in
  `GET /api/sessions/:id` handles historical runs in the DB, but B1 must verify
  end-to-end with a real run. Current `interactive-tools.e2e.ts` flow A creates a
  session + run; B1 should wait for that run's `chatSessionId` to have
  `workflows != []` before navigating.
- [ ] Verify `chatSessionId` is set on `execution_runs` rows created by Flow A.
  If the run was created without `chatSessionId`, neither persistence path fires.
  Check: `SELECT chat_session_id FROM execution_runs WHERE id = '<runId>'`.
- [ ] After sync: run `interactive-tools.e2e.ts` and confirm B1/C1 no longer skip.

---

## Files changed

- `frontend/server/routes.ts` — 3 edits (workflow_completed handler, orphan
  finalizer handler, GET /api/sessions/:sessionId handler)
- `frontend/e2e/interactive-tools.e2e.ts` — navigation overhaul (prior session)
- `frontend/e2e/_fixture-login.ts` — switched to `page.request.post()` (prior session)
- `frontend/server/security-config.ts` — CORS E2E bypass (prior session)
