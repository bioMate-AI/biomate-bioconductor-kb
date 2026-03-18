# Query Queue & Active-Runs Status — Implementation Findings

**Date:** 2026-03-10  
**Status:** Implemented, TypeScript-clean (1 pre-existing error in App.tsx unrelated to changes)

---

## What Was Implemented

### Feature 1B — Soft Query Queue (`chat-interface.tsx`, `chat-input.tsx`)

**Before:** Chat input was `disabled={displayTyping}` — completely locked while AI responded.

**After:**
- Input is always enabled (no `disabled` prop passed to `ChatInput`).
- A `handleSendOrQueue` wrapper intercepts submissions while `displayTyping` is true.
- Text messages are pushed onto `pendingMessages: string[]` state.
- A `useEffect` watching `displayTyping` auto-submits the next queued message as soon
  as each AI response completes.
- Messages with file attachments skip the queue and go immediately (files are perishable
  objects; queuing them is complex and rarely needed).

**UI signals:**
- While queued messages exist AND the AI is still responding, the "Analyzing…" bar
  below the input shows an amber indicator:
  ```
  ⏱ 1 message queued  [clear]
  ```
- The send button switches from `<Send />` to `<Clock />` with an amber badge
  showing the queue count (e.g. `1`). Tooltip: "1 message queued".
- Once the AI responds, the badge disappears and the next message auto-submits.

**Key files:**
- `frontend/client/src/components/chat-input.tsx` — new `pendingCount` prop; removed
  `disabled` from Textarea and send Button; Clock badge on send button.
- `frontend/client/src/components/chat-interface.tsx` — `pendingMessages` state +
  `pendingMessagesRef`; `handleSendOrQueue` wrapper; auto-dequeue `useEffect`.

---

### Feature 1A — Active-Runs Status Bar (`chat-with-artifacts.tsx`)

**Before:** Run status was hidden behind the "Run Manager" button in the toolbar.

**After:** A slim status bar appears automatically between the header and the chat area
whenever any run is active (running, queued, or failed):

```
▶ 2 running  ✓ 1 done today  ✗ 0 failed  |  [rna-seq-analysis · running · 4 min]  [all runs]
```

- **No progress bar** — only status label (running / queued) and elapsed time
  (`running · 4 min`, `< 1 min`, etc.).
- Elapsed time is computed from when the run first appeared as "running" in the poll;
  updated every 30 seconds via a lightweight `setElapsedTick` ticker.
- "all runs" link expands the full RunManager panel without navigating away.
- The bar is hidden entirely when there are no active or failed runs.
- Shows up to 3 individual run pills; broader counts (done today, failed) always shown.

**Implementation note:** `runStartTimesRef` records per-run start times in a `Map<string, number>`.
It is populated the first time a run appears with bucket `"running"` in the polled list.
The elapsed formatter uses `Date.now() - started` with 30-second granularity (sufficient;
Nextflow jobs run for minutes to hours).

**Key computed values added:**
```typescript
const queuedCount          // runs with status queued
const completedTodayCount  // completed within last 24 h
const failedCount          // failed runs
const activeRuns           // running+queued, max 3 for status bar
const formatElapsed(runId) // "4 min" | "< 1 min" | ""
```

---

### Feature 1C — In-app Completion Toast (`chat-with-artifacts.tsx`)

**Before:** Only email notifications via `WorkflowNotificationService`.

**After:** In-app toast fires on every status transition:

- **`running → completed`**: Green toast, 8 s auto-dismiss.
  - Action button "View results" scrolls to the chat message containing the workflow
    artifact. `ChatOutputAttachments` has already loaded output files (it polls
    `/api/invocations/{id}/outputs` during execution). No new page needed.
  
- **`running → failed`**: Destructive (red) toast, **stays until dismissed** (user must act).
  - Action button "View & fix" scrolls to the chat message AND opens the RunManager
    panel focused on that run, where the existing "Run AutoFix" button is available.

