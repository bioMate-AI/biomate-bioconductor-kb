#!/bin/bash
# enable_autofix3_on_dev.sh — flip BIOMATE_AUTOFIX3_AUTO=true on the dev
# Galaxy container, persistently across restarts.
#
# Why this script exists:
#   The dev Galaxy container (biomate-galaxy-dev) is launched by `docker run`
#   one-off, not by docker-compose. /opt/biomate/docker-compose.yml exists
#   but is unused for this container — the running container has no compose
#   labels and a different name (biomate-galaxy vs biomate-galaxy-dev). So
#   editing the compose file won't change the running container's env.
#   This script does what the compose change would do: capture the current
#   env, merge in BIOMATE_AUTOFIX3_AUTO, recreate the container.
#
# What the env var does:
#   Gates Path B autofix3 auto-trigger in
#   backend/lib/galaxy/jobs/runners/nextflow_workflow_runner.py:_mark_workflow_failed.
#   When false/unset (production-safe default), workflow failures behave
#   exactly as before. When true, every real execution failure spawns a
#   daemon thread that calls IterativeDebugger + 19 fixers to attempt
#   automatic remediation. See docs/20260606_AUTOFIX3_PATH_CHOICE.md.
#
# Idempotent: re-running with the var already set is a no-op (still recreates
# the container so any env-block changes are applied, but otherwise neutral).
#
# Usage:
#   bash scripts/enable_autofix3_on_dev.sh on    # flip ON
#   bash scripts/enable_autofix3_on_dev.sh off   # flip OFF
#   bash scripts/enable_autofix3_on_dev.sh status   # report current value

set -euo pipefail

EC2_USER=ubuntu
EC2_HOST=52.42.49.175
INSTANCE_ID=i-06696b0d91f4346e0
AZ=us-west-2a
KEY_FILE=/tmp/biomate_ec2_key_sync
CONTAINER=biomate-galaxy-dev
ENV_VAR=BIOMATE_AUTOFIX3_AUTO

action="${1:-status}"
case "$action" in
  on|off|status) ;;
  *) echo "usage: $0 {on|off|status}" >&2; exit 2 ;;
esac

inject_key() {
  [[ -f "$KEY_FILE" ]] || ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" \
    --ssh-public-key "file://${KEY_FILE}.pub" \
    --region us-west-2 --output text --query 'Success' > /dev/null
}

remote() {
  inject_key
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    "${EC2_USER}@${EC2_HOST}" "$@"
}

case "$action" in
  status)
    echo "Querying current $ENV_VAR on $CONTAINER..."
    val=$(remote "docker exec $CONTAINER printenv $ENV_VAR 2>/dev/null || true")
    echo "  $ENV_VAR=${val:-<unset>}"
    echo "  autofix3 status:"
    remote "curl -s http://127.0.0.1:8081/api/autofix3/status" | tr ',' '\n' | grep -E "status|available|tracked" || true
    exit 0
    ;;
esac

new_value="true"
[[ "$action" == "off" ]] && new_value="false"

echo "Will set $ENV_VAR=$new_value on $CONTAINER and recreate the container."
echo "Continuing in 3s (Ctrl-C to abort)..."
sleep 3

# Build a single-shot remote script: capture every existing env var EXCEPT
# the one we're flipping, then re-run `docker run` with the merged set.
remote bash -c "'
set -euo pipefail
CONTAINER='$CONTAINER'
ENV_VAR='$ENV_VAR'
NEW_VALUE='$new_value'

echo \"[1/4] capturing current env from running container...\"
ENV_FILE=\$(mktemp)
trap \"rm -f \$ENV_FILE\" EXIT
docker inspect \$CONTAINER --format \"{{range .Config.Env}}{{println .}}{{end}}\" \
  | grep -v \"^\$ENV_VAR=\" > \$ENV_FILE
echo \"[1/4] captured \$(wc -l < \$ENV_FILE) env vars\"

# Capture other run config we need to preserve
IMAGE=\$(docker inspect \$CONTAINER --format \"{{.Config.Image}}\")
NETWORK=\$(docker inspect \$CONTAINER --format \"{{.HostConfig.NetworkMode}}\")
PORTS=\$(docker inspect \$CONTAINER --format \"{{range \\\$p, \\\$bs := .HostConfig.PortBindings}}{{range \\\$bs}}-p {{.HostPort}}:{{\\\$p}} {{end}}{{end}}\" | sed \"s|/tcp||g\")
echo \"  image=\$IMAGE  network=\$NETWORK  ports=\$PORTS\"

echo \"[2/4] stopping and removing \$CONTAINER...\"
docker stop \$CONTAINER > /dev/null
docker rm \$CONTAINER > /dev/null

echo \"[3/4] re-running with \$ENV_VAR=\$NEW_VALUE merged in...\"
docker run -d --name \$CONTAINER \\
  --network \$NETWORK \\
  \$PORTS \\
  --restart unless-stopped \\
  --env-file \$ENV_FILE \\
  -e \$ENV_VAR=\$NEW_VALUE \\
  \$IMAGE > /dev/null

echo \"[4/4] waiting for container to be healthy...\"
for i in \$(seq 1 30); do
  status=\$(docker inspect \$CONTAINER --format \"{{.State.Status}}\" 2>/dev/null || echo unknown)
  if [[ \"\$status\" == \"running\" ]]; then
    # Confirm the new env var is actually present
    actual=\$(docker exec \$CONTAINER printenv \$ENV_VAR 2>/dev/null || echo \"\")
    if [[ \"\$actual\" == \"\$NEW_VALUE\" ]]; then
      echo \"  ✓ container running with \$ENV_VAR=\$actual\"
      break
    fi
  fi
  sleep 1
done

echo
echo \"autofix3 status post-restart:\"
sleep 3
curl -s http://127.0.0.1:8081/api/autofix3/status | tr , \"\\n\" | grep -E \"status|available|tracked\"
'"

echo
echo "Container recreated. Now re-running sync_to_dev.sh to restore backend"
echo "Python code into the fresh container's writable layer."
echo "(Background: docker cp deploy doesn't survive container recreation —"
echo " see docs/20260607_DEPLOY_FRAGILITY_DOCKER_CP_LAYER.md)"
echo

# Run the sync from the repo root so REPO_ROOT resolves correctly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
rm -f /tmp/biomate_sync_to_dev.lock
if bash "$REPO_ROOT/scripts/sync_to_dev.sh" 2>&1 | grep -E "Sync OK|FATAL|extracted [0-9]+ python|ERROR"; then
  echo
  echo "Verifying autofix3 trigger code is present in the recreated container:"
  trigger_count=$(remote "docker exec $CONTAINER grep -c '_trigger_autofix3_async' /app/lib/galaxy/jobs/runners/nextflow_workflow_runner.py 2>/dev/null || echo 0")
  if [[ "$trigger_count" -ge 2 ]]; then
    echo "  ✓ trigger code present (grep count=$trigger_count, expect ≥2)"
  else
    echo "  ✗ trigger code MISSING (grep count=$trigger_count). Investigate sync logs."
    exit 1
  fi
fi

echo
echo "Done. The next workflow execution failure on dev will auto-trigger autofix3."
echo "To verify: tail Galaxy logs for '🔧 autofix3 auto-trigger firing' lines."
echo "To revert: bash scripts/enable_autofix3_on_dev.sh off"
