# BioMate — Chat Queue, Task Orchestration & LangGraph Foundation
## Team Share Document

**Date:** 2026-03-10  
**Authors:** Engineering  
**Status:** Implementation complete (Phase A–C); Phase D (LangGraph parallel dispatch) is next  
**Files touched:** 12 files, 2992 insertions  

---

## Section 1: Executive Summary

### Problem solved

BioMate could only process one AI request at a time, with no way for users to queue follow-up
messages, no visibility into multi-step task progress, and a full-screen QC Gate modal that
hijacked the screen mid-workflow. Users asking compound questions like "Run QC, then differential
expression, then export" received no structured progress tracking and no clean way to stop or
redirect the AI mid-stream.

### What was built

- **Stop button** — the send button becomes a red ⏹ while the AI is streaming; clicking it aborts
  the `ReadableStream` via `AbortController`. If messages are queued, a disambiguation dialog asks
  whether to keep or clear them.
- **Soft query queue** — messages submitted while the AI is responding are held in
  `pendingMessages[]` and auto-submitted one-at-a-time as each reply completes.
- **`TaskList` component** — appears below the active reply bubble; shows LangGraph generation
  sub-tasks (via custom DOM events) and queued chat messages in one unified panel with per-row
  stop/retry/remove buttons.
- **QC Gate inline** — `showQcInline` state in `workflow-artifact.tsx` renders QC Gate review
  as an amber panel inside the right panel instead of a full-screen modal popup.
- **LangGraph foundation** — `langgraph>=1.1.2` installed; `pending_tasks` DB table added to
  LTM schema; `_looks_like_multi_task` heuristic + `_handle_multi_task_clarification` flow in
  `ai_assistant.py`; `/api/pipelines/:pipelineId/events` SSE endpoint wired to Redis.

### Current status

| What works | What is next |
|---|---|
| Stop button with abort + disambiguation dialog | LangGraph StateGraph nodes (Phase 1) |
| Query soft-queue with auto-submit | Backend→frontend task SSE publisher |
| `TaskList` component (client-side state only) | Per-task Celery revocation |
| QC Gate inline amber panel | Full QC Gate inline feature parity |
| Multi-task detection + clarification text reply | Parallel Celery dispatch |
| `/api/pipelines/:id/events` SSE endpoint | Backend publishing to Redis channel |

### Time investment

Planning documents were written on 2026-03-10. Implementation landed in a single commit the same
day: ~2.5 days of design work preceding the commit, implementation itself estimated at 2 days
per the UX plan (Phase A: 1 day, B: 0.5 day, C: 0.5 day, D multi-task detection: 0.5 day).

---

## Section 2: Background — Why These Changes

### The original problem

BioMate processed exactly one query at a time. While the AI was generating a reply, submitting
another message either failed silently or the UI blocked input. There was no task tracking across
a multi-step request — users had to remember what they asked for and manually verify each step
completed. Compound queries ("Run QC, then DE, then export results") were accepted but responded
to sequentially as a single undifferentiated block of text.

### UX confusion that existed

Two distinct things shared the name "pause" and "resume":

1. **Workflow execution pause** — `POST /api/workflows/runs/:id/pause` in the right panel.
   This changes a DB column to `'paused'` but does **not** send any signal to the running Nextflow
   process. The cluster job continues computing. The button label was misleading.

2. **LangGraph graph resume** — resuming a checkpointed state graph after the user answers a
   clarification question. Completely different semantics.

Additionally, the **`QCGateModal`** was a full-screen modal popup. When a `qc_gate_triggered` SSE
event fired, the modal covered the entire interface — users lost their chat context, could no
longer see the workflow state, and had no idea what was happening to other tasks. This was the
most-complained-about UX issue in internal testing.

### What users were asking for

The `20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md` audit captured the pattern clearly:
users routinely submit compound requests such as:

> "First run QC on my FASTQ, then align to hg38, then call variants"
> "Run RNA-seq analysis and then do differential expression"

These arrive as a single message but imply 2–5 sequential workflow generation tasks. BioMate had
no way to:
- Show which sub-task it was currently working on
- Let the user stop one sub-task without killing all of them
- Notify the user that earlier steps were done while later ones were still running

### The architectural analysis: what already existed

The analysis in `20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md` found that BioMate already
had most of the required infrastructure:

| Component | Status before this work |
|---|---|
| `TaskDecomposer` (backend) | Exists, not wired to production route |
| `TaskGraph` with topological sort | Exists, unused in API path |
| `WorkflowOptimizer._identify_parallel_groups()` | Exists, unused |
| Celery 5.5.3 | Installed, used by Galaxy for job metadata |
| Redis | Running, used for HTTP sessions |
| Postgres | Running, stores LTM schema |

The gap was not infrastructure — it was **orchestration wiring**: nothing connected
`TaskDecomposer` → Celery → `pending_tasks` → SSE → frontend.

### Design decision: minimal, additive-only changes

