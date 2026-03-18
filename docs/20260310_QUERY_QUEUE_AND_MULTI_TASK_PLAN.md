# Query Queuing, Concurrent Execution & Multi-Task Workflow Plan

**Date:** 2026-03-10  
**Supersedes:** `20260318_QUERY_QUEUING_AND_MULTI_STEP_DECOMPOSITION.md`  
**Status:** Updated plan incorporating recent architectural discoveries

---

## Part 1 — Query Queuing & Concurrent Execution

### What the User Expects

> "If the current workflow is running, I should be notified when it finishes.
> New queries should be executable at the same time. Show this at the front page."

This implies **three distinct things**, which are currently all missing:

| Expectation | Current State | Gap |
|-------------|--------------|-----|
| Submit a new query while a workflow runs | Chat input disabled during AI response | Input is locked; can't even type |
| Workflows execute concurrently (not sequentially) | Nextflow executor supports it; no UI control | No way to trigger concurrent runs |
| See active run status on the main page | RunManager panel exists (hidden behind button) | Not surfaced prominently; no completion toast |
| Get notified when a workflow finishes | Email notification exists (WorkflowNotificationService) | Email only; no in-app notification |

### Important Distinction

**AI response time** (~3–10 s for workflow generation) vs **workflow execution time** (minutes to hours for Nextflow).

- The chat input is locked during **AI response time** (correct — next query may depend on the answer)
- But once the **AI returns the workflow**, the Nextflow execution runs asynchronously in Galaxy
- A user absolutely should be able to send another query while Nextflow is executing
- Currently: the chat is free between AI responses, but users have no visibility into running workflows without opening the RunManager panel

---

### Implementation Plan — Part 1

#### 1A. Enable query submission while workflows execute (front page awareness)

**What to add on the main chat page** (the page after login — `chat-with-artifacts.tsx`):

A persistent **"Active Runs" status bar** at the top of the chat page (not behind a button):

```
┌─────────────────────────────────────────────────────────────────┐
│  ▶ 2 workflows running   ✓ 1 completed today   ✗ 0 failed       │
│  RNA-seq analysis [running]   Drug docking [queued]             │
└─────────────────────────────────────────────────────────────────┘
```

No progress bar — Nextflow execution time is non-deterministic and there is no
reliable percentage to show without constant expensive trace-file polling.
Instead, show a simple **status label** (running / queued / completed / failed)
with an **elapsed time** counter (`running for 4 min`).

This is a collapsed summary by default, expanding on click. Uses data already
available from the RunManager's `runList` state + the SSE workflow-state events.

**File changes:**
```
frontend/client/src/components/chat-with-artifacts.tsx
  - Promote RunManager summary to always-visible top bar (not hidden behind button)
  - Show: active count badge, workflow name, status label, elapsed time
  - "View all runs" expands the full RunManager panel

frontend/client/src/components/execution-control-panel.tsx
  - No change needed — already renders run detail correctly
```

---

#### 1B. Pending query queue while AI is responding

Remove the hard `disabled={displayTyping}` lock. Replace with a soft queue:

**File:** `frontend/client/src/components/chat-interface.tsx`

```typescript
// Replace: disabled={displayTyping}
// With:    always enabled, but submit enqueues if AI is mid-response

const [pendingMessages, setPendingMessages] = useState<string[]>([]);

const handleSendMessage = useCallback((text: string) => {
  if (displayTyping) {
    // AI is responding — queue the message
    setPendingMessages(prev => [...prev, text]);
    return;
  }
  // Normal submit path
  submitToBackend(text);
}, [displayTyping]);

// When AI finishes responding, auto-submit the next queued message
useEffect(() => {
  if (!displayTyping && pendingMessages.length > 0) {
    const [next, ...rest] = pendingMessages;
    setPendingMessages(rest);
    submitToBackend(next);
  }
}, [displayTyping]);
```

**File:** `frontend/client/src/components/chat-input.tsx`

Remove `disabled={displayTyping}`. Add a queue badge on the send button:

```typescript
// Send button shows pending count when queued
<Button type="submit">
  {pendingMessages.length > 0
    ? <span>Queued ({pendingMessages.length})</span>
    : <SendIcon />}
</Button>
```

