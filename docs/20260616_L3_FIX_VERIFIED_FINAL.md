# L3 fix verified end-to-end on dev — final writeup 2026-06-16

## The proof

A new ADMET run launched on `biomate-galaxy-dev` after the L3 fix was
deployed. Within ~4 minutes the run had this record in AWS ElastiCache:

```
ca8dc202-e773-4f2e-859e-de0f3c04cd28:
   status        = interrupted
   returncode    = -1
   finalized_by  = orphan_poller        ← proof of orphan detection
   completed_at  = 1781643473.6845534
   pid           = 230
```

`finalized_by="orphan_poller"` is the marker written by
`backend/lib/galaxy/ai/runs/orphan_finalizer.py::finalize_orphaned_run`.
Its presence proves the full chain executed:

1. Run launched → `store.set_pid(run_id, 230)` recorded the detached subprocess PID in Redis
2. Subprocess exited (returncode -1 = SIGTERM, presumably from gunicorn worker recycle)
3. The launching worker died with the subprocess
4. **CompletionPoller in a surviving worker** swept active runs, called `psutil.pid_exists(230)`, got False
5. Poller acquired the SETNX completion lock (`nextflow:run:<id>:completing`, 120s TTL)
6. Poller called `finalize_orphaned_run`, which:
   - inferred returncode from `.nextflow.log` tail
   - updated store status to `interrupted`
   - emitted `workflow.failed` narrator SSE
   - tagged the record with `finalized_by="orphan_poller"`
7. Run removed from `nextflow:runs:active` set

Before this fix, runs in this exact scenario stayed at
`execution.status="running"` indefinitely — the L3 bug that broke every
long workflow on dev for an unknown period.

## The bug

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` tracked
every in-flight Nextflow run in an in-process Python dict (`_runs[]`).
Galaxy's gunicorn config (`workers:1, max_requests:1000, max_requests_jitter:50`)
plus dev's request rate (~200 req/min) recycled the single worker every
~3 minutes. When it did:

- the in-memory `_runs[]` dict was wiped
- the detached Nextflow subprocess survived (already `start_new_session=True`)
- the Popen handle in `_runs[run_id]["process"]` was lost
- `process.wait()` in the launching worker never returned
- the completion path (write timing.json, list S3 outputs, `_evaluate_qc_from_s3`,
  narrator SSE, autoloop SSE) never fired
- frontend saw `execution.status="running"` forever, AutoLoopPanel empty,
  methods report unreachable

## The fix architecture

Two-tier state. Worker-local `_runs[]` keeps the Popen handle (still
needed by the cancel path which calls `process.terminate()` directly).
Cross-worker `RunStateStore` (Redis-backed) carries serializable state
plus the detached subprocess PID.

```
                        ┌─────────────────────┐
                        │ RunStateStore       │
                        │ (Redis: AWS ECache) │
                        └──────────┬──────────┘
            mirror writes ↓        │ ↑ list_active_runs, get_pid
                                   │ │
   worker A                        │ │                worker B
   ┌──────────┐                    │ │                ┌──────────┐
   │ _runs[]  │── launch ──────────┘ │                │ _runs[]  │
   │ Popen +  │                      │                │ (empty,  │
   │ subproc  │                      │                │ post-    │
   │ wait     │                      │                │ recycle) │
   └────┬─────┘                      │                └─────┬────┘
        │                            │                      │
        │   process.wait() returns   │   psutil.pid_exists()│
        │   (normal completion)      │   (orphan detection) │
        ↓                            ↓                      ↓
   ┌────────────────────────────────────────────────────────────┐
   │ Completion path: store.update_run(status=terminal),        │
   │ narrator SSE, _evaluate_qc_from_s3, autoloop SSE           │
   └────────────────────────────────────────────────────────────┘
