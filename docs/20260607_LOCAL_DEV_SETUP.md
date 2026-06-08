# BioMate Local Development Setup
**Date:** 2026-06-07  
**Status:** Fully working locally as of this session

---

## Why it wasn't working before

Three blockers, now all fixed:

| Blocker | Root cause | Fix applied |
|---------|-----------|-------------|
| `DATABASE_URL` missing | No `.env` file | Created `frontend/.env` with local postgres URL |
| Postgres not installed | macOS 11 ARM — no Docker, no homebrew pg | Installed `postgresql@15` via homebrew ARM |
| Galaxy backend hardcoded EC2 path | `start_backend.sh` does `cd /home/yzhang/biomate/backend` | Added local start script (see below) |
| S3Service throws at startup | `new S3Service()` at module level, throws if no AWS creds | Patched `s3-client.ts` to warn instead of throw in `NODE_ENV=development` |
| Galaxy API key missing | Frontend couldn't provision Galaxy users (403) | Added `GALAXY_API_KEY` + `GALAXY_CONFIG_BOOTSTRAP_ADMIN_API_KEY` |

---

## Full Local Stack

### Services and ports

| Service | Port | Start command |
|---------|------|--------------|
| PostgreSQL | 5432 | `brew services start postgresql@15` |
| Galaxy backend | 8081 | `cd backend && bash scripts/start_galaxy_local.sh` |
| BioMate app (Node.js) | 5000 | `cd frontend && npm run dev` |

### Prerequisites (one-time setup)

```bash
# 1. Install postgres (ARM Mac)
arch -arm64 brew install postgresql@15
brew services start postgresql@15

# Initialize DB (first time only)
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
initdb /opt/homebrew/var/postgresql@15 --auth=trust --username=$(whoami)
brew services restart postgresql@15

# Create biomate DB and user
psql -h localhost -d postgres -c "CREATE USER biomate WITH PASSWORD 'biomate';"
psql -h localhost -d postgres -c "CREATE DATABASE biomate OWNER biomate;"

# 2. Create frontend/.env (if not present)
cat > frontend/.env << 'EOF'
DATABASE_URL=postgresql://biomate:biomate@localhost:5432/biomate
JWT_SECRET=<generate: openssl rand -hex 32>
SESSION_SECRET=<generate: openssl rand -hex 32>
NODE_ENV=development
PORT=5000
ANTHROPIC_API_KEY=<your key>
GALAXY_API_URL=http://localhost:8081
GALAXY_API_KEY=biomate-local-dev-key
EOF

# 3. Install Node deps (if not done)
cd frontend && npm install
```

### Start order (every session)

```bash
# 1. Postgres (if not auto-started)
brew services start postgresql@15

# 2. Galaxy backend
cd /path/to/biomate/backend
bash scripts/start_galaxy_local.sh

# 3. BioMate app (wait for Galaxy to be up first)
cd /path/to/biomate/frontend
npm run dev
```

---

## Galaxy Local Start Script

`backend/scripts/start_galaxy_local.sh` — the dev-friendly version of `start_backend.sh`:

```bash
#!/usr/bin/env bash
# Local dev Galaxy start — no AWS Batch, no billing stack, SQLite DB
# Usage: cd backend && bash scripts/start_galaxy_local.sh

set -e
cd "$(dirname "$0")/.."   # always runs from backend/

export PYTHONPATH=lib
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"   # set in your shell or .env
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT=true
export GALAXY_CONFIG_FILE=lib/galaxy/config/sample/galaxy.yml.sample
export GALAXY_CONFIG_DATABASE_CONNECTION="sqlite:////tmp/biomate_local.sqlite"
export GALAXY_CONFIG_INSTALL_DATABASE_CONNECTION="sqlite:////tmp/biomate_local.sqlite"
export GALAXY_CONFIG_BOOTSTRAP_ADMIN_API_KEY="biomate-local-dev-key"
export GALAXY_CONFIG_ADMIN_USERS="admin@biomate.local"
export BILLING_DEV_MODE=true
export BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
export JWT_SECRET="grhFb+sJVOuSvQXQrxjjbSWWBby/w0oQFvg9tVv/KSc="
export NEXTFLOW_USE_AWS=false
export AWS_SECRET_ACCESS_KEY=local-dev-dummy
export AWS_ACCESS_KEY_ID=local-dev-dummy

echo "[galaxy] Starting on http://localhost:8081 ..."
exec .venv/bin/gunicorn \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 \
  --workers 1 \
  --log-level warning
```

### What's different from `start_backend.sh`

| `start_backend.sh` (production) | `start_galaxy_local.sh` (local dev) |
|---|---|
| `cd /home/yzhang/biomate/backend` | `cd $(dirname $0)/..` — works from any machine |
| `AWS_SECRET_ACCESS_KEY` required, aborts if missing | `local-dev-dummy` — passes check, Batch never called |
| `NEXTFLOW_USE_AWS=true` | `NEXTFLOW_USE_AWS=false` |
| 4 gunicorn workers | 1 worker (faster startup) |
| AWS Redis, Lago, Java billing | `BILLING_DEV_MODE=true` — skips external billing |
| `--log-level info` (verbose) | `--log-level warning` (cleaner output) |

### Important: Galaxy starts slowly

First run: ~90 seconds (builds SQLite schema, loads tool registry)  
Subsequent runs: ~30 seconds (SQLite DB already exists)

---

## Galaxy API Key for Local Dev

The bootstrap key `biomate-local-dev-key` is only valid when Galaxy is started with `GALAXY_CONFIG_BOOTSTRAP_ADMIN_API_KEY=biomate-local-dev-key`. It gives admin access.

Add to `frontend/.env`:
```
GALAXY_API_KEY=biomate-local-dev-key
```

This lets the Node.js frontend provision Galaxy users for new local accounts.

---

## Testing the Full Stack

```bash
# Health check
curl http://localhost:5000/api/health

# Login and get token
TOKEN=$(curl -s -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@biomate.local","password":"TestPass123!"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")

# Workflow search (goes through Galaxy AI backend)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5000/api/workflows/search?query=ADMET&limit=3"

# Instruments CRUD
curl -H "Authorization: Bearer $TOKEN" http://localhost:5000/api/instruments

# MCP server against live local stack
BIOMATE_API_URL=http://localhost:5000 BIOMATE_API_KEY=$TOKEN \
  python3 /path/to/biomate-connectors-v2/backend/lib/mcp/biomate_mcp_server.py
```

---

## Known Local Limitations

| Feature | Local status | Why |
|---------|-------------|-----|
| Workflow search / AI chat | ✅ Works | Galaxy AI assistant runs locally |
| Instruments CRUD + health check | ✅ Works | Pure Node.js + Postgres |
| MCP server (all 14 tools) | ✅ Works | Python subprocess, no server needed |
| Workflow execution (AWS Batch) | ❌ Won't run | `NEXTFLOW_USE_AWS=false`, no real creds |
| S3 file upload/download | ❌ Will error at call time | No AWS creds (warned at startup, not fatal) |
| Billing (Lago, Java service) | ❌ Skipped | `BILLING_DEV_MODE=true` |
| OAuth (Google, GitHub) | ❌ Not configured | Add `GOOGLE_CLIENT_ID` etc. to `.env` |
| Email (password reset) | ❌ Not configured | Add `EMAIL_HOST` etc. to `.env` |

Everything needed for connector development and MCP testing works locally.
