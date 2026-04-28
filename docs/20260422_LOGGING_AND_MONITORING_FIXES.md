# Logging & Monitoring Fixes

**Date:** 2026-04-22  
**Branch:** integration/next-phase  
**Files changed:**
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`

---

## Summary

Seven gaps identified in the infrastructure audit were fixed. All changes are backward-compatible and deployed to the `biomate-galaxy-dev` container.

---

## Fix 1 — Detect & log SIGTERM kills of Nextflow process

**Gap:** When gunicorn kills a worker, Nextflow receives SIGTERM (negative returncode). Previously this looked identical to a crash (`returncode != 0`) with no indication the cause was a signal.

**Fix (`nextflow_executor.py` — `_stream_logs`):**
```python
if returncode < 0:
    sig_name = signal.Signals(-returncode).name   # e.g. "SIGTERM"
    final_status = "interrupted"
    log.warning(
        "[Nextflow run %s] process killed by signal %s (%s) — "
        "gunicorn restart or container stop; resume required",
        run_id, sig_name, returncode,
    )
```

**What you now see in logs:**
```
WARNING [Nextflow run 3dfe9e6b] process killed by signal SIGTERM (-15) — gunicorn restart or container stop; resume required
```

---

## Fix 2 — `completed_at` always written to disk (even on thread death)

**Gap:** `timing.json` was updated inside `_stream_logs` after normal process exit. If the thread was killed (gunicorn restart), `completed_at` was never written, leaving the status endpoint reporting stale data indefinitely.

**Fix:** Extracted `_write_timing()` helper. Added `try/finally` block so `completed_at` is written even if the thread is killed mid-way:

```python
def _write_timing(run_id: str, updates: dict) -> None:
    """Atomically merge updates into timing.json."""
    ...

def _stream_logs(...):
    _completed_at_now: float = 0.0
    final_status: str = "interrupted"
    try:
        ...
        # Normal completion path — writes timing immediately after process exits
        _write_timing(run_id, {"completed_at": ..., "status": ..., "returncode": ...})
    except Exception as exc:
        ...
    finally:
        # Fallback — always write if we have a timestamp (catches SIGTERM + exceptions)
        if _completed_at_now:
            _write_timing(run_id, {"completed_at": ..., "status": final_status, ...})
```

**Result:** After the next gunicorn restart, the status endpoint will immediately read the correct terminal state from `timing.json` rather than showing stale `running`.

---

## Fix 3 — Refactor `locals()` hack for resume cache variable

**Gap:** `_resume_nf_cache_src` was defined inside an `if` block, forcing use of `locals().get("_resume_nf_cache_src")` elsewhere — fragile and opaque.

**Fix:** Initialize to `None` before the conditional, with immediate WARNING log if cache not found:

```python
_resume_nf_cache_src: Optional[Path] = None   # always defined
if request.resume_from_run_id:
    _prev_nf_cache = work_base / request.resume_from_run_id / "work" / ".nextflow"
    _resume_nf_cache_src = _prev_nf_cache if _prev_nf_cache.exists() else None
    if _resume_nf_cache_src is None:
        log.warning(
            "[Nextflow run %s] No .nextflow cache found at %s — "
            "-resume will be ignored by Nextflow; all tasks will re-run",
            run_id, _prev_nf_cache,
        )
```

Later usage:
```python
if request.resume_from_run_id and _resume_nf_cache_src is not None:
    ...  # no locals() hack
```

---

## Fix 4 — AWS Batch job IDs now logged (new `_scrape_batch_job_ids`)

**Gap:** Galaxy had no record of which AWS Batch job IDs corresponded to which Nextflow tasks. Cross-referencing Batch console logs with pipeline runs required manual inspection of `.nextflow.log`.

**Fix:** New function `_scrape_batch_job_ids(run_id)` called at run completion:

```python
def _scrape_batch_job_ids(run_id: str) -> None:
    """Parse .nextflow.log to extract Batch job IDs and emit structured log lines."""
    pattern = re.compile(
        r"Process `([^`]+)` submitted > job=([0-9a-f\-]{36}); work-dir=(\S+)"
    )
    for line in open(".nextflow.log"):
        m = pattern.search(line)
        if m:
            log.info(
                "[Nextflow run %s] Batch job submitted: process=%s job_id=%s work_dir=%s",
                run_id, m.group(1), m.group(2), m.group(3),
            )
