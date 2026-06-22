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

# --- Failure/rollback notification (real guardrail, previously only documented) ---
# deploy.yml's header claimed "auto-rollback (L17)" and "notify" were enforced in
# this script — they were not. Step 6 below implements the rollback on the host;
# this EXIT trap implements the notification. SNS publish failures are non-fatal
# (logged as a warning) so a missing IAM perm can never block a deploy.
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:$AWS_REGION:399683337364:biomate-deploy-events}"
GITHUB_RUN_URL="${GITHUB_RUN_URL:-${GITHUB_SERVER_URL:+$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID}}"
DEPLOY_STATE="unknown"   # set by Step 6; read by the EXIT trap

notify() {
  local state="$1" detail="${2:-}" subject icon
  case "$state" in
    healthy)         icon="OK";  subject="[deploy ok] $ENVIRONMENT -> $TAG" ;;
    rolled_back)     icon="!!";  subject="[deploy ROLLED BACK] $ENVIRONMENT -> $TAG" ;;
    rollback_failed) icon="!!!"; subject="[deploy + ROLLBACK FAILED] $ENVIRONMENT -> $TAG" ;;
    *)               icon="XX";  subject="[deploy FAILED] $ENVIRONMENT -> $TAG" ;;
  esac
  if aws sns publish --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN" \
       --subject "${subject:0:99}" \
       --message "[$icon] BioMate deploy
Environment: $ENVIRONMENT
Tag:         $TAG
Instance:    ${INSTANCE_ID:-unknown}
State:       $state
${detail:+Detail:      $detail}
${GITHUB_RUN_URL:+Run:         $GITHUB_RUN_URL}" >/dev/null 2>&1; then
    echo "SNS notified ($state) -> $SNS_TOPIC_ARN"
  else
    echo "::warning:: SNS publish failed (state=$state) — check sns:Publish on the deploy role and that the topic has a confirmed subscription"
  fi
}

