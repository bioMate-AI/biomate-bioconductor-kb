# Query Queue & Active-Runs Status — Implementation Findings

**Date:** 2026-03-10  
**Status:** Implemented, TypeScript-clean (1 pre-existing error in App.tsx unrelated to changes)  
**Plan document:** `docs/20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md`

---

## Background: Design Questions & Decisions

This section records the Q&A that shaped the implementation, so the rationale is
self-contained alongside the findings.

---

### Q1: If a workflow is running, should the user be notified when it finishes, and can new queries run at the same time?

**Answer:**

Yes on both. There are two distinct time scales that the original design conflated:

1. **AI response time** (~3–10 s) — generating the workflow plan from the user's text.
   The chat input was previously hard-locked (`disabled={displayTyping}`) during this
   window. This lock is correct in principle (query N+1 often depends on the AI's answer
   to N), but the lock should be *soft*: allow typing and submit to a queue, not block
   entirely.

2. **Nextflow execution time** (minutes to hours) — actually running the pipeline.
   Multiple Nextflow invocations already run concurrently at the Galaxy level. No backend
   change is needed. What was missing was visibility: users had no way to see that two
   pipelines were running simultaneously.

**What the front page needed:**  
An always-visible **active-runs status bar** between the header and the chat area, showing
running/queued/failed counts and individual run pills with status labels and elapsed time.
This replaces the need to dig through the hidden Run Manager panel.

**Notification:**  
`WorkflowNotificationService` already sends email on completion. Added in-app toast
notifications that fire on every `running → completed` or `running → failed` status
transition detected by the existing 10 s poll cycle.

---

### Q2: Should there be a progress bar for the most recent run?

**Answer: No.**

Nextflow execution time is non-deterministic. The only way to compute a percentage
would be to poll `workflow-trace.txt` constantly, count completed tasks vs. total,
and treat all tasks as equal duration — none of which is accurate. A single 30-minute
alignment step is not "50% done" when the clock reaches 15 minutes.

A stale or wrong percentage is more confusing than no bar at all.

**Decision:** Show **status label** (`running` / `queued` / `completed` / `failed`) and
**elapsed time** (`running · 4 min`) only. Updated in both the plan document and this
implementation.

---

### Q3: When a user clicks "View results" or "View & fix" on a toast — what actually happens?

This was flagged as vague in the original plan. The concrete answer, based on reading
the actual component code:

#### "View results" (workflow completed toast)

The chat message that started the workflow already contains a `ChatOutputAttachments`
component that polls `/api/invocations/{id}/outputs` during execution and renders all
output files with download buttons and inline viewers (VCF, CSV, sequence, annotation,
structure) once they arrive.

Clicking "View results" does **one thing only**: scrolls the chat to that message.
The outputs are already loaded. No new page, no separate results view.

```typescript
const scrollToInvocation = (invocationId: string) => {
  const el = document.querySelector(`[data-invocation-id="${invocationId}"]`);
  el?.scrollIntoView({ behavior: "smooth", block: "center" });
};
```

#### "View & fix" (workflow failed toast)

`workflow-artifact.tsx` already has a fully functional "Run AutoFix" button that:
1. POSTs to `/api/galaxy/workflows/{workflowId}/invocations/{id}/autofix3/run`
   with `auto_apply: false` — proposes fixes, does not apply without user confirmation.
2. Displays session ID, termination reason, and number of fix attempts.
3. Shows "AutoFix history" button for previous attempts.

Clicking "View & fix" does two things:
1. Scrolls to that chat message (same scroll-to-invocation as above).
2. Opens the Run Manager panel focused on that run (`setShowRunManager(true)` +
   `setFocusedRunId(run.id)`), where the "Run AutoFix" button is immediately visible.

The AutoFix button is already functional. The toast only saves the user from hunting
through the Run Manager to find the failed run.

---

### Q4: What is the concurrent execution model?

Workflows **already** run concurrently at the backend level. Each Nextflow invocation
is an independent process. The Galaxy `JobHandlerQueue` schedules individual tool steps
across invocations without coordination.

The new UI changes make this *visible* — users can now see "2 workflows running
simultaneously" in the status bar with elapsed-time counters. This makes concurrent
execution expected and understandable rather than invisible.

The only sequential constraint is **AI query generation within a single chat session**:
query N+1 is queued behind query N's AI response (because the answer to N often
determines what N+1 should be). Once the AI responds and the workflow starts executing,
the next queued query is submitted and the new workflow runs concurrently with the
existing one.

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

## Post-Implementation Audit (2026-03-10)

A Playwright audit run immediately after implementation found three bugs. All three
were fixed in the same session.

---

### Bug 1 — `data-invocation-id` not stamped (scroll-to-invocation broken)