The UX plan (`20260310_WORKFLOW_UX_SIMPLIFICATION.md`) set three rules that governed all design
decisions:

> 1. The **chat stop button** (⏹) stops the current AI reply stream and optionally clears the
>    task queue. It **never** touches a running workflow.
> 2. The **right panel** (existing Workflow Artifact Viewer with ExecutionControlPanel) controls
>    running cluster jobs. Its vocabulary — Pause, Resume, Cancel, QC Gate, Sandbox, Promote —
>    is unchanged and stays exactly where it is today.
> 3. **Per-task row buttons** in the task list give granular control over each AI generation task
>    and each queued message independently.

No `App.tsx` layout restructuring. No renaming of existing controls. No new panels added. Every
change is purely additive on top of what existed.

---

## Section 3: Architecture — What Changed

### 3.1 Frontend — Chat Input Layer

**File:** `frontend/client/src/components/chat-input.tsx`

The `ChatInput` component gained two new props and a conditional render of the action button:

```typescript
interface ChatInputProps {
  onSend: (message: string, files?: File[]) => void
  disabled?: boolean
  pendingCount?: number          // badge count on the button
  placeholder?: string
  onFilesSelected?: (files: File[]) => void
  isStreaming?: boolean          // NEW — true while AI is generating
  onStop?: () => void            // NEW — called when ⏹ is clicked
}
```

The button render branches on `isStreaming`:

```tsx
{isStreaming ? (
  <Button
    data-testid="chat-stop-button"
    onClick={onStop}
    size="icon"
    variant="destructive"
    className="h-[44px] w-[44px] flex-shrink-0 relative"
    title="Stop reply"
  >
    {pendingCount > 0 && (
      <span className="absolute -top-1.5 -right-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white">
        {pendingCount}
      </span>
    )}
    <Square className="w-4 h-4 fill-current" />
  </Button>
) : (
  <Button
    data-testid="chat-send-button"
    onClick={handleSend}
    disabled={!message.trim() && attachedFiles.length === 0}
    ...
  >
    <Send className="w-4 h-4" />
  </Button>
)}
```

`Square` (from `lucide-react`) renders as the ⏹ icon. When `pendingCount > 0`, an amber badge
appears at top-right of the stop button showing how many messages are queued.

**`AbortController` wiring in `chat-interface.tsx`:**

```typescript
const abortControllerRef = useRef<AbortController | null>(null)
```

The `chatMutation` function creates a fresh controller for every request and passes its signal
to the `fetch`:

```typescript
abortControllerRef.current = new AbortController()
const response = await fetch('/api/chat/stream', {
  method: 'POST',
  signal: abortControllerRef.current.signal,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ message: content, stream: true, context: { ... } })
})
```

On `AbortError`, the stream loop catches and returns a partial result gracefully:

```typescript
} catch (err: any) {
  if (err?.name === 'AbortError') {
    // Stream was stopped by user — not an error, just return what we have
    return finalPayload ?? { message: accumulatedText, aborted: true }
  }
  throw err
}
```

The `stopStreaming` callback:

```typescript
const stopStreaming = useCallback(() => {
  abortControllerRef.current?.abort()
  abortControllerRef.current = null
  setIsTypingLocal(false)
  const queuedCount = pendingMessagesRef.current.length
  if (queuedCount > 0) {
    setStopDialogQueueCount(queuedCount)
    setShowStopDialog(true)
  }
}, [])
```

If the queue is empty, the stream simply stops and the send button returns — no dialog. If
messages are queued, a snapshot of the count is taken (avoiding stale React state reads) and the
disambiguation dialog is shown.

**`isStreaming` prop flow:**

```typescript
// In chat-interface.tsx render:
<ChatInput
  onSend={handleSendOrQueue}
  pendingCount={pendingMessages.length}
  isStreaming={displayTyping}   // ← drives icon swap in chat-input.tsx
  onStop={stopStreaming}
/>
```

`displayTyping` is `true` when either `isTyping` (from parent) or `isTypingLocal` (local
streaming state) is true, and the streaming placeholder hasn't yet produced visible content.

**Disambiguation dialog** — rendered as an inline panel anchored just above the chat input,
not a full modal. Disappears after either choice:

```tsx
{showStopDialog && (
  <div
    className="mx-4 mb-2 rounded-lg border bg-background shadow-md p-3 text-sm"
    data-testid="stop-dialog"
  >
    <p className="font-medium mb-2 text-foreground">
      Reply stopped. What should happen to your {stopDialogQueueCount} queued message{stopDialogQueueCount !== 1 ? 's' : ''}?
    </p>
    <div className="flex gap-2">
      <button
        data-testid="stop-reply-only"
        onClick={() => setShowStopDialog(false)}
      >
        Keep queued ({stopDialogQueueCount})
      </button>
      <button
        data-testid="stop-and-clear-queue"
        onClick={() => {
          setPendingMessages([])
          setShowStopDialog(false)
        }}
      >
        Clear all queued
      </button>
    </div>
  </div>
)}
```