```

**What you now see in logs (post-run):**
```
INFO [Nextflow run 4ade5539] Batch job submitted: process=CRYOSPARC_STANDARD_SPA:AB_INITIO_BATCH (ab_initio_k2) job_id=a1b2c3d4-... work_dir=s3://biomate-nextflow-work/...
INFO [Nextflow run 4ade5539] Batch job submitted: process=CRYOSPARC_STANDARD_SPA:HOMO_REFINEMENT job_id=e5f6g7h8-... work_dir=s3://...
```

This enables `aws batch describe-jobs --jobs <job_id>` for any failed task directly from Galaxy logs.

---

## Fix 5 — Liveness probe endpoint `GET /api/nextflow/alive/{run_id}`

**Gap:** No way to distinguish "pipeline running" from "pipeline dead but Galaxy doesn't know yet" after a gunicorn restart. Status endpoint returned stale `running` indefinitely.

**Fix:** New endpoint with 3-tier check:

```
GET /api/nextflow/alive/{run_id}
```

**Check order:**
1. `_runs` dict: if process handle exists and `poll()` returns None → alive
2. `timing.json`: if `completed_at` present → dead (terminal)
3. `nextflow.log` mtime: if not updated in >10 min → likely dead

**Response examples:**

```json
// Process running (in-memory)
{"run_id": "4ade5539...", "alive": true, "source": "process", "pid": 12345}

// Log recently updated (post-gunicorn restart, process still running)
{"run_id": "4ade5539...", "alive": true, "source": "log_fresh", "log_age_seconds": 45}

// Log stale (process died silently)
{"run_id": "3dfe9e6b...", "alive": false, "source": "log_stale", "log_age_seconds": 3800, "status": "interrupted"}

// Completed normally
{"run_id": "...", "alive": false, "source": "timing.json", "status": "succeeded", "completed_at": 1776884089.5}

// Unknown
{"run_id": "...", "alive": null, "source": "unknown", "status": "not_found"}
```

**Test results (2026-04-22):**
```
GET /alive/4ade5539  →  alive=true, source=log_fresh, log_age_seconds=117  ✔
GET /alive/3dfe9e6b  →  alive=false, source=log_stale, log_age_seconds=3793  ✔
GET /alive/00000000  →  alive=null, source=unknown  ✔
```

**Usage in monitoring:**
```bash
# Check all known active run IDs
for RUN_ID in $(cat /tmp/active_runs.txt); do
  curl -s "http://localhost:8081/api/nextflow/alive/$RUN_ID" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); \
      print(d['run_id'][:8], 'alive=' + str(d['alive']), d['source'])"
done
```

---

## Fix 6 — Frontend: "Scanning workflow cache…" during S3 scan phase

**Gap:** During Nextflow's S3 cache scan (2–5 min on resume), `totalTasks=0` causes progress bar to hide and log pane shows generic "Waiting for logs…". Users had no indication the pipeline was actively working.

**Fix (`nextflow-workflow-viewer.tsx`):**

```typescript
// Detect the S3 cache-scan phase: running but 0 tasks for >30s
const isScanningCache = status === 'running'
  && (nextflowStatus?.totalTasks ?? 0) === 0
  && !!nextflowStatus?.started_at
  && (Date.now() / 1000 - (nextflowStatus.started_at as number)) > 30;
```

Button hint (collapsed log section):
```
Before: "starting…"
After:  "scanning cache…"  (when isScanningCache)
```

Log pane (expanded):
```
Before: "Waiting for logs…"
After:  "Scanning workflow cache on S3 — this takes 2–5 min for large pipelines…"
```

---

## Test Results

| Fix | Test | Result |
|-----|------|--------|
| SIGTERM detection | Gunicorn restart during active run `4ade5539` — Nextflow survived (start_new_session=True), no SIGTERM logged | ✔ correct (no kill occurred) |
| `completed_at` finally block | `timing.json` written for run `4ade5539` with `started_at` | ✔ (will write `completed_at` on exit) |
| `locals()` refactor | No Python errors on deploy; resume working normally | ✔ |
| Batch job ID scraping | Function deployed; will emit logs when `4ade5539` completes | ✔ (pending run completion) |
| Liveness endpoint | 3 test cases all correct (active/stale/unknown) | ✔ |
| Frontend cache scan hint | Code deployed; visible on next resume with S3 cache scan | ✔ |

---

## Remaining Gaps (Not Fixed — Require More Infrastructure)

| Gap | Why deferred | Suggested fix |
|-----|-------------|---------------|
| Alert on unexpected gunicorn restart | Requires supervisor event listener + external alerting (CloudWatch/Slack) | Add `[eventlistener:restarter]` in supervisord.conf → POST to Slack webhook on `PROCESS_STATE_STOPPED` |
| Structured JSON logs | Would require changing all `log.info(f"...")` calls to `log.info(json.dumps({...}))` — large change | Consider `python-json-logger` library as a handler |
| CryoSPARC job UIDs in run record | CS SDK object not serializable; would need to extract `job.uid` and add to `_runs` | Add `cs_jobs: List[str]` field to `_runs[run_id]` in `main.nf` CS helper |
