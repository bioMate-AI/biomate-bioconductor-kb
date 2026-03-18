# LangGraph Integration Plan — BioMate Task Orchestration

**Date:** 2026-03-10  
**Status:** Planning  
**Related docs:**
- [`20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md`](./20260310_TASK_ORCHESTRATION_AND_PARALLEL_EXECUTION.md) — Background analysis
- [`20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md`](./20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md) — UI/UX plan

---

## Executive Summary

LangGraph replaces BioMate's ad-hoc multi-task orchestration with a stateful directed graph
where each node is a composable AI action (clarify → decompose → compose_workflow → validate →
execute). Independent sub-tasks fan out in parallel via Celery. A `pending_tasks` table persists
the task list across page refreshes. SSE streams per-task status to the frontend in real time.

**No new infrastructure required.** Redis and Celery are already installed and running.

---

## Architecture Overview

```
User message (compound request)
         │
         ▼
┌────────────────────────────────────────────────────────┐
│               LangGraph StateGraph                     │
│                                                        │
│  ┌──────────┐    ┌────────────┐    ┌──────────────┐   │
│  │ CLASSIFY │───▶│ CLARIFY    │───▶│ DECOMPOSE    │   │
│  │          │    │ (optional) │    │ TaskGraph    │   │
│  └──────────┘    └────────────┘    └──────┬───────┘   │
│                                           │            │
│                        ┌──────────────────┤            │
│                        │   Fan-out on     │            │
│                        │  independence    │            │
│              ┌─────────▼──┐  ┌────────────▼──┐        │
│              │ COMPOSE    │  │ COMPOSE        │        │
│              │ sub-task A │  │ sub-task B     │        │
│              │ (Celery)   │  │ (Celery)       │        │
│              └─────────┬──┘  └────────────┬──┘        │
│                        └────────┬──────────┘           │
│                                 │                      │
│                        ┌────────▼──────┐               │
│                        │  MERGE &      │               │
│                        │  VALIDATE     │               │
│                        └────────┬──────┘               │
│                                 │                      │
│                        ┌────────▼──────┐               │
│                        │  RESPOND      │               │
│                        │  to user      │               │
│                        └───────────────┘               │
└────────────────────────────────────────────────────────┘
         │                     │
         ▼                     ▼
  pending_tasks DB        SSE stream
  (persists state)    (per-task updates)
```

---

## Relation to the Existing Workflow Control Panel

This section clarifies the boundary between the **existing execution control panel**
and the **new LangGraph orchestration layer**. They operate at different levels and
must not be confused or duplicated.

### What the existing control panel does (today, fully working)

```
┌─────────────────────────────────────────────────────────────────┐
│             Existing Workflow Control Panel                     │
│                                                                 │
│  Scope: ONE generated workflow, after it has been submitted     │
│                                                                 │
│  Pause/Resume   →  POST /api/workflows/runs/:id/pause|resume   │
│                     Updates status flag in DB only.             │
│                     Does NOT send SIGSTOP to the Nextflow proc. │
│                     Effectively a "soft pause" / user intent.   │
│                                                                 │
│  Cancel         →  POST /api/workflows/runs/:id/cancel         │
│                     Updates status flag in DB.                  │
│                     Galaxy cancel: deletes the invocation.      │
│                     Nextflow: nextflow_runner.stop_job() sends  │
│                     process.terminate() (SIGTERM) to NF proc.   │
│                                                                 │
│  QC Gate Pause  →  SSE event "qc_gate_triggered"               │
│  (most important)   User sees QCGateModal. They accept/reject   │
│                     parameter suggestions. Workflow continues   │
│                     or they cancel. Not a process-level pause.  │
│                                                                 │
│  Sandbox→Prod   →  Mode toggle + fraction slider               │
│  Promote        →  Run 10%/25% pilot first; promote to full.   │
│                                                                 │
│  Resume (ctrl)  →  Calls resumeRun() in useUnifiedExecution    │
│                     → POST /api/workflows/runs/:id/resume       │
│                     Changes status back to 'running'.           │
│                     Does NOT actually restart Nextflow.         │
└─────────────────────────────────────────────────────────────────┘
```

### What LangGraph adds (new layer, above the control panel)

```
┌─────────────────────────────────────────────────────────────────┐
│              LangGraph Orchestration (NEW)                      │
│                                                                 │
│  Scope: The AI GENERATION step, before any workflow runs        │
│                                                                 │
│  "Resume" here = resume the graph state after clarification     │
│                  (user answered a question → continue graph).   │
│                  Completely different from resuming a Nextflow  │
│                  run. Uses LangGraph checkpoint in Postgres.     │
│                                                                 │
│  "Pause" here  = interrupt_before="dispatch" node              │
│                  Graph checkpoints and waits. User can review   │
│                  the decomposed task list before sub-tasks are  │
│                  dispatched to Celery. Not a runtime pause.     │
│                                                                 │
│  "Cancel" here = abort the generation pipeline before any      │
│                  Nextflow workflow is even started.             │
└─────────────────────────────────────────────────────────────────┘
```

