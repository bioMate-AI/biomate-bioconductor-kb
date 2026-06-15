# Design — Persisting `_runs[]` to Redis with a Completion Poller

**Status:** Design — implementation deferred to a focused follow-up session.
**Author:** 2026-06-15 session.
**Motivation doc:** `docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md`.

## Problem (one paragraph)

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` tracks every
in-flight Nextflow run in an in-process Python dict (`_runs[]`). Galaxy's
gunicorn is configured with `workers:1, max_requests:1000, max_requests_jitter:50`
(`/app/config/galaxy.yml`). At dev's request rate (~200 req/min from
frontend health checks, SSE pings, and auth), the single worker recycles
every ~3 minutes. When it does, every entry in `_runs[]` is lost. The
Nextflow subprocess survives (`start_new_session=True` already), but
nothing in Galaxy knows about it anymore — so the completion handler that
calls `_evaluate_qc_from_s3` (and now the SSE emitter wired in commit
`45db54b48`) never fires. Every workflow that runs longer than 3 min
silently leaks: AWS Batch finishes, S3 has results, but the user sees
"running" forever.

## Goals

1. Galaxy worker recycling MUST NOT break in-flight workflow tracking.
2. Container restart MAY surface in-flight runs after recovery (best
   effort — Batch is idempotent).
3. No new heavy infrastructure: we use the AWS Redis already running
   for billing (`biomate-billing-redis...amazonaws.com:6379`).
4. The Popen / process-handle problem is solved by polling PID, not by
   refactoring how subprocesses are launched.
5. Implementation is staged so each stage is independently mergeable.

## Non-goals

- Replacing gunicorn or moving to Celery/RQ (defer until volume warrants).
- Restarting Nextflow processes after host reboot (Batch handles its
  own restart; Galaxy just re-attaches state on recovery).
- Cross-instance run handoff (single Galaxy instance on dev; this is
  scoped to one container).

## State model

### Current (in-memory)

```python
_runs: Dict[str, Dict[str, Any]] = {}   # nextflow_executor.py:53
_runs_lock = threading.Lock()
# Entry shape: ~25 fields, all JSON-serializable EXCEPT:
#   "process": subprocess.Popen   # ← the problem child
```

### New (Redis-backed, in-memory shadow optional)

Two Redis key families:

```
nextflow:run:<run_id>          # HASH of all serializable fields
nextflow:runs:active           # SET of run_ids currently un-terminated
nextflow:run:<run_id>:pid      # STRING — the detached subprocess PID
```

TTL on `nextflow:run:<run_id>` is 7 days (matches study log retention).
The `:pid` key is removed when status reaches a terminal state.

The Popen handle is **never** stored. Instead:
- We store `pid` (string) in Redis.
- We use `psutil.pid_exists(pid)` (or `os.kill(pid, 0)`) to check liveness.
- We rely on Nextflow's own trace + log files to determine final status.

## The `RunStateStore` abstraction

New file: `backend/lib/galaxy/ai/runs/run_state_store.py`

```python
class RunStateStore(Protocol):
    def set_run(self, run_id: str, fields: dict) -> None: ...
    def update_run(self, run_id: str, **fields) -> None: ...
    def get_run(self, run_id: str) -> dict | None: ...
    def delete_run(self, run_id: str) -> None: ...
    def list_active_runs(self) -> list[str]: ...
    def set_pid(self, run_id: str, pid: int) -> None: ...
    def get_pid(self, run_id: str) -> int | None: ...

