# Workflow Runs Dialog — Design, Purpose & Differentiation

**Date:** 2026-06-01
**Files touched:** `frontend/client/src/components/workflow-history-dialog.tsx`, `frontend/client/src/App.tsx`

---

## What this feature is

The **Workflow Runs dialog** is the panel that opens when you click **"Workflows"** in the sidebar. It shows every pipeline execution the user has ever submitted — across all chat sessions — sorted newest first, with search and pagination.

It is **not** the chat list. It is **not** the task progress panel. The three things look superficially similar (they all show a list of items with statuses) but they track completely different objects at completely different granularities.

---

## The three panels — how they differ

| | Chat list (sidebar) | Workflow Runs dialog | Task list (in chat) |
|---|---|---|---|
| **What is one row?** | A conversation thread (AI dialogue) | A pipeline execution job (Nextflow/Galaxy run) | One AI reasoning sub-step |
| **Scope** | This browser / user's history | All runs across all sessions, server-backed | The current AI reply being generated |
| **Lifetime** | Persists indefinitely | Persists indefinitely | Disappears when the reply is done |
| **Data source** | `chatHistoryService` (local + backend) | `/api/workflows/runs/overview` | SSE stream from the current LLM call |
| **What "open" does** | Loads that conversation into the chat pane | Jumps to the chat session where that run was launched | N/A |
| **Status dots** | Blue = run in progress in that chat | Green/blue/red = pipeline job status | Spinning/check/X = sub-task status |
| **Trigger** | Sidebar chat history list | Sidebar "Workflows" button | Automatic, bottom of AI message |

### Analogy

- **Chat list** = your email inbox (threads of conversation)
- **Workflow Runs dialog** = your job scheduler history (what computations ran, when, result)
- **Task list** = the spinner you see while the AI is thinking right now

A single chat session can have **multiple workflow runs** inside it. The chat list and the workflow runs list are related but independent: deleting a chat does not delete the run record, and a run record links back to a chat.

---

## What the Workflow Runs dialog lets you do

### 1. Find a past run and jump back to it
Click **Open** on any row → loads the chat session where that run was launched. The right panel re-attaches to the run automatically (session restore reconciliation in `chat-with-artifacts.tsx`).

**Before this fix:** "Open" navigated to `/?session=<id>` but App.tsx ignored that param — it just loaded the home page with no session.

**After this fix:** `RootRoute` reads `?session=` once auth resolves, calls `handleChatSelect(sessionId)`, then strips the param from the URL so refresh doesn't re-trigger.

### 2. Re-run a completed or failed workflow with the same parameters
Click **Run again** on a completed/failed row → navigates to `/?session=<id>&runAgain=<runId>`. `chat-with-artifacts.tsx` reads `runAgain` on mount, fetches the run record, extracts the previously submitted parameters, and pre-fills the workflow panel. The user sees the panel ready to submit with the old params, not the workflow defaults.

### 3. Search across all runs
The search box filters by workflow name, status, or run ID. Debounced 300ms. Results are server-side — the search param is passed to `/api/workflows/runs/overview?search=`.

### 4. Paginate
50 runs per page. The footer shows "1–50 of 127 runs" and Prev/Next buttons. Previously the list was silently capped at 50 with no indication.

---

## What it does NOT do

- It does not show AI chat messages or conversation context — use the chat list for that.
- It does not show live step-by-step progress of a currently-running pipeline — that is the workflow panel in the right pane (open the relevant chat session for live updates).
- It does not show AI reasoning sub-steps — that is the task list inside the chat message.
- It does not let you cancel a running job — open the session and use the workflow panel controls.

---

## Also present but separate: WorkflowHistoryPanel

`workflow-history-panel.tsx` is an older Galaxy-specific invocation viewer (Sheet/side panel, fetches `/api/invocations`, shows `WorkflowInvocation` objects). It is not wired into the sidebar and predates the new `ExecutionRun` model. It may be superseded by the Workflow Runs dialog once the migration to `ExecutionRun` is complete. Do not confuse the two.

---

## Changes made in this session

### `workflow-history-dialog.tsx`
- Removed the **Starred tab** entirely — there was no way to star a workflow anywhere in the product, so the tab always showed an empty list. Removed `StarredInlineList` component and all associated imports.
- Added **search input** (debounced 300ms, passes `?search=` to API).
- Added **pagination** (50/page, shows "X–Y of Z runs", Prev/Next buttons). Previously `limit=50` was hardcoded with no overflow handling.
- Added **total count display** — the API already returned `total` but it was ignored.
- Fixed **`formatWhen` null guard** — `new Date(undefined)` previously rendered "Invalid Date"; now returns `—`.
- Added **`title` tooltip** on disabled "Open"/"Run again" buttons explaining *why* they are disabled (no linked chat session).
- Renamed title from "Workflows" → "Workflow Runs" to distinguish from the sidebar button label.
- Simplified fetch — removed the tab dependency; now fetches whenever the dialog opens.
- Reset all state (search, offset, rows) when dialog closes.

### `App.tsx` (`RootRoute`)
- Added `useSearch()` + `useRef(handledSessionParam)` to read `?session=<chatSessionId>` on load.
- Effect fires once auth resolves (`isLoading=false, isAuthenticated=true`), calls `onChatSelect(sessionId)`, then strips the param via `window.history.replaceState`. This makes the "Open" button in the Workflow Runs dialog actually navigate to the correct chat session.

### `app-sidebar.tsx`
- Removed `StarredWorkflowsDialog` import, mount, and state (`showStarredDialog`) — the dialog was only triggered by the Actions panel which has been commented out since beta.

---

## Known gaps (not addressed here)

- **Live status refresh**: the dialog fetches once on open. If a job completes while the dialog is open, the status dot does not update. A simple polling interval or SSE subscription would fix this.
- **WorkflowHistoryPanel reconciliation**: the older Galaxy panel and the new dialog show overlapping data from different models. They should be unified once the `ExecutionRun` model fully covers all run types.