### Side-by-side comparison

| Dimension | Existing Control Panel | LangGraph (new) |
|-----------|----------------------|-----------------|
| **What it controls** | A single running Nextflow/Galaxy invocation | The AI generation pipeline (decompose → compose → merge) |
| **When it acts** | After workflow is executing on cluster | Before / during workflow code generation |
| **"Resume" meaning** | Change DB status `paused → running` (soft) | Resume checkpointed graph state from Postgres after clarification |
| **"Pause" meaning** | Change DB status `running → paused` (soft flag, not SIGSTOP) | `interrupt_before` — graph suspends at a node boundary, waits for user input |
| **"Cancel" meaning** | SIGTERM to Nextflow process + delete Galaxy invocation | Discard graph checkpoint; no Celery tasks fired |
| **QC Gate pause** | SSE event triggers modal; user reviews before accepting | Not in scope for LangGraph |
| **Sandbox/Promote** | Run 10% pilot → promote to 100% full run | Not in scope for LangGraph |
| **State persistence** | `execution_runs` table in Postgres | `langgraph_checkpoints` table in Postgres |
| **UI surface** | `ExecutionControlPanel` inside `workflow-artifact.tsx` | Active-runs status bar + pipeline sub-task pills (new) |

### Gap analysis

#### Gap 1 — Soft pause is not a real process pause

`POST /api/workflows/runs/:id/pause` changes a DB field to `'paused'` but does
**not** send any signal to the running Nextflow process. The Nextflow job continues
running on the cluster. The UI shows "Paused" but the computation does not stop.

**Impact:** Users may think pausing saves compute cost — it does not. Only Cancel
sends SIGTERM via `nextflow_runner.stop_job()`.

**Recommendation:** Add a warning next to the Pause button:
> "Pausing records your intent but does not stop the computation. Use Cancel to stop."

Or implement a true pause via `SIGSTOP` / Nextflow's `-resume` flag (Nextflow natively
supports `-resume` which re-uses cached results, effectively a soft restart from the
last completed step).

#### Gap 2 — Resume does not actually restart Nextflow

`POST /api/workflows/runs/:id/resume` sets status back to `'running'` but sends no
signal to Galaxy or the Nextflow process. If the process was cancelled/terminated,
the button has no real effect.

**Recommendation:** Wire resume to call
`POST /api/galaxy/workflows/:workflowId/invocations/:id` with `-resume` flag,
or re-submit the Nextflow job from the last successful checkpoint using
Nextflow's built-in `.nextflow/cache`.

#### Gap 3 — LangGraph "resume" vs control panel "resume" will confuse users

Two different things are called "resume":
- Control panel Resume: restores a paused running workflow
- LangGraph Resume: continues graph execution after answering a clarification question

**Recommendation:** Use distinct language in the UI:
- Control panel: **"Resume execution"** (workflow is running/paused)
- LangGraph clarification: **"Continue"** or **"Proceed with these settings"** (generation pipeline)

#### Gap 4 — No sub-task level control

The existing control panel controls a single run. With LangGraph multi-task pipelines,
a pipeline has 3 sub-tasks, each generating and then executing a workflow. There is
no UI to:
- Cancel only one sub-task while letting others proceed
- Retry a failed sub-task without re-running the whole pipeline

**Recommendation:** In the pipeline sub-task pills (new UI), add a per-pill
"retry" button for failed sub-tasks and "skip" for pending ones.

#### Gap 5 — Sandbox/Production mode applies per-run, not per-pipeline

Today, sandbox/production (fraction slider, promote button) is configured per individual
run. For multi-task pipelines, each sub-task gets the same fraction. There is no UI to
set different fractions per sub-task (e.g., pilot QC at 5%, full DE at 100%).

**Recommendation:** For Phase 1, inherit pipeline-level sandbox mode to all sub-tasks.
Document this as a known limitation. Pipeline-level fraction override is a future feature.

---

## Phase 0 — Foundation (Day 1, ~2 hours)

### 0A: Install LangGraph into backend venv

```bash
cd /home/yzhang/biomate/backend
.venv/bin/pip install "langgraph>=1.1.2" "langgraph-checkpoint-postgres>=2.0"
# langgraph-checkpoint-postgres: persists graph state to existing Postgres DB
```

Add to `backend/requirements.txt`:
```
langgraph>=1.1.2
langgraph-checkpoint-postgres>=2.0
```

### 0B: Add `pending_tasks` table to LTM schema

File: `frontend/shared/ltm-schema.ts` — add new table:

```typescript
export const pendingTasks = pgTable("pending_tasks", {
  id:            uuid("id").primaryKey().defaultRandom(),
  userId:        uuid("user_id").references(() => ltmUsers.id, { onDelete: "cascade" }),
  sessionId:     text("session_id"),
  parentPipelineId: uuid("parent_pipeline_id"),  // groups sub-tasks of one compound request
  description:   text("description").notNull(),
  taskType:      text("task_type"),               // WORKFLOW | RESEARCH | EXPORT | QC
  status:        text("status").default("pending"), // pending|dispatched|running|completed|failed
  dependsOn:     uuid("depends_on").array().default([]),
  celeryTaskId:  text("celery_task_id"),
  resultPath:    text("result_path"),
  errorMessage:  text("error_message"),
  createdAt:     timestamp("created_at").defaultNow(),
  startedAt:     timestamp("started_at"),
  completedAt:   timestamp("completed_at"),
});
```

Run migration:
```bash
cd /home/yzhang/biomate/frontend
npx drizzle-kit push  # or generate + migrate
```

### 0C: Celery broker configuration

`backend/start_backend.sh` already exports `REDIS_URL`. Add:
```bash
export CELERY_BROKER_URL="${REDIS_URL}"
export CELERY_RESULT_BACKEND="db+sqlite:////tmp/biomate_celery_results.db"
# Use SQLite for results (safe for single-node dev; swap to Postgres in prod)
```

Add a `backend/start_celery_worker.sh`:
```bash
#!/bin/bash
cd /home/yzhang/biomate/backend
export $(cat .env.local | xargs)
.venv/bin/celery -A galaxy.ai.celery_tasks worker \
  --queues biomate_workflow \
  --concurrency 4 \
  --loglevel info \
  --logfile /tmp/biomate_celery.log
```

---

## Phase 1 — LangGraph State Graph (Day 2–3, ~1 day)

### 1A: State schema

New file: `backend/lib/galaxy/ai/orchestration/state.py`

```python
from typing import TypedDict, List, Optional, Annotated
from langgraph.graph.message import add_messages

class SubTaskResult(TypedDict):
    task_id: str
    description: str
    status: str          # pending | running | completed | failed
    nextflow_path: Optional[str]
    error: Optional[str]
    celery_task_id: Optional[str]

class PipelineState(TypedDict):
    # Immutable inputs
    session_id: str
    user_id: Optional[str]
    pipeline_id: str           # UUID, groups sub-tasks in DB
    raw_query: str
    user_context: dict

    # Mutable across nodes
    messages: Annotated[list, add_messages]   # conversation history
    clarification_needed: bool
    clarification_questions: List[str]
    clarification_answers: List[str]

    tasks: List[dict]          # output of TaskDecomposer
    task_graph: dict           # adjacency list: task_id → [dep_task_ids]
    parallel_groups: List[List[str]]   # groups that can run concurrently

    sub_task_results: List[SubTaskResult]

    # Final output
    pipeline_nf_path: Optional[str]
    scientific_rationale: Optional[str]
    response_message: str
    error: Optional[str]
```

### 1B: Graph nodes

New file: `backend/lib/galaxy/ai/orchestration/nodes.py`

Each node is a pure async function: `(state: PipelineState) → dict` (partial state update).

#### Node: `classify`
```python
async def classify(state: PipelineState) -> dict:
    """Route: single-task vs multi-task vs research-only."""
    decomposer = TaskDecomposer(get_config())
    user_request = UserRequest(
        user_id=state["user_id"] or "anon",
        request_text=state["raw_query"],
        context=state["user_context"],
    )
    intent = decomposer.parse_intent(state["raw_query"])
    tasks = decomposer.decompose_request(user_request, intent)

    # Build dependency graph
    graph = decomposer.create_task_graph(tasks)
    groups = decomposer.optimize_task_sequence(tasks)  # returns ordered + parallel info

    # Persist to pending_tasks table
    _persist_tasks_to_db(state["pipeline_id"], state["session_id"], tasks)

    return {
        "tasks": [dataclasses.asdict(t) for t in tasks],
        "task_graph": dict(graph.edges),
        "parallel_groups": graph._identify_parallel_groups_ids(),
    }
```

#### Node: `check_clarification`
```python
async def check_clarification(state: PipelineState) -> dict:
    """Ask Tier 1/2 clarification if required parameters are missing."""
    missing = _find_missing_required_params(state["tasks"], state["user_context"])
    if missing:
        questions = _generate_clarification_questions(missing)
        return {"clarification_needed": True, "clarification_questions": questions}
    return {"clarification_needed": False}
```

#### Conditional edge after `check_clarification`:
```python
def route_after_clarification(state: PipelineState) -> str:
    return "wait_for_clarification" if state["clarification_needed"] else "dispatch"
```

