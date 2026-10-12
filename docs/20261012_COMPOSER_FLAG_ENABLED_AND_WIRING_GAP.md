# Composer flag enabled on dev — and the live-path wiring gap it revealed

**Date:** 2026-10-12
**Session outcome:** `BIOMATE_MULTITASK_DAG_ENABLED=true` is now live on `biomate-galaxy-dev`,
but the zero-cost draft test revealed the composer's code path is **not reached by the live
chat/generation flow**. Flag is active; behaviour is unchanged live because the gated code is dead
relative to `generate_workflow_unified`. This doc records what was done, the two sync-script bugs
fixed along the way, the wiring gap, and the proposed fix.

## 1. Flag activation (done, verified)
- Added `BIOMATE_MULTITASK_DAG_ENABLED=true` to dev `/opt/biomate/.env`, then recreated the Galaxy
  container through the sanctioned `BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh`
  (health-gated, rollback-protected). Registered the flag (+ `BIOMATE_PATTERN_ROUTER_ENABLED`) as a
  managed var in `deploy/biomate.env.manifest` (commit `4f53a2d5e`) so it is flipped in-band, not ad-hoc.
- **Verified in the RUNNING container** (not just exit code): `printenv BIOMATE_MULTITASK_DAG_ENABLED`
  → `true`; `decomposed_dag.py` present; module imports clean; `DATABASE_URL`/`JWT_SECRET`/
  `GALAXY_API_KEY` preserved across the recreate; container freshly recreated and healthy; sync
  `result=healthy`, smoke passed.

## 2. Two sync-script bugs fixed (commit `389b46870`)
The first resync run printed `[galaxy-env] Done` and `result=healthy` but the container was NOT
recreated (still "Up 19 hours", flag unset) — a **false green**. Root cause in
`resync_galaxy_env()` (`scripts/sync_to_dev.sh`), in code that had **never executed** (the function
always aborted at the first bug):

1. `CLEANUP_FILES="$CLEANUP_FILES $LIVE_ENV"` ran **inside the remote single-quoted ssh block** under
   `set -u`, where `CLEANUP_FILES` (a LOCAL `on_exit` var) is unbound → fatal → aborted **before**
   `docker stop/rm/run`. Fix: a **remote-side** `trap 'rm -f "$LIVE_ENV"' EXIT` (the remote temp file
   is cleaned remotely; this does not clobber the local lock/SNS `on_exit` trap).
2. `-v $GALAXY_DB_HOST_PATH:/app/database` also expanded remotely (unbound under `set -u`) **and**
   duplicated the `/app/database` mount already captured by `$MOUNTS` → "Duplicate mount point" →
   `docker run` fails **after** `docker rm` → **dev Galaxy down**. Fix: conditional `DB_MOUNT` — rely
   on `$MOUNTS` (verified it already has the mount), add an explicit mount only if missing, with the
   path interpolated locally.

Lesson (for the team): a sync that prints `result=healthy` can still have **skipped** a step — the
old (healthy) container passes the health gate. Always verify the *running container* reflects the
change (here: `printenv` the new var), never trust the "Done" line. Matches
`project_dev_backend_deploy_didnt_land` in memory.

## 3. The wiring gap (the real finding)
The composer DAG hook is in `backend/lib/galaxy/ai/ai_assistant.py`:
`route_and_handle` (≈481) → `_looks_like_multi_task` (≈512) → `_handle_multi_task_clarification`
(≈708) → flag-gated `build_dag_plan` + `to_pipeline_card` (≈764-783).

**But `route_and_handle` has zero live callers.** `grep -rn "route_and_handle|_looks_like_multi_task|
_handle_multi_task_clarification"` across `backend/` + `frontend/` returns only the definitions and
`lib/galaxy/ai/tests/test_multi_task_classifier.py`. The live chat/generation endpoint is
`POST /api/ai_assistant/generate_workflow` → **`generate_workflow_unified`** (≈3795,
"unified search-first"), which does not invoke `route_and_handle`, `_looks_like_multi_task`, or
`_handle_multi_task_clarification`. So:
- The entire multi-task clarification feature (not just the DAG slice) is **dormant** in the live path.
- Enabling `BIOMATE_MULTITASK_DAG_ENABLED` is **inert live** — its gate is never reached.
- The zero-cost draft e2e (`composer-dag-draft.e2e.ts`) correctly produced no DAG card (it also
  produced 0 workflow cards for the test phrasing — under investigation whether the "do not launch /
  prepare the plan" wording also suppressed single-task generation via the execution-intent guard;
  secondary to the wiring gap).

This is the "gap is SELECTION/wiring, not the primitive" pattern (memory
`feedback_audit_biomate_capabilities_first`). The composer primitive (`decomposed_dag.py`, 18 tests,
validated against `galaxy.chain.dag.validate_plan`) is solid; it is simply hooked into a method the
live path never calls.

## 4. Proposed fix (next step — careful, flag-gated, into a hot endpoint)
Wire multi-task detection + the composer into `generate_workflow_unified` so the live
`/api/ai_assistant/generate_workflow` path can emit a whole-plan DAG card:
- Early in `generate_workflow_unified`, when `BIOMATE_MULTITASK_DAG_ENABLED` is on and
  `_looks_like_multi_task(request.request_text)` is true, decompose → `build_dag_plan` →
  `to_pipeline_card`, and return the pipeline-card shape the frontend chain card renders.
- Fail-safe: any miss (not multi-task, a task unresolved, a handoff type-mismatch, any exception) →
  continue to the existing unified single-workflow generation (byte-for-byte current behaviour).
- Confirm the frontend renders the returned `workflow` object as a PipelineListView when
  `workflow_type === 'pipeline'` / `execution_mode === 'dag'` — and that `generate_workflow`'s
  response field name matches what the renderer reads (`workflow` vs `workflow_ga`). (Being mapped.)
- Validate: unit test the live-endpoint branch (hermetic, injected resolver); re-run the zero-cost
  draft e2e; only then sync. Do NOT trigger any Batch run.

**Discipline note:** `generate_workflow_unified` is a hot, critical endpoint. The hook must be
additive, flag-gated, and fail-safe — never alter the default single-task path. Review the full
function + frontend render contract before editing (per CLAUDE.md "Review Code Before Testing").