on_exit() {
  local rc=$?
  if [[ "$DEPLOY_STATE" == "unknown" ]]; then
    if [[ $rc -eq 0 ]]; then DEPLOY_STATE="healthy"; else DEPLOY_STATE="failed"; fi
  fi
  notify "$DEPLOY_STATE" "exit_code=$rc"
}
trap on_exit EXIT

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

  # base64-encode the command so multiline / quotes / $(...) survive the AWS CLI
  # `commands=["..."]` shorthand parser (which breaks on raw newlines and quotes).
  # The host decodes and runs it under bash (SSM RunShellScript runs as root).
  local cmd_b64
  cmd_b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')

  local cmd_id
  cmd_id=$(aws ssm send-command \
    --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"echo $cmd_b64 | base64 -d | bash\"]" \
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

      # Capture stdout into a global so callers can parse host-side markers
      # (e.g. Step 6's DEPLOY_RESULT=...), then show it.
      SSM_OUT=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$cmd_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
      echo "$SSM_OUT"

      return 0
    elif [[ "$status" == "Failed" || "$status" == "Cancelled" || "$status" == "TimedOut" ]]; then
      echo "✗ Command failed with status: $status"

      # Capture BOTH streams — a non-zero host exit (e.g. Step 6 rolling back
      # with exit 2/3) still carries its DEPLOY_RESULT marker on stdout.
      SSM_OUT=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$cmd_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
      SSM_ERR=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$cmd_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardErrorContent' \
        --output text 2>/dev/null || echo "")
      [[ -n "$SSM_OUT" ]] && echo "$SSM_OUT"
      echo "$SSM_ERR"

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

# Step 3: Ship docker-compose.deploy.yml to the host (from THIS checkout, via SSM)
echo "=== Step 3: Ship docker-compose.deploy.yml ==="
#
# Previously curled from GitHub `main`, but the file lives on the deploy branch
# (integration/next-phase), not main, so that 404'd. Shipping the local copy via
# SSM base64 removes the branch/network coupling and guarantees the host runs the
# exact compose from the deploying checkout — mirroring how Step 2 ships the loader.
COMPOSE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy/docker-compose.deploy.yml"
if [[ ! -f "$COMPOSE_SRC" ]]; then
  echo "Error: $COMPOSE_SRC not found"
  exit 1
fi
COMPOSE_B64=$(base64 < "$COMPOSE_SRC" | tr -d '\n')
# NOTE: keep this ssm_run command free of double quotes and $(...) — ssm_run wraps
# it in commands=["..."] and the AWS CLI shorthand parser breaks on either. The
# trailing grep -c prints the image-ref count as a sanity signal.
ssm_run "mkdir -p /opt/biomate && echo $COMPOSE_B64 | base64 -d > /opt/biomate/docker-compose.deploy.yml && grep -c 'image:' /opt/biomate/docker-compose.deploy.yml" \
  "Shipping docker-compose.deploy.yml"
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

# Step 6: Deploy + health check + auto-rollback (single host-side script)
echo "=== Step 6: Deploy + health check + auto-rollback ==="
#
# Run deploy, health check and rollback in ONE host script: the image that is
# currently in service is only known on the host, so capturing it there and
# reverting there is atomic — no need to round-trip the prior tag through the
# runner. The script prints a final `DEPLOY_RESULT=<state>` line that this
# script parses to drive messaging + the SNS notification. Host exit codes:
#   0 healthy · 1 failed (no prior image) · 2 rolled_back · 3 rollback_failed
DEPLOY_AND_VERIFY=$(cat <<HOSTEOF
set -u
cd /opt/biomate

NEW_BACKEND='$BACKEND_IMAGE'
NEW_FRONTEND='$FRONTEND_IMAGE'

# Capture the images currently in service so we can roll back to them. They are
# still present locally (we never prune — past-incident L3), so the revert is
# a fast \`compose up\` with no pull.
PREV_BACKEND=\$(docker inspect --format '{{.Config.Image}}' biomate-galaxy-deploy 2>/dev/null || echo '')
PREV_FRONTEND=\$(docker inspect --format '{{.Config.Image}}' biomate-frontend-deploy 2>/dev/null || echo '')
echo "prev_backend=\${PREV_BACKEND:-<none>}"
echo "prev_frontend=\${PREV_FRONTEND:-<none>}"

bring_up() {
  export BACKEND_IMAGE="\$1"
  export FRONTEND_IMAGE="\$2"
  docker compose -f docker-compose.deploy.yml up -d
}

health_ok() {
  local i
  for i in \$(seq 1 18); do   # up to ~90s
    if curl -fsS http://localhost:8081/api/version >/dev/null 2>&1 \\
       && curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

docker compose -f docker-compose.deploy.yml down --timeout 30 || true
bring_up "\$NEW_BACKEND" "\$NEW_FRONTEND"

if health_ok; then
  echo 'DEPLOY_RESULT=healthy'
  exit 0
fi

echo '*** New images failed health check — backend/frontend logs follow ***'
docker logs biomate-galaxy-deploy --tail 50 2>&1 || true
docker logs biomate-frontend-deploy --tail 50 2>&1 || true

if [ -n "\$PREV_BACKEND" ] && [ -n "\$PREV_FRONTEND" ] && [ "\$PREV_BACKEND" != "\$NEW_BACKEND" ]; then
  echo "Rolling back to \$PREV_BACKEND / \$PREV_FRONTEND"
  bring_up "\$PREV_BACKEND" "\$PREV_FRONTEND"
  if health_ok; then
    echo 'DEPLOY_RESULT=rolled_back'
    exit 2
  fi
  echo 'DEPLOY_RESULT=rollback_failed'
  exit 3
fi

echo 'DEPLOY_RESULT=failed_no_prev'
exit 1
HOSTEOF
)

# Don't let ssm_run's non-zero return (host rolled back -> exit 2/3) abort us
# before we parse the marker; SSM_OUT is captured even on a failed invocation.
set +e
ssm_run "$DEPLOY_AND_VERIFY" "Deploying + verifying + auto-rollback"
set -e

marker=$(printf '%s' "${SSM_OUT:-}" | grep -oE 'DEPLOY_RESULT=[a-z_]+' | tail -1 | cut -d= -f2)
case "$marker" in
  healthy)         DEPLOY_STATE="healthy" ;;
  rolled_back)     DEPLOY_STATE="rolled_back" ;;
  rollback_failed) DEPLOY_STATE="rollback_failed" ;;
  *)               DEPLOY_STATE="failed" ;;
esac
echo ""

# Step 7: Report (the EXIT trap publishes the SNS notification from DEPLOY_STATE)
case "$DEPLOY_STATE" in
  healthy)
    echo "=== Deploy Complete ==="
    echo "✓ Environment: $ENVIRONMENT"
    echo "✓ Tag: $TAG"
    echo "✓ Backend: $BACKEND_IMAGE"
    echo "✓ Frontend: $FRONTEND_IMAGE"
    echo ""
    echo "Instance: $INSTANCE_ID"
    echo "URL: http://stage-public.biomate.ai"
    ;;
  rolled_back)
    echo "=== Deploy FAILED — auto-rolled back to previous image ==="
    echo "✗ $TAG failed health check; previous image was restored and is healthy."
    echo "  Service is UP on the prior tag. Investigate $TAG before retrying."
    exit 2
    ;;
  rollback_failed)
    echo "=== Deploy FAILED — ROLLBACK ALSO FAILED (service may be DOWN) ==="
    echo "✗ Manual intervention required on $INSTANCE_ID."
    exit 3
    ;;
  *)
    echo "=== Deploy FAILED ==="
    echo "✗ $TAG failed health check; no previous image available to roll back to."
    exit 1
    ;;
esac
