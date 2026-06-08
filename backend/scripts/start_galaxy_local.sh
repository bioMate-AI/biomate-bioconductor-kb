#!/usr/bin/env bash
# Local dev Galaxy start — no AWS Batch, no billing stack, SQLite DB
# Usage: cd backend && bash scripts/start_galaxy_local.sh
#
# First run: ~90 seconds (builds SQLite schema, loads tool registry)
# Subsequent runs: ~30 seconds (SQLite DB already exists)

set -e
cd "$(dirname "$0")/.."   # always runs from backend/

export PYTHONPATH=lib
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
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