---

### 3.2 Frontend — Task List

**File:** `frontend/client/src/components/task-list.tsx` (new file)

**`TaskItem` type definition:**

```typescript
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'stopped' | 'skipped'

export interface TaskItem {
  id: string
  description: string
  status: TaskStatus
  elapsedMs?: number
}
```

**Status state machine:**

```
pending → running → completed
                 → failed → retry → pending → running → ...
                 → stopped → retry → pending → running → ...
```

`skipped` is a terminal state for tasks whose upstream dependency failed.

**Status icon rendering:**

```typescript
function StatusIcon({ status }: { status: TaskStatus }) {
  switch (status) {
    case 'completed': return <CheckCircle2 className="h-3.5 w-3.5 text-green-500 flex-shrink-0" />
    case 'running':   return <Loader2 className="h-3.5 w-3.5 text-blue-500 animate-spin flex-shrink-0" />
    case 'failed':    return <XCircle className="h-3.5 w-3.5 text-red-500 flex-shrink-0" />
    case 'stopped':   return <StopCircle className="h-3.5 w-3.5 text-amber-500 flex-shrink-0" />
    case 'skipped':   return <Minus className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
    default:          return <Circle className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
  }
}
```

**`langgraphTaskUpdate` custom DOM event protocol:**

`chat-interface.tsx` registers a `window` event listener on mount:

```typescript
useEffect(() => {
  const handler = (e: CustomEvent<{
    task_id: string
    status: TaskStatus
    description?: string
    elapsed_ms?: number
  }>) => {
    const { task_id, status, description, elapsed_ms } = e.detail
    setLanggraphTasks(prev => {
      const existing = prev.find(t => t.id === task_id)
      if (existing) {
        return prev.map(t =>
          t.id === task_id ? { ...t, status, elapsedMs: elapsed_ms } : t
        )
      }
      return [...prev, { id: task_id, description: description || task_id, status, elapsedMs: elapsed_ms }]
    })
  }
  window.addEventListener('langgraphTaskUpdate', handler as EventListener)
  return () => window.removeEventListener('langgraphTaskUpdate', handler as EventListener)
}, [])
```

**Event payload shape:**
```typescript
{
  task_id: string       // unique task identifier (UUID)
  status: TaskStatus    // one of the 6 states above
  description?: string  // human-readable task name (on first occurrence)
  elapsed_ms?: number   // shown on completed/failed rows
}
```

The protocol is deliberately simple: any code anywhere (SSE handlers, browser console) can fire
`window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', { detail: { ... } }))` and the task
list updates reactively.

**`TaskList` is rendered conditionally** — it only appears when there is something to show:

```tsx
{(langgraphTasks.length > 0 || pendingMessages.length > 0) && (
  <div className="px-4 pb-2">
    <TaskList
      tasks={langgraphTasks}
      queuedMessages={pendingMessages}
      onStopTask={handleStopTask}
      onRemoveTask={handleRemoveTask}
      onRetryTask={handleRetryTask}
      onRemoveMessage={(i) => setPendingMessages(prev => prev.filter((_, idx) => idx !== i))}
    />
  </div>
)}
```

Queued chat messages appear in the **same panel** below a visual divider, marked with `○` and
an italic truncated preview. Each has its own `[×]` remove button.

**Collapse-to-summary behaviour:**

When all tasks reach `completed` or `skipped`, a "collapse" button appears in the panel header.
After collapsing, the component renders as a single summary line with a "show steps" link:

```tsx
if (allDone && !expanded) {
  return (
    <div data-testid="task-list-summary" className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
      <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
      <span>{tasks.length} step{tasks.length !== 1 ? 's' : ''} complete</span>
      <button onClick={() => setExpanded(true)}>show steps</button>
    </div>
  )
}
```

---

### 3.3 Frontend — QC Gate Inline

**File:** `frontend/client/src/components/workflow-artifact.tsx`

**Before:** When `qc_gate_triggered` SSE fired, `setShowQCGateModal(true)` was called, rendering
`<QCGateModal>` as a full-screen dialog covering the entire interface.

**After:** A new `showQcInline` boolean state controls an inline amber panel at the top of the
right panel's content area.

```typescript
// State additions
const [showQCGateModal, setShowQCGateModal] = useState(false)    // legacy, never set to true now
const [showQcInline, setShowQcInline] = useState(false)          // new
```

When `qc_gate_triggered` SSE fires: `setShowQcInline(true)` (and `setShowQCGateModal` is never
called, so the old modal never appears).

**Inline panel render** (inside `workflow-artifact.tsx`, at the top of the artifact content):

```tsx
{showQcInline && qcGateData && (
  <div
    data-testid="qc-gate-inline"
    className="mt-3 rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-3"
  >
    <div className="flex items-start gap-2 mb-2">
      <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-400 mt-0.5 shrink-0" />
      ...
    </div>
    ...
    {qcGateData.suggestions.length > 0 && (
      <button
        data-testid="qc-gate-apply"
        onClick={() => { void handleRetryWithSuggestions() }}
      >
        Apply suggestions
      </button>
    )}
    <button data-testid="qc-gate-keep" onClick={handleProceedAnyway}>
      Keep current
    </button>
    ...
  </div>
)}
```

