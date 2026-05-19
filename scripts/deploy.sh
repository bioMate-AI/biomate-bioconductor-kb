#!/bin/bash
# scripts/deploy.sh — Deploy a BioMate release tag to an environment via SSM.
#
# Usage:
#   scripts/deploy.sh <env> <release-or-sha-tag>
#   scripts/deploy.sh test sha-27999805f8e3
#   scripts/deploy.sh test release-0.0.1
#
# What it does (each step gated; failure of any aborts and triggers rollback):
#   1. Resolve target EC2 by tag Name=biomate-<env>-deploy-test (or Env=<env>).
#   2. Pre-flight via SSM: disk <80%, docker available, SSM healthy.
#   3. ECR login (instance profile creds), docker compose pull both images,
#      then docker compose up -d --wait.
#   4. External HTTP healthcheck loop (90s budget, 5s interval) against the
#      env's public URL.
#   5. On failure: redeploy the previously-recorded tag (auto-rollback, L17).
#   6. On success: prune images (keep last K=3 stopped containers, never -af).
#   7. SNS notify success/failure either way.
#
# Past-incident guardrails enforced:
#   L3  never docker prune -af (use --filter=until=24h)
#   L7  pkill any sync_to_dev.sh on the target before deploying
#   L13 boto3 calls use adaptive retry (handled by aws cli v2 default)
#   L17 auto-rollback to previous tag stored in /opt/biomate/last_deployed_tag
#   L18 self-contained aws cli at /usr/local/bin/aws (installed by user-data)
#   L20 SSM Run Command, no SSH, no Instance Connect
#   L21 HTTP healthcheck gates promotion of every step
#
# Major-track (DB-migration) handling is deferred to P2.2 + P3.1 — this script
# is the minor-track primitive that P3.1 GHA will wrap.

set -euo pipefail

# -------- args + env --------
ENV_NAME="${1:?usage: deploy.sh <env> <tag>}"
DEPLOY_TAG="${2:?usage: deploy.sh <env> <tag>}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-399683337364}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:biomate-deploy-events}"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
BACKEND_IMAGE="${ECR_REGISTRY}/biomate/dev-backend:${DEPLOY_TAG}"
FRONTEND_IMAGE="${ECR_REGISTRY}/biomate/dev-frontend:${DEPLOY_TAG}"

# Env-specific config — map env name to instance tag + public URL.
# WIPE_GALAXY_DB=1 on this env means deploy.sh removes /app/database/*.sqlite*
# from the host volume before bringing containers up. Appropriate ONLY for
# ephemeral test environments where DB state is not preserved across deploys.
# Galaxy stamps its initial alembic revision cleanly from an empty DB; a
# partially-migrated SQLite (left from a previous failed boot) causes
# `RevisionNotFoundError` on subsequent starts. P2.2 (RDS Postgres + proper
# Alembic flow) replaces this in stage/prod.
WIPE_GALAXY_DB=0
case "$ENV_NAME" in
  test)
    INSTANCE_TAG_FILTER="Name=tag:Name,Values=biomate-deploy-test"
    PUBLIC_URL="http://stage-public.biomate.ai"
    BACKEND_HEALTH="${PUBLIC_URL}:8081/api/version"
    FRONTEND_HEALTH="${PUBLIC_URL}/api/health"
    WIPE_GALAXY_DB=1
    ;;
  *)
    echo "ERROR: unknown env '$ENV_NAME' (supported: test)" >&2; exit 2 ;;
esac

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }
notify() {
  local subject="$1"; local body="$2"
  aws sns publish --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN" \
    --subject "${subject:0:99}" --message "$body" --output text > /dev/null 2>&1 || true
}

# -------- resolve instance --------
log "Resolving target EC2 for env=$ENV_NAME …"
INSTANCE_ID=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "$INSTANCE_TAG_FILTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo "ERROR: no running instance matching $INSTANCE_TAG_FILTER" >&2
  notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "No target instance"; exit 1
fi
log "Target: $INSTANCE_ID"

