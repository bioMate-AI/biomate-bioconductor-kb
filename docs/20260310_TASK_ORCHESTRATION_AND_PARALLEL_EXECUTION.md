# Task List Memory & Parallel Orchestration in BioMate

**Date:** 2026-03-10  
**Context:** Can BioMate record tasks from users and execute them in parallel, like Claude Code?

---

## Question 1 — Does BioMate have a task list memory?

### Short answer: Partially — the structures exist but are not connected end-to-end.

BioMate has **three separate layers** of task/memory infrastructure that currently operate
independently:

---

### Layer 1: Per-turn conversation state (frontend, `conversation-state.ts`)

A `ConversationState` object accumulates facts across turns within a single session:
```
phase:     gathering → clarifying → tool_selection → parameterizing → ready → generated → executing
facts:     List[RawFact]   (organism, data_type, analysis_goal, tool_preference, …)
pending clarifications: clarification questions awaiting user response
```
This is saved to Postgres every turn (survives context compression). It is the closest
thing to "task list memory" today — but it stores *facts about the current task*, not
a *list of tasks*.

**Gap:** There is no persisted list of "tasks the user has requested". Once a workflow
is generated the conversation-state is not updated to reflect what was actually done.

---

### Layer 2: Long-term memory (backend `AgenticMemoryService` + frontend LTM schema)

The LTM schema persists across sessions:

| Table | Content |
|-------|---------|
| `project_episodes` | Outcomes of past workflow runs (success/failure, what was done) |
| `project_procedures` | Learned step-by-step procedures extracted from successful episodes |
| `project_knowledge` | Scientific facts attached to a project |
| `sessions` | Session summaries with workflow counts |
| `workflows` | Workflow execution history per user/project |

`AgenticMemoryService` on the backend reads these at session start to personalize
the AI's behavior. **This is real cross-session memory** — but it records *outcomes*,
not *pending tasks*.

**Gap:** There is no "task inbox" — no table for "tasks the user queued but hasn't run
yet" across sessions.

---

### Layer 3: `TaskDecomposer` + `TaskGraph` (backend, `task_decomposer.py`)

The most relevant component. `TaskDecomposer` can take a compound user request and
decompose it into an ordered `List[Task]` with:
- Dependency graph (`TaskGraph` with topological sort via `get_execution_order()`)
- `optimize_task_sequence()` which finds parallelizable groups
- LLM fallback for non-templated requests

`WorkflowOptimizer._identify_parallel_groups()` (uses `networkx`) already identifies
which workflow *steps* can run simultaneously based on their I/O dependency graph.

**Gap:** `TaskDecomposer` is not wired into the active API route and produces no
persistent task list — once the Python process responds, the decomposed tasks are gone.

---

## Question 2 — Can tasks run in parallel, like Claude Code?

### What Claude Code does

Claude Code spawns **subagents** (the `Task` tool) that:
- Each get their own isolated context and tool access
- Run concurrently as separate processes
- Report results back to the parent coordinator
- The parent waits for all to finish, then synthesizes

### What BioMate has today

**At the Nextflow/workflow level — YES, already parallel:**  
Galaxy's `JobHandlerQueue` runs multiple Nextflow invocations concurrently. If BioMate
generates 3 workflows from 3 queries, all 3 execute in parallel on the cluster. This
is fully functional today.

**At the AI query generation level — NO, sequential:**  
Each call to `generate_workflow_unified()` blocks until it finishes. There is no
mechanism to fire two AI generation calls simultaneously from a single user session.

**At the task-graph level — EXISTS but unused:**  
`WorkflowOptimizer._identify_parallel_groups()` computes which workflow steps can
run in parallel (using topological grouping). `TaskGraph.get_execution_order()` does
topological sort. These are correct implementations — they just aren't connected to
actual parallel execution.

---

## Question 3 — How can we make it happen?

### The gap is not computation — it's orchestration wiring.

The pieces already exist:
- `TaskDecomposer` → decomposes user intent into tasks
- `TaskGraph` + `_identify_parallel_groups` → knows which tasks are independent
- `NextflowComposer` → generates a Nextflow workflow per task
- Galaxy JobHandler → executes multiple workflows concurrently
- Celery 5.5.3 → **already installed**, used by Galaxy for job metadata

What is missing is the **coordinator** that:
1. Persists the task list
2. Dispatches independent tasks simultaneously
3. Waits for upstream tasks before starting downstream ones
4. Merges results into a single user-visible response

### Recommended architecture: Celery task queue (already installed)

```
User request
    │
    ▼
TaskDecomposer.decompose_request()
    │  → [task_A (QC), task_B (DE), task_C (export)]
    │  → task_B depends on task_A; task_C depends on task_B
    ▼
TaskOrchestrator.dispatch(task_graph)
    │
    ├── Celery.send_task("biomate.generate_workflow", args=[task_A]) → job_A
    │      (no dependencies — starts immediately)
    │
    ├── job_A.get() completes
    │
    ├── Celery.send_task("biomate.generate_workflow", args=[task_B]) → job_B
    │      (depends on job_A output)
    │
    └── Celery.send_task("biomate.export_results", args=[task_C]) → job_C
           (depends on job_B output)
    │
    ▼
SSE stream → frontend receives per-task status updates
```

