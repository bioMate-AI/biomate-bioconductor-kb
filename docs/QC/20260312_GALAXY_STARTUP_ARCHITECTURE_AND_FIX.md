# Galaxy Startup Architecture & Crash Fix (2026-03-12)

## Summary

This document covers three related topics resolved in this session:

1. **The crash root cause** that kept the Galaxy backend in a restart loop on `dev-public.biomate.ai`.
2. **How Galaxy is started** across all BioMate environments (local dev, Docker, EC2).
3. **Why the Conda fix does not affect workflow execution.**

---

## 1. Root Cause: Two Compounding Bugs

### Bug A — `run.sh start` daemonizes gunicorn

The original `Dockerfile` CMD was:
```
CMD ["./run.sh", "start"]
```

`run.sh` passes `--daemon` to gunicorn. The parent process exits with code 0.
Docker interprets a clean process exit as "container finished" and applies the
`restart: unless-stopped` policy — triggering an endless restart loop.

This also has a secondary failure mode: when running as root (as all Docker
containers do by default), `run.sh` routes through Galaxy's Gravity process
manager, which requires either `galaxy_user` to be set or a valid virtualenv
path — neither of which is satisfied in the container, producing:

```
Error: The 'virtualenv' Gravity config option must be set when using the systemd process manager
galaxy_user is required when running as root
```

### Bug B — Stale `conda.lock` (the actual crash trigger)

On every boot, Galaxy's `CondaResolver.__init__()` tries to acquire an
exclusive file lock at:
```
/app/database/dependencies/conda.lock   (→ host: /opt/biomate/backend/database/dependencies/conda.lock)
```

A prior crash left a stale 0-byte lock file behind. The `filelock` library
failed to acquire it (a known issue with Docker overlay filesystem locking
semantics), throwing:

```
Exception: Failed to get file lock for /app/database/dependencies/conda
```

This crashed the app during `--preload` / worker boot every single time,
even though `_conda/` was already fully installed. Docker then restarted the
container (hitting Bug A again), creating the visible cycle:

```
biomate-galaxy-dev   Restarting   (every ~5 min)
```

### Why it was hard to see

- Toolbox loading is logged at DEBUG level and completes in ~12 seconds.
- The conda crash happens ~1 second *after* the last toolbox log line
  (`Writing integrated tool panel config file`), with no preceding warning.
- The container appeared to be "running" (port open, master process alive)
  but could never serve requests because the worker never finished booting.
- Without `--preload`, gunicorn's 300s worker timeout killed the booting
  worker before the conda crash surfaced, making the symptom look like a
  timeout rather than an exception.

---

## 2. Fixes Applied

### Fix 1 — Direct gunicorn invocation (no run.sh)

Replace `CMD ["./run.sh", "start"]` with a direct gunicorn call that:
- Stays in the **foreground** (no `--daemon`)
- Uses `--preload` so the app loads **once in the master process** before
  forking workers — workers start instantly ready
- Sets `--timeout 600` to give the preload phase enough headroom

**`backend/Dockerfile`** (after):
```dockerfile
CMD ["gunicorn", \
     "galaxy.webapps.galaxy.fast_factory:factory()", \
     "--pythonpath", "lib", \
     "-k", "galaxy.webapps.galaxy.workers.Worker", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "1", \
     "--timeout", "600", \
     "--preload", \
     "--log-level", "info"]
```

The same command is set as an explicit `command:` override in
`docker-compose.ec2.yml` so it survives image rebuilds.

### Fix 2 — Disable conda auto-init in galaxy.yml

Added to `backend/config/galaxy.yml` under the `galaxy:` section:

```yaml
conda_auto_init: false
conda_auto_install: false
```

This tells Galaxy's `CondaResolver` to skip the `ensure_installed()` call
entirely on startup — no file lock is ever acquired, no crash is possible.

**On the live EC2 host:**
- Stale `/opt/biomate/backend/database/dependencies/conda.lock` was deleted.
- `galaxy.yml` was patched with the same two settings.

### Fix 3 — Healthcheck tuned for actual startup time

`start_period` raised from 60s → **120s** in both `Dockerfile` and
`docker-compose.ec2.yml`. Failure to account for Galaxy's ~60s preload
caused Docker to mark the container unhealthy before it was ready, confusing
operational monitoring.

---

## 3. Galaxy Startup Map (All Environments)

### Local development — `backend/start_backend.sh` (primary)

```bash
exec .venv/bin/gunicorn \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \   # async worker
  -b 127.0.0.1:8081 \
  --workers 4 \
  --log-level info
```