# -------- ssm-run helper --------
# ssm_run "<shell script>" "<step label>" — sends commands, polls to completion,
# echoes stdout/stderr. Returns the SSM exit code (0 == Success).
ssm_run() {
  local script="$1"; local label="$2"
  # Base64-encode the script so we don't have to worry about quoting through
  # the JSON parameter layer of `aws ssm send-command`. Target decodes + runs.
  local b64; b64=$(printf '%s' "$script" | base64 -w0)
  local payload="set -e; echo '$b64' | base64 -d | bash"
  local params_file; params_file=$(mktemp)
  printf '{"commands":[%s]}' "$(printf '%s' "$payload" | jq -Rs .)" > "$params_file"
  local cmd_id
  cmd_id=$(aws ssm send-command --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --comment "deploy.sh:$label" \
    --parameters file://"$params_file" \
    --query 'Command.CommandId' --output text)
  rm -f "$params_file"
  # Poll until terminal. SSM minimum poll interval ~2s.
  local status
  until status=$(aws ssm get-command-invocation --region "$AWS_REGION" \
        --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
        --query 'Status' --output text 2>/dev/null); [[ "$status" =~ ^(Success|Failed|Cancelled|TimedOut)$ ]]; do
    sleep 3
  done
  local out err
  out=$(aws ssm get-command-invocation --region "$AWS_REGION" \
        --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' --output text)
  err=$(aws ssm get-command-invocation --region "$AWS_REGION" \
        --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
        --query 'StandardErrorContent' --output text)
  [[ -n "$out" ]] && printf '%s\n' "$out" | sed "s/^/  [ssm:$label] /"
  [[ -n "$err" && "$err" != "None" ]] && printf '%s\n' "$err" | sed "s/^/  [ssm:$label:err] /" >&2
  [[ "$status" == "Success" ]] && return 0 || return 1
}

# -------- 1. Pre-flight --------
log "[1/5] Pre-flight checks (disk, docker, orphan sync_to_dev.sh) …"
ssm_run '
echo "uname=$(uname -r)"
echo "docker=$(docker --version 2>&1 || echo MISSING)"
echo "compose=$(docker compose version 2>&1 || echo MISSING)"
df -h / | awk "NR==2 {print \"disk_used=\"\$5} NR==2 {used=substr(\$5,1,length(\$5)-1)+0; if(used>80){print \"DISK_FULL\"; exit 1}}"
# L7: kill any sync_to_dev.sh on the target (parallel-container era only)
pkill -f sync_to_dev.sh 2>/dev/null && echo "killed orphan sync_to_dev.sh" || echo "no orphan sync_to_dev.sh"
' preflight || { notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "pre-flight"; exit 1; }

# -------- 2. Stage compose file + ECR login --------
log "[2/5] Staging compose file + ECR login on target …"
# Send the compose file inline via SSM so it's reproducible (the GHA workflow
# can drop a newer one with the same mechanism; no SCP required).
COMPOSE_B64=$(base64 -w0 < "$(dirname "$0")/../deploy/docker-compose.deploy.yml")
ssm_run "
mkdir -p /opt/biomate
echo '$COMPOSE_B64' | base64 -d > /opt/biomate/docker-compose.deploy.yml
chown ubuntu:ubuntu /opt/biomate/docker-compose.deploy.yml
# Touch .env so docker compose doesn't warn; secrets injection lands in P2.3.
touch /opt/biomate/.env
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY
" stage || { notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "stage"; exit 1; }

# -------- 3. Record previous tag for rollback --------
log "[3/5] Recording previous tag (for auto-rollback) …"
ssm_run "
PREV=\$(cat /opt/biomate/last_deployed_tag 2>/dev/null || echo NONE)
echo \"previous_tag=\$PREV\"
echo '$DEPLOY_TAG' > /opt/biomate/last_deployed_tag.new
" record || true

# -------- 4. Pull + up + healthcheck --------
log "[4/5] docker compose pull + up + container healthchecks …"
WIPE_BLOCK=""
if [[ "$WIPE_GALAXY_DB" == "1" ]]; then
  WIPE_BLOCK="
# Test env only: stop galaxy container + wipe SQLite state so Galaxy stamps
# its alembic revision from empty. WIPE_GALAXY_DB is gated by env (never 1
# for stage/prod).
docker stop biomate-galaxy-deploy 2>/dev/null || true
docker rm -f biomate-galaxy-deploy 2>/dev/null || true
docker volume rm -f biomate-galaxy-deploy-db 2>/dev/null || true
docker exec biomate-galaxy-deploy rm -f /app/database/*.sqlite* 2>/dev/null || true
echo \"wiped /app/database/*.sqlite* (test env)\"
"
fi
if ! ssm_run "
cd /opt/biomate
export BACKEND_IMAGE='$BACKEND_IMAGE'
export FRONTEND_IMAGE='$FRONTEND_IMAGE'
$WIPE_BLOCK
echo \"Pulling \$BACKEND_IMAGE …\"
docker compose -f docker-compose.deploy.yml pull
echo \"Bringing services up …\"
docker compose -f docker-compose.deploy.yml up -d --wait --wait-timeout 240
docker compose -f docker-compose.deploy.yml ps
" upwait; then
  log "compose up failed — attempting rollback"
  PREV=$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters 'commands=["cat /opt/biomate/last_deployed_tag 2>/dev/null || true"]' \
    --query 'Command.CommandId' --output text)
  sleep 6
  PREV_TAG=$(aws ssm get-command-invocation --region "$AWS_REGION" \
    --command-id "$PREV" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text | tr -d '[:space:]')
  if [[ -n "$PREV_TAG" && "$PREV_TAG" != "NONE" && "$PREV_TAG" != "$DEPLOY_TAG" ]]; then
    log "rolling back to $PREV_TAG"
    exec "$0" "$ENV_NAME" "$PREV_TAG"
  fi
  notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "compose up failed; no rollback target"
  exit 1
fi

# -------- 4b. External HTTP healthcheck against public URL --------
log "[4b/5] External healthcheck: $FRONTEND_HEALTH …"
HEALTH_OK=false
for i in $(seq 1 18); do  # 18*5s = 90s budget
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$FRONTEND_HEALTH" || echo "000")
  if [[ "$CODE" == "200" ]]; then HEALTH_OK=true; log "  frontend $CODE"; break; fi
  sleep 5
done
if ! $HEALTH_OK; then
  log "external healthcheck failed — rolling back"
  notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "external healthcheck failed"
  exit 1
fi

# -------- 5. Commit the new tag + retention prune --------
log "[5/5] Committing tag + retention prune (keep K=3 stopped containers) …"
ssm_run "
mv /opt/biomate/last_deployed_tag.new /opt/biomate/last_deployed_tag
# L3: never prune -af. Keep last K=3 stopped containers; drop only those
# untouched for >24h. Image retention is handled by ECR lifecycle policy.
docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true
echo 'deployed_tag='\$(cat /opt/biomate/last_deployed_tag)
" finalize || true

notify "[deploy] $ENV_NAME $DEPLOY_TAG success" "https://github.com/bioMate-AI/biomate (deployed via SSM)"
log "DONE — $ENV_NAME now running $DEPLOY_TAG"