Queued messages appear immediately in the chat as grey "pending" bubbles
so the user can see what's in the queue and optionally cancel:

```
You:  "run RNA-seq analysis on my data"          ← sent, AI responding
You:  "now do the same for the control group"    ← queued (grey, with × cancel)
```

---

#### 1C. In-app completion notification

`WorkflowNotificationService` already sends email on workflow completion.
Add an **in-app toast notification** using the existing `use-toast.ts` hook:

**File:** `frontend/client/src/components/chat-with-artifacts.tsx`

Subscribe to the SSE `workflow_completed` event (already fired by `workflow-sse.ts`):

```typescript
useEffect(() => {
  const handleWorkflowCompleted = (event: WorkflowSSEEvent) => {
    if (event.type === 'workflow_completed') {
      toast({
        title: `Workflow complete`,
        description: `${event.workflowName} finished successfully.`,
        action: (
          <ToastAction onClick={() => scrollToInvocation(event.invocationId)}>
            View results
          </ToastAction>
        ),
        duration: 8000,
      });
    } else if (event.type === 'error') {
      toast({
        variant: 'destructive',
        title: `Workflow failed`,
        description: `${event.workflowName} failed.`,
        action: (
          <ToastAction onClick={() => scrollToInvocationAndExpandAutofix(event.invocationId)}>
            View & fix
          </ToastAction>
        ),
        duration: 0,  // stays until dismissed — failure requires action
      });
    }
  };
}, []);
```

#### What "View results" does when clicked

The chat message that generated the workflow already contains a `ChatOutputAttachments`
component. It polls `/api/invocations/{id}/outputs` and renders all output files with
download and inline preview (VCF, CSV, sequence, annotation, structure viewers).

Clicking "View results" simply **scrolls to that chat message** — outputs are already
loaded inside it. No new page or separate results view.

```typescript
const scrollToInvocation = (invocationId: string) => {
  const el = document.querySelector(`[data-invocation-id="${invocationId}"]`);
  el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
};
```

#### What "View & fix" does when clicked

`workflow-artifact.tsx` already has a "Run AutoFix" button that:
1. POSTs to `/api/galaxy/workflows/{workflowId}/invocations/{id}/autofix3/run`
   with `auto_apply: false` — proposes fixes, does not apply without user confirmation
2. Displays: session ID, termination reason, number of fix attempts made
3. Shows an "AutoFix history" button for previous attempts

Clicking "View & fix" **scrolls to that chat message** and **expands the autofix panel**
(already rendered but collapsed). The user then clicks "Run AutoFix" themselves.

```typescript
const scrollToInvocationAndExpandAutofix = (invocationId: string) => {
  const el = document.querySelector(`[data-invocation-id="${invocationId}"]`);
  el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  setExpandedAutofixInvocation(invocationId); // lifts state to expand the panel
};
```

The AutoFix button is already functional — the toast just replaces the need for the
user to manually find the failed run in the RunManager and locate the button.

---

#### 1D. Concurrent workflow execution

Workflows already run concurrently at the Galaxy/Nextflow level — each invocation
is an independent process. No backend change needed.

What is missing is a **UI affordance** to make this clear to the user. The updated
active runs bar (1A) provides this: seeing "2 workflows running simultaneously" with
elapsed-time counters makes concurrent execution visible and expected.
No progress bars — status labels and elapsed time are the only reliable signals
from an asynchronous Nextflow process.

The only constraint: AI query generation is sequential within a single chat session
(because query N+1 may depend on the answer to query N). The queue in 1B handles this
gracefully — multiple queries submitted quickly are answered one at a time, but each
resulting Nextflow execution runs immediately and concurrently with prior ones.

---

#### 1E. Front page — logged-in home

The logged-in entry point is the chat page. "Front page" means the first thing visible
after login. Currently the RunManager is hidden behind a toolbar button.

**Changes:**
1. The active-runs status bar (1A) appears at the top of every chat page
2. If a workflow completed while the user was away (detected on reconnect via SSE
   catch-up or polling), show a `workflow_completed` toast immediately on page load
3. The sidebar (already has a chat history list) gains a small coloured dot next to
   chat sessions that have a running workflow:
   - 🟡 Running
   - ✓ Completed (new, unread result)
   - ✗ Failed (needs attention)