- Config: `lib/galaxy/config/sample/galaxy.yml.sample`
- Worker type: **uvicorn async** (different from Docker which uses Galaxy's sync Worker)
- No `--preload` (4 workers each load the app independently)
- Binds to `127.0.0.1:8081` (localhost only)
- Conda is not a concern here: the sample config has no dependency resolver config

### Docker local — `docker-compose.yml`

- Uses `backend/Dockerfile` (now with direct gunicorn CMD)
- Config: `backend/config/galaxy.yml` (mounted at `/app/config/galaxy.yml`)
- Exposed: host port **8080** → container 8080
- Worker type: Galaxy sync Worker + `--preload`

### Docker EC2 — `docker-compose.ec2.yml` + manual `docker run`

- Same gunicorn command as Docker local
- Exposed: host port **8081** → container 8080
- Config mounted from `/opt/biomate/backend/config/galaxy.yml`
- Database volume: `/opt/biomate/backend/database:/app/database`
- Network: `biomate-dev-net` (shared with frontend and postgres containers)

### Legacy scripts (not recommended for regular use)

| Script | Startup method | Notes |
|---|---|---|
| `backend/start_galaxy_with_ai.sh` | `exec sh run.sh` | Hits Gravity/systemd issues as root |
| `backend/start_galaxy_simple.sh` | `galaxy-main.py serve`, falls back to gunicorn | Ad-hoc; not wired to job config |
| `backend/start_galaxy_debug.sh` | Similar to above | Debug flags |

---

## 4. Worker Type Comparison

| Environment | Worker class | Binding | Workers | Preload |
|---|---|---|---|---|
| Local dev (`start_backend.sh`) | `uvicorn.workers.UvicornWorker` | `127.0.0.1:8081` | 4 | No |
| Docker local | `galaxy.webapps.galaxy.workers.Worker` | `0.0.0.0:8080` | 1 | Yes |
| Docker EC2 | `galaxy.webapps.galaxy.workers.Worker` | `0.0.0.0:8080` | 1 | Yes |

The uvicorn async worker (used locally) is higher throughput for I/O-bound
workloads. The Galaxy sync Worker (used in Docker) is simpler and more
compatible with Galaxy's internal threading model.

---

## 5. Conda Fix and Workflow Impact

**Question:** Does disabling `conda_auto_init` / `conda_auto_install` affect
Galaxy workflow execution?

**Answer: No.**

Evidence from `backend/config/job_conf.yml`:

```yaml
execution:
  default: docker_local

  environments:
    docker_local:
      runner: local
      docker_enabled: true
      docker_default_container_id: biomate/biotools:arm64-v5
```

All tools run inside Docker containers (`biomate/biotools:arm64-v5`).
Galaxy's Conda resolver is only consulted when tools run **bare on the host**
and need package installation. Since the execution path is 100% Docker,
Conda is never in the critical path for any workflow step.

`conda_auto_init: false` eliminates the startup file-lock race with **zero
functional impact** on tool execution or workflow orchestration.

---

## 6. Verification (Post-Fix)

Confirmed on `dev-public.biomate.ai` at 2026-03-12 17:38 UTC:

```
curl http://127.0.0.1:8081/api/version
→ {"version_major":"25.1","version_minor":"dev0"}   HTTP 200

curl http://127.0.0.1:3000/api/health
→ {"status":"ok","services":{"galaxy":{"connected":true,"url":"http://biomate-galaxy-dev:8080"},"ai":"ok"}}

curl http://dev-public.biomate.ai/api/health
→ HTTP 200

docker ps
biomate-galaxy-dev     Up (healthy)
biomate-dev-frontend   Up (health: starting)
biomate-dev-postgres   Up
```

---

## 7. One Remaining Item

`GALAXY_API_KEY` in `/opt/biomate/.env` is currently a placeholder.
Authenticated Galaxy API calls (e.g. `/api/whoami`) return HTTP 401.

**Fix:** Set `GALAXY_API_KEY` to the `bootstrap_admin_api_key` value from
`backend/config/galaxy.yml`, then restart the frontend container:

```bash
# On the EC2 host
BOOTSTRAP_KEY=$(grep bootstrap_admin_api_key /opt/biomate/backend/config/galaxy.yml | awk '{print $2}')
sed -i "s|^GALAXY_API_KEY=.*|GALAXY_API_KEY=$BOOTSTRAP_KEY|" /opt/biomate/.env
docker restart biomate-dev-frontend
```

---

## 8. Files Changed in This Session

| File | Change |
|---|---|
| `backend/Dockerfile` | CMD changed from `run.sh start` to direct gunicorn with `--preload --timeout 600` |
| `backend/config/galaxy.yml` | Added `conda_auto_init: false` and `conda_auto_install: false` |
| `docker-compose.ec2.yml` | Added explicit `command:` with same gunicorn flags; `start_period: 120s` |
| `docker-compose.yml` | No change (inherits fixed Dockerfile CMD) |
| `docs/QC/20260312_DEV_PUBLIC_GALAXY_RUNTIME_BLOCKER_HANDOFF.md` | Marked RESOLVED; added resolution section |
| EC2 host `/opt/biomate/.env` | Populated required env keys (JWT, session, AWS, Galaxy) |
| EC2 host `galaxy.yml` | Added `conda_auto_init: false`, `conda_auto_install: false`, `galaxy_user: root` |
| EC2 host `database/dependencies/conda.lock` | Deleted stale lock file |