#### Node: `dispatch`
```python
async def dispatch(state: PipelineState) -> dict:
    """
    Fan out sub-tasks to Celery.
    Tasks in the same parallel_group fire simultaneously.
    Tasks with dependencies wait for their upstream group to complete.
    """
    from .celery_tasks import compose_workflow_task

    all_results = []
    completed_ids = set()

    for group in state["parallel_groups"]:
        # Check all deps satisfied
        ready_tasks = [
            t for t in group
            if all(dep in completed_ids for dep in state["task_graph"].get(t, []))
        ]

        # Fire group in parallel
        celery_group = celery.group(
            compose_workflow_task.s(
                task_id=tid,
                description=_task_by_id(state["tasks"], tid)["description"],
                user_context=state["user_context"],
                pipeline_id=state["pipeline_id"],
            )
            for tid in ready_tasks
        )
        group_result = celery_group.apply_async(queue="biomate_workflow")

        # Wait for this group (blocking in async context via asyncio executor)
        results = await asyncio.get_event_loop().run_in_executor(
            None, group_result.get, 300  # 5 min timeout per group
        )
        all_results.extend(results)
        completed_ids.update(ready_tasks)

    return {"sub_task_results": all_results}
```

#### Node: `merge`
```python
async def merge(state: PipelineState) -> dict:
    """Compose a top-level pipeline main.nf from all sub-task outputs."""
    successful = [r for r in state["sub_task_results"] if r["status"] == "completed"]
    failed = [r for r in state["sub_task_results"] if r["status"] == "failed"]

    if not successful:
        return {
            "error": "All sub-tasks failed",
            "response_message": _format_failure_message(state["sub_task_results"]),
        }

    pipeline_path = _compose_pipeline_nf(successful, state["raw_query"])
    rationale = _build_rationale(successful, state["user_context"])

    warning = ""
    if failed:
        warning = f"\n\n⚠️ {len(failed)} sub-task(s) failed and were skipped: " + \
                  ", ".join(r["description"][:40] for r in failed)

    return {
        "pipeline_nf_path": str(pipeline_path),
        "scientific_rationale": rationale,
        "response_message": (
            f"Generated {len(successful)}-stage pipeline.{warning}\n\n{rationale}"
        ),
    }
```

#### Node: `respond`
```python
async def respond(state: PipelineState) -> dict:
    """Format final API response dict — identical shape to generate_workflow_unified()."""
    return {
        "response_message": state.get("response_message", "Done."),
    }
```

### 1C: Graph assembly

New file: `backend/lib/galaxy/ai/orchestration/graph.py`

```python
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres import PostgresSaver

from .state import PipelineState
from .nodes import classify, check_clarification, dispatch, merge, respond

def build_pipeline_graph(db_conn_str: str) -> StateGraph:
    """Build and compile the BioMate pipeline graph with Postgres checkpointing."""

    checkpointer = PostgresSaver.from_conn_string(db_conn_str)
    checkpointer.setup()  # creates langgraph_checkpoints table if missing

    g = StateGraph(PipelineState)

    # Add nodes
    g.add_node("classify",              classify)
    g.add_node("check_clarification",   check_clarification)
    g.add_node("dispatch",              dispatch)
    g.add_node("merge",                 merge)
    g.add_node("respond",               respond)

    # Linear backbone
    g.set_entry_point("classify")
    g.add_edge("classify", "check_clarification")

    # Conditional: clarify or go straight to dispatch
    g.add_conditional_edges(
        "check_clarification",
        route_after_clarification,
        {
            "wait_for_clarification": END,   # suspend; resume when user answers
            "dispatch": "dispatch",
        }
    )

    g.add_edge("dispatch", "merge")
    g.add_edge("merge", "respond")
    g.add_edge("respond", END)

    return g.compile(checkpointer=checkpointer, interrupt_before=["dispatch"])
    # interrupt_before="dispatch": graph pauses for human-in-the-loop before firing Celery
```

**Key LangGraph features used:**
- **`interrupt_before`**: Graph checkpoints its state and returns to the caller, allowing the
  user to confirm or cancel before workflow generation begins. The caller resumes by calling
  `graph.invoke(None, config={"configurable": {"thread_id": pipeline_id}})`.
- **Postgres checkpointing**: If the server restarts mid-execution, the graph resumes from
  the last checkpoint rather than starting over.
- **`add_messages` reducer**: Accumulates conversation history across turns using LangGraph's
  built-in message reducer (avoids manual list merging).

### 1D: Wire into `ai_assistant.py`

Modify `route_and_handle()`:
```python
async def route_and_handle(self, query: str, context: dict) -> dict:
    # Single-task quick path (unchanged for speed — no graph overhead)
    if not self._looks_like_multi_task(query):
        return await self._handle_workflow_generation(query, context)

    # Multi-task → use LangGraph orchestration
    from .orchestration.graph import build_pipeline_graph
    graph = build_pipeline_graph(POSTGRES_CONN_STR)

    pipeline_id = str(uuid.uuid4())
    config = {"configurable": {"thread_id": pipeline_id}}
    initial_state = PipelineState(
        session_id=context.get("sessionId", ""),
        user_id=context.get("userId"),
        pipeline_id=pipeline_id,
        raw_query=query,
        user_context=context,
        messages=[],
        ...
    )
    result = await graph.ainvoke(initial_state, config=config)
    return _format_graph_result(result, pipeline_id)
```