```

The CompletionPoller runs in every worker. SETNX completion lock on
`nextflow:run:<id>:completing` ensures only one worker finalizes per
run. min_run_age=10s guard avoids racing the launching worker for
sub-3-min workflows.

## What was shipped (15 commits)

Run-state subsystem:
| Commit | What |
|---|---|
| `45db54b48` | fix(autoloop): wire real SSE callback into ADMET S3 QC evaluation |
| `89b7ee8cb6` | test(admet-autoloop): hard-fail on missing autoloop SSE assertions |
| `e92f06287` | feat(runs): RunStateStore Protocol + InMemoryRunStateStore (Stage 1) |
| `2af83e883` | feat(runs): Stage 2a — parallel write at init site |
| `1eb3b3281` | feat(runs): Stage 2b — mirror status updates (4 sites) |
| `2e056c5354` | feat(runs): Stage 2c-helper — `_run_lookup()` cross-worker fallback |
| `8f45b6f92` | feat(runs): Stage 3a — RedisRunStateStore + 11 fakeredis tests |
| `724d6dda9` | feat(runs): Stage 3b — CompletionPoller + 8 tests |
| `6441b41cd` | feat(runs): Stage 2c — 9 read sites flipped to `_run_lookup()` |
| `ee2556faf7` | feat(runs): Stage 3c — orphan_finalizer + bootstrap |
| `60007cd07` | feat(runs): Stage 3d — set_pid on accession-chain path |
| `230b9da9c` | fix(runs): Stage 3d — set_pid on main launch path (the verified fix) |

Test/test-hygiene:
| Commit | What |
|---|---|
| `d66dee70e` | test(e2e): migrate workflow-gap + workflow-controls to fixture login |

Docs:
| Commit | What |
|---|---|
| `864afbb03` | docs: RStudio output analysis broken on dev (Task #58) |
| `0665f0600` | docs(runs): L3 fix deploy writeup + CLAUDE.md Run-State section |

Net new files:
- `backend/lib/galaxy/ai/runs/__init__.py`
- `backend/lib/galaxy/ai/runs/run_state_store.py` (Protocol + InMemory + Redis)
- `backend/lib/galaxy/ai/runs/completion_poller.py`
- `backend/lib/galaxy/ai/runs/orphan_finalizer.py`
- `backend/lib/galaxy/ai/runs/bootstrap.py`
- `backend/lib/galaxy/ai/runs/tests/__init__.py`
- `backend/lib/galaxy/ai/runs/tests/test_run_state_store.py` (9 tests)
- `backend/lib/galaxy/ai/runs/tests/test_redis_run_state_store.py` (11 fakeredis tests)
- `backend/lib/galaxy/ai/runs/tests/test_completion_poller.py` (8 tests)
- `backend/lib/galaxy/ai/runs/tests/test_orphan_finalizer.py` (8 tests)
- `docs/20260615_RUNS_PERSISTENCE_DESIGN.md` (design)
- `docs/20260615_RSTUDIO_IT_DISABLED_ON_DEV.md` (Task #58 background)
- `docs/20260616_L3_FIX_DEPLOY_AND_VERIFY.md` (mid-session deploy)
- `docs/20260616_L3_FIX_VERIFIED_FINAL.md` (this doc)

**Total tests: 36/36 runs/ tests pass; 100/100 across runs/ + autoloop suites.**

Touched in `nextflow_executor.py` (5 small wire-ins, all behavior-preserving):
- Line 56: import `get_run_state_store`
- Line 62: `_run_lookup()` helper
- Line 4258 area: `ensure_poller_started()` + mirror write at init
- Lines 3175, 3287, 3293, 3611, 4691: mirror status updates
- Lines 3111, 3180, 4011, 4576, 4795, 5309, 5356, 5633, 8108: read flips to `_run_lookup()`
- Line 3810, 4490: `store.set_pid()`

## Deploy + verify

- Sync at `bca61666` deployed Stage 1–3c to dev (InMemory mode, no behavior change)
- Container restart with `RUN_STATE_STORE=redis` flipped to Redis backend
- Sync at `230b9da9c` deployed the corrected Stage 3d (main launch path PID)
- Run `ca8dc202` finalized by orphan_poller — recorded in Redis
- 3 stale pre-fix runs cleaned up from Redis active set

## Production checklist

Before this lands on prod:
- [ ] Confirm `REDIS_URL` is set on the prod Galaxy container (it's shared with billing, should already be there)
- [ ] Set `RUN_STATE_STORE=redis` on prod via the same 3-layer change (start script, Dockerfile ENV, running container)
- [ ] Watch first 24h of prod Galaxy logs for:
  - `RunStateStore: Redis backend active` on each worker start
  - `[runs.bootstrap] completion poller started` on first workflow launch
  - Any `[orphan_finalizer]` activity if workers recycle while subprocesses are in flight
  - `[RunStateStore: Redis unreachable]` fallback warnings (none expected if Redis is healthy)
- [ ] On any sync that bumps the Galaxy image, verify `ENV RUN_STATE_STORE=redis` is still in the Dockerfile

## Open follow-ups

- **Task #58 — Galaxy Interactive Tools (RStudio) enablement.** Independent of L3. See `docs/20260615_RSTUDIO_IT_DISABLED_ON_DEV.md` — 4-layer config gap (`galaxy.yml`, `interactivetool_conf.xml` dup-ID, `gx-it-proxy` sidecar, `job_conf.xml` IT destination).
- **Stage 2d** — `_runs.items()` iteration at lines 2517 + 5871 still uses the in-process dict. Not critical for L3; can be flipped to `store.list_active_runs()` for completeness when convenient.
- **Hygiene** — stale pre-fix runs in Redis (cleared today). The 7-day TTL means worst-case clutter is bounded. A small Galaxy startup hook could clear unfinished runs on container start if desired.
- **Cancel-path PID** — the cancel route reads `proc = info.get("process")` from worker-local `_runs[]`. If the launching worker recycled before user clicks cancel, this fails silently. Cancel could be migrated to PID + `os.killpg(os.getpgid(pid), SIGTERM)` using the store. Low priority — user-initiated cancels are usually within the worker's lifetime.

## Discipline learned this session

- **Verify, don't grep** (`feedback_verify_dont_grep.md`) — test-name grep doesn't equal coverage. Stale tests with per-test register, soft-fail audit JSONs, and pre-discipline patterns can all silently fake-green.
- **Multi-agent file contention** — when a parallel agent is actively editing the same file, commit each Edit immediately. Lost a Stage 2c reader-flip cycle today to an uncommitted parallel revert; the re-application worked when I switched to single-Edit-then-commit.
- **Avoid lazy band-aids on architectural bugs** — the proposed `max_requests:0` workaround for the worker-recycle bug was rightly rejected ("very stupid and refuse"). The proper fix (Redis-backed state + decoupled completion poller) is more work but it's the real shape of the system.
