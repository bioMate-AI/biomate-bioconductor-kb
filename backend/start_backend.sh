#!/bin/bash
# Start Galaxy backend with billing environment variables
set -e
cd /home/yzhang/biomate/backend

# Core Galaxy settings
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

exec .venv/bin/gunicorn \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 \
  --workers 1 \
  --log-level info