The handlers (`handleRetryWithSuggestions`, `handleProceedAnyway`, `handleCancelWorkflow`) are
**unchanged** — the same API calls, the same logic, just triggered from the inline panel
instead of the modal.

**Rollback path** — `QCGateModal` is kept in the codebase but rendered under a `false &&` guard:

```tsx
{/* QC Gate Modal (Gap 3) — kept for restoration; replaced by inline panel above */}
{false && showQCGateModal && qcGateData && (
  <QCGateModal ... />
)}
```

To roll back to the modal: delete the `false &&` prefix and set `showQcInline` trigger to call
`setShowQCGateModal(true)` instead.

---

### 3.4 Backend — LangGraph Foundation

**LangGraph installed:**

```
# backend/requirements.txt (line 99)
langgraph>=1.1.2
```

**`pending_tasks` DB table** — added to `frontend/shared/ltm-schema.ts`:

```typescript
export const pendingTasks = pgTable("pending_tasks", {
  id:               uuid("id").primaryKey().defaultRandom(),
  userId:           uuid("user_id").references(() => ltmUsers.id, { onDelete: "cascade" }),
  sessionId:        text("session_id"),
  parentPipelineId: uuid("parent_pipeline_id"),   // groups sub-tasks of one compound request
  description:      text("description").notNull(),
  taskType:         text("task_type"),             // WORKFLOW | RESEARCH | EXPORT | QC
  status:           text("status").default("pending"),  // pending|dispatched|running|completed|failed
  dependsOn:        uuid("depends_on").array().default([]),
  celeryTaskId:     text("celery_task_id"),
  resultPath:       text("result_path"),
  errorMessage:     text("error_message"),
  createdAt:        timestamp("created_at").defaultNow(),
  startedAt:        timestamp("started_at"),
  completedAt:      timestamp("completed_at"),
});
```

**`_looks_like_multi_task` heuristic** in `ai_assistant.py`:

```python
def _looks_like_multi_task(self, query: str) -> bool:
    """
    Quick heuristic check: does this query contain multiple distinct workflow intents?
    If yes, route to TaskDecomposer. If no, use the fast single-task path.
    """
    multi_task_signals = [
        ' then ', ' and then ', ', then ',
        'first.*then', 'step 1', 'step 2',
        'followed by', 'after that', 'next,',
        'also run', 'also do', 'additionally',
    ]
    query_lower = query.lower()
    signal_count = sum(1 for s in multi_task_signals if s in query_lower)
    return signal_count >= 1
```

Threshold is **1 signal** — if any one signal phrase appears, the multi-task path is taken.

**`_handle_multi_task_clarification` flow:**

```python
async def _handle_multi_task_clarification(self, query: str, context: dict) -> dict:
    pipeline_id = str(uuid_mod.uuid4())
    # 1. Decompose into tasks
    decomposer = TaskDecomposer(config)
    parsed_intent = decomposer.parse_intent(query)
    tasks = decomposer.decompose_request(user_request, parsed_intent)

    if not tasks:
        return await self._handle_workflow_generation(query, context)

    # 2. Check for missing required parameters
    missing = self._find_missing_context(tasks, context)

    if missing:
        # Return a plain text reply with clarification questions — no special UI needed
        questions_text = '\n'.join(f'{i+1}. {q}' for i, q in enumerate(missing))
        return {
            'message': f"Before I prepare your {len(tasks)}-step workflow, I have a few questions:\n\n"
                       f"{questions_text}\n\nOnce you answer, I'll get started right away.",
            'needs_clarification': True,
            'pipeline_id': pipeline_id,
        }

    # 3. No missing context — generate sequentially for now (Phase 1: parallel Celery dispatch)
    log.info(f"[MultiTask] {len(tasks)} tasks detected, generating sequentially for now")
    return await self._handle_workflow_generation(query, context)
```

**`_find_missing_context`** checks two categories of required parameters:

```python
def _find_missing_context(self, tasks: list, context: dict) -> list:
    missing = []
    ctx = context or {}

    # Check organism (required for sequencing tasks)
    has_organism = any(k in ctx for k in ('organism', 'species', 'genome', 'reference')) \
        or any(k in str(ctx.get('accumulatedFacts', ''))
               for k in ('organism', 'species', 'homo sapiens', 'mus musculus', 'human', 'mouse'))

    needs_seq = any(
        any(kw in t.description.lower()
            for kw in ('rna', 'seq', 'fastq', 'align', 'mapping', 'qc'))
        for t in tasks
    )

    if needs_seq and not has_organism:
        missing.append("What organism are you working with? (e.g., Homo sapiens, Mus musculus)")

    if needs_seq and 'read_type' not in ctx and 'paired' not in str(ctx.get('accumulatedFacts', '')):
        missing.append("Are your reads paired-end or single-end?")

    return missing
```