class InMemoryRunStateStore: ...    # back-compat default
class RedisRunStateStore: ...       # production
```

Selection via env var: `RUN_STATE_STORE=redis|memory` (default `memory`
locally, `redis` on dev/prod via `start_backend.sh`).

## The completion poller

New module: `backend/lib/galaxy/ai/runs/completion_poller.py`

A single background thread, started on Galaxy worker init. It:

1. Every 5s, calls `store.list_active_runs()` → list of run_ids.
2. For each, reads `pid` from store. If `psutil.pid_exists(pid)` is
   False AND the run's `status` is still non-terminal AND the log file
   has the Nextflow finish marker:
   - Lock on `nextflow:run:<run_id>:completing` (Redis SETNX, 60s TTL)
     — only ONE worker handles completion per run, even across recycles.
   - Read trace.txt to determine final status (succeeded / failed).
   - Run the existing completion path: write timing.json, list S3
     outputs, **call `_evaluate_qc_from_s3` (which emits autoloop SSE
     thanks to commit 45db54b48)**, record StudyRunLogger, record LTM,
     enqueue billing.
   - Set terminal status in store, remove from active set, delete `:pid`.
3. Idempotent: if another worker already completed the run, the SETNX
   lock fails and we skip.

This decouples completion from the worker that launched the run. After
this, gunicorn worker recycling is harmless — any worker can complete
any run.

## Migration plan (4 stages, each independently mergeable)

### Stage 1 — Abstraction + default-memory

- New file `run_state_store.py` with the Protocol and `InMemoryRunStateStore`.
- New file `runs/__init__.py`, `runs/run_state_store.py`, `runs/completion_poller.py` (poller is no-op until Stage 3).
- Add `_run_state_store_singleton()` helper in `nextflow_executor.py`.
- Replace ONE call site (`_runs[run_id] = {...}` at line 4207) with
  `store.set_run(run_id, {...})` AND keep the old `_runs[]` write for
  back-compat read paths.
- Behavior unchanged. Stage 1 is a pure refactor with a smoke-test
  branch.

### Stage 2 — Switch reads + writes

- Replace all 57 `_runs[...]` reads/writes in `nextflow_executor.py`
  with store calls.
- Remove the legacy `_runs[]` dict (and `_runs_lock`).
- Same for `cryosparc_executor.py`, `ai_assistant.py`,
  `study_run_logger.py`, `results_analyzer.py`.
- Default store is still `InMemoryRunStateStore` — Stage 2 is a
  semantics-preserving refactor. No Redis dependency yet on dev.

### Stage 3 — Redis impl + completion poller

- Implement `RedisRunStateStore` (mirrors the billing pattern at
  `realtime_cost_service.py`).
- Implement the completion poller thread (~80 lines).
- On worker init in `start_backend.sh` / gunicorn `post_fork`:
  - Instantiate the store via env var.
  - Start the poller thread.
- Set `RUN_STATE_STORE=redis` on dev via `docker exec ... env`.

### Stage 4 — Verify + clean up

- Run the recycle-survival unit test (below).
- Launch one real ADMET on dev. Verify completion + autoloop SSE end-to-end.
- Remove dead code paths from Stage 1's compat shim.
- Document the env var in `CLAUDE.md` Local Service Map.

## Recycle-survival test (the requested unit test)

New file: `backend/lib/galaxy/ai/runs/tests/test_recycle_survival.py`

Test scenario:

```python
def test_completion_survives_worker_recycle(tmp_path, redis_client):
    """Simulate the dev scenario where gunicorn SIGTERMs the worker
    holding the Popen handle, then a fresh worker picks up completion
    via Redis state."""

    store = RedisRunStateStore(redis_client)
    poller = CompletionPoller(store, interval=0.1)

    # ── Stage A: worker 1 launches a fake "nextflow" subprocess that
    # writes a sentinel to outdir, then exits ───────────────────────
    run_id = "test-recycle-001"
    outdir = tmp_path / "outdir"
    outdir.mkdir()
    proc = subprocess.Popen(
        ["python", "-c", f"import time, json; time.sleep(0.5); "
         f"open('{outdir}/.nextflow.log','w').write('finished'); "
         f"json.dump({{'status':'COMPLETED'}}, open('{outdir}/trace.txt','w'))"],
        start_new_session=True,
    )
    store.set_run(run_id, {
        "run_id": run_id, "status": "running",
        "outdir": str(outdir),
        "log_path": str(outdir / ".nextflow.log"),
        "trace_path": str(outdir / "trace.txt"),
        "workflow_domain": "ADMET",
        "qc_overrides": {},
    })
    store.set_pid(run_id, proc.pid)

    # ── Stage B: "worker 1" dies (we just drop the Popen, simulating
    # SIGTERM dropping the in-memory state) ─────────────────────────
    del proc   # NOT proc.kill — the subprocess keeps running detached

    # ── Stage C: completion poller (running in any worker) detects
    # the orphaned-but-finished process and runs completion ─────────
    poller.start()
    wait_for(lambda: store.get_run(run_id)["status"] in ("completed", "failed"),
             timeout=10)
    poller.stop()

    final = store.get_run(run_id)
    assert final["status"] == "completed"
    assert store.get_pid(run_id) is None   # cleaned up
    # If the SSE callback was wired (it is, post commit 45db54b48), the
    # completion path also fires _evaluate_qc_from_s3 → autoloop SSE.