**Detection mechanism:** `prevRunStatusesRef` (a `Map<string, string>`) stores the
last-seen bucket per run ID. The `useEffect` watching `runList` compares current buckets
to previous ones on each poll (every 10 s). Transitions are detected exactly once per
poll cycle, preventing duplicate toasts.

**Scroll-to-invocation:** Uses `document.querySelector('[data-invocation-id="..."]')`
which is already stamped on the workflow artifact elements.

---

### Feature 1E — Sidebar Status Dots (`app-sidebar.tsx`)

**Before:** Sidebar showed chat sessions with no run-status indication.

**After:** Each chat session in the sidebar shows a small colored dot:
- 🔵 Blue pulsing dot — workflow running in this chat session
- 🔴 Red dot — workflow failed, needs attention  
- 🟢 Green dot — workflow completed (hidden if this is the active chat session)

**Implementation:** `AppSidebar` fetches `/api/workflows/runs?limit=50` independently
every 15 seconds (a separate, lightweight poll). It builds a `Map<chatSessionId, status>`,
prioritising "running" > "failed" > "completed" when a session has multiple runs.
No state-lifting through `App.tsx` required.

---

## Audit: What Works vs. What Cannot Be Tested Without a Live Run

| Behaviour | Testable in current local env | Notes |
|-----------|-------------------------------|-------|
| Chat input enabled while AI responds | ✅ Yes | `disabled` attribute removed |
| Queue badge appears on send button | ✅ Yes | Requires fast second message during AI response |
| Queued message auto-submits | ✅ Yes | Verifiable by observing second message appear after first response |
| "N messages queued" indicator in status bar | ✅ Yes | Visible during AI response with pending messages |
| Clear queue button | ✅ Yes | Clears `pendingMessages` state |
| Active-runs status bar hidden when no runs | ✅ Yes | Conditional render on `runningCount > 0 \|\| queuedCount > 0 \|\| failedCount > 0` |
| Active-runs bar shows running run | ⚠️ Requires live Nextflow run | Status bar only appears when `runList` contains active runs |
| Elapsed time display | ⚠️ Requires live run | `runStartTimesRef` populated on first "running" poll |
| Completion toast fires | ⚠️ Requires workflow to complete | Transition detection fires when polled status changes |
| Failure toast fires | ⚠️ Requires workflow to fail | Same |
| "View results" scroll works | ✅ Yes | `[data-invocation-id]` already stamped on elements |
| "View & fix" opens RunManager | ✅ Yes | `setShowRunManager(true)` + `setFocusedRunId` |
| Sidebar dots appear | ⚠️ Requires live run with chatSessionId | API must return `chatSessionId` on runs |

---

## TypeScript Status

One pre-existing error (not introduced by this change):
```
App.tsx(319): Property 'onCollapseSidebar' does not exist on type
  'IntrinsicAttributes & ChatWithArtifactsProps'.
```
This was present before. All four modified files (`chat-input.tsx`, `chat-interface.tsx`,
`chat-with-artifacts.tsx`, `app-sidebar.tsx`) are type-clean.

---

## Known Gaps / Follow-Up

1. **`chatSessionId` on runs API**: The sidebar dots require `/api/workflows/runs` to
   return `chatSessionId` per run. If the backend omits this field, the dot map stays
   empty. Needs a backend check.

2. **`data-invocation-id` stamping**: The "View results" scroll relies on this attribute
   already being on workflow artifact elements. Verified it exists in
   `workflow-artifact.tsx` but should be confirmed on the exact container element.

3. **Queue for file attachments**: Currently, messages with files bypass the queue. If
   a user attaches files during an AI response, the message submits immediately. This is
   correct behaviour (files may be context-dependent) but should be documented in the UI
   tooltip.

4. **Multi-tab scenarios**: `pendingMessages` is component state — it does not survive
   page reload or tab switches. A queued message is lost if the user navigates away.
   Acceptable for an MVP; could be persisted to `sessionStorage` if needed.
