#!/bin/bash
# Start Galaxy for ANDV / BioMate UI E2E — uses universe.sqlite (full workflow registry).
# Do NOT use start_backend.sh for ANDV; that points at /tmp/biomate_connection_formal.sqlite.
set -e
cd "$(dirname "$0")"
set -a
[ -f .env ] && source .env
set +a

export GALAXY_CONFIG_FILE=config/galaxy.yml
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT=true
unset GALAXY_CONFIG_DATABASE_CONNECTION
unset GALAXY_CONFIG_INSTALL_DATABASE_CONNECTION

echo "[andv] GALAXY_CONFIG_FILE=$GALAXY_CONFIG_FILE"
echo "[andv] DB: database/universe.sqlite (from galaxy.yml)"
exec .venv/bin/gunicorn \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 \
  --workers 2 \
  --log-level info
