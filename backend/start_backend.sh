#!/bin/bash
# Start Galaxy backend with billing environment variables
set -e
cd /home/yzhang/biomate/backend

# Core Galaxy settings
export ANTHROPIC_API_KEY=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
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT=true
export GALAXY_CONFIG_FILE=lib/galaxy/config/sample/galaxy.yml.sample
export GALAXY_CONFIG_DATABASE_CONNECTION=sqlite:////tmp/biomate_connection_formal.sqlite

# Billing settings
export BILLING_DEV_MODE=true
export BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
export JWT_SECRET="grhFb+sJVOuSvQXQrxjjbSWWBby/w0oQFvg9tVv/KSc="
export REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379

# Lago (placeholder until configured)
export LAGO_API_URL=https://api.getlago.com

# Java billing service
export JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
export JAVA_BILLING_ENABLED=true

# Start billing monitoring stack (Prometheus + Grafana) if Docker is available
MONITORING_DIR="$(dirname "$0")/../billing_system/monitoring"
if command -v docker &>/dev/null && [ -f "$MONITORING_DIR/docker-compose.yml" ]; then
  echo "[billing] Starting monitoring stack (Prometheus :9090, Grafana :3000)..."
  docker compose -f "$MONITORING_DIR/docker-compose.yml" up -d --quiet-pull 2>&1 | grep -v "^time=" || true
fi

exec .venv/bin/gunicorn \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 \
  --workers 4 \
  --log-level info