---

## Part 2 — Multi-Task Interpretation & Workflow Generation

### Original Plan (2026-03-18) — Core Gaps

The original plan identified:

1. **`TaskDecomposer` is dead code** — not wired into `generate_workflow_unified()`
2. **No cross-workflow chaining** — each `compose_workflow()` call is independent
3. **No output-format awareness** — "export as CSV" is a keyword, not a typed constraint
4. **No inter-task data handoff** — task N output not connected to task N+1 input

These gaps remain. The following updates reflect what recent architectural work has changed.

---

### What Changed Since the Original Plan

#### Update 1: `NextflowComposer` is now the single generation engine

The original plan envisioned calling `NextflowComposer` once per sub-task. This is now
cleaner because `NextflowComposer` is the fallback for ALL confidence levels (medium and
low). The multi-task path naturally calls it N times — once per sub-task.

**New advantage:** The **L0 SubworkflowLibrary cache** means repeated sub-tasks across
different compound queries hit the cache. If "QC + trimming" is sub-task 1 of many
pipelines, it is generated once and reused instantly for subsequent requests.

**New advantage:** The **L2 tool-plan validation** runs independently per sub-task
before generation. Each sub-task gets pre-validated tool lists, reducing hallucinated
`include{}` paths in chained workflows.

---

#### Update 2: Tiered clarification must cover the whole pipeline, not sub-tasks

The tiered clarification plan (Phase 1–6) collects organism, replicates, read type, etc.
For compound requests, the same user_context applies to ALL sub-tasks. Questions should
be asked **once before decomposition**, not once per sub-task.

**Modified flow for compound requests:**

```
User: "Pre-process my RNA-seq, then run DE, then export as CSV"
          │
          ▼
    Tier 1: No ambiguity (RNA-seq is clear)
          │
          ▼
    Tier 2: Collect context for the WHOLE pipeline (one message):
      "Organism? Replicates? Paired-end?"
      Answer: "Human, 4 replicates, paired-end"
          │
          ▼
    TaskDecomposer.decompose_request() → [QC_task, DE_task, Export_task]
          │
          ▼
    For each task: NextflowComposer.compose_workflow(user_context=collected_context)
          │
          ▼
    _compose_pipeline_nf() → top-level main.nf including all sub-workflows
```