`_looks_like_multi_task()` uses `TaskDecomposer.parse_intent()` cheaply — if it returns
`IntentType.MULTI_STEP` or contains multiple verbs mapped to different `TaskType`s, route
to the graph. Otherwise, use the existing fast single-task path.

---

## Phase 2 — Celery Task Worker (Day 3–4, ~1 day)

### 2A: Celery task definition

New file: `backend/lib/galaxy/ai/orchestration/celery_tasks.py`

```python
from celery import Celery
import os

celery_app = Celery(
    "biomate",
    broker=os.environ["CELERY_BROKER_URL"],
    backend=os.environ.get("CELERY_RESULT_BACKEND", "rpc://"),
)
celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    task_acks_late=True,           # retry on worker crash
    task_reject_on_worker_lost=True,
    worker_prefetch_multiplier=1,  # fair dispatch
    task_routes={"biomate.*": {"queue": "biomate_workflow"}},
)

@celery_app.task(name="biomate.compose_workflow", bind=True, max_retries=2)
def compose_workflow_task(self, *, task_id: str, description: str,
                          user_context: dict, pipeline_id: str) -> dict:
    """
    Runs in a Celery worker process.
    Calls NextflowComposer and updates pending_tasks table.
    """
    try:
        _update_task_status(pipeline_id, task_id, "running")
        _notify_sse(pipeline_id, task_id, "running")

        from galaxy.ai.nextflow_composer import NextflowComposer
        composer = NextflowComposer()
        result = composer.compose_workflow(
            user_intent=description,
            user_context=user_context,
        )

        _update_task_status(pipeline_id, task_id, "completed",
                            result_path=result.get("nextflow_path"))
        _notify_sse(pipeline_id, task_id, "completed", result)
        return {"task_id": task_id, "status": "completed", **result}

    except Exception as exc:
        _update_task_status(pipeline_id, task_id, "failed", error=str(exc))
        _notify_sse(pipeline_id, task_id, "failed", {"error": str(exc)})
        raise self.retry(exc=exc, countdown=10)
```

### 2B: `_notify_sse` — bridge from Celery worker to SSE

The Celery worker is a separate process; it cannot directly write to the Express SSE
connection. Bridge via Redis pub/sub:

```python
def _notify_sse(pipeline_id: str, task_id: str, status: str, data: dict = {}):
    """Publish a task-status event to the Redis channel the SSE server listens on."""
    import redis, json, os
    r = redis.from_url(os.environ["REDIS_URL"])
    r.publish(
        f"biomate:pipeline:{pipeline_id}",
        json.dumps({"task_id": task_id, "status": status, **data})
    )
```

On the Node.js side (Express `routes.ts`), add a new SSE endpoint:
```typescript
// GET /api/pipelines/:pipelineId/events
app.get("/api/pipelines/:pipelineId/events", (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.flushHeaders?.();

  const sub = redisClient.duplicate();
  sub.subscribe(`biomate:pipeline:${req.params.pipelineId}`);
  sub.on("message", (_chan, msg) => {
    res.write(`data: ${msg}\n\n`);
  });
  req.on("close", () => sub.quit());
});
```

---

## Phase 3 — Frontend Task List + Left Panel (Day 5, ~1 day)

> **See:** [`20260310_WORKFLOW_UX_SIMPLIFICATION.md`](./20260310_WORKFLOW_UX_SIMPLIFICATION.md)
> for the full UX design, layout changes, and use-case test definitions.

### 3A: Task list in chat stream

Sub-task status updates arrive via SSE (`/api/pipelines/:id/events`) and are
rendered as a `<TaskList>` component **inside the current AI reply bubble**,
below the text content. Each row has stop/remove/retry buttons.

The active-runs status bar above the chat is **removed** — the task list replaces it.

### 3B: Left panel for Workflow Execution Panel

The existing `ExecutionControlPanel` is promoted to a persistent left panel
(third `ResizablePanel` slot in `App.tsx`), visible whenever any run is active.
The panel auto-hides when all runs complete.

The `QCGateModal` popup is replaced with an inline section inside the left panel.

### 3C: Chat stop button

The send button becomes a stop button (⏹) when the AI is streaming. It aborts the
`ReadableStream` fetch via `AbortController`. If tasks are queued, a small
disambiguation popover asks: "Stop reply only" vs "Stop reply + clear all queued tasks."

Running Nextflow workflows in the left panel are never affected by the chat stop button.

---

## Phase 4 — Human-in-the-Loop Clarification (Day 6, ~half day)

LangGraph's `interrupt_before=["dispatch"]` pauses graph execution before any Celery
tasks are dispatched. The backend returns to the frontend with:

```json
{
  "needs_clarification": true,
  "pipeline_id": "...",
  "questions": ["What organism?", "Paired-end or single-end?"]
}
```

