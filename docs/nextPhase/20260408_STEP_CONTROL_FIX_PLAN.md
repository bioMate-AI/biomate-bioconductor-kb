# Step Control Buttons Fix + Architecture Status (2026-04-08)

## Summary

Two findings this session:

1. **DOMAIN_CATALOGS is already fully populated** — S6 was completed in a prior session.
   All domains (genomics, single_cell, epigenomics, proteomics, cryo_em, systems_biology,
   synthetic_biology, bioimaging, lab_automation, drug_discovery, cancer_biology,
   cell_biology) have catalog entries. No work needed.

2. **Single-step control buttons were architecturally broken** — the "Run Step" button
   was wired to Galaxy's tool execution API, which is irrelevant for Nextflow pipelines.
   Fix implemented this session.

---

## Architecture Improvement Status (S1–S6)

| Item | Status | Notes |
|------|--------|-------|
| S1 — `_clarificationGate()` extraction | ✅ Done | `galaxy-assistant.ts` |
| S2 — Confidence-gated session memory | ✅ Done | `galaxy-assistant.ts` |
| S3 — DOMAIN_SPECIALIST_GUIDANCE injection | ✅ Done | Previous session |
| S4 — Step-by-step approval gate (PipelineListView) | ✅ Done | Previous session |
| S5 — CLARIFICATION_FALLBACKS completeness test | ✅ Done | 59 unit tests |
| S6 — Domain catalog injection (all domains) | ✅ Done | All 12 domains populated |

**All S1–S6 items complete.**

---

## Step Control Button Root Cause

### What the buttons do today (before fix)

The per-step "Run Step" button in `nextflow-workflow-viewer.tsx` was always disabled
for Nextflow pipelines because of a guard condition:

```typescript
runDisabled={
  !phase.toolId ||   // ← always true for Nextflow phases — Galaxy toolId ≠ Nextflow process
  phase.isExecuting === true || ...
}
```

Nextflow phases are derived from `workflowDefinition.steps`, which store Nextflow process
definitions. They have no `tool_id` (that is a Galaxy concept). So `phase.toolId` is
always `undefined` for every step in every Nextflow pipeline, making every "Run Step"
button permanently disabled.

Even if a button somehow did fire, `handleRunStep` called:

```typescript
fetch("/api/workflow/step/execute", {
  body: JSON.stringify({ step_id, tool_id, parameters, inputs })
})
```

Which hit `routes.ts:2447` → `userProxy(req).submitToolJob(tool_id, ...)` → Galaxy Tool
API. This has no relationship to the Nextflow pipeline that was actually run.

Status polling (`/api/workflow/step/:step_id/status`) called `galaxyAPIProxy.getJob()`
— again Galaxy, not Nextflow.

### Why Nextflow cannot re-run a single step in isolation

Nextflow does not support per-process filtering at runtime. There is no flag like
`--process.only FASTQC`. The correct Nextflow approach for "retry a failed step" is:

```
nextflow run <pipeline> -resume -w <original_work_dir>
```

`-resume` reuses the work cache: all completed tasks are skipped; only failed, errored,
or never-run tasks execute. This is exactly what "retry from a step" means in practice.

---

## Fix Design

### New endpoint: `POST /api/nextflow/resume/{run_id}`

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

Looks up the original run from `_runs` (has `nextflow_path`, `work_dir`, `profile`,
`entry`, `user_id`, `is_batch`), builds a `NextflowExecuteRequest` with
`resume_from_run_id=run_id`, and calls `execute_nextflow()`. The existing `-resume`
logic at line ~2073 appends `-resume -w <prev_work_dir>` to the Nextflow command.

Returns the standard `{run_id, invocation_id, success, ...}` payload of a new run.

### New route: `POST /api/workflows/runs/:runId/resume`

**File**: `frontend/server/routes.ts`

Thin proxy: forwards to `GALAXY_URL/api/nextflow/resume/:runId` with the backend API
key. Returns the new `run_id` to the frontend.

### Viewer: `handleRunStep` rewritten

**File**: `frontend/client/src/components/nextflow-workflow-viewer.tsx`

Old: called `POST /api/workflow/step/execute` (Galaxy toolId, always failed).

New:
```typescript
const response = await fetch(
  `/api/workflows/runs/${encodeURIComponent(activeRunId)}/resume`,
  { method: "POST" }
);
const { run_id: newRunId } = await response.json();
if (newRunId) setRerunRunId(newRunId);  // viewer switches to tracking new run
```

`rerunRunId` already existed in viewer state. `activeRunId = rerunRunId ?? runId`.
When `rerunRunId` is set, the existing Nextflow status polling automatically tracks
the new run — no new polling machinery needed.

### Viewer: `runDisabled` condition fixed

Old:
```typescript
!phase.toolId || phase.isExecuting === true || ...
```

New:
```typescript
!activeRunId || phase.isExecuting === true || ...
```

Button is now enabled whenever a run exists (even after failure), regardless of whether
the phase has a Galaxy `tool_id`.

### Viewer: terminal status clears `isExecuting`

New `useEffect`:
```typescript
useEffect(() => {
  const isTerminal = status === 'completed' || status === 'failed' || status === 'error';
  if (!isTerminal) return;
  setStepExecutionById((prev) => {
    const hasExecuting = Object.values(prev).some((e) => e.isExecuting);
    if (!hasExecuting) return prev;
    const next: Record<string, StepExecutionState> = {};
    for (const [id, exec] of Object.entries(prev)) {
      next[id] = exec.isExecuting ? { ...exec, isExecuting: false } : exec;
    }
    return next;
  });
}, [status]);
```

When the resumed run reaches `completed`/`failed`/`error`, all step `isExecuting` flags
are cleared, re-enabling the Run Step buttons for further retries.

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Added `POST /api/nextflow/resume/{run_id}` endpoint |
| `frontend/server/routes.ts` | Added `POST /api/workflows/runs/:runId/resume` proxy route |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | `handleRunStep`: Galaxy→Nextflow resume; `runDisabled`: toolId→activeRunId; added terminal-status useEffect |

---

## E2E Test: GC-8 — PASSING (2026-04-08)

**File**: `frontend/e2e/germline-complete-e2e.e2e.ts`

GC-8 is implemented and **passes** as part of the full 8/8 germline suite.

Flow:
1. Register user, send germline query with `SRR1518169 max_spots=100`
2. Confirm & Run → execute API returns frontend storage UUID (`runId`)
3. Poll until terminal (`failed` expected without real FASTQ data)
4. Dismiss "Before you go" survey dialog (`{ force: true }` for overlay)
5. Find enabled Run Step button (`button-run-step-setup`)
6. Click with `{ force: true }` and intercept `/rerun` POST response
7. Assert HTTP 200; verify response `run_id` equals original `runId`
   (route updates existing record in-place — same frontend UUID, new Nextflow UUID underneath)
8. Assert `GET /api/workflows/runs/{runId}/status` → 200, `status=running`
9. Assert viewer evidence panel shows updated Nextflow run ID

Key implementation detail: `/api/workflows/runs/:runId/rerun` returns the same
frontend storage UUID (not the new Nextflow UUID), after updating the record's
`nextflowRunId` to point to the resumed run. This keeps the viewer's polling machinery
pointing at the same storage record without any changes.

---

## What Remains Open

- **GC-2 real SRA run**: Still requires AWS Batch + ~1hr. Not yet executed.
