# Dev Stability: DB Volume Mount + Schema Migration

**Date:** 2026-07-11  
**Branch:** integration/next-phase

---

## What Happened

A tester reported "workflow is not available" on dev. Root cause was a **missing `input_types` column** in the dev copy of `galaxy_ai_tools.db`. The column was added to the schema after the DB was last built; `CREATE TABLE IF NOT EXISTS` is a no-op on existing tables, so the column was never applied to the live DB.

There was also a missing `workflow_chains` table, added by `index_all_workflows.py` but never created at runtime startup.

---

## Fixes Shipped

### 1. Runtime schema self-healing (`unified_workflow_search.py`)

`_migrate_schema()` is called from `_ensure_workflows_table()` at every Galaxy startup. It:

- Uses `PRAGMA table_info(workflows)` to detect missing columns
- Runs `ALTER TABLE workflows ADD COLUMN …` for any of: `input_types`, `output_types`, `annotation_v2`, `step_metadata`, `params_schema`
- Creates `workflow_chains` table with `CREATE TABLE IF NOT EXISTS`

This means future schema additions never require manual DB migration or container intervention. Galaxy repairs itself on boot.

### 2. Persistent DB volume mount (`scripts/sync_to_dev.sh`)

The 304 MB `galaxy_ai_tools.db` was previously synced into the container's writable layer via `docker cp`. On container recreation, the DB was lost.

New approach:
- `GALAXY_DB_HOST_PATH="/opt/biomate/galaxy_db"` on the EC2 host
- Sync writes the DB to the host path: `mv /tmp/galaxy_ai_tools_sync.db $GALAXY_DB_HOST_PATH/galaxy_ai_tools.db`
- Galaxy container runs with: `-v $GALAXY_DB_HOST_PATH:/app/database`
- DB now persists across container restarts/recreations

**Gotcha fixed:** The host directory must be world-writable (`chmod 777`) because Galaxy's process manager (gravity/supervisord) needs to create `gravity/` inside `/app/database/` at startup, and it runs as a non-root user inside the container.

### 3. Post-sync workflow smoke test (`scripts/sync_to_dev.sh`)

Added `smoke_test_workflow()` after the health gate. It calls `/api/ai_assistant/generate_workflow` with a simple test intent and validates:
- HTTP 200
- Response body has `"success": true`
- No `"db_unavailable"` error string

The sync only marks `SYNC_RESULT=healthy` if the smoke test passes. If it fails, the script rolls back to the previous container.

---

## Incident During This Session

While implementing the volume mount, the Galaxy container was recreated manually (ad-hoc, outside `sync_to_dev.sh`). This caused two failure modes:

1. **First recreation**: missing env vars → crash loop (container exited immediately)
2. **Second recreation**: correct env vars but host directory owned by root → `PermissionError: /app/database/gravity` → crash loop

Fix: `chmod -R 777 /opt/biomate/galaxy_db/` resolved the permission error and Galaxy booted.

**Lesson**: Never recreate containers outside of `sync_to_dev.sh`. The sync script handles the full lifecycle (env vars, volume mounts, rollback). Manual `docker run` outside that path is brittle and dangerous.

---

## Ongoing Rule

| What to do | How |
|------------|-----|
| Schema additions | Add column in `CREATE TABLE` + add to `_migrate_schema()` migration list |
| DB changes | Push via `sync_to_dev.sh` only — never manual `docker cp` |
| Container changes | In `sync_to_dev.sh` deploy path only — never ad-hoc `docker run` |
| Verifying a deploy | Wait for `smoke_test_workflow()` pass in sync output |

---

## Open Issues

- The `bioconductor_skill/` directory in the repo root is untracked — should be cleaned up or committed.
- Dev Galaxy permissions should be documented in the EC2 instance setup notes so any future container recreation gets `chmod 777` right the first time.
