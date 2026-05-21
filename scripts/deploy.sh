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
RDS_SECRET_NAME=""    # if set, deploy fetches this from Secrets Manager and
                      # writes GALAXY_CONFIG_DATABASE_CONNECTION to /opt/biomate/.env
case "$ENV_NAME" in
  test)
    INSTANCE_TAG_FILTER="Name=tag:Name,Values=biomate-deploy-test"
    PUBLIC_URL="http://stage-public.biomate.ai"
    BACKEND_HEALTH="${PUBLIC_URL}:8081/api/version"
    FRONTEND_HEALTH="${PUBLIC_URL}/api/health"
    # test env is ephemeral: drop+recreate the Galaxy schema on every deploy.
    # Galaxy's migration code refuses to boot against a non-empty DB that has
    # no alembic_version table (NoVersionTableError) — which is exactly what a
    # previous half-failed boot leaves behind. The SQLite wipe used to handle
    # this on the SQLite path; the Postgres equivalent is to drop schema public.
    WIPE_GALAXY_DB=1
    RDS_SECRET_NAME="test/biomate/rds-galaxy"
    # Consolidated KEY=VAL JSON secret. Galaxy's billing module + several other
    # subsystems require these env vars at import time; absent them, gunicorn
    # workers crash before binding the port. Future additions (JWT, Stripe,
    # etc.) go into this same secret without code change.
    ENV_SECRET_NAME="test/biomate/galaxy-env"
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
  # Capture stderr separately so we can fail loudly when SendCommand is
  # denied (otherwise an empty cmd_id would leave us polling forever — that's
  # exactly what happened on the first GHA run: AccessDenied on SendCommand
  # caused ssm_run to spin until the 20-min GHA job-timeout fired).
  local cmd_id err_file
  err_file=$(mktemp)
  cmd_id=$(aws ssm send-command --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --comment "deploy.sh:$label" \
    --parameters file://"$params_file" \
    --query 'Command.CommandId' --output text 2>"$err_file")
  local send_rc=$?
  rm -f "$params_file"
  if [[ $send_rc -ne 0 || -z "$cmd_id" || "$cmd_id" == "None" ]]; then
    echo "ERROR: ssm send-command failed for label=$label (rc=$send_rc)" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi
  rm -f "$err_file"
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
set -e
echo "uname=$(uname -r)"
echo "docker=$(docker --version 2>&1 || echo MISSING)"
echo "compose=$(docker compose version 2>&1 || echo MISSING)"
USED=$(df / | awk "NR==2 {sub(/%/,\"\",\$5); print \$5+0}")
echo "disk_used=${USED}%"
if [ "$USED" -gt 80 ]; then
  echo "DISK_FULL ($USED% > 80%) — aborting deploy"
  exit 1
fi
# L7: kill any sync_to_dev.sh on the target (parallel-container era only)
pkill -f sync_to_dev.sh 2>/dev/null && echo "killed orphan sync_to_dev.sh" || echo "no orphan sync_to_dev.sh"
' preflight || { notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "pre-flight"; exit 1; }

# -------- 2. Stage compose file + ECR login --------
log "[2/5] Staging compose file + ECR login on target …"
# Send the compose file inline via SSM so it's reproducible (the GHA workflow
# can drop a newer one with the same mechanism; no SCP required).
COMPOSE_B64=$(base64 -w0 < "$(dirname "$0")/../deploy/docker-compose.deploy.yml")
RDS_SECRET_BLOCK=""
if [[ -n "$RDS_SECRET_NAME" ]]; then
  RDS_SECRET_BLOCK="
