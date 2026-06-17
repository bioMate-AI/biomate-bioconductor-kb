# Galaxy → Frontend SSE delivery fix on dev (2026-06-17)

## The bug

Galaxy backend's `_post_sse()` posts workflow events (chat narrator,
autoloop QC gate, completion) to `${FRONTEND_URL}/internal/sse-inject`
so the React UI receives real-time updates. The env var was never set
on `biomate-galaxy-dev`, so it defaulted to `http://localhost:5000` —
which from inside the Galaxy container points at Galaxy itself, not at
the frontend container.

Every SSE inject silently failed:

```
[narrate_chat] SSE inject failed for chat_progress: <urlopen error
[Errno 111] Connection refused>
```

User-visible symptoms:
- Frontend Postgres `execution_runs.status` stays `running` forever
  even though Galaxy logged `Nextflow run … finished — status=succeeded`
- AutoLoopPanel never renders — `autoloop_gate_results` / `autoloop_update`
  events never reach the UI
- Chat history doesn't show the "Workflow finished" narrator line

This was the missing piece of the L3 fix. Even after Stage 3a-3d
landed (Redis state + completion poller + orphan finalizer), the
frontend never learned that runs had completed.

## The fix

Set `FRONTEND_URL=http://biomate-dev-frontend:3000` on the Galaxy
container. Same 3-layer pattern as `RUN_STATE_STORE`:

1. **Container `/app/start_biomate.sh`** — `export` at line 5 (next to
   the existing `RUN_STATE_STORE` export). Picks up on container restart.
2. **Host `/opt/biomate/galaxy_build/start_biomate.sh`** — same export.
   This is the image-build source; persists through future rebuilds.
3. **Dockerfile** — `ENV FRONTEND_URL=http://biomate-dev-frontend:3000`
   so the env is set even before start_biomate.sh runs (covers any code
   path that reads env at module import time).

## Verification

Before fix:

```
$ docker exec biomate-galaxy-dev bash -c '
  GPID=$(pgrep -f "gunicorn.*master" | head -1)
  cat /proc/$GPID/environ | tr "\0" "\n" | grep ^FRONTEND_URL='
(empty)
```

After fix + restart:

```
$ docker exec biomate-galaxy-dev bash -c '...'
FRONTEND_URL=http://biomate-dev-frontend:3000
```

Connectivity test from Galaxy → frontend:

```
http://biomate-dev-frontend:3000 → 200
```

Live workflow log post-fix (run 928fa346):

```
[QC Monitor] SSE inject endpoint: http://biomate-dev-frontend:3000/internal/sse-inject
[workflow.qc_gate_blocked] QC blocked on herg_ic50_uM (value=0.24, threshold=1.0)
[workflow.phase_completed] PREDICT_ADMET_PROPERTIES (run) done
pN:main.1,p:48,tN:run-completion-poller   ← orphan poller fired
[workflow.failed] Workflow stopped — workflow was interrupted
```

The autoloop SSE chain — `qc_gate_blocked`, `phase_completed`,
`workflow.failed` — all delivered to the frontend cleanly. The original
"autoloop SSE silent on ADMET" symptom that started this entire
investigation is fixed end-to-end.

## Why we missed this earlier

- The SSE-callback fix in commit `45db54b48` plumbed the callback INTO
  `_evaluate_qc_from_s3`, but the callback function (`_post_sse`)
  silently swallowed connection errors with a `log.debug(...)` line.
  Failures were never surfaced.
- The L3 fix verified `finalized_by="orphan_poller"` in Redis, but
  didn't check that the frontend Postgres status had also reached
  terminal — which would have caught this gap.
- The full audit ran today (after user request) caught it on the first
  pass.

## Prod checklist

Before this lands on prod:

- [ ] Set `FRONTEND_URL` on prod Galaxy container env (same pattern)
- [ ] Confirm `prod-frontend:3000` (or equivalent) is reachable from
      the Galaxy container on the prod Docker network
- [ ] Watch first day of prod logs for any new `[narrate_chat] SSE
      inject failed` warnings

## Open follow-up

The `_post_sse` failure handler is `log.debug(...)` — silent at INFO
level. Consider promoting to `log.warning(...)` so future
misconfigurations show up in routine log scans. Trivial change in
`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:~100`.
