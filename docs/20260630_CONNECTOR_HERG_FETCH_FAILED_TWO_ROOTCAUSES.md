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

## Status
- #1: fixed, merged (PR #68), deployed (`sha-273918d32a25`), verified.
- #2: fixed on test (.env), deployed, verified. Repo-level durability flagged.
- The connector hERG path now runs Batch → completes → returns real data.