# P2.2: fetch Galaxy DB connection URL from Secrets Manager and write into
# /opt/biomate/.env. Galaxy reads GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION
# as the database_connection override (the OVERRIDE_ prefix is required to
# beat galaxy.yml.template's pre-populated sqlite default — see
# lib/galaxy/util/properties.py:116-124).
# EC2 instance-profile creds gate the read (BioMateEc2DeployRole has
# secretsmanager:GetSecretValue for THIS arn only).
DB_URL=\$(aws secretsmanager get-secret-value --region $AWS_REGION \
  --secret-id $RDS_SECRET_NAME --query SecretString --output text \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"url\"])')
# Drop any prior DATABASE_CONNECTION line (old name or new), then append fresh.
grep -vE '^GALAXY_CONFIG(_OVERRIDE)?_DATABASE_CONNECTION=' /opt/biomate/.env 2>/dev/null > /opt/biomate/.env.new || true
echo \"GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION=\$DB_URL\" >> /opt/biomate/.env.new
mv /opt/biomate/.env.new /opt/biomate/.env
chown ubuntu:ubuntu /opt/biomate/.env
echo \"OVERRIDE_DATABASE_CONNECTION sourced from $RDS_SECRET_NAME\"
"
fi
ENV_SECRET_BLOCK=""
if [[ -n "${ENV_SECRET_NAME:-}" ]]; then
  # Fetch the KEY=VAL JSON secret and append each pair to .env. Existing keys
  # with the same name are dropped first (idempotent). One Secrets Manager
  # fetch covers all env-var secrets; adding more is a `aws secretsmanager
  # update-secret` away, no deploy.sh change needed.
  ENV_SECRET_BLOCK="
ENV_JSON=\$(aws secretsmanager get-secret-value --region $AWS_REGION \
  --secret-id $ENV_SECRET_NAME --query SecretString --output text)
KEYS=\$(echo \"\$ENV_JSON\" | python3 -c 'import sys,json; print(\"\\n\".join(json.load(sys.stdin).keys()))')
# Drop any prior copies of these keys from .env
TMP_ENV=/opt/biomate/.env.next
cp /opt/biomate/.env \$TMP_ENV
for k in \$KEYS; do
  grep -vE \"^\$k=\" \$TMP_ENV > \$TMP_ENV.f && mv \$TMP_ENV.f \$TMP_ENV
done
# Append fresh values
echo \"\$ENV_JSON\" | python3 -c 'import sys,json
for k,v in json.load(sys.stdin).items(): print(f\"{k}={v}\")' >> \$TMP_ENV
mv \$TMP_ENV /opt/biomate/.env
chown ubuntu:ubuntu /opt/biomate/.env
echo \"galaxy env vars sourced from $ENV_SECRET_NAME (\$(echo \$KEYS | wc -w) keys)\"
"
fi
ssm_run "
mkdir -p /opt/biomate
echo '$COMPOSE_B64' | base64 -d > /opt/biomate/docker-compose.deploy.yml
chown ubuntu:ubuntu /opt/biomate/docker-compose.deploy.yml
# Touch .env so docker compose doesn't warn (it gets rewritten below if RDS_SECRET_NAME is set).
touch /opt/biomate/.env
$RDS_SECRET_BLOCK
$ENV_SECRET_BLOCK
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

# -------- 3b. (test-env only) Wipe Galaxy Postgres schema --------
# Galaxy expects either:
#   - an empty DB                              → bootstraps tables + stamps alembic
#   - a populated DB with alembic_version      → runs upgrade
#   - a populated DB WITHOUT alembic_version   → hard error (NoVersionTableError)
# The third state is what a previous half-failed boot leaves behind, and it
# bricks every subsequent deploy. For the ephemeral test env we recover by
# dropping `schema public` so Galaxy is back in the empty-DB state. Postgres
# client runs via the official image (EC2 host doesn't need psql installed).
if [[ "$WIPE_GALAXY_DB" == "1" && -n "$RDS_SECRET_NAME" ]]; then
  log "[3b/5] Wiping Galaxy schema (WIPE_GALAXY_DB=1 on $ENV_NAME) …"
  ssm_run "
DB_URL=\$(aws secretsmanager get-secret-value --region $AWS_REGION \
  --secret-id $RDS_SECRET_NAME --query SecretString --output text \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"url\"])')
# Convert sqlalchemy-style postgresql+psycopg2:// to plain postgresql:// for psql
PSQL_URL=\$(echo \"\$DB_URL\" | sed -E 's|^postgresql\+psycopg2://|postgresql://|')
docker run --rm postgres:15-alpine psql \"\$PSQL_URL\" \
  -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;' 2>&1
" wipe || { notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "schema wipe"; exit 1; }
fi

# -------- 4. Pull + up + healthcheck --------
log "[4/5] docker compose pull + up + container healthchecks …"
if ! ssm_run "
cd /opt/biomate
export BACKEND_IMAGE='$BACKEND_IMAGE'
export FRONTEND_IMAGE='$FRONTEND_IMAGE'
echo \"Pulling \$BACKEND_IMAGE …\"
docker compose -f docker-compose.deploy.yml pull
# Force fresh container creation: idempotent 'up' won't re-create when the
# image digest + env are unchanged from the running container, which would
# silently ignore .env updates (e.g. a rotated DB secret). --force-recreate
# guarantees the new env is applied. Also \`down --volumes\` first to drop
# any stale container + any local SQLite state left by a previous failed
# boot in the container's writable layer.
docker compose -f docker-compose.deploy.yml down --remove-orphans --volumes 2>/dev/null || true
echo \"Bringing services up (forced fresh) …\"
docker compose -f docker-compose.deploy.yml up -d --wait --wait-timeout 240 --force-recreate
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
  log "external healthcheck failed"
  # Auto-rollback if a previously healthy tag is recorded. last_deployed_tag
  # is only written AFTER a healthy boot (step 5), so it's a safe target.
  PREV_CMD=$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters 'commands=["cat /opt/biomate/last_deployed_tag 2>/dev/null || true"]' \
    --query 'Command.CommandId' --output text)
  sleep 4
  PREV_TAG=$(aws ssm get-command-invocation --region "$AWS_REGION" \
    --command-id "$PREV_CMD" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text 2>/dev/null | tr -d '[:space:]')
  if [[ -n "$PREV_TAG" && "$PREV_TAG" != "NONE" && "$PREV_TAG" != "$DEPLOY_TAG" ]]; then
    log "rolling back to previously healthy tag: $PREV_TAG"
    notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "external healthcheck failed; rolling back to $PREV_TAG"
    exec "$0" "$ENV_NAME" "$PREV_TAG"
  fi
  notify "[deploy] $ENV_NAME $DEPLOY_TAG FAILED" "external healthcheck failed; no prior healthy tag to roll back to"
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
