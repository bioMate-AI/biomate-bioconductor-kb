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

# Step 2: Merge secrets (backward compatible)
echo "=== Step 2: Configure environment variables (backward compatible) ==="

# Check if ANY GitHub Secrets are provided
SECRETS_PROVIDED=false
if [[ -n "${ANTHROPIC_API_KEY:-}" ]] || \
   [[ -n "${JWT_SECRET:-}" ]] || \
   [[ -n "${SESSION_SECRET:-}" ]] || \
   [[ -n "${BILLING_INTERNAL_KEY:-}" ]]; then
  SECRETS_PROVIDED=true
fi

if [[ "$SECRETS_PROVIDED" == "true" ]]; then
  echo "GitHub Secrets detected → Merging with existing .env..."

  # Build env file with secrets (only set non-empty values)
  ENV_CONTENT=""

  # Critical secrets
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && ENV_CONTENT+="ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}\n"
  [[ -n "${JWT_SECRET:-}" ]] && ENV_CONTENT+="JWT_SECRET=${JWT_SECRET}\n"
  [[ -n "${SESSION_SECRET:-}" ]] && ENV_CONTENT+="SESSION_SECRET=${SESSION_SECRET}\n"
  [[ -n "${BILLING_INTERNAL_KEY:-}" ]] && ENV_CONTENT+="BILLING_INTERNAL_KEY=${BILLING_INTERNAL_KEY}\n"
  [[ -n "${DATABASE_URL:-}" ]] && ENV_CONTENT+="DATABASE_URL=${DATABASE_URL}\n"

  # AWS secrets
  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && ENV_CONTENT+="AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}\n"
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] && ENV_CONTENT+="AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}\n"
  [[ -n "${AWS_REGION:-}" ]] && ENV_CONTENT+="AWS_REGION=${AWS_REGION}\n"
  [[ -n "${S3_BUCKET_NAME:-}" ]] && ENV_CONTENT+="S3_BUCKET_NAME=${S3_BUCKET_NAME}\n"

  # Galaxy secrets
  [[ -n "${GALAXY_API_KEY:-}" ]] && ENV_CONTENT+="GALAXY_API_KEY=${GALAXY_API_KEY}\n"
  [[ -n "${GALAXY_URL:-}" ]] && ENV_CONTENT+="GALAXY_URL=${GALAXY_URL}\n"

  # Optional secrets
  [[ -n "${REDIS_URL:-}" ]] && ENV_CONTENT+="REDIS_URL=${REDIS_URL}\n"
  [[ -n "${LAGO_API_KEY:-}" ]] && ENV_CONTENT+="LAGO_API_KEY=${LAGO_API_KEY}\n"
  [[ -n "${OPENAI_API_KEY:-}" ]] && ENV_CONTENT+="OPENAI_API_KEY=${OPENAI_API_KEY}\n"
  [[ -n "${GEMINI_API_KEY:-}" ]] && ENV_CONTENT+="GEMINI_API_KEY=${GEMINI_API_KEY}\n"
  [[ -n "${NVIDIA_API_KEY:-}" ]] && ENV_CONTENT+="NVIDIA_API_KEY=${NVIDIA_API_KEY}\n"
  [[ -n "${BIOLM_API_KEY:-}" ]] && ENV_CONTENT+="BIOLM_API_KEY=${BIOLM_API_KEY}\n"

  # Encryption secrets
  [[ -n "${ENCRYPTION_KEY:-}" ]] && ENV_CONTENT+="ENCRYPTION_KEY=${ENCRYPTION_KEY}\n"
  [[ -n "${CSRF_SECRET:-}" ]] && ENV_CONTENT+="CSRF_SECRET=${CSRF_SECRET}\n"

  # Create temporary file with secrets
  TEMP_ENV="/tmp/.env.secrets.$$"
  echo -e "$ENV_CONTENT" > "$TEMP_ENV"

  # Upload secrets to EC2
  aws s3 cp "$TEMP_ENV" "s3://biomate-deploy-temp/.env.secrets" --region "$AWS_REGION"

  # Merge on EC2 (preserve existing values, add new ones)
  ssm_run "
    set -e
    mkdir -p /opt/biomate
    cd /opt/biomate

    # Download secrets from S3
    aws s3 cp s3://biomate-deploy-temp/.env.secrets /tmp/.env.secrets --region $AWS_REGION

    # If .env exists, merge (new secrets override old values)
    if [ -f .env ]; then
      # Load existing .env
      cp .env .env.old

      # Merge: existing .env + new secrets (secrets take precedence)
      cat .env.old /tmp/.env.secrets | sort -u > .env.merged
      mv .env.merged .env

      echo 'Merged GitHub Secrets with existing .env'
    else
      # No existing .env, just use secrets
      mv /tmp/.env.secrets .env
      echo 'Created new .env from GitHub Secrets'
    fi

    chmod 600 .env
    rm -f /tmp/.env.secrets .env.old
  " "Merging secrets with existing .env"

  # Cleanup
  rm -f "$TEMP_ENV"
  aws s3 rm "s3://biomate-deploy-temp/.env.secrets" --region "$AWS_REGION" 2>/dev/null || true

else
  echo "No GitHub Secrets detected → Using existing /opt/biomate/.env (backward compatible mode)"
  echo "If you want to use GitHub Secrets, configure them at:"
  echo "https://github.com/bioMate-AI/biomate/settings/secrets/actions"
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
