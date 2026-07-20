# Workflow History: Literature Task Leak & Run-Reuse Fix

**Date:** 2026-07-11  
**Branch:** integration/next-phase  
**Files changed:** `server/run-overview.ts`, `client/src/components/workflow-history-dialog.tsx`, `client/src/components/app-sidebar.tsx`, `client/src/components/chat-with-artifacts.tsx`

---

## Problem

Two bugs reported by user in the sidebar Workflows panel:

### 1. Literature/research tasks appearing in the workflow run list

The `WorkflowHistoryDialog` fetches from `/api/workflows/runs/overview`, which calls `storage.getExecutionRuns()` and returns **all** `execution_runs` records. Some runs have no actual execution engine (no Nextflow, no Galaxy invocation). These are research/literature knowledge tasks that somehow accumulated an execution_run record but have no callable backend. They appeared in the list without any distinguishing label.

### 2. "Run again" triggered a Nextflow error

The "Run again" button in `WorkflowHistoryDialog` navigated to `/?session=<id>&runAgain=<runId>`. The `chat-with-artifacts.tsx` `?runAgain` handler loaded the prior run's `workflowDefinition` and immediately called `handleRunWorkflow()` — which POSTs to the Nextflow executor. For research tasks (no `nextflowRunId`), this failed with a Nextflow error. Even for real Nextflow runs, users complained that "running again" is wrong behavior: they want to start a new analysis (new files, possibly adjusted parameters), not literally re-execute the identical run.

---

## Root Cause

**Literature tasks in the run list:** `execution_runs` rows with `execution.executionEngine = undefined` (or empty) and no `nextflowRunId`/`galaxyInvocationId` have no discriminator in the overview API. There was no `runType` field to tell the UI "this is a research task, not an executable workflow."

**Nextflow error on re-run:** `?runAgain` was designed as a literal re-execution shortcut. The concept conflates "open the same workflow template" with "re-execute the same run" — which is wrong for users.

---

## Fix

### `server/run-overview.ts`

Added `RunType = "nextflow" | "chain" | "galaxy" | "research"` export type.

Added `runType: RunType` field to `RunOverviewRow` interface.

Added `toRunType(run: ExecutionRun): RunType` helper:

```typescript
function toRunType(run: ExecutionRun): RunType {
  const engine = (run.execution as any)?.executionEngine as string | undefined;
  if (engine === "nextflow" || (run.execution as any)?.nextflowRunId) return "nextflow";
  if (engine === "chain") return "chain";
  if (engine === "galaxy" || (run.execution as any)?.galaxyInvocationId) return "galaxy";
  return "research";  // no real execution backend
}
```

`buildRunOverviewRow` now populates `runType`. The field is serialized by `res.json(overview)` automatically — no route changes needed.

### `client/src/components/workflow-history-dialog.tsx`

- Added `runType?: string` to `RunRow` interface.
- Map `row.runType` from API response.
- Research runs get a purple "Research" badge next to their status text.
- "Run again" button is **hidden** for `runType === 'research'` tasks (they have no executable workflow definition to reuse).
- Button renamed from **"Run again"** → **"New analysis"** for all other run types (nextflow/chain/galaxy).
- Removed `disabled={!r.chatSessionId}` from the "New analysis" button — the new flow no longer requires a session (opens a fresh chat).
- Updated `title` tooltip to "Start a new analysis with this workflow — add new files or adjust parameters".

### `client/src/components/app-sidebar.tsx`

