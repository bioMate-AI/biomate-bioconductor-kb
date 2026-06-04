# Gaps surfaced by Phase 1 async-job-queue migration smoke test (2026-06-03)

Verified on dev (52.42.49.175) at commit `7b3fe842b` + migration `0012`.

---

## Gap A — `sync_to_dev.sh` does not apply pending DB migrations

**Symptom.** Phase 1 sync went green (`Sync OK at 179d9848`). First authenticated `POST /api/jobs` returned `502 Bad Gateway` from nginx. Frontend container log showed:

```
[FATAL] Unhandled rejection: error: relation "download_jobs" does not exist
```

**Root cause.** `frontend/migrations/0012_download_jobs.sql` was created in this branch but `scripts/sync_to_dev.sh` only ships code — it never runs migrations against `biomate-dev-postgres`. The Node worker crashed on the first DB call into the missing table, taking the API down (nginx returned 502 until the container restarted).

**Workaround used.** Manual:
```bash
scp <KEY> frontend/migrations/0012_download_jobs.sql ubuntu@52.42.49.175:/tmp/
ssh ... 'docker cp /tmp/0012_download_jobs.sql biomate-dev-postgres:/tmp/ && \
         docker exec biomate-dev-postgres psql -U biomate -d biomate -f /tmp/0012_download_jobs.sql'
docker restart biomate-dev-frontend  # recover from prior FATAL
```

**Proper fix.** Add a `apply_pending_migrations()` step to `scripts/sync_to_dev.sh`:
1. After `frontend_sync.tar.gz` extraction, diff `frontend/migrations/*.sql` against an `applied_migrations` table (create it if missing).
2. For each unapplied file, `docker cp` + `psql -f`, record in `applied_migrations(filename, applied_at, sha256)`.
3. Abort sync if any migration fails — do not proceed to restart.
4. Same logic for `backend/migrations/` if/when that gets one.

**Why this matters.** Any future schema change ships dark until a human notices the 502. Detection latency is "next user-visible request" — for the jobs subsystem that meant my own smoke test, but for a less-exercised feature it could be days.

**Severity.** P1 — silent prod-outage class. Worth wiring before Phase 2 ships (Phase 2 adds `methods_report_cache` table per design §6).

---

## Gap B — Output ZIP download is broken for nextflow-native runs (pre-existing, not Phase 1)

**Symptom.** All 5 most-recent `succeeded` `execution_runs` on dev return `404 Invocation not found` from **both** endpoints:
- legacy `GET /api/invocations/:id/download-all`
- new `POST /api/jobs { kind: download_all_zip }`

Verified with `id`, `galaxy_invocation_id`, and `runId` — every form 404s.

**Root cause.** Both endpoints' resolution chain is:
```
storage.getInvocation(id) → getInvocationByGalaxyId(id) → getExecutionRun(id).galaxyInvocationId → getInvocationByGalaxyId(...)
```
This walks the Galaxy `workflow_invocations` table. Nextflow-native runs (rows in `execution_runs` with `nextflow_run_id`/`nextflow_output_dir` set and `galaxy_invocation_id` populated only as a synthetic UUID) have no matching row in `workflow_invocations`, so resolution fails at every step.

Confirmed on dev:
```
id                                   | galaxy_invocation_id                 | status     | nextflow_output_dir
713cfb18-dc39-4aec-ab5a-e3ec9d8b285c | 498f67f1-bbb7-4d30-a64f-475aabde29e3 | succeeded  | s3://biomate-nextflow-work/nextflow/outputs/unknown/d87691a4
a854243f-...                         | 05a4c9dd-...                         | succeeded  | s3://.../3a7f32bf
... (3 more, all same shape)
```

**Impact.** No user can download an outputs ZIP for any nextflow-native run today. This is the path 100% of nf-core / drug-discovery / cryo-EM runs take. Phase 1 inherits the gap from legacy — it's neither caused nor masked by the migration.

**Proper fix.** Add an `execution_runs`-aware branch to `resolveInvocation()` in `frontend/server/jobs/handlers/download-all-zip.ts` (and the legacy endpoint, until it's retired):

```ts
// 4) Nextflow-native fallback: synthesize an "invocation-like" descriptor
//    from the execution_run row and stream files directly from S3.
const executionRun = await storage.getExecutionRun(idOrRunId);
if (executionRun?.execution?.nextflowOutputDir) {
  return {
    id: executionRun.execution.id,
    workflowName: executionRun.execution.workflowName,
    _nextflowSource: { s3Uri: executionRun.execution.nextflowOutputDir },
  };
}
```

…and teach the archiver loop to handle the `_nextflowSource` shape by `aws s3 ls --recursive` + `s3.getObject().createReadStream()` per key, instead of calling `storage.getInvocationOutputs()` (which is Galaxy-only).

**Severity.** P1 user-visible — but **not new**. Pre-existed Phase 1; was hidden because no one tested the legacy endpoint end-to-end on a nextflow-native run. Surfaced today by the Phase 1 parity check.

**How to apply.** Slot this fix into Phase 1.5 (before Phase 2's methods-report caching) so the JobButton on the AfterRunReport's OutputsTab actually produces a usable download for the dominant run type.

---

## Cross-cutting hardening worth doing alongside

3. **Executor `dispatch()` should swallow async DB errors instead of crashing Node.** Today an unhandled rejection in `runJob` becomes a process FATAL (Node 20 default). Wrap the `await db.execute(...)` calls in `runJob` start/finish in try/catch that logs + marks the row failed — never let a DB error escape the executor.

4. **Add a startup-time `SELECT 1 FROM download_jobs LIMIT 0` smoke check** in `routes.ts` after `registerJobsRouter(app)`. If it fails, log a loud warning. Cheap insurance against future migration drift.

These two are 30 minutes of work; recommend bundling with Gap A's migration-runner change.