**`/api/pipelines/:pipelineId/events` SSE endpoint** in `frontend/server/routes.ts`:

```typescript
app.get("/api/pipelines/:pipelineId/events", (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  res.flushHeaders?.();

  // Send a ready event immediately so the client knows the channel is open
  res.write(`event: ready\ndata: {"ok":true}\n\n`);

  // Subscribe to Redis channel published by Celery workers
  let redisSub: any = null;
  try {
    const { getRedisClient } = require('./redis-session');
    const client = getRedisClient?.();
    if (client) {
      redisSub = client.duplicate();
      redisSub.subscribe(`biomate:pipeline:${req.params.pipelineId}`);
      redisSub.on("message", (_chan: string, msg: string) => {
        res.write(`data: ${msg}\n\n`);
      });
    }
  } catch (e) {
    console.warn('[PipelineSSE] Redis not available, events will not relay:', e);
  }

  // Heartbeat every 30s to keep connection alive through proxies
  const heartbeat = setInterval(() => { res.write(`: heartbeat\n\n`); }, 30000);

  req.on("close", () => {
    clearInterval(heartbeat);
    redisSub?.quit?.();
  });
});
```

The Redis channel convention is `biomate:pipeline:{pipelineId}`. When a Celery worker publishes
to this channel, the SSE endpoint relays the raw JSON to the browser. The browser SSE handler
would then fire `window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', { detail: parsed }))`.

---

## Section 4: Data Flow Diagrams

### Diagram 1: Stop button flow

```
User types message → clicks ▶ (Send)
         │
         └─── AI starts streaming reply ──────────────────────────────┐
                   │                                                   │
                   │  (isStreaming = true → button shows red ⏹)       │
                   │                                                   │
              User types more messages while waiting                   │
                   │                                                   │
                   └── added to pendingMessages[]                      │
                         (badge count shows on ⏹ button)              │
                                                                       │
                                             User clicks ⏹            │
                                                    │                  │
                                   abortControllerRef.current.abort() ─┘
                                                    │
                                          setIsTypingLocal(false)
                                                    │
                                     pendingMessages.length > 0?
                                                    │
                        ┌───────────────────────────┼──────────────────┐
                       yes                          no (empty queue)
                        │                           │
                 snapshot count,                stream aborted
                 setShowStopDialog(true)        send button returns (▶)
                        │                       no dialog shown
                        ▼
             ┌──────────────────────────┐
             │  "Reply stopped. What    │
             │   should happen to your  │
             │   N queued messages?"    │
             │                          │
             │  [Keep queued (N)]       │
             │  [Clear all queued]      │
             └──────────────────────────┘
                        │
         ┌──────────────┴────────────────┐
    "Keep queued"                  "Clear all queued"
         │                              │
  setShowStopDialog(false)        setPendingMessages([])
  queue intact                    setShowStopDialog(false)
  useEffect auto-submits          queue empty, send button idle (▶)
  next queued message
```

### Diagram 2: Multi-task query flow (backend)

```
User sends compound query (e.g. "Run QC, then DE, then export")
         │
         ▼
ai_assistant.route_and_handle()
         │
_looks_like_multi_task(query)
         │
   checks for signals: ' then ', 'followed by', 'also run', etc.
   threshold: >= 1 signal
         │
   no ───┤──→ existing single-task path (unchanged)
         │
   yes
         │
         ▼
_handle_multi_task_clarification(query, context)
         │
         ├── generate pipeline_id (UUID)
         │
         ▼
TaskDecomposer.parse_intent(query)
TaskDecomposer.decompose_request(user_request, parsed_intent)
         │
         ├── no tasks → fall back to single-task path
         │
         ▼
_find_missing_context(tasks, context)
         │
   checks: organism? read_type? (for sequencing tasks)
         │
         ├── missing params found
         │         │
         │         ▼
         │   return {
         │     message: "Before I prepare your N-step workflow, I have a few questions:\n..."
         │     needs_clarification: true,
         │     pipeline_id: "...",
         │   }
         │   → frontend renders as normal text reply
         │   → user types answer → next message processed normally
         │
         └── no missing params
                   │
                   ▼
            generate sequentially for now (single-task path called once)
            [logged: "[MultiTask] N tasks detected, generating sequentially for now"]
                   │
                   ▼
            ┌─────────────────────────────────────────────────────────┐
            │  FUTURE (Phase 1 — not yet implemented):                │
            │                                                         │
            │  LangGraph StateGraph.ainvoke(initial_state)            │
            │    classify node → check_clarification node             │
            │       → dispatch node (Celery fan-out)                  │
            │          ├── compose_workflow_task(task_A) ─┐           │
            │          └── compose_workflow_task(task_B) ─┤           │
            │                                             ▼           │
            │                              merge node → respond node  │
            │  Each Celery task publishes to Redis:                   │
            │    biomate:pipeline:{id} → SSE endpoint → browser       │
            │    → window.dispatchEvent('langgraphTaskUpdate')         │
            │    → TaskList component updates in real time             │
            └─────────────────────────────────────────────────────────┘
```

