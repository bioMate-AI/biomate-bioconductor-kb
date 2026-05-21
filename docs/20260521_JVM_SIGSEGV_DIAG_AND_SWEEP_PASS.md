# 2026-05-21 — JVM SIGSEGV diagnosis, dev recovery, sweep #3 (all 3 pass), recommendation

Continues `docs/20260520_DEV_WORKFLOW_FIXES_AND_ALEMBIC_MERGE.md`. Session
purpose: re-run the 3 use cases (ADMET / Allometric / AutoDock) after the
prior day's 10-commit fix burst, find out what is still broken, fix it.

---

## TL;DR

- **3/3 use cases now pass on dev** with real AWS Batch execution and
  real S3 outputs (`174ced5f` ADMET 80s, `3812df8c` Allometric 99s,
  `5d37562a` AutoDock 116s).
- **Today's regression chain** that had to be untangled before the
  sweep could run cleanly:
  1. publishDir mass-fix shipped, but a symlink-vs-directory shape
     conflict on dev kept `drug_discovery/ADMET_pred` stale (the chat
     path was hitting the unfixed file).
  2. sync_to_dev.sh did not invalidate Python `.pyc`, Nextflow script
     cache, or per-run dirs — fresh code could ship without taking
     effect.
  3. Alembic merge migration `204367c6a604` (from Task #19) shipped to
     dev as code, but the live SQLite DB was never upgraded — Galaxy
     refused to boot ("OutdatedDatabaseError: DB has 3af58c192752, code
     expects 204367c6a604").
  4. A duplicate uncommitted merge migration from another session
     (`m1g3h3ad5fix_*`) created a fresh multi-head condition that
     blocked `manage_db.sh upgrade`.
- **JVM SIGSEGV in AWS SDK CRT loader is still latent.** The fix
  applied yesterday (`4efb990e1`: per-run CRT cache + `-Xss2m`) ships
  the flags into the JVM CLI correctly but does not eliminate the
  race. It survived sweep #3 (3/3 pass) but reproduced before that.
  Recommendation: ship a config-level CRT-disable first; fall back to
  a base-image switch if that doesn't work.

---

## Today's commits (after yesterday's 10)

| # | SHA | What |
|---|---|---|
| 11 | `0e8da8424` | Reconcile preserves `cancelled` status (was being collapsed into `failed`) — consistency-audit finding |
| 12 | `8de1df86f` | sync_to_dev.sh: clear `__pycache__/`, `~/.nextflow/cache`, orphan `/tmp/nextflow_runs/`; in-container per-file replace to handle symlink-vs-dir; HUP Galaxy on workflow-only commits |

Plus operational fixes applied directly on dev (no commit needed —
they're state, not code):
- Deleted duplicate `m1g3h3ad5fix_*` merge migration on local + dev.
- Manually upgraded Galaxy SQLite DB to revision `204367c6a604`.
- Cleared stranded `a7f3deepagent` row from `alembic_version` table.
- Restarted Galaxy container → boots clean.

---

## What went wrong with sync_to_dev.sh before today's fix

`docker cp <host>:<container>` cannot replace a directory with a
non-directory (e.g., a symlink). When local repo has
`drug_discovery/ADMET_pred → pharmacology/ADMET_pred` as a symlink but
dev has it as a standalone directory (older deployment shape), the
host-side `docker cp -r` silently leaves the stale directory in place.
The publishDir fix from `84c4a0923` was already in the local symlink's
target but never propagated to the dev directory's `main.nf`.

`8de1df86f` rewrites `deploy_workflows()` to extract the tar
*inside* the container and per-file replace, removing any pre-existing
dest entry (file/dir/symlink) before placing the new entry. Now
`cp -P` preserves symlinks correctly.

Also added cache invalidation:
- `__pycache__/` + `*.pyc` under `/app/lib/galaxy/ai` and
  `/app/lib/galaxy/webapps/galaxy/api` — wiped before HUP so fresh
  `.py` always wins.
- `~/.nextflow/cache` + `~/.nextflow/tmp` — Nextflow keys its
  compiled-script cache by content hash, but stale per-plugin state
  could still pin to old behaviour.
- `/tmp/nextflow_runs/*` older than 60 min — so the disk-fallback
  status path can't latch onto a stale `timing.json`.
- HUP Galaxy on workflow-only commits too (was: backend-only) —
  Galaxy's in-process `workflow_search` step cache stayed pinned
  across .nf file changes otherwise.

---

## Alembic recovery procedure (for the runbook)

When dev's Galaxy refuses to boot with `OutdatedDatabaseError`:

```bash
# 1. Confirm heads
docker exec biomate-galaxy-dev bash -c \
  "cd /app/lib/galaxy/model/migrations && PYTHONPATH=/app/lib alembic heads"

# 2. If a duplicate merge file exists (another session's hand-written
#    merge with the same down_revision tuple), delete one:
docker exec biomate-galaxy-dev rm -f \
  /app/lib/galaxy/model/migrations/alembic/versions_gxy/<dupe>_merge_*.py

# 3. Inspect the DB's alembic_version table:
docker exec biomate-galaxy-dev bash -c \
  'sqlite3 /app/database/universe.sqlite "SELECT * FROM alembic_version;"'

# 4. Run the upgrade (now that heads is unique):
docker exec biomate-galaxy-dev bash -c "cd /app && ./manage_db.sh upgrade"

# 5. If there's a stranded parent revision row (one of the merge
#    parents that was never cleaned up by the upgrade), delete it:
docker exec biomate-galaxy-dev bash -c \
  'sqlite3 /app/database/universe.sqlite \
   "DELETE FROM alembic_version WHERE version_num = '"'"'<stranded>'"'"';"'

# 6. Restart Galaxy:
docker restart biomate-galaxy-dev
```

---

## Sweep #3 results (post-recovery)

All three use cases fired in parallel via `/api/workflows/execute`:

| Workflow | runId | Duration | Status | Real outputs in S3? |
|---|---|---|---|---|
| ADMET (`pharmacology/ADMET_pred`) | `174ced5f-…` | 80s | ✅ completed | 7 files — ADMET_pred_output.txt, ADMET_pred_results.json + pipeline_info HTMLs |
| Allometric Scaling (`pharmacology/allometric_scaling`) | `3812df8c-…` | 99s | ✅ completed | 9 files — allometric_regression.csv, fih_dose_recommendation.json, human_pk_prediction.json, … |
| AutoDock Vina (`pharmacology/docking_autodock_vina`) | `5d37562a-…` | 116s | ✅ completed | 7 files — docking_autodock_vina_output.txt, results.json + pipeline_info HTMLs |

All three: `is_batch: True`, outdir `s3://biomate-nextflow-work/nextflow/outputs/unknown/<8-char>/`, no JVM SIGSEGV.

Open cosmetic gap: `progress.totalSteps = 0` in the run record. The
`69382a760` backfill code only fires when `nfs.completedTasks /
nfs.totalTasks` are reported in the reconcile payload; reconcile
happened so quickly here that those fields weren't yet populated.
The canonical `/api/runs/:id/outputs` endpoint is the source of
truth for the user-facing artifact list and shows real counts.

---

## JVM SIGSEGV — diagnosis + recommendation

### What we have

The crash always presents as:
```
SIGSEGV (0xb) at pc=0x...575a inside ld-linux-x86-64.so.2+0x2475a
Current thread: JavaThread "PublishDir-N"
Native frames:
  jdk.internal.loader.NativeLibraries.load(...)
  java.lang.System.load(...)
  software.amazon.awssdk.crt.CRT.extractAndLoadLibrary(...)
  software.amazon.awssdk.crt.CRT.loadLibraryFromJar(...)
  software.amazon.awssdk.crt.CRT.<clinit>(...)
  software.amazon.awssdk.crt.CrtResource.<clinit>(...)
```

Host: Debian trixie (glibc 2.41), OpenJDK 21.0.11+10. AWS SDK CRT's
static initializer extracts a bundled `.so` from the CRT JAR to
`/tmp/.aws-crt-cache/`, then calls `System.load()` → the dynamic
linker chains a sequence of `dlopen`s, and somewhere in that chain
on glibc 2.41 the loader's internal state corrupts.

### What yesterday's mitigation does and doesn't do

`4efb990e1` injects three JVM options into `NXF_OPTS` per run:
```
-Daws.crt.lib.dir=<per-run-cache>     # each head extracts to its own dir
-Daws.crt.disable.crt.in.client=true  # ASK the AWS SDK to skip CRT
-Xss2m                                # 2 MB thread stack (default 1 MB)
```

Verified the flags reach the JVM CLI (visible in `hs_err_pid*.log`
Command Line). The first two reduce the race window but don't
eliminate it (CRT's `<clinit>` still runs because the JAR is on the
classpath). The third gives the loader more room.

The flags helped — sweep #3 went 3/3 — but on yesterday's parallel
4-up sweep, 3/4 still crashed. The race is statistical, not gone.

### Recommendation (in priority order)

| # | Approach | Time | Risk | Stops crash? |
|---|---|---|---|---|
| 1 | Disable nf-amazon's CRT path via nextflow.config `aws { client { s3.useCrtClient = false } }` — falls back to Java HTTP client | 5 min experiment | low (one config block, easy revert) | **Likely yes** — CRT JAR's `<clinit>` may not even fire if client never instantiates it |
| 2 | Switch base image Debian trixie → Ubuntu 22.04 (glibc 2.41 → 2.35) | 30–60 min, rebuild biomate-nextflow-base + biomate-galaxy | medium (pip wheel ABI for C extensions; need force-reinstall) | **Yes** — known stable JDK 21 + glibc 2.35 combo with long production track record |
| 3 | Pre-extract AWS CRT `.so` files at image build time, set `java.library.path` | 20 min | low | **Maybe** — fixes the extraction race only; other JNI loads could still race on glibc 2.41 |
| 4 | Downgrade JDK 21 → 17 LTS | 15 min | medium (Galaxy upstream is moving to 21+) | **Yes** for this specific crash; future-incompatible with upstream |

Going with **#1 first**, falling back to **#2** if it doesn't take effect.

Reasoning: #1 is reversible in 5 minutes, doesn't require image rebuild
or redeploy, and if the right knob is `s3.useCrtClient` (or similar
under `aws { client { ... } }`), CRT loading is bypassed entirely. #2
is the right permanent fix if #1 doesn't work, because it removes the
glibc-version variable from the equation rather than working around the
symptom.

---

## Still-open issues (carrying over from yesterday)

1. `biomni-tools:x86` container has incompatible numpy + rdkit
   versions (`AttributeError: _ARRAY_API not found`,
   `Standardizer not found`). Blocks CYP-DDI runtime.
2. Alembic merge end-to-end verification against a fresh-DB deploy
   (test env) — dev's DB is now upgraded so we can't reproduce here.
3. **16 stashes** of other agents' uncommitted WIP. Today's
   `m1g3h3ad5fix_*` duplicate was a tangible cost of the stash
   backlog (the other agent's manual fix collided with mine).
4. The sample-data fabrication issue in `galaxy-assistant.ts:5170`
   (LLM treats "demo" exception as "fabricate results"). Design
   discussed yesterday; not implemented.
5. Three `mock_mode = True` defaults still live in the backend
   runtime validators.

---

## What's next this session

- Implement disable-CRT (option #1) in the executor config
  generator, sync, fire 3 use cases sequentially + then a 4-up
  parallel burst to stress-test the race.
- If 3-of-3 sequential + 4-of-4 parallel pass: ship the config
  change as the JVM SIGSEGV fix.
- If parallel burst still crashes: pivot to option #2 (Ubuntu base
  image), document the dockerfile diff, plan the rebuild + redeploy
  for the next session.
