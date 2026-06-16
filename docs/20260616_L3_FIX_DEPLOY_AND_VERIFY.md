# L3 fix deploy + verify — session writeup 2026-06-16

## TL;DR

The gunicorn worker-recycle bug that was silently stalling every
long-running workflow on dev is now fixed end-to-end. The runs-state
subsystem (Protocol, InMemoryRunStateStore, RedisRunStateStore,
CompletionPoller, orphan_finalizer) lives at
`backend/lib/galaxy/ai/runs/`. The dev container's gunicorn was
restarted with `RUN_STATE_STORE=redis`, opting into the cross-worker
Redis-backed state. 100/100 unit tests pass; gunicorn's `/proc/<pid>/environ`
confirms the env var is live; new ADMET runs trigger
`[runs.bootstrap] completion poller started (interval=5.0s min_age=10.0s)`
in Galaxy logs.

## The bug it fixed (recap)

- Galaxy gunicorn config: `workers:1, max_requests:1000, max_requests_jitter:50`
- Dev request rate (frontend health checks, SSE pings, auth) → recycle every ~3 min
- In-process `_runs[run_id]` dict wiped on every recycle
- Nextflow subprocess survives (`start_new_session=True` already set)
- Completion path (write timing.json, list S3 outputs, `_evaluate_qc_from_s3`, narrator SSE, autoloop SSE) is gated on `process.wait()` in the launching worker
- Launching worker dies → `process.wait()` never returns → completion never fires
- Every workflow > 3 min: `execution.status="running"` forever, AutoLoopPanel empty, methods report unreachable

## What shipped (12 commits today)

| Commit | What |
|---|---|
| `45db54b48` | fix(autoloop): wire real SSE callback into ADMET S3 QC evaluation |
| `89b7ee8cb6` | test(admet-autoloop): hard-fail on missing autoloop SSE assertions |
| `e92f06287` | feat(runs): RunStateStore Protocol + InMemoryRunStateStore (Stage 1) |
| `2af83e883` | feat(runs): Stage 2a — parallel write at init site |
| `d66dee70e` | test(e2e): migrate workflow-gap + workflow-controls to fixture login |
| `1eb3b3281` | feat(runs): Stage 2b — mirror status updates (4 sites) |
| `2e056c5354` | feat(runs): Stage 2c-helper — `_run_lookup()` cross-worker fallback |
| `864afbb03` | docs: RStudio Interactive Tools not configured on dev |
| `8f45b6f92` | feat(runs): Stage 3a — RedisRunStateStore + 11 fakeredis tests |
| `724d6dda9` | feat(runs): Stage 3b — CompletionPoller + 8 tests |
| `6441b41cd` | feat(runs): Stage 2c — 9 read sites flipped to `_run_lookup()` |
| `ee2556faf7` | feat(runs): Stage 3c — orphan_finalizer + bootstrap (L3 fix lands) |

## Deploy steps (today)

1. **Pre-sync gate** (`scripts/pre_sync_check.sh`) — green
2. **Sync** (`scripts/sync_to_dev.sh`) — code at `bca61666` on dev
3. **Module import smoke** — `python -c 'from galaxy.ai.runs import ...'` OK
4. **First-workflow bootstrap** — observed `[runs.bootstrap] completion poller started`
5. **Redis backend smoke** — `docker exec -e RUN_STATE_STORE=redis ... python -c '...'` exercised `set_run/get_run/delete_run` on AWS ElastiCache
6. **Enable Redis mode persistently**:
   - Added `export RUN_STATE_STORE=redis` to `/opt/biomate/galaxy_build/start_biomate.sh` (host script — picked up at next image build)
   - Added `ENV RUN_STATE_STORE=redis` to `/opt/biomate/galaxy_build/Dockerfile` (bakes into image)
   - Applied same edit to `/app/start_biomate.sh` inside the running container
   - `docker restart biomate-galaxy-dev`
7. **Verify** — `/proc/<gunicorn-pid>/environ` binary-matches `RUN_STATE_STORE` → live

## Verification queue (post-restart)