---

## Section 5: What Is NOT Yet Done (Honest Gap Analysis)

### Gap 1 — LangGraph StateGraph not yet wired

`_handle_multi_task_clarification` **detects** multi-task queries and **asks clarification
questions** when context is missing. But the actual parallel Celery dispatch — the LangGraph
StateGraph with `classify → check_clarification → dispatch → merge → respond` nodes — is
**not implemented**. When no context is missing, the code falls back to the single-task
`_handle_workflow_generation()` path with a log message:

```python
# No missing context — fall back to single-task generation for now.
# Full parallel dispatch (LangGraph + Celery) is Phase 1 of the main plan.
log.info(f"[MultiTask] {len(tasks)} tasks detected, generating sequentially for now")
return await self._handle_workflow_generation(query, context)
```

The `pending_tasks` table exists in the DB schema but **nothing writes to it from production
code paths yet**. The `langgraph_checkpoints` table (for graph state persistence) has not been
created — that happens via `PostgresSaver.setup()` when the graph is first built.

**What is needed:** Implement `backend/lib/galaxy/ai/orchestration/` directory with
`state.py`, `nodes.py`, `graph.py`, `celery_tasks.py` per the `LANGGRAPH_INTEGRATION_PLAN.md`
Phase 1–2 spec.

---

### Gap 2 — Task list only shows client-side state

The `TaskList` component receives `langgraphTasks` state, which is populated by
`langgraphTaskUpdate` custom DOM events. Currently **no backend code fires these events**.
The `/api/pipelines/:id/events` SSE endpoint exists and relays Redis messages — but the Celery
worker `compose_workflow_task` that should publish to Redis (`_notify_sse()`) does not exist yet.

The task list can be tested manually by injecting events from the browser console:

```javascript
// Simulate a running task
window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
  detail: { task_id: 'test-1', status: 'running', description: 'Write QC workflow' }
}))

// Mark it complete
window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
  detail: { task_id: 'test-1', status: 'completed', elapsed_ms: 3200 }
}))
```

But in production, the task list will remain empty until the Celery→Redis→SSE bridge is wired.

---

### Gap 3 — QC Gate inline is minimal

The full `QCGateModal` included:
- A metric detail table showing each QC metric value vs. threshold
- Per-suggestion checkboxes (apply some, skip others)
- A two-step confirm flow ("are you sure?" before applying)
- Domain-specific troubleshooting steps (e.g., "If mito fraction > 30%, check...")
- Citation badges linking to papers that established the thresholds

The inline panel has only three buttons: **Apply suggestions**, **Keep current**, **Cancel run**.
No metric table. No per-suggestion selection. No troubleshooting steps.

**Priority:** Medium. The most important actions (apply/keep/cancel) are present. The metric
table and per-suggestion granularity are the first things to restore.

---

### Gap 4 — Pause button still a soft flag

`POST /api/workflows/runs/:id/pause` sets the `status` column to `'paused'` in the DB.
The running Nextflow process on the cluster continues computing. This is a **pre-existing gap**
documented in both `LANGGRAPH_INTEGRATION_PLAN.md` (Gap 1) and the UX plan:

```
[Pause]  ⓘ Records intent; computation continues until Cancel
```

The informational note has been added to the UI, but real process suspension is not implemented.
True pause would require either `SIGSTOP` (fragile) or Nextflow's `-resume` flag (checkpoint
re-use), which would require re-submitting from the last cached step.

---

### Gap 5 — `_looks_like_multi_task` is a heuristic with false positives

The signal list includes broad phrases. A query like:

> "Run QC and show me the results"

...contains `' and '` adjacent to `' then '` patterns and may trigger the multi-task path when
it should be handled as a single task. The threshold of **1 signal** is intentionally conservative
but may route too many requests through multi-task clarification unnecessarily, adding latency.

Confirmed signals that should reliably trigger the path: `' then '`, `'followed by'`, `'after that'`.  
Borderline: `'also run'`, `'additionally'` — these appear in single-task queries too.

**Mitigation options:**
1. Raise threshold to 2 signals
2. Replace heuristic with `TaskDecomposer.parse_intent()` LLM classification (more accurate, adds ~100ms)
3. Add a negative-signal list (single-task markers) to cancel out false positives

---

### Gap 6 — No per-task Celery revocation

The `[Stop]` button in the `TaskList` calls `handleStopTask(taskId)` which sets local React
state to `stopped`. It does **not** call any API endpoint:

```typescript
const handleStopTask = useCallback((taskId: string) => {
  setLanggraphTasks(prev =>
    prev.map(t => t.id === taskId ? { ...t, status: 'stopped' as TaskStatus } : t)
  )
}, [])
```

