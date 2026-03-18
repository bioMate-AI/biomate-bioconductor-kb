# Dev-Public Galaxy Runtime Blocker Handoff (2026-03-12)

> **STATUS: RESOLVED (2026-03-12 17:38 UTC)**
> Galaxy backend is `healthy`. Both `/api/version` (HTTP 200) and
> `/api/health` via the public endpoint are responding. See "Resolution" section below.

## Scope and Intent

This handoff documents the current deployment/debugging state for `dev-public.biomate.ai`, focused on why Galaxy backend remains unstable/unreachable even after config completeness was enforced.

Primary objective during this session:
- Ensure required deployment config is present.
- Restart runtime with corrected env wiring.
- Make Galaxy backend reachable at `http://127.0.0.1:8081/api/version` so strict contract tests can pass.

Current outcome:
- Config completeness is now validated and passing.
- Frontend HTTP health has intermittently returned `200`.
- Galaxy backend is still the critical blocker (`/api/version` unreachable or timing out).

---

## Environment Snapshot

- Domain: `dev-public.biomate.ai`
- Region: `us-west-2`
- EC2 instance: `i-06696b0d91f4346e0`
- Public IP: `52.42.49.175`
- Active remote deploy root detected: `/opt/biomate`
- Active remote env file detected: `/opt/biomate/.env`
- Runtime model on host is manual `docker run` containers (not stable compose orchestration yet):
  - `biomate-galaxy-dev` (port 8081 -> 8080)
  - `biomate-dev-frontend` (port 3000 -> 3000)
  - `biomate-dev-postgres` (port 5432 -> 5432)

---

## What Was Implemented Locally (Repository Changes)

### 1) Config completeness tooling
- Added `scripts/deployment/validate-ec2-config.sh`
  - Validates required env keys and required Galaxy config files.
- Wired `scripts/deployment/ec2-deploy-from-s3.sh`
  - Hard-fails if env file missing.
  - Runs validator before `docker compose up`.

### 2) Dev helper for EC2 validation without PEM
- Added `scripts/deployment/run-ec2-config-validator-eic.sh`
  - Uses EC2 Instance Connect (temporary key; no pem file required).
  - Resolves instance via Route53 A record.
  - Supports legacy remote layouts.
  - Supports inline fallback validation when remote validator script is absent.
  - Auto-detect supports:
    - `/opt/biomate/current`
    - `/opt/biomate-dev/current`
    - `/opt/biomate`
    - `$HOME/biomate`

### 3) Template/docs hardening
- Updated `.env.ec2.example` with explicit required keys and DB options.
- Updated `docker-compose.ec2.yml` with stronger runtime wiring and defaults.
- Updated `docs/QC/20260312_EC2_DOCKER_S3_RELEASE_RUNBOOK.md` with required key/file checklist and validation step.

---

## Remote State Changes Performed on EC2

### 1) Required env keys were populated in `/opt/biomate/.env`
Added/fixed presence of keys required by frontend + runtime checks:
- `JWT_SECRET`
- `SESSION_SECRET`
- `BILLING_INTERNAL_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET_NAME`
- `GALAXY_URL`
- `GALAXY_API_URL`
- `GALAXY_API_KEY`
- AI keys already present (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)

### 2) Galaxy config files verified present
In `/opt/biomate/backend/config`:
- `galaxy.yml` present
- `tool_conf.xml.sample` present
- `shed_tool_conf.xml` present

### 3) Admin user added directly to Galaxy SQLite DB
DB: `/opt/biomate/backend/database/universe.sqlite`
- Inserted admin (idempotent path):
  - `email=admin@galaxy.org`
  - `username=admin`
  - `active=1`

Note: This required elevated write because DB was read-only to non-root user on host.

---

## Validation Results

### Config completeness
Command:
- `bash /home/yzhang/biomate/scripts/deployment/run-ec2-config-validator-eic.sh --domain dev-public.biomate.ai --root-domain biomate.ai --region us-west-2`

Result:
- `EC2 config validation passed.`

### Public health
- `http://dev-public.biomate.ai/api/health` returned `200` at points during session.
- HTTPS (`https://dev-public.biomate.ai`) is not currently serving successfully.

---

## Active Blocker (Current)

Galaxy backend container does not provide stable, reachable API on `:8081`.

Observed symptoms across attempts:
- `curl http://127.0.0.1:8081/api/version`
  - either timeout (no bytes)
  - or connection refused during restart loops

Container states observed:
- `biomate-galaxy-dev`: repeatedly `Restarting` or `Up (unhealthy)`.
- `biomate-dev-frontend`: often `unhealthy` due to backend dependency issues.

---

## Key Errors and Evidence

### A) Gravity/systemd mode failure
When Galaxy entered gravity path:
- `Error: The 'virtualenv' Gravity config option must be set when using the systemd process manager`

### B) Root execution constraints (seen in earlier attempts)
- `Error: 1 validation error for Settings`
- `galaxy_user is required when running as root`

### C) Daemonization behavior conflict with containers
When using `run.sh ... start`:
- logs show Gunicorn launched with `--daemon`.
- parent process exits cleanly, causing Docker to treat lifecycle incorrectly (restart loops / unstable behavior depending on command wrapper).

