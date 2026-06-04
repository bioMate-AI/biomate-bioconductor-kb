# HT-1 False-Failure Chain — Diagnosis + 3-Layer Fix

**Date:** 2026-06-03
**Status:** Fixed across all 3 layers; verified live on dev
**Trigger:** HT-1 browser E2E assertion "Run reached terminal state: failed" on dev EC2

## TL;DR

HT-1 was reporting `status=failed, returncode=1, duration_s=18, totalTasks=0` for runs that ACTUALLY succeeded on AWS Batch (`exit=0`, `succeededCount=1`, ~2m30s wall time, S3 outputs uploaded). Three independent bugs stacked on top of each other to produce a uniformly bogus "failed" verdict at the top of the stack.

## The full chain

1. **`scripts/sync_to_dev.sh`** sent SIGHUP to gunicorn mid-run. HUP killed the Python worker process. Its child Nextflow JVM (launched with `start_new_session=True`) survived as an orphan in a new session group, kept running on AWS Batch, and ultimately succeeded.

2. The Python `_stream_logs` worker thread lost its stdout pipe at HUP time (~18 seconds in). `process.wait()` returned with `rc=1`. The worker wrote a bogus `failed` terminal state to `timing.json` even though the actual JVM was still alive and on the way to success.

3. Node's `/api/workflows/runs/:id/status` polled Galaxy at 18s, got `failed`, and wrote `execution.status='failed'` to PostgreSQL.

4. Later (at ~2m30s), Galaxy reported `succeeded` once the real Nextflow process completed and rewrote `timing.json`. But Node's route checked `isAlreadyTerminal = ['completed', 'failed', 'cancelled'].includes(run.execution.status)` — saw `'failed'` was already terminal — and **refused to overwrite**, locking the bogus failure in PG forever.

## Three fixes

### Layer 1 — Don't HUP in the first place

`scripts/sync_to_dev.sh::restart_galaxy` now inspects whether any Nextflow JVMs are running inside the container before issuing HUP:

```bash
NF_ACTIVE=$(docker exec biomate-galaxy-dev sh -c \
  "pgrep -c -f '/usr/local/bin/nextflow' || true")
if [[ "$NF_ACTIVE" =~ ^[0-9]+$ ]] && (( NF_ACTIVE > 0 )); then
  echo "[galaxy] HUP SKIPPED — $NF_ACTIVE Nextflow JVM(s) running"
else
  kill -HUP $GPID
fi
```

Python edits get picked up at next worker rotation; in-flight work is not interrupted.

Verified live: subsequent sync printed `[galaxy] HUP SKIPPED — 1 Nextflow JVM(s) running`.

### Layer 2 — Recognize orphan-from-HUP as recoverable

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py::_looks_like_log_stream_orphan_failure`

Existing check caught `rc=-1` (SIGTERM-induced detachment) with `elapsed<30s`. HUP-induced detachment gives `rc=1` too. Extended the check to `rc in (-1, 1)`. The downstream `_revive_orphan_nextflow_run` salvage path then verifies via the workflow-trace + S3 outputs whether the run is actually alive and recovers the run record.

### Layer 3 — Allow failed→succeeded rescue at PG layer

`frontend/server/routes.ts::/api/workflows/runs/:id/status`

Added an explicit one-way rescue branch:

```js
const allowRescue =
  isAlreadyTerminal && run.execution.status === 'failed' && nfState === 'succeeded';
```

The direction is intentionally one-way: failure can be premature (HUP, gunicorn worker recycle, OOM); success cannot — never allow succeeded→failed transitions, which would let a transient Galaxy hiccup nuke a real success.

Logs the rescue with a clear warning:
```
[ExecutionRun] failed→succeeded rescue: <id> — Galaxy reports nextflow
succeeded; flipping BioMate status (was failed, likely log-stream-orphan)
```

### Layer 0 — Surface the actual error in log_tail when runs do fail

Independent of this chain, the `_read_run_nextflow_log_text` function used to return only the last 20 cleaned lines. For an early-failure those were all DEBUG startup boilerplate; operators got zero signal about the actual cause without ssh-ing in. Now the function also scans the FULL log for ERROR/WARN/FATAL/"Caused by:"/"Exception:" markers and appends the last 15 matching lines under a `--- error context ---` separator.

## Commits

| Commit | Layer | What |
|---|---|---|
| `aa088a111` | 0 | surface error-context lines in log_tail |
| `7777d346b` | 1 + 2 | extend orphan check + skip HUP if NF active |
| `bce0f29fc` | 3 | failed→succeeded rescue at PG layer |

## Verification (dev EC2)

Pre-fix state for run `c0b74808-f33f-4aa3-96e7-50a9af40e6c7` (HT-1 from 2026-06-03 21:28):

| Source | Verdict |
|---|---|
| `.nextflow.log` (ssh) | `Workflow completed > succeededCount=1; failedCount=0`, duration 2m12s |
| `timing.json` on disk | `completed_at=1780522285, status=failed, returncode=1` (timing right, status wrong from initial write) |
| `/api/workflows/runs/<id>` (Node, pre-fix) | `status=failed, returncode=1, duration_s=18` ← the bogus verdict |

After all 3 layers deploy + next status poll, the rescue branch flips PG to `succeeded`.

## Why this matters

This isn't just a test-cosmetic bug. **Real users running real workflows on dev (or prod) hit this any time the gunicorn worker is recycled or restarted while a workflow is in flight.** The workflow itself succeeds — outputs land in S3 — but the user sees "failed" in the UI and has no path to recovery. The fix recovers state on the next poll without the user needing to know what happened.

## Related context

- `frontend/server/routes.ts:8840` — "stuck-running guard" comment notes the same class of detachment: "Nextflow JVM is almost certainly dead (container restart, OOM, gunicorn worker recycle)". That guard catches the long-tail (>12h running); the new fix catches the short-tail (gunicorn HUP at 18s in).
- `docs/20260601_GALAXY_SLOWNESS_DIAGNOSTIC.md` — earlier investigation of dev-EC2 Galaxy crashes (different root cause, but adjacent: anything that bounces gunicorn during a run hits the same false-failure path).