The actual Celery task (if one existed) would continue running. To truly cancel, the backend
needs `celery.control.revoke(celery_task_id, terminate=True)` and an update to the
`pending_tasks` row.

---

## Section 6: How to Test

### Local setup

```bash
cd /home/yzhang/biomate/frontend
npm run dev  # starts on port 5000
```

### Run the new tests

```bash
npx playwright test e2e/phase-ab-stop-button-task-list.e2e.ts --reporter=list
npx playwright test e2e/deep-audit-implementation.e2e.ts --reporter=list
```

### Manual test checklist

#### Stop button

- [ ] Send a message → send button shows ▶ (Send icon)
- [ ] While AI is responding → button shows red ⏹ (Square icon, destructive variant)
- [ ] Click ⏹ with no queued messages → stream stops, ▶ returns immediately, no dialog appears
- [ ] Queue a message while AI responds → ⏹ shows amber badge with count
- [ ] Click ⏹ with queued messages → `data-testid="stop-dialog"` appears with correct count in text
- [ ] Click "Keep queued (N)" → dialog closes, queue badge still shows N, next message auto-submits
- [ ] Click "Clear all queued" → dialog closes, badge gone, no further auto-submit

#### Task list

- [ ] No tasks + no queued messages → `data-testid="task-list"` is not rendered
- [ ] Queue a message while AI responds → task list appears with queued message row (Circle icon, italic text)
- [ ] Inject `langgraphTaskUpdate` event with `status: 'running'` → row appears with `[Stop]` button
- [ ] Click `[Stop]` → row shows amber StopCircle icon, `[Retry]` button appears
- [ ] Click `[Retry]` → row changes to pending (Circle icon), `[Stop]` button returns
- [ ] Inject `status: 'completed'` with `elapsed_ms: 3200` → row shows green checkmark, "3.2s" elapsed
- [ ] All tasks completed → "collapse" button appears in panel header
- [ ] Click "collapse" → panel shrinks to one-line summary "N steps complete · show steps"
- [ ] Click "show steps" → full panel re-expands

#### QC Gate

- [ ] Open a workflow artifact in right panel
- [ ] Verify `data-testid="qc-gate-modal"` is **never** present in the DOM (modal is fully suppressed)
- [ ] Simulate `qc_gate_triggered` SSE → `data-testid="qc-gate-inline"` amber panel appears
- [ ] Panel contains AlertTriangle icon + "Apply suggestions" + "Keep current" + "Cancel run" buttons
- [ ] Click "Apply suggestions" → `handleRetryWithSuggestions` runs, panel closes when done
- [ ] Click "Keep current" → `handleProceedAnyway` runs, panel closes
- [ ] Chat stream and right panel controls (Pause/Resume/Cancel) remain visible throughout — no overlay

### Inject test events from browser console

```javascript
// Test task list with a running task
window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
  detail: { task_id: 'test-1', status: 'running', description: 'Write QC workflow' }
}))

// Update to completed with elapsed time
window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
  detail: { task_id: 'test-1', status: 'completed', elapsed_ms: 3200 }
}))

// Add a failed task to test retry button
window.dispatchEvent(new CustomEvent('langgraphTaskUpdate', {
  detail: { task_id: 'test-2', status: 'failed', description: 'Write DE workflow' }
}))
```

---

## Section 7: Next Steps (Prioritised)

**1. Wire LangGraph StateGraph to Celery** *(Phase 1 of LANGGRAPH_INTEGRATION_PLAN.md)*  
Create `backend/lib/galaxy/ai/orchestration/` with `state.py`, `nodes.py`, `graph.py`. Implement
the `classify → check_clarification → dispatch → merge → respond` graph with Postgres
checkpointing. Replace the sequential fallback in `_handle_multi_task_clarification` with
`graph.ainvoke()`. This is the core parallel dispatch — without it, multi-task queries still
run sequentially.

**2. Backend → frontend task SSE bridge** *(Phase 2 of LANGGRAPH_INTEGRATION_PLAN.md)*  
Implement `backend/lib/galaxy/ai/orchestration/celery_tasks.py` with `compose_workflow_task`
Celery task. Each status transition (`running`, `completed`, `failed`) calls `_notify_sse()` which
publishes to `biomate:pipeline:{id}` Redis channel. The SSE endpoint exists and relays — the
publisher doesn't. Once wired, the `TaskList` component will receive live updates without any
frontend changes.

**3. Per-task Celery revocation**  
When user clicks `[Stop]` on a task row, call
`POST /api/pipelines/:pipelineId/tasks/:taskId/stop` → backend calls
`celery.control.revoke(celery_task_id, terminate=True)` and sets `pending_tasks.status = 'stopped'`.
Currently the [Stop] button only changes local React state.

**4. QC Gate inline enrichment**  
Restore the full feature set from the old `QCGateModal` into the inline amber panel:
metric detail table, per-suggestion checkboxes, two-step confirmation before applying, domain
troubleshooting steps per failure type, citation badges. The handlers are already wired — only
the UI content needs expanding.

