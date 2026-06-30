# Connector hERG "fetch failed" — two independent root causes (2026-06-30)

**Env:** `https://test.stage-public.biomate.ai` (instance `i-0482a6fa98c6f301a`)
**Reported:** connector `herg_cardiac_safety_qsar` run failed 3×, all `fetch failed`
at the execute-dispatch stage (run `a4e0ef18`, created 06:25:19 → failed 06:30:20).

The async-execute change (PR #67) did **not** fix it because the real cause was
upstream of the launch path. Two distinct bugs were found and fixed.

---

## Root cause #1 — `_runs_lock` starvation (the actual "fetch failed")

`nextflow_executor.py` run-completion path held the global `_runs_lock`
**across two blocking S3 network calls** — `_list_s3_output_files()` and
`_evaluate_qc_from_s3()` (the latter downloads + parses output objects). When S3
stalls (throttling / large file / boto retries), the completion thread holds the
lock indefinitely. Every other run-registry consumer — `/api/nextflow/execute`
**and** `/api/nextflow/status` both do `with _runs_lock` — then blocks forever
until the gunicorn worker recycles.

The Node→Galaxy execute `fetch()` hung the full **300s undici headers timeout** →
`TypeError: fetch failed (UND_ERR_HEADERS_TIMEOUT)` → the run was marked failed
though nothing was wrong with the workflow.

### Why my direct test passed but the connector didn't
The 0.1s "async works" verification (c018ab82) called the backend at a moment
when no completion thread held the lock. By 06:25 a completion thread was wedged
in S3 QC eval under the lock → poisoned.

### Reproduced on test (before fix)
With the lock held, a bare `POST /api/nextflow/execute` **and**
`GET /api/nextflow/status/<id>` both hung 30s+/300s while `/api/version` stayed
instant — textbook single-lock starvation, not launch slowness. `py-spy`
unavailable (no ptrace); proven instead by the status-endpoint hang + code read.

### Fix — PR #68 (merged to integration/next-phase)
Read the needed fields under a brief lock, run the S3 LIST + QC evaluation
**lock-free**, write results back under a second brief lock. `_runs_lock` now
only ever guards in-memory dict access, never network I/O.

**Verified (test `sha-273918d32a25`):** execute **0.012s** + run_id (was 300s),
status **0.009s** (was 30s+).

---

## Root cause #2 — `NEXTFLOW_USE_AWS` unset on test → local exec → rdkit 503

Once #1 was fixed, the run launched fast and then **failed in the background with
a clear reason**: `launch failed (503): Missing required runtime modules and
auto-install failed: rdkit`.

`NEXTFLOW_USE_AWS` was **absent** on both test containers (and host
`/opt/biomate/.env`). The backend (`nextflow_executor.py`):
- routes to AWS Batch only when `NEXTFLOW_USE_AWS=true` or `executor=awsbatch`
  (line ~4288–4294);
- for awsbatch it **skips** the runtime-module check (the ECR `biomni-tools:x86`
  container has rdkit); for local runs it **raises 503** on missing modules
  (line ~4456–4467).

So without the flag, every connector workflow ran **locally** and any that needs
a non-baked Python module (hERG → rdkit) 503'd. My earlier working hERG
(c018ab82) reached Batch + the x86 container, which is why it succeeded. The
design intends "all production workflows use AWS Batch" (line ~947).

### Fix — test `/opt/biomate/.env`
Appended `NEXTFLOW_USE_AWS=true` (both containers read this env_file) and
recreated via `deploy.sh test sha-273918d32a25` (healthcheck + auto-rollback).
The galaxy backend now overrides incoming `profile:'standard'` → awsbatch.

**Verified end-to-end:** connector-style hERG (`profile:'standard'`) →
`-w s3://…` + `--outdir s3://…` (Batch) → `status=succeeded returncode=0` → 11
S3 output files incl. `herg_cardiac_results.json` (hERG IC50 0.248 µM, QTc HIGH,
ICH E14 CLINICAL_CONCERN).

### Durability / follow-up
`NEXTFLOW_USE_AWS=true` now lives in the test host `.env` (survives `deploy.sh`,
which preserves existing `.env`). It is **not** in the repo. To prevent this gap
recurring (and to guarantee dev/test/prod parity), consider baking
`NEXTFLOW_USE_AWS=true` into the `environment:` block of both services in
`deploy/docker-compose.deploy.yml`. NOT done here because that compose is shared
with prod — flagged for an explicit decision.

---

## Root cause #1b — the ACTUAL lock holder: self-deadlock on a non-reentrant lock

PR #68 (move S3 out of `_runs_lock`) was correct hygiene but **did not fix the
hang** — run `8088d4ff` failed identically right after a "successful" run
(`57895ed6`) completed. A `py-spy` dump of the wedged worker (taken from the
**host** — the container's seccomp blocks ptrace) caught the real holder:

```
Thread nf-log-57895ed6 (completion):
    _run_lookup   nextflow_executor.py:95     <- acquires _runs_lock
    _stream_logs  nextflow_executor.py:3469   <- ALREADY holds _runs_lock
```

`_stream_logs` (and 3 other locked sections) call `_run_lookup()` /
`_find_run_by_invocation_id()` **while already holding `_runs_lock`**; those
helpers take the same lock. With a non-reentrant `threading.Lock()` the
completion thread blocks forever re-acquiring its own lock and keeps holding it
→ every consumer (`execute`, `status`) hangs 300s → "fetch failed". The run
still shows **succeeded** because `orphan_finalizer` finalizes it on a separate
thread — which is why each run's completion poisons the **next** run's execute
(5 consecutive hERG fails). Self-deadlock call sites: 3468→3469, 3533→3538,
4520→4521, 5127→5128. Introduced by the Stage 2c/2d persistence refactor.

**Fix — PR #70 (merged):** `_runs_lock = threading.RLock()` (reentrant). Every
critical section only guards the in-memory dict, so reentrancy is safe.

**Verified (test `sha-a6b904934755`) — two sequential runs with a completion
between:** run1 → Batch → succeeded (status 0.02–0.7s throughout); post-
completion (the poison point) status probe 0.006s + run2 execute 0.009s → **PASS,
the lock survives a completion** (previously run2 hung 300s).

> Lesson: the symptom (execute/status hang 300s, `/api/version` fine) pointed at
> lock starvation, and the S3-under-lock block was a plausible-but-wrong holder.
> The host `py-spy` dump was decisive — it named the deadlocked thread + line.
> Always get the live stack before concluding which critical section is stuck.

## Root cause #3 — read side: preview/analyze couldn't pull the (correct) S3 outputs

After execution worked end-to-end (run succeeded, 6 files in S3), the three
connector READ tools failed:

**#3a `preview_file` → HTTP 500 "must be addressed using the specified
endpoint".** `/api/files/preview` built `new S3Client({ region: AWS_REGION })`;
deploy host `AWS_REGION=us-west-2` but `biomate-nextflow-work` is **us-east-1** →
PermanentRedirect on GetObject + presigned URL. The write path is fine because it
uses `_s3ClientForBucket()` (resolves region via GetBucketLocation). **Fix — PR
#72 (merged):** use `_s3ClientForBucket(bucket)` in the preview route. Verified
(`sha-292c13e81806`): JSON → 200 text, CSV → 200 table, both with real data.

**#3b `analyze_results` → empty `output_files_sampled`.** Its own S3 read has
`followRegionRedirects`, so NOT the region bug. Root cause: the run record had
**vanished** — `RUN_STATE_STORE` was unset on test, so records were InMemory and
died on gunicorn worker recycle → `/api/invocations/:id/outputs` (resolves the
run via frontend storage → backend `s3_output_files`) returned empty → analyze
degraded to a generic template. **Fix:** set `RUN_STATE_STORE=redis` on test
`.env` (the documented L3 fix; `biomate-redis` was already up + reachable, galaxy
has the redis module). Verified: post-fix a completed run's record persists with
`s3_output_files`=6. (Full connector analyze path resolves via the frontend
execution record, which only the connector/UI flow creates — re-confirm via the
connector.)

**#3c `browse_data` → "Unknown tool".** MCP tool-registry on the **connector**
side, not the biomate backend (the `/api/...` browse route exists). Out of scope
for the backend; flag to the connector repo.

## Status
- #1 (S3 out of lock): merged PR #68 — correct hygiene, reduced hold time.
- #1b (RLock self-deadlock): merged PR #70 — **the actual fix**, deployed
  (`sha-a6b904934755`), verified across a completion boundary.
- #2 (NEXTFLOW_USE_AWS): fixed on test (.env), deployed, verified. Repo-level
  durability flagged (bake into compose, prod-shared — needs sign-off).
- The connector hERG path now runs Batch → completes → returns real data, and
  back-to-back runs no longer poison each other.