Independent tasks (no shared dependencies) are dispatched simultaneously via
`Celery.group()`:
```python
from celery import group, chain

# QC and alignment are independent → run in parallel
parallel_group = group(
    generate_workflow_task.s(qc_task),
    generate_workflow_task.s(alignment_task),
)
# Export depends on both → runs after
full_pipeline = chain(parallel_group, export_task.s())
result = full_pipeline.apply_async()
```

### Persistent task list: add one table

```sql
CREATE TABLE pending_tasks (
  id          UUID PRIMARY KEY,
  user_id     UUID REFERENCES users(id),
  session_id  TEXT,
  description TEXT NOT NULL,
  task_type   TEXT,
  status      TEXT DEFAULT 'pending',  -- pending | running | completed | failed
  depends_on  UUID[],                  -- other task IDs that must complete first
  celery_task_id TEXT,                 -- Celery async result ID
  result_path TEXT,                    -- where output was written
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  started_at  TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);
```

This table is the "task inbox" that survives page refreshes and multi-session gaps.
The frontend Run Manager already polls `/api/workflows/runs` — the same pattern works
for `/api/tasks`.

---

## Question 4 — Existing GitHub projects to leverage

### Option A: LangGraph (best fit for BioMate's needs)

**Repo:** https://github.com/langchain-ai/langgraph  
**What it does:** Builds stateful, multi-step LLM agent workflows as directed graphs.
Nodes are Python functions (LLM calls, tool calls, condition checks). Edges define
control flow including parallel branches.

**Why it fits BioMate:**
- Already uses Python + async
- Graph nodes map directly to BioMate's TaskGraph concept
- Built-in checkpointing (persists state to Postgres — BioMate already has Postgres)
- Supports parallel branches natively (`Send` primitive for fan-out)
- Human-in-the-loop pauses (for Tier 2 clarification questions)

**Integration path:**
- Replace the ad-hoc `TaskDecomposer` + `_generate_multi_task_workflow()` with a
  LangGraph `StateGraph`
- Each node = one `NextflowComposer.compose_workflow()` call
- Conditional edge = "does this task have dependencies that aren't done yet?"
- Parallel branch = `graph.add_node("task_B", fn_B); graph.add_node("task_C", fn_C)`
  with both branching from the same upstream node

**Install:** `pip install langgraph` — no conflict with existing stack.

---

### Option B: Prefect (best for production scheduling)

**Repo:** https://github.com/PrefectHQ/prefect  
**What it does:** Python-native workflow orchestration. Tasks decorated with `@task`,
flows decorated with `@flow`. Parallel execution via `.submit()` on a thread or process pool.

**Why it fits:**
- `@task` maps to `NextflowComposer.compose_workflow()`
- `@flow` maps to `_generate_multi_task_workflow()`
- Built-in retries, scheduling, observability UI
- Works with Celery (already installed)

**Example:**
```python
from prefect import task, flow

@task
def compose_subtask(description: str, user_context: dict):
    return nextflow_composer.compose_workflow(description, user_context=user_context)

@flow
def multi_task_pipeline(tasks: list[Task], user_context: dict):
    futures = [compose_subtask.submit(t.description, user_context) for t in tasks]
    results = [f.result() for f in futures]  # waits, collects
    return compose_pipeline_nf(results)
```

---

### Option C: CrewAI (best for role-based multi-agent)

**Repo:** https://github.com/crewAIInc/crewAI  
**What it does:** Defines AI agents with roles, goals, and tools. A "crew" runs agents
sequentially or in parallel on a shared task.

**Why it fits:**
- "QC Agent" + "DE Agent" + "Export Agent" map naturally to CrewAI's role concept
- Each agent can call `NextflowComposer` as a tool
- Built-in task delegation and result passing between agents
- Supports parallel execution (`Process.hierarchical`)

**Why it may NOT fit:**
- Adds another LLM loop per agent (more latency, more cost)
- BioMate's agents are more computational than conversational — CrewAI's agent model
  is optimized for research/writing tasks, not bioinformatics pipeline composition
- Overhead may not be worth it given TaskDecomposer + NextflowComposer already cover
  the decomposition+generation steps

---

### Recommendation: LangGraph + Celery (both already partially present)

| Component | What uses it today | What to add |
|-----------|-------------------|-------------|
| Celery (installed) | Galaxy job metadata | `@celery.task` for `compose_workflow()` per sub-task |
| Postgres (running) | LTM schema, conversation-state | `pending_tasks` table |
| `TaskGraph` (exists) | Unused in production path | Wire to Celery `group()`/`chain()` |
| LangGraph (add) | Nothing yet | Replace ad-hoc orchestration with StateGraph |
| Redis (running) | HTTP sessions | Add as Celery broker (already supported) |

Celery uses Redis as a broker and Postgres as a result backend — both already running
in BioMate. No new infrastructure required. LangGraph adds ~30 kB to the Python
environment and provides the state management layer for persistent task lists.

---

## Summary

| Question | Answer |
|----------|--------|
| Task list memory today? | Partial: conversation-state (per-turn facts), LTM episodes (post-run outcomes). No "pending task inbox" across sessions. |
| Parallel execution today? | At Nextflow/workflow level: YES. At AI generation level: NO. |
| Infrastructure to add? | One DB table (`pending_tasks`) + Celery task dispatcher. Redis + Celery already installed. |
| Best GitHub project? | **LangGraph** for orchestration graph; **Celery** for dispatch (already installed). CrewAI/Prefect viable alternatives. |
| Effort estimate? | ~1 week to wire TaskDecomposer → Celery group/chain → persistent task list + SSE status updates. |
