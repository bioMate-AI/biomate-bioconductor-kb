#!/usr/bin/env bash
#
# Deploy script for BioMate
#
# Usage:
#   deploy.sh <environment> <tag>
#
# Arguments:
#   environment: test, staging, or production
#   tag: ECR image tag (sha-*, release-*, beta-*, dev-*, or <branch>-latest)
#
# Environment Variables (Optional - Backward Compatible):
#   If these are set (from GitHub Secrets), they will be injected into /opt/biomate/.env
#   If not set, the script preserves existing /opt/biomate/.env file (backward compatible)
#
#   ANTHROPIC_API_KEY, JWT_SECRET, SESSION_SECRET, BILLING_INTERNAL_KEY,
#   DATABASE_URL, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION,
#   S3_BUCKET_NAME, GALAXY_API_KEY, REDIS_URL, LAGO_API_KEY, etc.
#
# Backward Compatibility:
#   - If NO GitHub Secrets are configured → uses existing /opt/biomate/.env (old method)
#   - If GitHub Secrets ARE configured → merges them with existing .env (new method)
#   - Never overwrites existing .env unless secrets are explicitly provided
#

set -euo pipefail

# Parse arguments
ENVIRONMENT="${1:-test}"
TAG="${2:-}"

if [[ -z "$TAG" ]]; then
  echo "Error: Image tag is required"
  echo "Usage: $0 <environment> <tag>"
  exit 1
fi

# AWS region mapping
case "$ENVIRONMENT" in
  test)
    AWS_REGION="${AWS_REGION:-us-west-2}"
    INSTANCE_TAG_KEY="Env"
    INSTANCE_TAG_VALUE="test"
    ;;
  staging)
    AWS_REGION="${AWS_REGION:-us-west-2}"
    INSTANCE_TAG_KEY="Env"
    INSTANCE_TAG_VALUE="staging"
    ;;
  production)
    AWS_REGION="${AWS_REGION:-us-west-2}"
    INSTANCE_TAG_KEY="Env"
    INSTANCE_TAG_VALUE="production"
    ;;
  *)
    echo "Error: Unknown environment '$ENVIRONMENT'"
    exit 1
    ;;
esac

ECR_REGISTRY="${ECR_REGISTRY:-399683337364.dkr.ecr.$AWS_REGION.amazonaws.com}"
BACKEND_REPO="${BACKEND_REPO:-biomate/dev-backend}"
FRONTEND_REPO="${FRONTEND_REPO:-biomate/dev-frontend}"

BACKEND_IMAGE="$ECR_REGISTRY/$BACKEND_REPO:$TAG"
FRONTEND_IMAGE="$ECR_REGISTRY/$FRONTEND_REPO:$TAG"

echo "=== BioMate Deploy ==="
echo "Environment: $ENVIRONMENT"
echo "Tag: $TAG"
echo "Backend: $BACKEND_IMAGE"
echo "Frontend: $FRONTEND_IMAGE"
echo ""

# Find target EC2 instance(s) by tag
echo "Finding EC2 instances with tag $INSTANCE_TAG_KEY=$INSTANCE_TAG_VALUE..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters \
    "Name=tag:$INSTANCE_TAG_KEY,Values=$INSTANCE_TAG_VALUE" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
  echo "Error: No running instances found with tag $INSTANCE_TAG_KEY=$INSTANCE_TAG_VALUE"
  exit 1
fi

INSTANCE_ID=$(echo "$INSTANCE_IDS" | head -n1)
echo "Found instance: $INSTANCE_ID"
echo ""

# Helper function to run commands via SSM
ssm_run() {
  local cmd="$1"
  local description="${2:-Running command}"

  echo "$description..."

  local cmd_id
  cmd_id=$(aws ssm send-command \
    --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$cmd\"]" \
    --query 'Command.CommandId' \
    --output text)

  if [[ -z "$cmd_id" ]]; then
    echo "Error: Failed to send SSM command"
    exit 1
  fi

  # Wait for command to complete (max 5 minutes)
  local timeout=300
  local elapsed=0
  local status=""

  while [[ $elapsed -lt $timeout ]]; do
    status=$(aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --command-id "$cmd_id" \
      --instance-id "$INSTANCE_ID" \
      --query 'Status' \
      --output text 2>/dev/null || echo "Pending")

    if [[ "$status" == "Success" ]]; then
      echo "✓ Command completed successfully"

      # Show output
      aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$cmd_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' \
        --output text

      return 0
    elif [[ "$status" == "Failed" || "$status" == "Cancelled" || "$status" == "TimedOut" ]]; then
      echo "✗ Command failed with status: $status"

      # Show error output
      aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$cmd_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardErrorContent' \
        --output text

      return 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "✗ Command timed out after ${timeout}s"
  return 1
}

# Step 1: Backup existing .env (if it exists)
echo "=== Step 1: Backup existing .env ==="
ssm_run "if [ -f /opt/biomate/.env ]; then cp /opt/biomate/.env /opt/biomate/.env.backup.\$(date +%Y%m%d_%H%M%S); echo 'Backed up existing .env'; else echo 'No existing .env found'; fi" \
  "Backing up existing .env"
echo ""

