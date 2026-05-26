# Gap 4 — Sidebar Workflow History (Recent Runs + Run-from-Past)

**Status:** Open
**Owner:** unassigned
**Opened:** 2026-05-21
**Related:** Gap 3 (param carryover from prior runs)

## Problem

The sidebar "Workflows" button (`frontend/client/src/components/app-sidebar.tsx:419-420`) opens `StarredWorkflowsDialog`, which is **purely client-side**:
- Data source: `localStorage` key `'biomate-starred-workflows'` (`frontend/client/src/lib/starred-workflows.ts:8-17`)
- Falls back to 3 hardcoded defaults if empty
- No connection to the user's actual run history

The "Runs" → `/dashboard` button beneath it is commented out (`app-sidebar.tsx:422-424`). The dashboard page exists but shows mock data, not real runs.

Meanwhile, the user's executed workflows *are* recorded server-side and queryable via `/api/workflows/runs` — the chat-page Run Manager (`chat-with-artifacts.tsx:990-1150`) reads it. But that surface is scoped to the chat page and is read-only.

**Net:** users can't see "what workflows have I run before" from anywhere in the app shell, can't rerun one with one click, and can't see runs after switching out of the chat page.

## Goal

The sidebar exposes the user's run history globally — not just starred favorites. From any page, the user can find a prior run, see its status, and one-click "Run again" (which pre-fills params per Gap 3).

## Approach

Replace or augment `StarredWorkflowsDialog` with a tabbed dialog: **Recent Runs | Starred | Catalog**. Recent Runs is server-backed via `/api/workflows/runs`.

## Steps

1. **Server endpoint check.** Confirm `/api/workflows/runs` supports `limit`, `offset`, optional `status` filter, and returns: `id`, `workflow_path`, `workflow_name`, `status`, `started_at`, `completed_at`, `submitted_params`. Patch if any are missing.
2. **New dialog component** `frontend/client/src/components/workflow-history-dialog.tsx`. Three tabs:
   - **Recent Runs** — list of last 50 runs, grouped by week. Each row: workflow name, status dot, started timestamp, "Open" (jumps to chat session + opens panel) and "Run again" (opens panel with params pre-filled).
   - **Starred** — existing `StarredWorkflowsDialog` content, unchanged.
   - **Catalog** — search all workflows from `backend/database/galaxy_ai_tools.db` via `/api/ai_assistant/search_ranked`. New surface; can defer to v2.
3. **Sidebar wiring.** Update `app-sidebar.tsx:419-420` to open the new dialog. Keep the button label "Workflows."
4. **Run-again flow.** "Run again" calls `/api/workflows/runs/:id` to fetch the workflow JSON + submitted params, then navigates to the chat session (or a new one) with the workflow artifact emitted and the panel auto-opened. Param pre-fill uses the same mechanism as Gap 3.
5. **Activity dot rollup.** The sidebar's per-chat dot logic (`app-sidebar.tsx:273-298`) is fine; leave it. Optionally add a small badge on the "Workflows" button itself: count of currently-running workflows across all sessions.
6. **E2E.** `frontend/e2e/sidebar-run-history.e2e.ts`:
   - Run two workflows (one completed, one failed)
   - Open sidebar → Workflows → Recent Runs tab
   - Assert both rows present with correct status dots
   - Click "Run again" on the completed row → assert panel opens with submitted params pre-filled

## Files Touched

| File | Change |
|---|---|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Verify `/api/workflows/runs` query params + response shape |
| `frontend/client/src/components/workflow-history-dialog.tsx` | New tabbed dialog |
| `frontend/client/src/components/app-sidebar.tsx` | Swap dialog binding on Workflows button |
| `frontend/client/src/components/starred-workflows-dialog.tsx` | Extract content into a tab panel; keep file |
| `frontend/e2e/sidebar-run-history.e2e.ts` | New test |

## Risks

- **Large run history paginates.** Don't load all runs at once. Infinite scroll with `limit=50` offset pagination.
- **Starred favorites are local-only today.** Recent Runs is global per user (server-backed); Starred is still localStorage-only. Acceptable for v1; add a `starred_workflows` table in a follow-up if cross-device sync is requested.
- **Run-again from sidebar needs a target chat session.** If the user clicks Run Again from a non-chat page, decide: (a) open in current chat session, (b) create a fresh session, or (c) navigate to the original session. Default to (c) — least surprising.

## Out of Scope (v1)

- Cross-device starred sync (move starred to server)
- Run cancellation/deletion from the history list (read-only for v1)
- Run search / filter UI

## Done When

- [ ] Recent Runs tab shows real data
- [ ] Run-again pre-fills params per Gap 3
- [ ] "Open" jumps to the original chat session and opens the panel
- [ ] E2E green
- [ ] Sidebar button shows live running-count badge
