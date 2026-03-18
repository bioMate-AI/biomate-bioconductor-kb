> **SUPERSEDED** — This document is kept for historical reference only.  
> The current plan is in [`20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md`](./20260310_QUERY_QUEUE_AND_MULTI_TASK_PLAN.md).  
> Key changes: progress bars removed, toast click behaviour specified, AutoFix chaining added,
> tiered clarification scoped to whole pipeline, L0/L2 per sub-task documented.

---

# BioMate: Query Queuing & Multi-Step Request Handling
## Current State + Implementation Plan (original, 2026-03-18)

**Date:** 2026-03-18  
**Author:** Engineering  
**Status:** Gap analysis + plan for review

---

## Question 1 — Can BioMate queue multiple input queries?

### Current answer: No.

If a user submits a second query while the first is still processing, they cannot. The
chat input is **disabled** in the UI (`disabled={displayTyping}` in `chat-interface.tsx`,
line 1369) until the AI finishes responding. There is no queue: the second message simply
cannot be typed or submitted.

At the backend level there is also no queue:

| Layer | What exists | Does it queue user queries? |
|-------|-------------|----------------------------|
| Frontend | Chat input disabled while AI is responding | No |
| Frontend Run Manager | Read-only status view of workflow runs (running/queued/failed/completed) | No — display only, not a submission queue |
| Backend HTTP | Synchronous POST `/api/ai_assistant/generate_workflow` | No async queue |
| Redis | Used for HTTP session storage only | No task queue (no BullMQ / Celery) |
| Galaxy JobManager | Queues individual tool *steps* within a running workflow | Not user queries — internal only |

The Galaxy `JobHandlerQueue` does allow multiple workflows to run in parallel at the
tool-step level, but this is Galaxy's internal scheduler and is not exposed as a
user-query queue.

---

## Question 2 — Can BioMate split a compound request into sub-tasks and chain them?

### Example request
> "Pre-process my noisy RNA-seq data, then run differential expression, then export the
> results as a downloadable CSV."

This is three sequential tasks with data flow between them:
1. QC / trimming (pre-processing)
2. DE analysis (core analysis)
3. Export formatting (output)

### Current answer: Partially, but not correctly for multi-workflow chaining.

There are two separate mechanisms and it is important to understand what each actually does:

#### Mechanism A — Internal 4-phase structure (GalaxyWorkflowGenerator)

The `GalaxyWorkflowGenerator._generate_workflow_structure()` LLM prompt defines four
domain-specific phases for **every** generated workflow:

```
Phase 1: Data Validation / QC
Phase 2: Core Analysis
Phase 3: Post-Processing
Phase 4: Output Preparation
```

This runs entirely within a **single** workflow execution. If the LLM receives the
compound request above, it will try to fit all three tasks into one workflow. This works
reasonably well when all steps use the same engine and the data flow is simple, but it
has no explicit understanding of sub-task boundaries — it just fills the four phases.

This mechanism is now running inside `NextflowComposer` (the new fallback generator)
as well, via the LLM prompt's instruction to use domain-appropriate phases.

#### Mechanism B — TaskDecomposer (exists, but bypassed)

`TaskDecomposer` in `backend/lib/galaxy/ai/task_decomposer.py` is a fully implemented
class that:

- Matches compound requests against **pre-built templates** for 6 common pipelines
  (rna_seq_analysis, genome_assembly, variant_calling, etc.) with typed Tasks and
  dependency graphs
- Falls back to **LLM-based decomposition** for non-templated requests, returning an
  ordered `List[Task]` with explicit input/output types, task types, and dependencies
- Produces a `TaskGraph` with explicit dependency ordering

**It is not called by `generate_workflow_unified()`**, which is the active production
path. It is only called by the older `process_request()` function, which itself is
not reachable from the active API route (`/api/ai_assistant/generate_workflow`). The
`TaskDecomposer` is dead code in the current production system.

#### What is missing for true compound-request handling

Even if `TaskDecomposer` were wired in, three gaps remain:

1. **No cross-workflow chaining**: There is no engine that takes `[task1_result → task2_input → task2_result → task3_input]` and executes them as a sequenced pipeline. Each call to `generate_workflow_unified()` is independent.

2. **No output-format awareness**: Requesting "export as CSV" is treated as a description keyword, not as a typed output constraint that routes to a specific converter tool.

3. **No inter-task data handoff**: If task 1 produces a BAM file and task 2 needs a BAM file, there is nothing that connects the output path of task 1 to the input parameter of task 2.

---

## Implementation Plan

### Priority 1 — Query Queuing (client-side, lower complexity)

**Approach:** Add a client-side pending queue. When the AI is responding, additional
messages are held in a queue and submitted sequentially once the previous response
completes. No backend change required.

**Changes:**

```
frontend/client/src/components/chat-interface.tsx
  - Add `pendingMessages: string[]` state
  - On submit while displayTyping=true: push to pendingMessages instead of
    calling handleSendMessage directly
  - In the useEffect that sets displayTyping=false: if pendingMessages.length > 0,
    pop the front and call handleSendMessage

frontend/client/src/components/chat-input.tsx
  - Keep input enabled while AI is responding (remove disabled={displayTyping})
  - Add a visual "queued" badge on the send button showing pending count
```

