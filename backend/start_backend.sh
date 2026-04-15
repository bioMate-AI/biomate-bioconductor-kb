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
# LOCAL DEV:  Redis = biomate-redis-test Docker container on port 6379
#             Lago  = lago-api Docker container on port 3010
# PRODUCTION: Redis = redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
#             Lago  = http://35.86.137.71:3000  key=01b71711-be39-49af-8d14-87a4ee827157
#             Java  = http://35.86.137.71:8080  JAVA_BILLING_ENABLED=true
export BILLING_DEV_MODE=false
export BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
export JWT_SECRET="grhFb+sJVOuSvQXQrxjjbSWWBby/w0oQFvg9tVv/KSc="
export REDIS_URL=redis://localhost:6379

# Lago billing (local Docker)
export LAGO_API_URL=http://localhost:3010
export LAGO_API_KEY=ba049ead-f0da-494a-b0ec-b76bdc26fc96
export LAGO_WEBHOOK_SECRET=9ef2c8b4-9d99-47f5-98d8-520a22ed3bde

# Java billing service — disabled in local dev (AWS EC2 instance stopped)
export JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
export JAVA_BILLING_ENABLED=false

# AWS Batch execution — ALL Nextflow workflows run on AWS Batch by default
export NEXTFLOW_USE_AWS=true
export AWS_BATCH_QUEUE=galaxy-cloud-queue
export GPU_BATCH_QUEUE=galaxy-cloud-queue-gpu
export AWS_S3_BUCKET=biomate-nextflow-work
export AWS_DEFAULT_REGION=us-west-2
export AWS_ACCESS_KEY_ID=AKIAV2DX3XSKGYVKVDET
export AWS_SECRET_ACCESS_KEY=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

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
