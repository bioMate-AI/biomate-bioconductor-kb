#!/usr/bin/env bash
# enable_generalized_routing_on_dev.sh — flip the two 2026-11-04 generalization
# routing flags (ML_TRAINING_ROUTING, MULTIOMICS_ROUTING) on the dev Galaxy
# container, persistently across restarts.
#
# Why this script exists (same situation as enable_autofix3_on_dev.sh):
#   biomate-galaxy-dev is launched by a one-off `docker run` (no compose
#   labels), so the only way to change its process env is to recreate it.
#   The generalized routing code (ml_training/routing.py, multiomics/routing.py)
#   is already deployed; it is just gated by these env flags, read at process
#   start and defaulting OFF. See:
#     - docs/20261104_GENERALIZATION_SESSION_IMPLEMENTATION.md  (what the flags gate)
#     - docs/20261104_ACTIVATION_RUNBOOK_AND_QC_WIRING_PATCH.md  (§A, the manual runbook this automates)
#
# CRITICAL — why `docker commit`, not "recreate from the image":
#   Dev's backend code is docker-cp'd into the container's WRITABLE LAYER by
#   sync_to_dev.sh; the biomate-galaxy-dev:rollback IMAGE is a stale snapshot.
#   Recreating from that image would REVERT dev to the rollback code (verified
#   2026-11-04: the running container had newer code than the image). So this
#   script snapshots the LIVE container with `docker commit` first and recreates
#   from that snapshot — preserving all currently-deployed code with NO re-sync,
#   NO clean working tree, and NO sync lock required. (This is the key difference
#   from enable_autofix3_on_dev.sh, which re-runs sync_to_dev.sh afterward.)
#
# Idempotent and reversible:
#   on     — set both flags = 1 and recreate
#   off    — remove both flags and recreate (routing goes dormant; code untouched)
#   status — report current flag values (no change)
#
# Usage:
#   bash scripts/enable_generalized_routing_on_dev.sh on
#   bash scripts/enable_generalized_routing_on_dev.sh off
#   bash scripts/enable_generalized_routing_on_dev.sh status

set -euo pipefail

EC2_USER=ubuntu
INSTANCE_ID=i-06696b0d91f4346e0
AZ=us-west-2a
KEY_FILE=/tmp/biomate_ec2_key_sync
CONTAINER=biomate-galaxy-dev
FLAG1=ML_TRAINING_ROUTING
FLAG2=MULTIOMICS_ROUTING
# A code-sanity canary: a string that only exists in currently-deployed code.
# After recreate we grep for it to PROVE the snapshot preserved the live layer
# (i.e. we did not silently revert to the stale image).
CODE_CANARY_FILE=/app/lib/galaxy/ai/multiomics/routing.py
CODE_CANARY_STR=_MODALITY_KEYWORDS

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

# SSM-SSH (works without the instance having a reachable public IP).
remote() {
  inject_key
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=20 \
    -o ProxyCommand="aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2" \
    "${EC2_USER}@${INSTANCE_ID}" "$@"
}

if [[ "$action" == "status" ]]; then
  echo "Querying $FLAG1 / $FLAG2 on $CONTAINER..."
  remote "echo \"  $FLAG1=\$(docker exec $CONTAINER printenv $FLAG1 2>/dev/null || echo '<unset>')\"; echo \"  $FLAG2=\$(docker exec $CONTAINER printenv $FLAG2 2>/dev/null || echo '<unset>')\""
  exit 0
fi

if [[ "$action" == "on" ]]; then NEW1=1; NEW2=1; else NEW1=""; NEW2=""; fi

echo "Recreating $CONTAINER with $FLAG1=${NEW1:-<removed>} $FLAG2=${NEW2:-<removed>} (snapshot-preserving)..."

# All remote steps in one SSH session so the snapshot/stop/run are atomic.
remote "set -e
  C=$CONTAINER
  TS=\$(date +%Y%m%d_%H%M%S)
  SNAP=biomate-galaxy-dev:routing-\$TS

  echo '[1/6] snapshotting live container code into '\$SNAP' ...'
  docker commit \$C \$SNAP >/dev/null

  echo '[2/6] capturing run config (env minus the two flags, net/ports/binds)...'
  ENV_FILE=/tmp/galaxy_routing_env.\$TS
  docker inspect \$C --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -vE '^($FLAG1|$FLAG2)=' \
    | grep -vE '^(PATH|HOME|TERM|HOSTNAME|SHELL|SHLVL|LOGNAME|USER|_)=' > \$ENV_FILE
  NETWORK=\$(docker inspect \$C --format '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}{{end}}')
  PORTS=\$(docker inspect \$C --format '{{range \$p,\$bs := .HostConfig.PortBindings}}{{range \$bs}}-p {{.HostPort}}:{{\$p}} {{end}}{{end}}' | sed 's|/tcp||g')
  BINDS=\$(docker inspect \$C --format '{{range .HostConfig.Binds}}-v {{.}} {{end}}')
  ENTRY=\$(docker inspect \$C --format '{{if .Config.Entrypoint}}{{index .Config.Entrypoint 0}}{{end}}')
  echo \"      net=\$NETWORK ports=\$PORTS binds=\$BINDS\"

  echo '[3/6] stopping + removing old container...'
  docker stop \$C >/dev/null
  docker rm \$C >/dev/null

  echo '[4/6] running from snapshot with flags applied...'
  EXTRA=''
  [ -n '${NEW1}' ] && EXTRA=\"\$EXTRA -e $FLAG1=${NEW1}\"
  [ -n '${NEW2}' ] && EXTRA=\"\$EXTRA -e $FLAG2=${NEW2}\"
  docker run -d --name \$C --network \"\$NETWORK\" \$PORTS \$BINDS \
    --restart unless-stopped --env-file \$ENV_FILE \$EXTRA \$SNAP >/dev/null

  echo '[5/6] verifying code was preserved (canary) + flags...'
  sleep 2
  if ! docker exec \$C grep -q '$CODE_CANARY_STR' '$CODE_CANARY_FILE' 2>/dev/null; then
    echo '      ✗ CODE CANARY MISSING — snapshot did not preserve live code! Investigate.' >&2
    exit 3
  fi
  echo \"      ✓ code preserved; $FLAG1=\$(docker exec \$C printenv $FLAG1 2>/dev/null || echo '<unset>') $FLAG2=\$(docker exec \$C printenv $FLAG2 2>/dev/null || echo '<unset>')\"

  echo '[6/6] waiting for Galaxy /api/version to come up...'
  for i in \$(seq 1 60); do
    if docker exec \$C sh -c 'curl -fsS http://localhost:8080/api/version >/dev/null 2>&1'; then
      echo '      ✓ galaxy up'; break
    fi
    sleep 2
  done
  rm -f \$ENV_FILE
"

echo
echo "Done. Routing flags are now ${action^^}. Verify end-to-end with:"
echo "  E2E_FIXTURE_PASSWORD='<pw>' EXPECT_FLAGS_ON=1 bash scripts/smoke_generalized_routing.sh"
echo "Revert with: bash scripts/enable_generalized_routing_on_dev.sh off"
