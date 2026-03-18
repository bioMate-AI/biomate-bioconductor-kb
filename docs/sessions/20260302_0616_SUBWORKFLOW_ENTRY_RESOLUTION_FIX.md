# Subworkflow Entry Resolution Fix (2026-03-02 06:16)

## Why this change
- Prior failures showed `No entry workflow specified` during Nextflow execution.
- Root issue: some selected `.nf` files required an explicit entry workflow.
- A blanket "reject subworkflows" policy is too strict because some subworkflows are runnable with explicit entry.

## What changed

### 1) Backend Nextflow executor now supports entry resolution
- File: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- Added request field:
  - `entry` (optional)
- Added automatic entry detection for named-workflow scripts:
  - if anonymous `workflow { ... }` exists -> no explicit `-entry` needed
  - otherwise detects named workflows and selects preferred entry (`main`, `run`, `workflow`) or first available
- Execution command now appends `-entry <name>` when resolved.
- Selected entry is recorded in runtime metadata.

### 2) Removed overly strict frontend selection guard
- File: `frontend/server/galaxy-api-proxy.ts`
- Removed blanket rejection of paths containing `subworkflows`.
- Kept runnable path requirement (`.nf` path), while backend now handles entry resolution safely.

## Runtime restart
- Restarted backend service on `:8081`.
- Rebuilt/restarted frontend service on `:5310`.

## Validation
- Ran:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
- Result: **PASS**
- The previously recurring `No entry workflow specified` failure did not occur in this validation run.

## Current status
- Subworkflows are no longer categorically blocked.
- Execution now prefers explicit entry resolution when needed, while preserving normal runs for scripts with default/anonymous workflow entry.