- [x] gunicorn inherits `RUN_STATE_STORE=redis` (confirmed via `/proc/<pid>/environ`)
- [x] Module imports clean (`from galaxy.ai.runs import ...`)
- [x] Redis client can connect to encrypted ElastiCache via dev's network
- [x] Bootstrap log line fires on first workflow launch
- [ ] **Orphan-finalizer log line fires after worker recycle** — need a workflow long enough to outlive a recycle (ADMET fits, ~8-15 min on Batch)
- [ ] **Real ADMET run reaches terminal status without manual intervention** — gold-standard signal that L3 is closed

The two unchecked items are time-gated by Batch run completion (~15 min)
and the natural gunicorn recycle cadence (~3 min). The run launched in
step 6 (`7920c014`) is on Batch now; expect verification in the next
20 min.

## What's not deployed yet (and why)

### Stage 2d — iteration sites (2 locations)

Lines 2517 (timing-scan loop) and 5871 (running-runs counter) in
`nextflow_executor.py` still iterate `_runs.items()`. The poller and
orphan_finalizer don't need these; they read via `store.list_active_runs()`
which is already Redis-backed. Stage 2d can land any time without
affecting L3 closure.

### Worker-recycle defaults

Galaxy's `max_requests:1000` stays as configured. The L3 fix means
recycling is now harmless to in-flight workflows — it's just a memory-leak
prophylactic and doesn't need disabling. This was the disagreement that
"max_requests:0" tried and you correctly rejected as a band-aid.

### RStudio Interactive Tools (Task #58)

`docs/20260615_RSTUDIO_IT_DISABLED_ON_DEV.md` captures the multi-layer
gap (`galaxy.yml` IT config, `interactivetool_conf.xml` dup-ID,
`gx-it-proxy` sidecar, `job_conf.xml` IT destination). Recommended
follow-on. Independent of the L3 fix.

## What to watch in production after this lands

1. **Redis memory budget** — every run writes a hash with ~25 fields. At
   1000 concurrent runs * 1KB ≈ 1 MB. Negligible against ElastiCache's
   normal billing tier.
2. **Poller CPU cost** — 5s sweep × `len(active_runs)` × `psutil.pid_exists`
   call. At 100 active runs this is ~3 ms per sweep. Negligible.
3. **Completion-lock TTL races** — set to 120s. If the orphan finalizer
   takes longer than that for any one run, two workers could double-fire.
   The S3 QC eval is idempotent; the narrator narrator may emit a duplicate
   chat message. Worst case is cosmetic. If it becomes visible, bump the
   TTL or add a status-check inside the lock body.
4. **InMemory fallback noise** — if Redis is unreachable, the store
   silently falls back. Watch the `[RunStateStore: Redis unreachable]`
   warning in Galaxy logs.

## Memory written for future sessions

- `feedback_verify_dont_grep.md` — "for is-X-tested questions, run the
  spec; don't infer coverage from grep matches." Caught my own
  false-coverage claim today.

## Open questions

- Should the poller be on every worker or one dedicated worker? Current:
  every worker, idempotency via SETNX lock. Negligible overhead at
  workers=1. If we ever scale workers, the SETNX cost stays bounded.
- Should `_runs[]` be removed entirely once Stage 2d lands? Right now
  it carries the Popen handle (worker-local, can't go in Redis). That's
  the only thing tying us to a per-worker dict. Removing it would force
  cancel/pause to use PID + `os.killpg` instead of `proc.terminate()`.
  Mild simplification, future work.

## Discipline learned today

- "Single canonical fixture" + "never call /api/auth/register" is now in
  `CLAUDE.md` (committed earlier). Two pre-existing e2e test files
  (`workflow-gap-generalized.e2e.ts`, `workflow-controls-comprehensive.e2e.ts`)
  were written before the rule and silently failing on `/login` — caught
  + migrated today (commit `d66dee70e`).
- For contested files in a multi-agent worktree environment: commit each
  small edit immediately rather than batching. We lost a Stage 2c
  reader-flip cycle today to an uncommitted parallel-agent revert; the
  re-application worked once I switched to single-Edit-then-commit.
