# Outputs, Step Execution & Parameter Settings Analysis

**Date**: 2026-03-12  
**Branch**: connection_formal  
**Status**: Gaps identified; step-level output registration being implemented

---

## 1. Where Are Intermediate and Final Outputs?

### Final Outputs
After a workflow completes, outputs are registered in the SQLite storage via `storage.addOutput()` and accessible at:

| Access Method | How |
|---|---|
| Output panel in chat | `ChatOutputAttachments` fetches `GET /api/invocations/:id/outputs` |
| Download all | Button opens `GET /api/invocations/:id/download-all` (zip stream) |
| Individual file | Each card → `GET /api/outputs/:id/download` |
| Preview / display | `GET /api/outputs/:id/preview` (image) or `GET /api/outputs/:id/display` (iframe) |

For **Batch / AWS** runs: final outputs land in `s3://biomate-nextflow-work/nextflow/work/{hash}/` and are copied to the Galaxy dataset location by `nextflow_runner.py:_collect_outputs()`.

### Intermediate Outputs (Not Yet Surfaced)
Nextflow intermediate work files are in:
- **Local**: `/tmp/nextflow_work/{job_id}/` — each process hash subdirectory
- **Batch**: `s3://biomate-nextflow-work/nextflow/work/{hash}/{process-dir}/` — not directly browsable from UI

**Gap**: The Nextflow trace file (`workflow-trace.txt`) records every process with its work directory, start/end times, and exit code — but it is only parsed for progress % (completedTasks/totalTasks). No per-process output files are extracted from it.

---

## 2. Step-by-Step Execution — Current State

### What IS implemented (Galaxy tool mode)

| Component | File | Status |
|---|---|---|
| "Run Step" button in PhaseCard | `phase-card.tsx:187` | ✅ UI exists |
| `handleRunStep()` in viewer | `nextflow-workflow-viewer.tsx:390` | ✅ Calls `/api/workflow/step/execute` |
| `POST /api/workflow/step/execute` | `routes.ts:1823` | ✅ Submits Galaxy tool job |
| `GET /api/workflow/step/:id/status` | `routes.ts:1878` | ✅ Polls Galaxy job state + returns `outputs[]` |
| Step status displayed in PhaseCard | `nextflow-workflow-viewer.tsx:~1190` | ✅ backendState, jobId, runCount shown |
| Step re-run (runCount increment) | `nextflow-workflow-viewer.tsx:~440` | ✅ Each call increments runCount |

**How it works**: The "Run Step" button submits the step's current `phase.parameters` as a Galaxy tool job. Repeating with different parameters is supported — each call creates a new job in the Galaxy history. `runCount` tracks attempts per step. `lastRunAt` shows the most recent run time.

### What is NOT implemented

1. **Nextflow single-step execution**: Nextflow always runs the full workflow DAG. There is no `--entry` or step-skip mechanism wired in the executor. The step execution route (`/api/workflow/step/execute`) uses the **Galaxy** tool runner, NOT the Nextflow runner.

2. **Per-step output registration**: `OutputDataset` has no `stepId` field. When a Galaxy job completes, its output datasets are returned by `/api/workflow/step/:id/status` in the JSON body but are **not persisted** to storage with a step association. `StepExecution.outputs[]` in the schema exists but is always empty `[]`.

3. **`updateExecutionRunStep()` never called**: This storage method exists at `storage.ts:514` and correctly maps step outputs, but is never invoked during execution.

4. **Trace-based step output extraction**: The Nextflow trace file contains `work` directory paths per process but no code reads those directories to list output files.

---

## 3. Parameter Settings & Per-Step Parameters

### What IS implemented

- `buildViewerParameters()` in `nextflow-workflow-viewer.tsx` builds a flat list of all workflow-level params using `workflowDefinition.parameter_metadata` (from backend DB)
- `ParameterGroup` groups params by level: Required (★), Recommended by AI (✦ purple), Optional (collapsible), Advanced (hidden)
- Per-step parameters: `buildPhaseParameters(phase, params)` builds step-level inputs from `phase.parameters` shown in each PhaseCard (collapsible "Parameters (N)" section)
- File/data params: compound widget with text input + "Upload file" button + "My datasets" picker
- `handleParamChange(id, value)` updates `params` state; updated params are passed to `onExecute(params)` when "Confirm & Run" is clicked

### What has NOT been tested

- **"Run Step" with modified parameters**: The `handleRunStep` function passes `phase.parameters` which comes from `workflowDefinition.steps[i].parameters` merged with user edits. If the user changes a param in the PhaseCard's parameter section and then clicks "Run Step", the edited value should be used — but this path has not been end-to-end tested.
- **Repeated step runs**: `runCount` increments correctly in the UI state, but whether the same Galaxy job history accumulates all runs (or creates separate jobs) has not been verified.
- **Required param validation on step run**: The global "required params missing" banner blocks "Confirm & Run" for the full workflow, but there is no per-step validation — a step's "Run Step" button is enabled even if step-specific required params are empty.

---

## 4. Gaps Being Fixed (2026-03-12)

### Gap A: Per-step output registration (implementing now)
- Add `stepId?: string` to `OutputDataset` schema
- In `GET /api/workflow/step/:id/status`, when `state === 'ok'`, persist output datasets to storage with `stepId`  
- Call `updateExecutionRunStep()` to populate `StepExecution.outputs`
- Frontend: show step-specific outputs in PhaseCard after completion

### Gap B: Chat file upload → session dataset picker (DONE)
- `chatHistoryService.addDatasets()` now called in `chat-interface.tsx` after upload
- `DatasetConfig.galaxyDatasetId` field added to schema
- `chat-with-artifacts.tsx` mapping updated to include `galaxyDatasetId`

### Gap C: `nextflow_run_summary` placeholder output (DONE)
- Filtered from main output cards; shown only as a small "Run log ↓" text link

---

## 5. Nextflow Trace → Step Output Mapping (Future Work)

The Nextflow trace file format (TSV):
```
task_id  hash   native_id  name           status  exit  submit  duration  realtime  %cpu  peak_rss  peak_vmem  rchar  wchar
1        ab/cd  job-xyz    TRIM_READS (1) COMPLETED 0   ...     1m30s     ...
```

The `hash` field (e.g., `ab/cd`) maps to the work directory: `<workDir>/ab/cd*/`. Output files are in that directory.

To implement trace-based output registration:
1. After Nextflow run completes, read `workflow-trace.txt`
2. For each completed process, list the work directory  
3. Filter files that look like outputs (not `.command.*`, not `.exitcode`, not `work/` subdirs)
4. Register each file as an output with `stepId = process.name`
5. Skip intermediate work files (`.nf.*.nf`, ``.nf.`, `.command.sh`, `.command.err`)

**Effort**: Medium — requires S3 directory listing for Batch runs, local `fs.readdir` for local runs.

---

## 6. S3 Credentials for Parameter Fields

When users type an `s3://` path directly in a file parameter field:
- **Batch runs (AWS)**: The ECS task role (`ecsInstanceRole` with `GalaxyNextflowS3Access`) provides transparent access to `biomate-nextflow-work` and `galaxy-cloud-data-*` buckets — no credentials needed in the parameter field
- **Local runs**: The server's `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars are used by boto3 — again transparent
- **External S3 buckets** (user's own): User must provide credentials. UI currently offers no credential injection for parameter fields. Workaround: use presigned URLs (valid 1h) generated via `POST /api/s3/upload/init`

**Gap**: No per-parameter S3 credential UI. Low priority given most data lives in BioMate's own buckets.
