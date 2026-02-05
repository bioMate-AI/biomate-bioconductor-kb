# Nextflow-First Comprehensive Test Checklist

Date: 2026-02-03

This checklist validates that Nextflow execution is the primary engine while Galaxy continues to manage histories, datasets, and visualizations. It also verifies the soft fallback output flow (history re-resolution only).

## Prerequisites

- BioMate frontend/server running (default `http://localhost:5000`)
- Galaxy backend running (default `http://localhost:8081`)
- `GALAXY_API_KEY` available in environment for protected endpoints
- A valid Galaxy workflow definition JSON file (`.ga`) compatible with Nextflow execution
- Optional: inputs JSON file if the workflow has input steps

## Environment Variables

Set these before running tests:

- `BIOMATE_URL` (default `http://localhost:5000`)
- `GALAXY_URL` (default `http://localhost:8081`)
- `GALAXY_API_KEY` (required for protected endpoints)
- `WORKFLOW_JSON` (path to a Galaxy workflow JSON file)
- `INPUTS_JSON` (optional; path to input datasets JSON list)
- `AUTO_FIX` (optional; `true` to auto-trigger AutoFix when failed)

## Test Areas

### A) Backend Integration

- Nextflow scheduler invoked via Galaxy invocation (`scheduler=nextflow`).
- Nextflow monitor status endpoint returns task counts and progress.
- AutoFix endpoints respond without error.
- Outputs are written into Galaxy history.

### B) Server (Node/Express)

- `/api/workflows/execute` accepts `executionEngine=nextflow` and returns invocation IDs.
- `/api/invocations/:id/outputs` returns history outputs after completion.
- `/api/invocations/:id/fetch-outputs` re-resolves history ID when outputs missing.
- `/api/invocations/:id/ai/autofix` triggers AutoFix.

### C) Client (React)

- Workflow History Panel shows engine badge.
- Workflow Artifact header shows engine badge.
- Outputs dialog shows AutoFix button for Nextflow runs.
- "Fetch Outputs" button works when no outputs are available.

## Scripted Validation (Recommended)

Use the automated script:

```
python3 /home/yzhang/biomate/codex_work/run_nextflow_tests.py
```

The script:
- Executes a workflow with `executionEngine=nextflow`
- Polls run status
- Fetches outputs (and triggers fallback if needed)
- Optionally triggers AutoFix

## Manual Steps (UI)

1. Send a chat request that generates a workflow.
2. Click Execute.
3. Confirm the engine badge shows "Nextflow".
4. Confirm the run completes and outputs appear.
5. If outputs are missing, click "Fetch Outputs".
6. If failed, click "Run AutoFix".

## Expected Results

- Run completes with `status=completed` and outputs appear in Galaxy history.
- Outputs are visible in BioMate UI and can be downloaded.
- If outputs missing, fallback re-resolves history and outputs appear.
- AutoFix returns a result when invoked.
