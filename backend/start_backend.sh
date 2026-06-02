#!/bin/bash
# Start Galaxy backend with billing environment variables
set -e
cd /home/yzhang/biomate/backend

# Core Galaxy settings
export ANTHROPIC_API_KEY=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
export GEMINI_API_KEY=AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI

# Regulatory-LLM backend selection — frontier API as primary until BioMate
# v6 (Qwen3-8B + LoRA) is proven on Modal/vLLM. GPT-5 hit 90.0% macro on the
# n=100 9-checker eval (vs Sonnet 4.6 87.1%, Opus 4.8 85.9%); per-IND-paragraph
# cost ~$0.04. Override with claude-sonnet-4-6 / claude-opus-4-8 / gemini-3.1-pro-preview.
# Set to empty string to fall through to Modal/vLLM (when those are deployed).
export REGULATORY_LLM_FRONTIER_MODEL=${REGULATORY_LLM_FRONTIER_MODEL:-gpt-5}
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT=true
export GALAXY_CONFIG_FILE=lib/galaxy/config/sample/galaxy.yml.sample
export GALAXY_CONFIG_DATABASE_CONNECTION=sqlite:////tmp/biomate_connection_formal.sqlite
# Install DB shares same connection (tool shed tables created by manage_db.sh init on first run)
export GALAXY_CONFIG_INSTALL_DATABASE_CONNECTION=sqlite:////tmp/biomate_connection_formal.sqlite

# Billing settings
# LOCAL DEV:  Redis = biomate-redis-test Docker container on port 6379
#             Lago  = lago-api Docker container on port 3010
# PRODUCTION: Redis = redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
#             Lago  = http://35.86.137.71:3000  key=01b71711-be39-49af-8d14-87a4ee827157
#             Java  = http://35.86.137.71:8080  JAVA_BILLING_ENABLED=true
export BILLING_DEV_MODE=false
export BILLING_INTERNAL_KEY=w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE
export JWT_SECRET="grhFb+sJVOuSvQXQrxjjbSWWBby/w0oQFvg9tVv/KSc="
export REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379

# Lago billing — AWS production instance
export LAGO_API_URL=http://35.86.137.71:3000
export LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
export LAGO_WEBHOOK_SECRET=9ef2c8b4-9d99-47f5-98d8-520a22ed3bde

# Java billing service
export JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
export JAVA_BILLING_ENABLED=true

# AWS Batch execution — ALL Nextflow workflows run on AWS Batch by default
export NEXTFLOW_USE_AWS=true
export AWS_BATCH_QUEUE=galaxy-cloud-queue
export GPU_BATCH_QUEUE=galaxy-cloud-queue-gpu
export AWS_S3_BUCKET=biomate-nextflow-work
export AWS_DEFAULT_REGION=us-west-2
export AWS_ACCESS_KEY_ID=AKIAV2DX3XSKLG5H4HQ6
# AWS_SECRET_ACCESS_KEY must be set in the environment before running this script
# Retrieve from: AWS Console → IAM → Users → biomate-admin → Security credentials
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"

# CryoSPARC direct executor — server-level connection config (shared infrastructure)
# Each user's license key is stored separately in their credential vault, NOT here.
export CRYOSPARC_HOST=100.54.207.255
export CRYOSPARC_PORT=30000
export CRYOSPARC_EMAIL=admin@biomate.ai
export CRYOSPARC_PASSWORD=BioMate2026!
export CRYOSPARC_AMI_ID=ami-008607f719aaac1b0
export CRYOSPARC_INSTANCE_REGION=us-east-1
export CRYOSPARC_INSTANCE_TYPE=g6.2xlarge
export CRYOSPARC_PROJECT_DIR=/home/ubuntu/cryosparc_projects
export CRYOSPARC_SSH_KEY=/home/yzhang/.ssh/cryosparc-benchmark.pem
export CRYOSPARC_MOVIES_S3=s3://biomate-cryo-data/empiar-10028/Micrographs

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
