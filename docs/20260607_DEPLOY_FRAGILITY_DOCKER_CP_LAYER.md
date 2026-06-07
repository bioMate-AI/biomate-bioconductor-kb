# Deploy fragility — docker cp into running container does not survive recreation

Surfaced 2026-06-07 while validating Path B autofix3 trigger on dev.

## What happened

1. Path B autofix3 trigger committed + synced (commit `87066577b`)
2. Verified live on dev: trigger code present, smoke test fires correctly
3. Wrote `scripts/enable_autofix3_on_dev.sh` to flip `BIOMATE_AUTOFIX3_AUTO=true`
4. Script recreates the container (`docker stop` + `docker rm` + `docker run`
   with merged env) — necessary because env vars are immutable on a running
   container.
5. **Container came back without my code.** `_trigger_autofix3_async` grep
   returns 0 in `/app/lib/galaxy/jobs/runners/nextflow_workflow_runner.py`.
   The new `nextflow_runner.py` file is missing entirely.

## Why

`sync_to_dev.sh:deploy_backend_python()` (line 200-300 area) deploys backend
Python code via:

```
ec2_scp tarball.tar.gz → /tmp/backend_py_sync.tar.gz
ec2_ssh '
  tar -xzf ...
  find … | while read src; do docker cp "$src" biomate-galaxy-dev:$dest; done
'
```

`docker cp` writes into the container's **writable layer** — not the image.
Anything written this way survives container restart (`docker restart`) but
NOT container recreation (`docker stop && docker rm && docker run`).

The base image `biomate-galaxy-backend:latest` was built once and hasn't
been rebuilt for weeks. Every backend sync since has been writing to layers
on top of it that exist only as long as the container does.

This is why:
- ✓ Daily syncs work (container is never recreated)
- ✓ `docker restart biomate-galaxy-dev` keeps changes (same writable layer)
- ✗ `docker rm && docker run` (this script + any future redeploy) loses everything

## Blast radius

Anything that ran through `deploy_backend_python` since the last image build is
ephemeral. Worst case: a Docker daemon restart, host reboot, or any operator
running `docker rm biomate-galaxy-dev` wipes all backend Python changes for
weeks of work. Galaxy comes back at the image's stale baseline silently
(no error — just old code).

## Three valid fixes (pick one)

### Fix A: rebuild the image on every backend sync
- `sync_to_dev.sh` does `docker build -t biomate-galaxy-backend:latest backend/`
  + `docker stop && docker run` instead of `docker cp`
- Pro: layer correctness; future-proof
- Con: slow (multi-minute rebuild for any one-line change); harder caching;
  must preserve env vars / network on every cycle

### Fix B: bake an `enable_autofix3_on_dev.sh`-style env-flip pattern that
re-syncs after recreation
- After the script recreates the container, automatically re-run the backend
  Python deploy step before declaring success
- Pro: minimal change; reuses existing sync machinery
- Con: still leaves the writable-layer fragility for any operator who
  recreates the container outside this script

### Fix C: bind-mount the backend code from the host
- `docker run -v /opt/biomate/backend_code:/app/lib …` so the host filesystem
  IS the source of truth
- `sync_to_dev.sh` writes files to the host path; gunicorn HUP reloads
- Pro: correct by construction (no writable-layer trick); container is purely
  runtime
- Con: requires a one-time container recreation to add the mount; biggest
  architectural change of the three

## Recommendation

**Fix B for today** (immediate, contained): make `enable_autofix3_on_dev.sh`
call the sync after recreation, and add a `--rebuild` flag for users who
want to refresh from scratch.

**Fix C for the proper resolution** (next platform-cleanup sprint): bind-mount
the backend lib directory. Eliminates the writable-layer class of bug
permanently and makes future env-var flips trivial.

## What I'm doing right now

1. Re-running `sync_to_dev.sh` to restore the autofix3 trigger to the new
   container (already in flight as task `bq5iutuxo`).
2. Filing this doc.
3. Updating `enable_autofix3_on_dev.sh` to chain the sync after recreation
   so this class of regression never happens again from this script.

## Lesson

When a deploy mechanism writes to a place that's not the image, document
the survival guarantees loudly. The pattern `docker cp …` is a one-way trip
to confusion the next time someone recreates the container.
