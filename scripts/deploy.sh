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
    INSTANCE_TAG_KEY="biomate:env"
    INSTANCE_TAG_VALUE="test"
    ;;
  staging)
    AWS_REGION="${AWS_REGION:-us-west-2}"
    INSTANCE_TAG_KEY="biomate:env"
    INSTANCE_TAG_VALUE="staging"
    ;;
  production)
    AWS_REGION="${AWS_REGION:-us-west-2}"
    INSTANCE_TAG_KEY="biomate:env"
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

# Step 2: Upsert pre-rendered managed env into /opt/biomate/.env
echo "=== Step 2: Configure environment variables (manifest-driven) ==="
#
# The managed env file is rendered upstream (scripts/render_env_manifest.sh,
# invoked by deploy.yml) from deploy/biomate.env.manifest, using the APP's
# secret values. It is passed here via $MANAGED_ENV_FILE. This split is
# deliberate: rendering needs the app's AWS_ACCESS_KEY_ID as a *value to write*,
# while deploy.sh's own aws calls below must use the OIDC deploy-role creds —
# same env var name, two identities, so they cannot share one process.
#
# We upsert per-key into the host .env (managed value overrides; host-only keys
# NOT in the manifest — EMAIL_PASS, GALAXY_MASTER_API_KEY, LAGO_WEBHOOK_SECRET,
# etc. — are preserved). Replaces the old `cat | sort -u` merge, which produced
# duplicate keys and reordered the file.

if [[ -z "${MANAGED_ENV_FILE:-}" || ! -s "${MANAGED_ENV_FILE:-}" ]]; then
  # No managed env rendered (operator hasn't opted into GitHub Secrets yet, or
  # render produced nothing) → preserve existing /opt/biomate/.env.
  echo "No managed env file provided → keeping existing /opt/biomate/.env (backward compatible)."
  echo "To manage env via CI/CD, set values in GitHub Secrets/Variables; see deploy/biomate.env.manifest."
else
  MANAGED_COUNT=$(grep -c '=' "$MANAGED_ENV_FILE" || true)
  echo "Upserting $MANAGED_COUNT managed env var(s) into /opt/biomate/.env"

  # Transport to EC2 via the deploy temp bucket (runner has no SSH path).
  aws s3 cp "$MANAGED_ENV_FILE" "s3://biomate-deploy-temp/.env.managed" --region "$AWS_REGION"

  ssm_run "
    set -e
    mkdir -p /opt/biomate
    cd /opt/biomate
    aws s3 cp s3://biomate-deploy-temp/.env.managed /tmp/.env.managed --region $AWS_REGION
    touch .env

    # Per-key upsert: drop any existing line for each managed key, then append
    # the fresh managed block. Host-only keys (not in the managed file) survive.
    while IFS='=' read -r k _; do
      [ -n \"\$k\" ] && sed -i \"/^\${k}=/d\" .env
    done < /tmp/.env.managed
    cat /tmp/.env.managed >> .env

    chmod 600 .env
    rm -f /tmp/.env.managed
    echo \"Upserted managed vars; .env now has \$(wc -l < .env) line(s)\"
  " "Upserting managed env vars into /opt/biomate/.env"

  aws s3 rm "s3://biomate-deploy-temp/.env.managed" --region "$AWS_REGION" 2>/dev/null || true
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