Changed `onRunAgain` callback from:
```typescript
window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}&runAgain=${encodeURIComponent(row.runId)}`);
```
to:
```typescript
window.location.assign(`/?reuseWorkflow=${encodeURIComponent(row.runId)}`);
```

Key differences:
- **No `session` param** — opens a fresh chat session (blank context), not the old session.
- **`reuseWorkflow` instead of `runAgain`** — handled by a different, non-auto-executing code path.

### `client/src/components/chat-with-artifacts.tsx`

Added new `useEffect` for `?reuseWorkflow=<runId>`:

```typescript
const handledReuseWorkflow = useRef<string | null>(null)
useEffect(() => {
  const url = new URL(window.location.href)
  const runId = url.searchParams.get('reuseWorkflow')
  if (!runId || handledReuseWorkflow.current === runId) return
  handledReuseWorkflow.current = runId
  ;(async () => {
    try {
      const r = await fetch(`/api/workflows/runs/${encodeURIComponent(runId)}`, ...)
      const run = await r.json()
      const wf = run?.workflowDefinition
      if (!wf) return
      // Load workflow into panel WITHOUT auto-executing
      const template = { ...wf, nextflowRunId: undefined, galaxyInvocationId: undefined }
      setPanelWorkflow(template)
    } catch ...
    finally {
      url.searchParams.delete('reuseWorkflow')
      window.history.replaceState({}, '', url.toString())
    }
  })()
}, [])
```

Critical difference from `?runAgain`: does **not** call `handleRunWorkflow()`. The user lands on a fresh chat with the workflow panel pre-populated, adds new input files, and clicks Run manually. This is the correct "reuse as template" behavior.

The old `?runAgain` handler is preserved for backward compatibility (it's still used by the v2 AfterRunReport's "Run again with edits" CTA which intentionally re-executes).

---

## Behavior After Fix

| Scenario | Before | After |
|---|---|---|
| Research task in sidebar list | Appears with no label, "Run again" crashes | Appears with purple "Research" badge, no action button |
| Nextflow run "Run again" | Re-executes immediately, no chance for new inputs | Opens fresh chat with workflow pre-loaded, user provides new files/params |
| Chain run "Run again" | Re-executes immediately | Same as above — "New analysis" template behavior |
| AfterRunReport "Run again with edits" | Re-executes with edited params (intentional) | Unchanged — still uses `?runAgain` path |

---

## Architecture Observations (Open Science Tools)

Discussed in session. Three patterns from nf-core/Galaxy worth adopting:

### 1. Parameter schema as first-class artifact (nf-core)

nf-core workflows carry `nextflow_schema.json` — a JSON Schema describing every parameter with type, description, default, and enum options. The BioMate UI partially adopts this via BC-PARAM, but `workflowDefinition` remains a free-form blob. Full adoption would enable:
- Auto-generated parameter forms (no manual mapping)
- Diff of "what changed between Run 3 and Run 4 of the same workflow"
- Pre-execution validation against schema constraints

**Action:** When creating a workflow draft, fetch and cache the workflow's `nextflow_schema.json`. Store it alongside `workflowDefinition` in the `execution_runs` row. Use it to render the "New analysis" parameter form.

### 2. Data provenance graph (Galaxy)

Galaxy stores a directed graph: `dataset → tool_invocation → output_dataset`. You can traverse the graph to answer "what produced this file?" BioMate has `step_name` and `input_context` as metadata fields on `project_files`, but no graph edges. 

**Action (medium-term):** When `save-to-project` fires, write rows to a `file_lineage` table: `(input_file_id, run_id, output_file_id, step_name)`. The Files tab can then show a provenance chain — "this VCF came from this FASTQ via nf-core/sarek Run 3."

### 3. Resumability via `-resume` (Nextflow)

Nextflow hashes inputs + params to a content-addressed work directory. `-resume` skips unchanged steps. The BioMate backend supports `/api/nextflow/resume/:runId` but the product-level "New analysis" flow currently starts from scratch. 

**Action:** In the "New analysis" panel, add a toggle "Resume from checkpoint" that, when enabled, passes the prior `nextflowRunId` to the execution endpoint and routes through the resume path instead of a fresh run. Best for iterative parameter tuning (e.g., adjusting a QC threshold and rerunning only downstream steps).

---

## Pending Work (not in this session)

- DB migrations `0019_user_llm_api_keys.sql` and `0020_project_members.sql` need to run on EC2.
- GitHub Actions workflow files need `gh auth login --scopes workflow` to push.
- Tauri updater pubkey: run `tauri signer generate` in an interactive terminal.
- Tauri code signing: macOS Developer ID cert required for public distribution.
- `OPENROUTER_API_KEY` env var on EC2 if system-level default model is desired.