The collected `user_context` flows into every `NextflowComposer` call, activating the
EnhancedToolSearch scoring for each sub-task independently. A sub-task that doesn't need
a certain field (e.g., DESeq2 doesn't need `compound_format`) simply ignores it.

---

#### Update 3: AutoFix applies per sub-workflow in a chain

When a chained pipeline runs, each sub-workflow is an independent Nextflow invocation
(or Nextflow subworkflow with its own process namespace). The AutoFix system
(`ContainerErrorFixer` → `WorkflowRestarter`) can trigger independently per sub-workflow.

**This creates a new requirement not in the original plan:**

If sub-task 2 fails and AutoFix restarts it, the chained pipeline must:
1. Not re-run sub-task 1 (already succeeded; cache `NEXTFLOW_RESUME` or use Galaxy invocation state)
2. Feed the original output of sub-task 1 as input to the restarted sub-task 2

This requires the `_generate_multi_task_workflow()` method to record output paths
per sub-task and pass them as explicit input parameters to the restarted sub-task.

---

#### Update 4: scientific_rationale should cover the full pipeline

`_build_scientific_rationale()` currently generates a rationale per workflow.
For a chained pipeline, the user needs a single rationale covering the whole pipeline:

```
Pre-processing (FASTP):
  When to use: paired-end reads with adapter contamination
  Key parameter: --thread 8 for large datasets

Differential Expression (DESeq2):
  When to use: bulk RNA-seq ≥3 biological replicates
  ⚠️ Do not use: fewer than 3 replicates (you have 4 ✓)

Export (custom CSV converter):
  Output: results_table.csv with log2FC, p-value, FDR columns
```

The pipeline-level rationale is the concatenation of per-task rationales, with
cross-task dependencies highlighted (e.g., "DESeq2 requires the count matrix
produced by featureCounts in the previous step").

---

#### Update 5: Execution tracing for multi-task pipelines

The tracing UX gap analysis identified that the `workflow_ai_realtime.py` endpoint
is never polled by the frontend. For multi-task pipelines this is more critical —
users need to see which sub-task is running and which are queued.

The active-runs status bar (Part 1A) should show sub-task breakdown for compound requests:

```
Pipeline: "RNA-seq end-to-end" (3 sub-tasks)
  ✓ Sub-task 1: QC & trimming       [completed · 8 min]
  ▶ Sub-task 2: DE analysis         [running · 4 min elapsed]
  ○ Sub-task 3: CSV export          [waiting]
```

No progress bar — status label + elapsed time only.

---

### Updated Implementation Plan — Part 2

#### Step 2A: Activate TaskDecomposer (unchanged from original)

```python
# In generate_workflow_unified() — BEFORE the workflow search loop:

tasks = self.task_decomposer.decompose_request(
    UserRequest(request_id=..., request_text=user_intent, ...),
    parsed_intent={}
)

if len(tasks) > 1:
    return self._generate_multi_task_workflow(
        user_intent=user_intent,
        tasks=tasks,
        user_context=user_context,   # NEW: pass collected context
    )
```

**Trigger condition:** `len(tasks) > 1` after decomposition. `TaskDecomposer` already
has a heuristic that returns a single-item list for non-compound requests — no false triggers.

---

#### Step 2B: `_generate_multi_task_workflow()` — updated

```python
def _generate_multi_task_workflow(
    self,
    user_intent: str,
    tasks: List[Task],
    user_context: Optional[Dict] = None,
) -> Dict[str, Any]:

    sub_workflows = []
    prev_output_type = None

    for i, task in enumerate(tasks):
        # Validate I/O compatibility between sub-tasks
        if prev_output_type and task.input_data_type:
            if prev_output_type != task.input_data_type:
                log.warning(
                    f"[MultiTask] Type mismatch: sub-task {i-1} outputs "
                    f"'{prev_output_type}', sub-task {i} expects '{task.input_data_type}'"
                )
                # Insert an implicit conversion task if types are compatible
                # (e.g. BAM → sorted BAM, count_matrix → TSV)

        # Generate each sub-workflow — L0 cache hits are instant
        result = self.nextflow_composer.compose_workflow(
            user_intent=task.description,
            max_tools=20,
            user_context=user_context,     # NEW: context flows to tool scoring
        )

        sub_workflows.append({
            "task_id": task.id,
            "task_type": task.task_type.value,
            "description": task.description,
            "result": result,
            "input_type": task.input_data_type,
            "output_type": task.output_data_type,
            "output_channel": f"ch_{task.id}_out",
            # Record output path for AutoFix restart recovery
            "output_path_hint": f"results/{task.id}/",
        })
        prev_output_type = task.output_data_type

    # Compose the top-level pipeline main.nf
    pipeline_nf = self._compose_pipeline_nf(sub_workflows, user_intent)
    pipeline_file = self._write_workflow(pipeline_nf, _slugify(user_intent))

    # Build pipeline-level rationale (all sub-tasks)
    pipeline_rationale = self._build_pipeline_rationale(sub_workflows, user_context)

    return {
        "success": True,
        "nextflow_path": str(pipeline_file.relative_to(BACKEND_ROOT)),
        "workflow_type": "nextflow",
        "source": "nextflow_multi_task",
        "task_count": len(tasks),
        "sub_workflows": [
            {"task": sw["description"], "path": sw["result"].get("nextflow_path")}
            for sw in sub_workflows
        ],
        "scientific_rationale": pipeline_rationale,
        "needs_user_feedback": True,
        "message": (
            f"Composed {len(tasks)}-stage pipeline: "
            + " → ".join(t.description[:30] for t in tasks)
        ),
    }
```

---

#### Step 2C: `_compose_pipeline_nf()` — top-level workflow

The top-level `main.nf` includes each sub-workflow and chains outputs:

```nextflow
#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

// Auto-generated multi-task pipeline
// Tasks: QC_TRIMMING → DIFFERENTIAL_EXPRESSION → CSV_EXPORT

include { QC_TRIMMING_WF }           from './qc_trimming/main.nf'
include { DIFFERENTIAL_EXPRESSION_WF } from './differential_expression/main.nf'
include { CSV_EXPORT_WF }            from './csv_export/main.nf'

workflow {
    take:
        reads_ch     // input: raw FASTQ pairs

    main:
        QC_TRIMMING_WF(reads_ch)
        DIFFERENTIAL_EXPRESSION_WF(QC_TRIMMING_WF.out.trimmed_reads)
        CSV_EXPORT_WF(DIFFERENTIAL_EXPRESSION_WF.out.results)

    emit:
        final_csv = CSV_EXPORT_WF.out.csv
}
```

Generated by the LLM with the sub-workflow I/O types as context, using the `take` /
`emit` DSL2 channel naming from each sub-workflow's own `main.nf`.

---

#### Step 2D: Output-format detection (unchanged from original, minor refinement)

In `TaskDecomposer._llm_decompose()`, the LLM prompt explicitly instructs:

> "If the request mentions a desired output format (CSV, PDF, HTML, GFF3, VCF, etc.),
> append a final task of type OUTPUT_FORMAT with output_type set to that format."

The `tools` table already contains format-converter tools (CSV writers, VCF exporters,
MultiQC report generators). The `NextflowComposer` will find them via tool search.

---

#### Step 2E: AutoFix integration for chained execution (NEW — not in original plan)

When a sub-workflow in the chain fails:

1. `NextflowMonitor` detects the failure → triggers `_attempt_auto_fix()`
2. `ContainerErrorFixer` generates `updated_parameters`
3. `WorkflowRestarter.restart_workflow()` re-queues only that sub-workflow
4. On restart, the `WorkflowRestarter` must pass the recorded `output_path_hint` from
   the previous (successful) sub-workflow as an input parameter

**New field needed in FixContext:**
```python
context.metadata['upstream_outputs'] = {
    "qc_trimming": "/results/qc_trimming/trimmed.fastq.gz",
    # provided by _generate_multi_task_workflow at pipeline creation time
}
```

This is stored in `invocation.input_parameters` alongside `autofix_params` and
read by the restarted `WorkflowRestarter`.

---

## Summary: What Changes vs. Original Plan

| Item | Original Plan (2026-03-18) | Updated Plan (2026-03-10) |
|------|---------------------------|--------------------------|
| Chat input locking | Disable during AI response | Soft queue; input always enabled |
| Concurrent execution visibility | Not addressed | Active-runs status bar on main page |
| Completion notification | Not addressed | In-app toast + sidebar dot |
| TaskDecomposer activation | Wire into generate_workflow_unified | Unchanged + pass user_context |
| Per-task generation | NextflowComposer once per task | Same + L0 cache + L2 validation per task |
| Clarification questions | Not addressed for multi-task | Asked ONCE before decomposition |
| scientific_rationale | Per-workflow | Pipeline-level (all tasks concatenated) |
| AutoFix in chained pipelines | Not addressed | upstream_outputs passed to restarter |
| Progress visibility | Not addressed | Sub-task breakdown in active-runs bar |

---

## File Change Summary

| File | Change | Part |
|------|--------|------|
| `frontend/client/src/components/chat-interface.tsx` | Soft queue: remove hard disabled, add pendingMessages state | 1B |
| `frontend/client/src/components/chat-input.tsx` | Remove disabled, add queued-count badge | 1B |
| `frontend/client/src/components/chat-with-artifacts.tsx` | Promote RunManager to always-visible status bar; wire toast on SSE completion | 1A, 1C |
| `frontend/client/src/App.tsx` / sidebar | Coloured dot on sessions with active/completed/failed workflows | 1E |
| `backend/lib/galaxy/ai/ai_assistant.py` | TaskDecomposer wired in, `_generate_multi_task_workflow()`, `_build_pipeline_rationale()` | 2A, 2B |
| `backend/lib/galaxy/ai/nextflow_composer.py` | Accept `user_context` arg; pass to tool search | 2B |
| `backend/lib/galaxy/ai/task_decomposer.py` | Add `input_data_type`/`output_data_type` to Task; output-format detection | 2D |
| `backend/lib/galaxy/ai/workflow_ops/autofix/base.py` | Add `upstream_outputs` to FixContext.metadata schema | 2E |
| `backend/lib/galaxy/ai/workflow_ops/autofix/workflow_restarter.py` | Read upstream_outputs for chained restart | 2E |