The frontend renders these as a structured clarification card (already partially
implemented in `conversation-state.ts`). When the user answers, the frontend POSTs to:

```
POST /api/pipelines/:pipelineId/resume
{ "answers": ["Homo sapiens", "paired-end"] }
```

The backend resumes the graph:
```python
graph.invoke(
    {"clarification_answers": answers},
    config={"configurable": {"thread_id": pipeline_id}}
)
```

The graph picks up from the checkpoint, updates `user_context`, and proceeds to `dispatch`.

---

## Implementation Order & Time Estimate

| Phase | Task | Files changed | Est. time |
|-------|------|--------------|-----------|
| 0A | Install LangGraph | `requirements.txt`, venv | 15 min |
| 0B | `pending_tasks` table | `ltm-schema.ts`, migration | 30 min |
| 0C | Celery broker env | `start_backend.sh`, new `start_celery_worker.sh` | 15 min |
| 1A–C | LangGraph state + nodes + graph | `orchestration/` (3 new files) | 4 hrs |
| 1D | Wire into `ai_assistant.py` | `ai_assistant.py` | 1 hr |
| 2A | Celery task | `orchestration/celery_tasks.py` | 2 hrs |
| 2B | Redis pub/sub SSE bridge | `routes.ts` (1 new endpoint) | 1 hr |
| 3A | Pipeline sub-task UI | `chat-with-artifacts.tsx` | 2 hrs |
| 4 | Resume endpoint | `routes.ts`, `ai_assistant.py` | 2 hrs |
| **Total** | | ~10 new/modified files | **~2 days** |

---

## Testing Plan

### Level 1 — Unit Tests (Python, `pytest`)

**File:** `backend/tests/ai/orchestration/test_graph_nodes.py`

| Test | What it validates |
|------|------------------|
| `test_classify_single_task` | Single verb query → 1 task, no parallel groups |
| `test_classify_multi_task` | "QC then DE then export" → 3 tasks, 1 parallel group (QC alone), dependency graph correct |
| `test_classify_parallel` | Two independent tasks → 2 tasks in same parallel group |
| `test_clarification_missing_organism` | Missing organism → `clarification_needed=True`, 1 question generated |
| `test_clarification_complete` | Full context → `clarification_needed=False` |
| `test_dispatch_celery_mock` | Mock Celery; assert `compose_workflow_task.s()` called N times for N tasks |
| `test_dispatch_parallel_grouping` | Independent tasks → both Celery tasks sent before `get()` is called |
| `test_merge_all_success` | All sub-tasks completed → `pipeline_nf_path` is set |
| `test_merge_partial_failure` | 1 of 3 sub-tasks failed → pipeline generated for 2, warning in response |
| `test_merge_all_failure` | All failed → `error` is set, no pipeline path |
| `test_graph_checkpoint_resume` | Graph interrupted before `dispatch`; resume with user answers → reaches `merge` |

**Run:** `backend/.venv/bin/pytest backend/tests/ai/orchestration/ -v`

---

### Level 2 — Integration Tests (Python)

**File:** `backend/tests/ai/orchestration/test_graph_integration.py`

Uses a real SQLite Postgres-compatible checkpoint store (or `MemorySaver` for speed).

| Test | What it validates |
|------|------------------|
| `test_single_task_fast_path` | Single-task query bypasses graph entirely; timing < 100ms overhead |
| `test_multi_task_end_to_end_mock_celery` | Full graph with mock Celery `apply_async` → all nodes visited, state shape correct |
| `test_pending_tasks_db_written` | After `classify`, `pending_tasks` table has N rows with `status=pending` |
| `test_celery_task_updates_db` | Calling `compose_workflow_task()` directly updates `pending_tasks.status` to `completed` |
| `test_sse_redis_publish` | `_notify_sse()` publishes to correct Redis channel with correct payload |
| `test_graph_persists_across_restart` | Pickle state, re-build graph, resume → correct output (simulates server restart) |

---

### Level 3 — API Tests (Node.js, `supertest`)

**File:** `frontend/server/__tests__/pipeline-sse.test.ts`

| Test | What it validates |
|------|------------------|
| `test_pipeline_events_endpoint` | GET `/api/pipelines/abc/events` returns SSE headers |
| `test_pipeline_events_relay` | Publish to Redis → SSE client receives event within 200ms |
| `test_pipeline_resume_endpoint` | POST `/api/pipelines/abc/resume` calls `graph.ainvoke` with answers |
| `test_pipeline_resume_404` | Unknown pipeline_id → 404 |

---

### Level 4 — End-to-End Tests (Playwright)

**File:** `frontend/e2e/langgraph-orchestration.e2e.ts`

#### Iteration 1 — Smoke (no real LLM, mock responses)