**5. Multi-task clarification session handoff**  
When user answers the clarification questions, `_handle_multi_task_clarification` generates a
`pipeline_id` and includes it in the response. The frontend currently renders this as a plain
text reply but does **not** pass the `pipeline_id` back in the next message's context. The backend
cannot resume the correct LangGraph checkpoint without it. Fix: store `pipeline_id` in conversation
context and include it in subsequent API calls; add `POST /api/pipelines/:pipelineId/resume`
endpoint to resume graph execution with user answers.

**6. Fix soft Pause**  
Implement real checkpoint-based pause via Nextflow's `-resume` flag. This would re-submit the
Nextflow job specifying the `.nextflow/cache` directory from the prior run, resuming from the
last successful step. Alternatively, add `SIGSTOP` support to `nextflow_runner.stop_job()` and a
corresponding `SIGCONT` for resume. Currently Pause only sets a DB flag.

**7. `_looks_like_multi_task` tuning**  
Raise threshold from 1 to 2 signals, or replace the keyword heuristic with
`TaskDecomposer.parse_intent()` LLM classification. Add a negative-signal list to suppress
false positives on phrases like "run X and show me Y" (single-task with a display request).

---

## Section 8: Files Changed

From `git show --stat HEAD`:

```
12 files changed, 2992 insertions(+), 533 deletions(-)
```

| File | What changed |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py` | Added `_looks_like_multi_task`, `_handle_multi_task_clarification`, `_find_missing_context` methods; multi-task detection at the top of `route_and_handle()` (+105 lines) |
| `docs/20260310_LANGGRAPH_INTEGRATION_PLAN.md` | New document — full LangGraph integration plan including StateGraph node code, Celery task template, SSE bridge design, phased implementation schedule |
| `docs/20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md` | New document — background analysis of existing TaskDecomposer/Celery/Redis infrastructure; options evaluation (LangGraph vs Prefect vs CrewAI) |
| `docs/20260310_WORKFLOW_UX_SIMPLIFICATION.md` | New document — UX design for stop button, task list, and QC Gate inline; 10 use-case test definitions |
| `frontend/client/src/App.tsx` | Minor wiring changes for task list and streaming state propagation |
| `frontend/client/src/components/chat-input.tsx` | Added `isStreaming` and `onStop` props; conditional Send/Stop button render; amber badge on stop button for queued count |
| `frontend/client/src/components/chat-interface.tsx` | Added `abortControllerRef`; AbortController wired to `/api/chat/stream` fetch; `stopStreaming()` callback; soft queue (`pendingMessages` state + auto-submit effect); `langgraphTasks` state + DOM event listener; `showStopDialog` + disambiguation UI; `<TaskList>` render |
| `frontend/client/src/components/task-list.tsx` | New file — `TaskItem` type, `TaskStatus` type, `StatusIcon` component, `TaskList` component with collapse behaviour |
| `frontend/client/src/components/workflow-artifact.tsx` | Added `showQcInline` state; inline QC Gate amber panel render; `false &&` guard on old `QCGateModal`; `handleRetryWithSuggestions`, `handleProceedAnyway`, `handleCancelWorkflow` handlers unchanged |
| `frontend/e2e/phase-ab-stop-button-task-list.e2e.ts` | New E2E test file — stop button behaviour (no queue, with queue, disambiguation), task list render/collapse/retry, queued message remove |
| `frontend/server/routes.ts` | Added `GET /api/pipelines/:pipelineId/events` SSE endpoint with Redis pub/sub relay and 30s heartbeat; removed ~533 lines (cleanup/consolidation) |
| `frontend/shared/ltm-schema.ts` | Added `pendingTasks` pgTable definition; `insertPendingTaskSchema`, `selectPendingTaskSchema`, `PendingTask` and `InsertPendingTask` type exports |

---

## Section 9: References

| Document | Purpose |
|---|---|
| [`docs/20260310_WORKFLOW_UX_SIMPLIFICATION.md`](./20260310_WORKFLOW_UX_SIMPLIFICATION.md) | Full UX design: stop button decision tree, task list layout, QC Gate inline spec, 10 use-case definitions |
| [`docs/20260310_LANGGRAPH_INTEGRATION_PLAN.md`](./20260310_LANGGRAPH_INTEGRATION_PLAN.md) | LangGraph StateGraph implementation plan: state schema, node code, graph assembly, Celery task template, phased schedule, test plan |
| [`docs/20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md`](./20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md) | Background analysis: what infrastructure existed before, gap analysis, why LangGraph+Celery was chosen |
| [`docs/20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md`](./20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md) | Earlier queue and multi-task UX planning |
| [`docs/20260310_QUEUE_AND_STATUS_IMPLEMENTATION_FINDINGS.md`](./20260310_QUEUE_AND_STATUS_IMPLEMENTATION_FINDINGS.md) | Implementation audit findings |