```

The InMemory variant of the same test runs without Redis, against the
InMemoryRunStateStore, proving Stage 1+2 don't regress.

## File-by-file change list (estimate)

| File | Lines changed | Stage |
|---|---|---|
| `backend/lib/galaxy/ai/runs/__init__.py` (new) | ~5 | 1 |
| `backend/lib/galaxy/ai/runs/run_state_store.py` (new) | ~180 | 1 (Memory) + 3 (Redis) |
| `backend/lib/galaxy/ai/runs/completion_poller.py` (new) | ~120 | 3 |
| `backend/lib/galaxy/ai/runs/tests/test_recycle_survival.py` (new) | ~80 | 3 |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | ~57 sites, ~200 net lines changed | 2 |
| `backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py` | ~15 sites | 2 |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | ~3 sites | 2 |
| `backend/lib/galaxy/ai/study_run_logger.py` | ~2 sites | 2 |
| `backend/start_backend.sh` | +2 lines (env var) | 3 |
| `CLAUDE.md` (Local Service Map) | +3 lines | 4 |
| **Total** | **~600 lines** | **4 stages, 4 PRs** |

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Redis becomes a SPoF | Galaxy degrades gracefully to InMemoryRunStateStore if Redis is unreachable (back to current behavior, no regression) |
| Multiple workers race on completion | SETNX `:completing` lock with 60s TTL |
| Subprocess PID gets recycled by OS | Combine `pid_exists` check with a "started_at" timestamp recorded both in Redis and in the subprocess command (e.g., via env var). If `/proc/<pid>/stat` shows a start_time newer than ours, treat as gone |
| Poller falsely concludes "completed" when subprocess just hasn't started yet | Require `psutil.pid_exists(pid) == False` AND log file has Nextflow finish marker AND a min-age (5s after `started_at`) — three signals, not just one |
| Existing in-flight runs at deploy time are orphaned | Stage 3 deploy includes a one-shot script that scans S3 outdirs for unfinished runs and seeds them into Redis with status=running and a "force_complete_after" timestamp |

## Open questions

1. **Should the poller live in every worker or just one?** Easier: every
   worker runs it, idempotency comes from the SETNX lock. The redundancy
   cost (multiple workers doing the same check every 5s) is negligible
   given workers:1 anyway.
2. **Should `_runs[]`'s `process` field be removed entirely, or kept as
   an optional cache for the launching worker?** Recommend: keep as
   optional, since the launching worker can short-circuit polling with
   `process.poll()` for sub-second completion detection (e.g., when a
   workflow fails immediately). The poller is the fallback, not the
   primary.
3. **What about CryoSPARC?** Same architecture applies. Stage 2's scope
   includes `cryosparc_executor.py`. The CryoSPARC subprocess monitoring
   logic is independent of Nextflow's and uses the same `_runs[]`-ish
   pattern, so the store abstraction extends cleanly.

## Done criteria (Stage 4)

- [ ] Recycle-survival unit test passes locally + in CI.
- [ ] One real ADMET run on dev completes end-to-end with `qc_gates`
      populated AND autoloop SSE events visible in Network panel.
- [ ] Dev `/api/workflows/runs/<id>` shows `execution.status="completed"`
      within 30 min of launch (not "running" forever).
- [ ] No regression in chat-only or short workflow flows (existing e2e
      green).
- [ ] `CLAUDE.md` documents the `RUN_STATE_STORE` env var.