```typescript
test("single-task query bypasses orchestration - input stays enabled", async ({ page }) => {
  // Submit a simple single-task message
  await page.goto('/');
  await page.fill('[data-testid="chat-input"]', 'Run FastQC on my FASTQ files');
  await page.click('[data-testid="chat-send-button"]');
  // Chat input should remain enabled (soft queue feature)
  await expect(page.locator('[data-testid="chat-input"]')).toBeEnabled();
  // Screenshot
  await page.screenshot({ path: 'e2e/screenshots/langgraph/01_single_task_input_enabled.png' });
});

test("multi-task query shows sub-task breakdown in status bar", async ({ page }) => {
  await page.goto('/');
  await page.fill('[data-testid="chat-input"]',
    'First run QC on my FASTQ, then align to hg38, then call variants');
  await page.click('[data-testid="chat-send-button"]');
  // Status bar should show pipeline container
  await expect(page.locator('[data-testid="active-runs-bar"]')).toBeVisible({ timeout: 10000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/02_multi_task_status_bar.png' });
});

test("clarification card appears for missing required params", async ({ page }) => {
  await page.goto('/');
  await page.fill('[data-testid="chat-input"]', 'Run RNA-seq analysis');  // no organism
  await page.click('[data-testid="chat-send-button"]');
  await expect(page.locator('[data-testid="clarification-card"]')).toBeVisible({ timeout: 15000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/03_clarification_card.png' });
});

test("pipeline resumes after clarification answered", async ({ page }) => {
  // Answer clarification
  await page.locator('[data-testid="clarification-answer-0"]').fill('Homo sapiens');
  await page.locator('[data-testid="clarification-submit"]').click();
  // Sub-task pills should appear
  await expect(page.locator('[data-testid^="subtask-pill-"]').first()).toBeVisible({ timeout: 20000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/04_after_clarification_subtasks.png' });
});

test("sub-task status updates reflect in real time via SSE", async ({ page }) => {
  // Inject a mock SSE event
  await page.evaluate(() => {
    window.__mockSSE?.emit('data', JSON.stringify({
      task_id: 'task-1', status: 'completed', nextflow_path: 'workflows/qc/main.nf'
    }));
  });
  await expect(page.locator('[data-testid="subtask-pill-task-1"]'))
    .toHaveAttribute('data-status', 'completed', { timeout: 3000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/05_subtask_completed.png' });
});

test("pipeline completion fires toast", async ({ page }) => {
  await expect(page.locator('[data-testid="toast-title"]'))
    .toHaveText('Pipeline complete', { timeout: 5000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/06_pipeline_complete_toast.png' });
});
```

#### Iteration 2 — Real API (with real LLM, no mock)

```typescript
test("real multi-task: QC + DE produces two sub-workflows", async ({ page }) => {
  await page.goto('/');
  await page.fill('[data-testid="chat-input"]',
    'Run FastQC on my samples, then do differential expression with DESeq2');
  await page.click('[data-testid="chat-send-button"]');

  // Wait for status bar with 2 sub-task pills
  await expect(page.locator('[data-testid^="subtask-pill-"]')).toHaveCount(2, { timeout: 60000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/real/01_two_subtasks.png' });

  // Verify the pipeline .nf file is linked
  await page.locator('[data-testid="view-pipeline-btn"]').click();
  await expect(page.locator('[data-testid="workflow-artifact"]')).toBeVisible({ timeout: 5000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/real/02_pipeline_artifact.png' });
});
```

#### Iteration 3 — Failure & recovery

```typescript
test("partial failure: one sub-task fails, pipeline still generated for others", async ({ page }) => {
  // Use a query known to trigger a failing sub-task (bad tool name)
  await page.fill('[data-testid="chat-input"]',
    'Run FastQC, then run NonExistentTool, then align with STAR');
  await page.click('[data-testid="chat-send-button"]');

  // Sub-task 2 should show failed
  await expect(page.locator('[data-testid="subtask-pill-task-2"]'))
    .toHaveAttribute('data-status', 'failed', { timeout: 60000 });

  // Warning should appear in chat message
  await expect(page.locator('[data-testid="pipeline-warning"]'))
    .toContainText('1 sub-task(s) failed', { timeout: 5000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/failure/01_partial_failure.png' });
});

test("failed pipeline toast shows View & fix action", async ({ page }) => {
  await expect(page.locator('[data-testid="toast-title"]'))
    .toHaveText('Pipeline failed', { timeout: 5000 });
  await page.locator('text=View & fix').click();
  await expect(page.locator('[data-testid="run-manager-panel"]')).toBeVisible({ timeout: 3000 });
  await page.screenshot({ path: 'e2e/screenshots/langgraph/failure/02_view_fix_panel.png' });
});
```

---

## Audit & Logging Plan

### Backend structured logs

Every LangGraph node emits a structured log entry:

```
[LangGraph][classify]     pipeline_id=abc123 tasks=3 groups=[[task-1],[task-2,task-3]] elapsed=42ms
[LangGraph][dispatch]     pipeline_id=abc123 group=1 celery_ids=[x,y] 
[LangGraph][dispatch]     pipeline_id=abc123 group=2 celery_ids=[z]
[LangGraph][merge]        pipeline_id=abc123 success=2 failed=0 pipeline_path=...
[Celery][compose]         pipeline_id=abc123 task_id=task-1 status=running
[Celery][compose]         pipeline_id=abc123 task_id=task-1 status=completed elapsed=8.2s
```

Log file: `/tmp/biomate_langgraph.log` (separate from main Galaxy log for easy tailing).

### Per-iteration audit checklist

After each implementation iteration, run the following and save output:

```bash
# 1. Tail LangGraph logs
tail -n 200 /tmp/biomate_langgraph.log > docs/QC/langgraph_audit_iter_N.log

# 2. Query pending_tasks table
psql $POSTGRES_CONN -c "SELECT task_type, status, COUNT(*) FROM pending_tasks GROUP BY 1,2;"

# 3. Check Celery task results
.venv/bin/celery -A galaxy.ai.orchestration.celery_tasks inspect active
.venv/bin/celery -A galaxy.ai.orchestration.celery_tasks inspect reserved

# 4. Run Playwright screenshots
npx playwright test e2e/langgraph-orchestration.e2e.ts --reporter=html
# → report opens at playwright-report/index.html

# 5. Verify checkpoint persistence
psql $POSTGRES_CONN -c "SELECT COUNT(*), MIN(created_at), MAX(created_at) FROM langgraph_checkpoints;"
```

### Screenshot inventory (per iteration)

| # | Filename | What to verify |
|---|----------|----------------|
| 01 | `single_task_input_enabled.png` | Chat input is NOT disabled while AI responds |
| 02 | `multi_task_status_bar.png` | Status bar visible with pipeline container |
| 03 | `clarification_card.png` | Clarification questions rendered as card |
| 04 | `after_clarification_subtasks.png` | Sub-task pills appear after answering |
| 05 | `subtask_completed.png` | First pill turns green |
| 06 | `pipeline_complete_toast.png` | Success toast with "View results" |
| 07 | `real/01_two_subtasks.png` | Real LLM: 2 pills for QC + DE query |
| 08 | `real/02_pipeline_artifact.png` | Clickable `.nf` file artifact |
| 09 | `failure/01_partial_failure.png` | One red pill, warning in chat |
| 10 | `failure/02_view_fix_panel.png` | Run Manager opens on toast click |

---

## Rollout Strategy

### Feature flag

Add `BIOMATE_LANGGRAPH_ENABLED=false` to `.env.local`. When `false`, all requests use the
existing `generate_workflow_unified()` path. Set to `true` in dev to test. This guarantees
the existing single-task path is never broken by the new orchestration code.

### Rollback plan

If LangGraph introduces instability:
1. Set `BIOMATE_LANGGRAPH_ENABLED=false` — existing path immediately restored.
2. `pending_tasks` table has no FK constraints on existing tables — safe to ignore.
3. `langgraph_checkpoints` table can be dropped without side effects.

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Celery worker crashes mid-task | Medium | Medium | `task_acks_late=True`, `max_retries=2` |
| LangGraph checkpoint Postgres schema conflict | Low | Low | Uses isolated `langgraph_checkpoints` table |
| Redis pub/sub delivery gap (SSE missed event) | Low | Low | Frontend polls `/api/pending-tasks` as fallback |
| Multi-task LLM cost spike | Medium | Medium | L0 cache hits are free; cap max tasks per request to 5 |
| Graph hangs in `dispatch` (Celery timeout) | Low | High | 5 min per group timeout; partial results merged |
| `_looks_like_multi_task()` false positives | Medium | Low | Conservative threshold; single-task path is fast fallback |

---

## Files Created / Modified (summary)

```
backend/
  lib/galaxy/ai/orchestration/          ← NEW directory
    __init__.py
    state.py                            ← PipelineState TypedDict
    nodes.py                            ← classify, clarify, dispatch, merge, respond
    graph.py                            ← StateGraph assembly + Postgres checkpoint
    celery_tasks.py                     ← @celery.task compose_workflow_task
  lib/galaxy/ai/ai_assistant.py         ← wire route_and_handle() to graph for multi-task
  requirements.txt                      ← add langgraph, langgraph-checkpoint-postgres
  start_backend.sh                      ← add CELERY_BROKER_URL env
  start_celery_worker.sh                ← NEW: worker start script

frontend/
  shared/ltm-schema.ts                  ← add pendingTasks table
  server/routes.ts                      ← add /api/pipelines/:id/events SSE endpoint
                                           add /api/pipelines/:id/resume POST endpoint
  client/src/components/
    chat-with-artifacts.tsx             ← pipeline container + sub-task pills in status bar
    clarification-card.tsx              ← NEW: structured clarification UI component

docs/
  20260310_LANGGRAPH_INTEGRATION_PLAN.md  ← this file
```

Total: ~12 files changed, ~5 new files, ~2 days of implementation.