### D) API still not responsive in forced Gunicorn mode
Even in explicit gunicorn attempts where process appeared running:
- `/api/version` remained timing out repeatedly.

### E) Prior frontend-side runtime errors (fixed path but relevant history)
Earlier logs showed:
- `ECONNREFUSED 127.0.0.1:5432`
- `ECONNREFUSED 127.0.0.1:8081`
This was due to loopback URLs inside container. Fixed by moving to service-name URLs on shared Docker network, but Galaxy remained unstable.

---

## Why This Is Still Hard (Root Cause Hypothesis)

The backend image/startup path appears to be mixing Galaxy startup modes in a container-unsafe way:
- gravity/systemd expectations when running as root,
- daemonized gunicorn lifecycle when using `start`,
- and potentially heavy startup (toolbox initialization + external lookups) causing health-check starvation and unstable readiness.

Most likely final fix requires a deterministic, container-native startup contract, not ad-hoc `run.sh` permutations.

---

## Recommended Team Recovery Plan (Priority Order)

### P0: Lock startup model (single-source of truth)
Choose one and standardize:
1. **Container-native Gunicorn foreground process** (preferred for Docker), or
2. Gravity with explicit, valid root/systemd config (less ideal in containers).

For Docker, avoid daemon mode in container entrypoint.

### P0: Build a known-good compose profile for dev-public
Define one compose file used in production-like dev:
- explicit command/entrypoint
- explicit healthcheck with realistic startup timeout
- no mixed manual `docker run` drift
- stable network aliases (`galaxy-backend`, `postgres`)

### P1: Stabilize health checks
- Increase startup/readiness windows for Galaxy.
- Health endpoint should tolerate initialization period (or use phased readiness signal).

### P1: Remove root/systemd ambiguity
- Ensure Galaxy is not forced into systemd manager in container.
- If root unavoidable, include all required settings (`galaxy_user`, possibly `virtualenv` where gravity expects it) in the exact config section consumed by chosen startup path.

### P2: Re-run strict contract tests after backend green
After `:8081/api/version` steady `200`:
- run strict execute contract on dev-public URL.

---

## Useful Commands for Team

### Check current runtime quickly
```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl --max-time 8 -sS -o /dev/null -w 'galaxy:%{http_code}\n' http://127.0.0.1:8081/api/version || true
curl --max-time 8 -sS -o /dev/null -w 'frontend:%{http_code}\n' http://127.0.0.1:3000/api/health || true
```

### Validate config presence (from local machine)
```bash
bash /home/yzhang/biomate/scripts/deployment/run-ec2-config-validator-eic.sh \
  --domain dev-public.biomate.ai \
  --root-domain biomate.ai \
  --region us-west-2
```

### Verify admin user exists in DB (remote)
```bash
python3 - <<'PY'
import sqlite3
conn=sqlite3.connect('/opt/biomate/backend/database/universe.sqlite')
cur=conn.cursor()
cur.execute("select id,email,username,active from galaxy_user order by id")
print(cur.fetchall())
conn.close()
PY
```

---

---

## Resolution (2026-03-12)

### Root cause (found)

Galaxy crashed on every boot with:
```
Exception: Failed to get file lock for /app/database/dependencies/conda
```

A **stale 0-byte `conda.lock` file** at `/opt/biomate/backend/database/dependencies/conda.lock`
(left behind by a prior crash) prevented the CondaResolver from initialising. This caused the
app to crash during `--preload` / worker boot, which Docker then restarted — creating the
endless restart cycle. Conda itself (`_conda/`) was fully installed; only the lock was bad.

### Fixes applied

| Layer | Change |
|---|---|
| `backend/config/galaxy.yml` | Added `conda_auto_init: false` + `conda_auto_install: false` so Galaxy never tries to acquire the conda file-lock on startup |
| `backend/Dockerfile` | Replaced `CMD ["./run.sh", "start"]` with direct `gunicorn` invocation (foreground, `--preload`, `--timeout 600`) — bypasses run.sh/Gravity/systemd entirely |
| `docker-compose.ec2.yml` | Same gunicorn command override + `--preload` + `start_period: 120s` healthcheck |
| EC2 host (live) | Deleted stale `conda.lock`; patched remote `galaxy.yml`; restarted container with new command |

### Verification

```
{"version_major":"25.1","version_minor":"dev0"}   ← /api/version HTTP 200
{"status":"ok","services":{"galaxy":{"connected":true,...}}}  ← /api/health HTTP 200
frontend-public:200   ← dev-public.biomate.ai/api/health HTTP 200
```

Container state at resolution:
```
biomate-galaxy-dev     Up About a minute (healthy)
biomate-dev-frontend   Up 15 seconds (health: starting)
biomate-dev-postgres   Up 9 hours
```

---

## Handoff Summary

What is done:
- Required config information is now present and programmatically validated.
- Admin user has been inserted in Galaxy DB.
- Frontend and env wiring improved significantly.
- **Galaxy backend is now stable and healthy.**
- Root cause (stale conda.lock + wrong startup mode) identified and fixed at all layers.

What remains:
- The GALAXY_API_KEY in `/opt/biomate/.env` is a placeholder — API auth calls return 401.
  Set `GALAXY_API_KEY` to the value of `bootstrap_admin_api_key` from `galaxy.yml` and
  restart the frontend to fix authenticated Galaxy API calls.