This is intentionally shallow: it queues *messages*, not workflow *executions*.
The next query begins only after the previous chat response is complete. This is
appropriate because later queries often depend on the AI's answer to earlier ones.

**Effort:** ~1 day frontend work. No backend change.

---

### Priority 2 — Compound Request Decomposition (backend, higher complexity)

**Approach:** Wire `TaskDecomposer` into `generate_workflow_unified()` as a pre-step.
For compound requests (multiple distinct tasks detected), produce a `TaskGraph`, then
execute each task in sequence using `NextflowComposer`, chaining outputs to inputs.

#### Step 2A — Activate TaskDecomposer in the main path

```python
# In generate_workflow_unified() — add BEFORE the workflow search loop:

tasks = self.task_decomposer.decompose_request(
    UserRequest(request_id=..., request_text=user_intent, ...),
    parsed_intent={}
)

if len(tasks) > 1:
    # Compound request — delegate to multi-task handler
    return self._generate_multi_task_workflow(user_intent, tasks)

# else: single task — proceed with existing search-first flow
```

#### Step 2B — Implement `_generate_multi_task_workflow()`

```python
def _generate_multi_task_workflow(self, user_intent, tasks: List[Task]) -> Dict:
    """
    Execute a TaskGraph: compose each task as a Nextflow subworkflow,
    chain outputs to inputs, generate a top-level main.nf that includes all.
    """
    sub_workflows = []

    for task in tasks:
        # Use existing NextflowComposer for each sub-task
        result = self.nextflow_composer.compose_workflow(
            user_intent=task.description,
            max_tools=20,
        )
        sub_workflows.append({
            "task": task,
            "result": result,
            "output_channel": f"ch_{task.id}_out",
        })

    # LLM writes a top-level main.nf that:
    #   include { SUBTASK_1 } from './subtask_1/main.nf'
    #   include { SUBTASK_2 } from './subtask_2/main.nf'
    #   workflow {
    #     SUBTASK_1(input)
    #     SUBTASK_2(SUBTASK_1.out.results)
    #   }
    top_level_nf = self._compose_pipeline_nf(sub_workflows, user_intent)
    ...
```

#### Step 2C — Output format handling

Add explicit output-format detection in `TaskDecomposer._llm_decompose()`:

```
If user request contains: "download as X", "export to X", "output format X"
  → append a final Task(type=OUTPUT_FORMAT, output_type="X", tool_hint="format_converter")
```

The `NextflowComposer` already handles output format tools (e.g. CSV converters exist
in the tools table). This step ensures they are explicitly requested.

#### Step 2D — Inter-task data typing

Extend `TaskDecomposer` to annotate each task with explicit I/O types:

```python
@dataclass
class Task:
    ...
    input_data_type: str   # e.g. "fastq", "bam", "count_matrix", "results_csv"
    output_data_type: str  # e.g. "bam", "count_matrix", "results_csv", "pdf"
```

`_generate_multi_task_workflow()` uses these to validate that task N's
`output_data_type` matches task N+1's `input_data_type` before chaining.

---

## Summary Table

| Capability | Current State | Gap | Effort to Fix |
|---|---|---|---|
| **Queue multiple input queries** | ❌ Input disabled while AI responds | No client-side queue | ~1 day (frontend only) |
| **Detect compound request** | ❌ Treated as single query | TaskDecomposer exists but bypassed | ~2 days (wire-up) |
| **Generate sub-workflow per task** | ⚠️ Single 4-phase workflow for all tasks | No per-task decomposition | ~3 days (new method) |
| **Chain sub-workflow outputs → inputs** | ❌ Not implemented | No cross-workflow data handoff | ~3 days (new composer logic) |
| **Typed output format (download CSV)** | ⚠️ Best-effort keyword match | Not an explicit output constraint | ~1 day (TaskDecomposer extension) |
| **End-to-end: pre-process → analyze → export** | ❌ All crammed into one workflow | All gaps above | ~10 days total |

---

## What Already Exists (can be reused)

| Component | Location | Reuse plan |
|-----------|----------|-----------|
| `TaskDecomposer` | `lib/galaxy/ai/task_decomposer.py` | Wire into `generate_workflow_unified()` |
| Template library (6 pipelines) | `TaskDecomposer.task_templates` | Extend with more domain templates |
| LLM decomposition | `TaskDecomposer._llm_decompose()` | Already production-quality |
| `NextflowComposer` | `lib/galaxy/ai/nextflow_composer.py` | Call once per sub-task |
| `UnifiedToNextflowConverter` | `lib/galaxy/ai/workflow_converters/nextflow_converter.py` | Generate top-level include-chain main.nf |
| `SubworkflowLibrary` | `lib/galaxy/ai/subworkflow_library.py` | Cache composed sub-workflows for reuse |