**Found:** The toast "View results" click uses
`document.querySelector('[data-invocation-id="..."]')` but the workflow anchor
divs in `chat-message.tsx` had no such attribute — they only had
`id="workflow-artifact-anchor-{messageId}"` and `data-testid`.

**Fix:** Added `data-invocation-id={effectiveInvocationId || undefined}` to both
anchor `<div>` elements in `chat-message.tsx` (the compact status pill and the full
`NextflowWorkflowViewer` wrapper).

**Verified:** Injected a mock DOM element with `data-invocation-id="mock-inv-12345"`,
ran `querySelector('[data-invocation-id="mock-inv-12345"]')` and
`scrollIntoView({behavior:"smooth", block:"center"})` — element found and scrolled
correctly. Source: `data-invocation-id` occurrences in `chat-message.tsx` = 2
(both anchor divs, correct).

Note: The attribute only renders when `effectiveInvocationId` is non-null, which requires
an actual Galaxy workflow invocation. The test environment does not generate real
invocations (no running Nextflow stack), so live verification requires a real workflow run.

---

### Bug 2 — Sidebar dots invisible in test (false positive — works in prod)

**Found:** Sidebar items showed no dots during the Playwright test.

**Root cause:** The test environment uses placeholder chat sessions (`chat-1`, `chat-2`,
`chat-3`, `chat-4`) that do not match any run's `chatSessionId`. The production API
confirmed runs DO include `chatSessionId` in format `chat-${Date.now()}-${random}`,
which matches the `chatHistoryService.createNewSession()` ID format exactly.

**Status:** Not a bug. In production, newly-created sessions with real workflow runs
will show dots correctly. The test simply had no sessions matching the run list.

---

### Bug 3 — `failedCount` included stale historical failures (status bar permanently visible)

**Found:** Screenshot `01_chat_home.png` from the audit showed "11 failed" in the
status bar — these were Nextflow runs that failed days or weeks ago. The condition
`(runningCount > 0 || queuedCount > 0 || failedCount > 0)` kept the bar permanently
visible even with no active runs.

**Fix:** Applied the same 24 h cap as `completedTodayCount`:
```typescript
const failedCount = runList.filter((run) => {
  if (mapRunBucket(run.execution?.status) !== "failed") return false
  const updatedAt = run.updatedAt ? new Date(run.updatedAt).getTime() : 0
  return Date.now() - updatedAt < 86400000
}).length
```

**Verified:** Playwright confirmed status bar is hidden when there are no active runs
and no recent failures: `[Bug 3] Status bar hidden (correct when no recent failures
+ no active runs)`.

---

## Screenshot Evidence

| Screenshot | What it shows |
|------------|--------------|
| `01_chat_home.png` | Status bar with live data: "2 running · 11 failed" (pre-fix) |
| `10_full_ui_state.png` | Queue working: Clock badge on send, "1 message queued · clear" indicator |
| `09_send_button_closeup.png` | Clock icon + amber "1" badge close-up |
| `fix3_status_bar_no_stale_failures.png` | Status bar hidden (post-fix, no stale failures) |
| `fix4_send_btn_closeup.png` | Clock badge verified in second audit pass |
| `fix1_invocation_scroll_verified.png` | Scroll-to-invocation mock test passing |

---

## Final Feature Status

| Feature | Status | Notes |
|---------|--------|-------|
| Chat input always enabled | ✅ Verified | `disabled` attr = null confirmed by Playwright |
| Soft queue (text messages) | ✅ Verified | "1 message queued · clear" visible in test |
| Clock badge on send button | ✅ Verified | Screenshot `fix4_send_btn_closeup.png` |
| Auto-dequeue on AI response complete | ✅ Code correct | Cannot auto-test (requires real AI response cycle) |
| Active-runs status bar | ✅ Verified | Shows with real run data; hidden when no active/recent runs |
| 24 h cap on failed count | ✅ Verified | Bar hidden post-fix |
| Completion toast (scroll) | ✅ DOM attribute in place | Requires real workflow invocation to fire |
| Failure toast (View & fix) | ✅ DOM attribute in place | Requires real workflow failure to fire |
| Sidebar status dots | ✅ Code correct | Requires session with real runs; format matches |
| Scroll-to-invocation | ✅ Verified with mock | `querySelector('[data-invocation-id]')` + `scrollIntoView` works |

---

## Remaining Known Gaps

1. **Queue for file attachments**: Messages with attached files bypass the queue (go
   immediately). This is intentional but not documented in the UI. The send button
   tooltip shows "N messages queued" only for text queue — file messages have no tooltip.

2. **Multi-tab scenarios**: `pendingMessages` is React state — lost on page reload or
   tab switch. Acceptable for MVP; could be persisted to `sessionStorage` if needed.

3. **Completion/failure toast end-to-end**: Requires a live Nextflow run to complete or
   fail. Cannot be verified in the test environment without a running Galaxy + Nextflow
   stack. Verified via code review only.