# Step 2: Materialize runtime env from AWS Secrets Manager (GitLab-style external config)
echo "=== Step 2: Load runtime env from Secrets Manager ==="
#
# Runtime env VALUES live in AWS Secrets Manager at <env>/biomate/galaxy-env; the
# repo holds only variable NAMES (deploy/biomate.env.manifest). Values never transit
# GitHub, the repo, or a developer workstation. The deploy host pulls them with its
# EC2 instance role (BioMateEc2DeployRole has secretsmanager:GetSecretValue on
# <env>/biomate/*) and per-key upserts them into /opt/biomate/.env — host-only keys
# are preserved. See scripts/load_env_from_secrets.sh + deploy/biomate.env.manifest.
#
# The loader is shipped to the host via SSM (base64-inlined; the instance role has no
# S3 read, so no S3 hop is used). If the secret is missing/unreadable we fall back —
# LOUDLY — to the host-managed /opt/biomate/.env so a not-yet-provisioned env still
# deploys. Containers (Step 6) start AFTER this, so they read the refreshed .env.
case "$ENVIRONMENT" in
  production) SECRETS_ENV="prod" ;;
  *)          SECRETS_ENV="$ENVIRONMENT" ;;
esac
LOAD_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load_env_from_secrets.sh"
if [[ -f "$LOAD_SCRIPT_PATH" ]]; then
  LOAD_B64=$(base64 < "$LOAD_SCRIPT_PATH" | tr -d '\n')
  if ssm_run "echo $LOAD_B64 | base64 -d > /tmp/load_env_from_secrets.sh && BIOMATE_ENV='$SECRETS_ENV' bash /tmp/load_env_from_secrets.sh; rc=\$?; rm -f /tmp/load_env_from_secrets.sh; exit \$rc" \
       "Loading env from Secrets Manager ($SECRETS_ENV/biomate/galaxy-env)"; then
    echo "✓ Runtime env materialized from Secrets Manager"
  else
    echo "::warning:: Secrets Manager load failed for $SECRETS_ENV/biomate/galaxy-env — falling back to host-managed /opt/biomate/.env"
    ssm_run "if [ -f /opt/biomate/.env ]; then echo \"env present: \$(grep -c '=' /opt/biomate/.env) var(s)\"; else echo '::error:: /opt/biomate/.env missing AND Secrets Manager load failed — app will not start'; exit 1; fi" \
      "Verifying host /opt/biomate/.env (fallback)"
  fi
else
  echo "::warning:: $LOAD_SCRIPT_PATH not found — using host-managed /opt/biomate/.env"
  ssm_run "if [ -f /opt/biomate/.env ]; then echo \"env present: \$(grep -c '=' /opt/biomate/.env) var(s)\"; else echo '::error:: /opt/biomate/.env missing — app will not start'; exit 1; fi" \
    "Verifying host /opt/biomate/.env"
fi
echo ""

# Step 3: Pull docker-compose.deploy.yml
echo "=== Step 3: Pull docker-compose.deploy.yml ==="
ssm_run "
  set -e
  mkdir -p /opt/biomate
  cd /opt/biomate

  # Download latest docker-compose file from repo
  curl -fsSL https://raw.githubusercontent.com/bioMate-AI/biomate/main/deploy/docker-compose.deploy.yml -o docker-compose.deploy.yml

  echo 'Downloaded docker-compose.deploy.yml'
" "Downloading docker-compose.deploy.yml"
echo ""

# Step 4: Login to ECR
echo "=== Step 4: Login to ECR ==="
ssm_run "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY" \
  "Logging into ECR"
echo ""

# Step 5: Pull images
echo "=== Step 5: Pull Docker images ==="
ssm_run "docker pull $BACKEND_IMAGE" "Pulling backend image"
ssm_run "docker pull $FRONTEND_IMAGE" "Pulling frontend image"
echo ""

# Step 6: Deploy with compose
echo "=== Step 6: Deploy containers ==="
ssm_run "
  set -e
  cd /opt/biomate

  export BACKEND_IMAGE='$BACKEND_IMAGE'
  export FRONTEND_IMAGE='$FRONTEND_IMAGE'

  # Stop old containers gracefully
  docker compose -f docker-compose.deploy.yml down --timeout 30 || true

  # Start new containers
  docker compose -f docker-compose.deploy.yml up -d

  echo 'Containers deployed successfully'
" "Deploying with docker compose"
echo ""

# Step 7: Health check
echo "=== Step 7: Health check ==="
echo "Waiting 30s for containers to start..."
sleep 30

ssm_run "
  # Check backend health
  if curl -fsS http://localhost:8081/api/version >/dev/null 2>&1; then
    echo '✓ Backend is healthy'
  else
    echo '✗ Backend health check failed'
    docker logs biomate-galaxy-deploy --tail 50
    exit 1
  fi

  # Check frontend health
  if curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; then
    echo '✓ Frontend is healthy'
  else
    echo '✗ Frontend health check failed'
    docker logs biomate-frontend-deploy --tail 50
    exit 1
  fi
" "Running health checks"
echo ""

echo "=== Deploy Complete ==="
echo "✓ Environment: $ENVIRONMENT"
echo "✓ Tag: $TAG"
echo "✓ Backend: $BACKEND_IMAGE"
echo "✓ Frontend: $FRONTEND_IMAGE"
echo ""
echo "Instance: $INSTANCE_ID"
echo "URL: http://stage-public.biomate.ai"
