# BioMate UX — Chat + Task List + Workflow Panel

> ## ⚠ STATUS — 2026-06-04 — partially superseded
>
> This doc describes the right panel as *"existing Workflow Artifact Viewer
> with **ExecutionControlPanel**"*. **`ExecutionControlPanel` was built
> (frontend/client/src/components/execution-control-panel.tsx) but is gated
> behind `useUnifiedExecution={true}` on `<WorkflowArtifact>`. That prop
> defaults to `false` at `workflow-artifact.tsx:160` and is not overridden
> by any caller in `frontend/client/src/`. The panel does not render in
> production today.**
>
> The actively-rendered execution UI lives in
> `frontend/client/src/components/nextflow-workflow-viewer.tsx` — phase
> cards, per-phase QC blocks (className `qc-block`, testid
> `qc-edit-toggle-*`), and the event-driven `qc-gate-inline` /
> `qc-report-panel`. Tests and design discussions should target that
> tree, not `ExecutionControlPanel`, until somebody flips the
> `useUnifiedExecution` flag and ships it.
>
> Forward-looking sections of this doc that assume `ExecutionControlPanel`
> is rendered are aspirational, not current state. Confirmed by the HT-1
> E2E investigation in `frontend/e2e/hts-workflows-ux-e2e.e2e.ts:350-385`
> and commit `7e5d392cd` ("test(ht-1): retarget QC assertion to the UI
> that actually renders").

**Date:** 2026-03-10  
**Design Direction:** Claude-style chat stream with a task list at the bottom,
workflow execution panel on the left, stop button at the chat box.

---

## Mental Model (Final)

```
┌──────────────────┬──────────────────────────────┬──────────────────────────┐
│   LEFT PANEL     │   CHAT STREAM                │   RIGHT PANEL            │
│   (unchanged)    │                              │   (unchanged)            │
│                  │   [User message]             │                          │
│   Chat session   │                              │   Workflow Artifact      │
│   history        │   [BioMate reply...]         │   Viewer                 │
│                  │                              │                          │
│   • Recent chats │   Tasks                      │   • Pause                │
│   • Session dots │   ✓ Write QC workflow  [rm]  │   • Resume               │
│                  │   ↻ Write DE workflow  [stop]│   • Cancel               │
│                  │   ○ Write export step  [rm]  │   • QC Gate (inline)     │
│                  │   ─────────────────────────  │   • Sandbox              │
│                  │   ○ Queued: "Run on samples" │   • Promote              │
│                  │                              │                          │
│                  │   [input ··············  ⏹ ] │   (all unchanged)        │
└──────────────────┴──────────────────────────────┴──────────────────────────┘
```

**Three rules that eliminate all confusion:**

1. The **chat stop button** (⏹) stops the current AI reply stream and optionally
   clears the task queue. It **never** touches a running workflow.

2. The **right panel** (existing Workflow Artifact Viewer with ExecutionControlPanel)
   controls running cluster jobs. Its vocabulary — Pause, Resume, Cancel, QC Gate,
   Sandbox, Promote — is unchanged and stays exactly where it is today.

3. **Per-task row buttons** in the task list give granular control over each
   AI generation task and each queued message independently.

---

## Layout Changes from Current State

### What does NOT change (no dramatic layout changes)

| Component | Location | Status |
|-----------|----------|--------|
| AppSidebar (chat session history) | Left panel | **Unchanged** |
| Workflow Artifact Viewer + ExecutionControlPanel | Right panel (opens on "View") | **Unchanged** |
| Run Manager overlay | Top of chat area (slide-down) | **Unchanged** |
| Toast notifications | Bottom-right | **Unchanged** |
| Sidebar session status dots | Left panel, next to chat sessions | **Unchanged** |

### What changes (minimal, additive only)

| Component | Current | Change |
|-----------|---------|--------|
| Send button | Always ▶ | Becomes ⏹ while AI is streaming |
| "N messages queued / clear" text | Below typing indicator | Replaced by TaskList component |
| QC Gate | Full-screen modal popup | Inline section inside the existing right-panel workflow viewer |
| Active-runs status bar | Separate bar above chat | Removed — info lives in TaskList + right panel |

---

## Chat Stop Button — Detailed Behaviour

### Visual

```
[  Type a message...                          ▶  ]   ← idle, send icon
[  Type a message...                          ⏹  ]   ← AI is replying, stop icon
[  Type a message...                       2  ⏹  ]   ← tasks queued, badge + stop
```

The stop icon replaces the send icon whenever `isTyping === true` (AI is streaming).
The badge count shows pending tasks (same as today's queue badge).

### What ⏹ does — decision tree

```
User clicks ⏹
       │
       ├─ pendingMessages.length === 0 AND no LangGraph tasks queued
       │       → Stop streaming reply immediately (abort fetch reader)
       │         No dialog needed.
       │
       └─ pendingMessages.length > 0 OR LangGraph tasks are queued
               → Show inline disambiguation:

               ┌─────────────────────────────────────────────────┐
               │  Stop current reply?                            │
               │                                                 │
               │  [Stop reply only]                              │
               │  Continue queued tasks after this reply ends    │
               │                                                 │
               │  [Stop reply + clear all queued tasks]          │
               │  Removes N queued messages and M pending tasks   │
               └─────────────────────────────────────────────────┘

               Running workflows in left panel: NOT affected by either option.
```

### Implementation — `chat-interface.tsx`

**Current state:** fetch to `/api/chat/stream` uses `ReadableStream` reader with no
`AbortController`. The stream runs to completion even if the user navigates away.

**Change needed:** wire an `AbortController` to the fetch call so ⏹ can cancel it.

```tsx
// Add to handleSendMessage:
const abortController = useRef<AbortController | null>(null)

const stopStreaming = useCallback(() => {
  abortController.current?.abort()
  abortController.current = null
  setIsTypingLocal(false)
  // Show dialog if tasks are queued
  if (pendingMessagesRef.current.length > 0 || langgraphTasksRef.current.length > 0) {
    setShowStopDialog(true)
  }
}, [])

// In the fetch call:
abortController.current = new AbortController()
const response = await fetch('/api/chat/stream', {
  method: 'POST',
  signal: abortController.current.signal,
  // ...
})
```

**Disambiguation dialog** — small inline popover anchored to the stop button,
not a full modal. Disappears after choice is made.

---

## Task List — Detailed Design

### What it shows

The task list appears as a section **at the bottom of the current AI reply bubble**
while the AI is working. It lists two categories of pending work, separated by a divider.

```
  BioMate is preparing your workflows...

  ┌ Tasks ──────────────────────────────────────────────────────────┐
  │  ✓  Write QC workflow (FastQC)         done · 0.8s   [remove]  │
  │  ↻  Write DE workflow (DESeq2)         running · 3s  [stop]    │
  │  ○  Write export step                  queued        [remove]  │
  │  ──────────────────────────────────────────────────────────     │
  │  ○  Queued: "Now run on my samples"                  [remove]  │
  └─────────────────────────────────────────────────────────────────┘
```

### Status icons

| Icon | Meaning |
|------|---------|
| ✓ | Completed |
| ↻ | Running (animated spin) |
| ○ | Queued / waiting |
| ✗ | Failed |
| – | Skipped (dependency failed) |

### Per-row buttons

| Button | When shown | Action |
|--------|-----------|--------|
| `[stop]` | Task is running | Abort that specific Celery task; mark as stopped; show `[retry]` |
| `[remove]` | Task is queued or done | Remove from list (if queued: discard; if done: collapse row) |
| `[retry]` | Task stopped or failed | Re-dispatch the single task to Celery |

### Parallel workflows in chat history — NOT shown here

Workflows that are already running on the cluster (submitted in previous messages)
are **not** in this task list. They appear in the left panel. The task list only
shows AI generation tasks for the **current** compound request.

### Collapses when done

When all tasks complete, the task list collapses to a single summary line:

```
  ✓  3 workflows prepared · submitted to cluster   [show steps ▾]
```

---

## Right Panel — Workflow Artifact Viewer (unchanged except QC Gate)

The right panel is the existing workflow artifact viewer (`workflow-artifact.tsx` +
`execution-control-panel.tsx`). It opens when the user clicks "View" on a workflow
in the chat. **Nothing about it changes except the QC Gate.**

### Existing controls — all kept, all unchanged

```
┌─ Workflow Artifact (right panel) ─────────────────────────┐
│  QC (FastQC)          ✓ done · 1m 12s                    │
│  DE (DESeq2)          ↻ running · 2m 30s                 │
│  Export               ○ waiting                           │
│  ──────────────────────────────────────────────────────   │
│  [Pause]  [Resume]  [Cancel]                              │
│  ──────────────────────────────────────────────────────   │
│  Sandbox · 10%  [5%][10%][25%][50%][100%]                │
│  ──────────────────────────────────────────────────────   │
│  QC gate: OFF  [Turn on]                                  │
│  ──────────────────────────────────────────────────────   │
│  [Promote to Production]                                  │
└───────────────────────────────────────────────────────────┘
```

Nothing renamed. Nothing removed. The Pause button keeps its honest note:
```
[Pause]  ⓘ Records intent; computation continues until Cancel
```

### Only change: QC Gate inline in the right panel, not a modal popup

Currently, when `qc_gate_triggered` SSE fires, a full-screen `QCGateModal` pops up
and covers the screen. This loses the user's context (they can no longer see the
chat or the workflow state).

**Change:** render the QC gate review as a highlighted section **at the top of the
right panel**, inside `workflow-artifact.tsx`, instead of a modal:

```
┌─ Workflow Artifact (right panel) ─────────────────────────┐
│  ⚠  QC Gate — Review Required                            │  ← new inline
│  Mito fraction: 28%  (threshold: 20%)                    │    section only
│  Suggestion: raise threshold to 30%                      │
│  [Apply]   [Keep default]   [Cancel run]                 │
│  ──────────────────────────────────────────────────────   │
│  [Pause]  [Resume]  [Cancel]           ← all unchanged   │
│  ...                                                      │
└───────────────────────────────────────────────────────────┘
```

Same options, same logic, same API calls — just no popup that hijacks the screen.
`QCGateModal` component is kept in the codebase but no longer rendered.

---

## Implementation Plan

### Phase A — Chat stop button (1 day)

**Files:** `chat-interface.tsx`, `chat-input.tsx`

1. Add `abortController = useRef<AbortController|null>(null)` to `chat-interface.tsx`
2. Wire `signal: abortController.current.signal` into the `/api/chat/stream` fetch
3. Rename send icon → stop icon (`Square` from lucide) when `isTyping === true`
4. Add `stopStreaming()` handler: aborts fetch, sets `isTypingLocal = false`
5. Add `StopDialog` inline popover: "Stop reply only" vs "Stop reply + clear queue"
6. Pass `isStreaming` prop to `ChatInput` to toggle icon
7. Keep badge count on stop icon when tasks are queued

**Test:** Phase A tests below.

---

### Phase B — Task list component (1 day)

**Files:** `chat-interface.tsx`, new `task-list.tsx`

1. Create `TaskList` component:
   - Props: `tasks: TaskItem[]`, `queuedMessages: string[]`,
     `onStopTask`, `onRemoveTask`, `onRetryTask`, `onRemoveMessage`
   - Renders two sections with a divider
   - Uses status icons from table above
2. Add `langgraphTasks: TaskItem[]` state to `chat-interface.tsx`
   - Populated by SSE events from `/api/pipelines/:id/events`
   - Status updates (pending → running → completed/failed) arrive via SSE
3. Render `<TaskList>` inside the current streaming placeholder message bubble,
   below the text content
4. Collapse to summary line when all tasks complete

---

### Phase C — QC Gate inline (0.5 days)

**Files:** `workflow-artifact.tsx` only. No layout changes to `App.tsx`.

1. Add a `showQcInline` boolean state (initially `false`)
2. On `qc_gate_triggered` SSE event: set `showQcInline = true`, `setShowQCGateModal(false)` (suppress old modal)
3. Render the inline QC review section at the top of the artifact panel when `showQcInline`:
   - Same `qcGateData` state already populated
   - Same "Apply / Keep / Cancel run" action handlers already wired
4. After user makes a choice: set `showQcInline = false`
5. `QCGateModal` component: keep in place, just stop rendering it (set `showQCGateModal` to never become `true`)

No new component needed. No `App.tsx` changes. No layout restructuring.

---

### Phase D — LangGraph clarification as chat reply (0.5 days)

**Files:** `ai_assistant.py`, `routes.ts`

When LangGraph `interrupt_before` fires (clarification needed):
- Backend returns `{ needs_clarification: true, questions: [...], pipeline_id: "..." }`
  as the final SSE payload
- Frontend renders this as a normal assistant message with the questions inline
- User answers by typing — no special card, no Section 1/2
- Next user message is automatically detected as an answer if `pipeline_id` is in context
- Backend resumes graph: `graph.invoke(answers, config={thread_id: pipeline_id})`

---

## Use Case Based Tests

### UC-1: Stop button stops reply only (no tasks queued)

**Setup:** User sends a single message. AI is streaming a reply. No tasks queued.

**Steps:**
1. User clicks ⏹ during streaming
2. Streaming stops immediately
3. No dialog appears
4. Chat input re-enables, ready for next message
5. Send icon returns (⏹ → ▶)

**Verify:**
- `AbortController.abort()` was called (check fetch was cancelled via network tab)
- Partial reply is visible in the chat (not blank)
- Task list is not shown
- Left panel (if run was active) is unchanged — run still shows `running`

**Playwright test:** `task-list-stop-button.e2e.ts` → `test("stop-reply-only-no-tasks")`

---

### UC-2: Stop button with queued messages — shows disambiguation

**Setup:** User sends message 1 (AI replying). User sends messages 2 and 3 while waiting
(they are queued). User clicks ⏹.

**Steps:**
1. ⏹ is clicked
2. Inline popover appears: "Stop reply only" | "Stop reply + clear all queued tasks"
3. User chooses "Stop reply only"
4. Current reply stops. Messages 2 and 3 remain in queue (badge shows 2).
5. Queue auto-submits message 2 immediately.

**Verify:**
- Badge shows 2 before dialog
- Dialog shows "2 queued messages and 0 pending tasks"
- After "Stop reply only": badge still shows 2, message 2 starts sending
- After "Stop reply + clear": badge shows 0, input is idle

**Playwright test:** `test("stop-reply-disambiguation-queued-messages")`

---

### UC-3: Stop button with queued messages — clears all

**Extends UC-2, user chooses "Stop reply + clear all queued tasks"**

**Verify:**
- Badge drops to 0
- No further messages are auto-submitted
- Task list (if visible) clears queued rows
- Running task rows remain (cannot be bulk-cleared)

**Playwright test:** `test("stop-reply-and-clear-all-queued")`

---

### UC-4: Per-task [stop] on a running task

**Setup:** Compound query "Run QC, then DE, then export". Task list shows 3 rows.
DE row is in `running` state.

**Steps:**
1. User clicks `[stop]` on the DE row
2. DE task is aborted (Celery task revoked)
3. DE row changes to ✗ stopped with `[retry]` button
4. Export row changes to `–` skipped (dependency failed)
5. Toast: "DE task stopped. Export was skipped."

**Verify:**
- Celery task was revoked: `celery.control.revoke(task_id, terminate=True)`
- `pending_tasks` DB row: `status = 'stopped'`
- Export row shows `–` not `○`
- `[retry]` button visible on DE row
- Left panel workflow (if it had started): unaffected

**Playwright test:** `test("per-task-stop-running-task")`

---

### UC-5: Per-task [retry] after failure

**Setup:** DE task failed (e.g., tool not found).

**Steps:**
1. DE row shows ✗ failed + `[retry]`
2. User clicks `[retry]`
3. DE task re-dispatched to Celery
4. DE row returns to `↻ running`
5. On success: DE row → ✓ done, export row unblocked → `○ queued`

**Verify:**
- New Celery task ID issued (different from the failed one)
- `pending_tasks` DB: new row with `status = pending`, same `parent_pipeline_id`
- Export row unblocks and transitions to running when DE completes
- Task list summary line updates count

**Playwright test:** `test("per-task-retry-after-failure")`

---

### UC-6: Parallel workflows — left panel not affected by chat stop

**Setup:** User ran workflow A in session 1 (still running). User opens session 2,
sends a compound query. Left panel shows workflow A running.

**Steps:**
1. User clicks ⏹ in session 2 chat
2. Session 2 AI reply stops
3. "Stop reply + clear all queued tasks" is chosen

**Verify:**
- Left panel still shows workflow A as `running`
- Left panel Pause/Resume/Cancel still functional for workflow A
- `pendingMessages` in session 2 cleared
- No API call to `/api/workflows/runs/:id/pause` or `/cancel` was made

**Playwright test:** `test("parallel-workflow-unaffected-by-chat-stop")`

---

### UC-7: LangGraph clarification answered inline

**Setup:** User asks "Run RNA-seq analysis". BioMate needs organism.

**Steps:**
1. BioMate reply: "Before I prepare your workflows, I need a couple of details:
   What organism are you working with? (e.g., Homo sapiens, Mus musculus)"
2. Task list shows: `○ Write QC workflow — waiting for your answer`
3. User types "Homo sapiens" and hits send
4. LangGraph resumes from checkpoint
5. Task list updates: `↻ Write QC workflow — generating...`
6. Eventually: `✓ Write QC workflow — done`

**Verify:**
- No `QCGateModal` or any popup appears
- Task list row transitions: `waiting → generating → done`
- `pipeline_id` is carried in context of user's reply
- Graph resumes correctly (checkpoint in `langgraph_checkpoints` table)

**Playwright test:** `test("langgraph-clarification-inline-chat-reply")`

---

### UC-8: QC gate fires — inline in right panel, no popup

**Setup:** Workflow A is open in the right artifact panel. Mito fraction exceeds threshold.

**Steps:**
1. QC gate SSE event fires
2. Right artifact panel shows ⚠ QC Gate review section at its top (inline)
3. No modal popup covers the screen
4. User clicks "Apply suggestion"
5. Workflow continues with updated parameter
6. QC gate inline section collapses; existing Pause/Resume/Cancel controls visible again

**Verify:**
- `QCGateModal` is NOT rendered (check `data-testid="qc-gate-modal"` absent)
- Inline review section `data-testid="qc-gate-inline"` visible within 1s of SSE event
- Chat stream still visible behind right panel (not obscured by modal overlay)
- After "Apply": review section gone, `execution.status` returns to `running`

**Playwright test:** `test("qc-gate-inline-right-panel-no-modal")`

---

### UC-9: Sandbox → Promote (left panel, unchanged flow)

**Setup:** Workflow completed in sandbox (10%) mode.

**Steps:**
1. Left panel shows ✓ Complete with "Promote to Production" button
2. User clicks Promote
3. New run created at 100% fraction
4. Left panel updates: new run → `↻ running`

**Verify:**
- Button text unchanged: "Promote to Production"
- New `execution_run` created with `fraction: 1.0`, `mode: 'production'`
- Left panel transitions from done state to running state for the new run

**Playwright test:** `test("sandbox-promote-to-production-left-panel")`

---

### UC-10: Left panel auto-hides when no runs active

**Setup:** All runs completed or cancelled.

**Steps:**
1. Last run completes
2. After 3 seconds grace period, left panel collapses
3. Layout returns to [AppSidebar 20%] | [Chat 80%]

**Verify:**
- Panel CSS transition to zero width (not abrupt removal)
- AppSidebar becomes visible again
- Chat area expands to fill space
- Re-running a workflow re-expands the left panel

**Playwright test:** `test("left-panel-auto-hide-no-active-runs")`

---

## Files Changed Summary

```
frontend/
  client/src/
    components/
      chat-interface.tsx     Phase A, B: stop button + AbortController, task list wiring
      chat-input.tsx         Phase A: stop icon (⏹) when isStreaming, keep badge
      task-list.tsx          Phase B: NEW component (generation tasks + queued messages)
      workflow-artifact.tsx  Phase C: QC gate inline section, suppress modal
      chat-with-artifacts.tsx Phase A: remove "N messages queued" text (replaced by TaskList)
      qc-gate-modal.tsx      Phase C: kept, just not rendered (rollback safety)

backend/
  lib/galaxy/ai/
    orchestration/           Phase D: LangGraph graph (from main plan)
    ai_assistant.py          Phase D: route clarification as a chat reply payload

frontend/e2e/
  task-list-stop-button.e2e.ts        UC-1, 2, 3
  task-list-per-task-control.e2e.ts   UC-4, 5
  parallel-workflow-isolation.e2e.ts  UC-6
  langgraph-clarification.e2e.ts      UC-7
  qc-gate-inline.e2e.ts              UC-8  (right panel, not left)
  sandbox-promote.e2e.ts             UC-9, 10
```

**No changes to:**
- `App.tsx` — left panel (AppSidebar) layout unchanged
- `execution-control-panel.tsx` — all controls intact, no renaming
- `app-sidebar.tsx` — unchanged

Total: ~4 modified files, ~2 new files, ~6 new test files.
Estimated time: **2.5 days** (A: 1d, B: 0.5d, C: 0.5d, D: 0.5d).
