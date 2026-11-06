#!/usr/bin/env bash
# Build & push the nf-core compatibility images listed in backend/lib/galaxy/ai/nfcore_compat_images.py.
# Each entry rebuilds a published task image with one fix (infra/nfcore-compat/Dockerfile.<fix>) so
# it runs on BioMate's AWS Batch hosts; the executor substitutes it per process. Idempotent: a tag
# already in ECR is skipped.
#
# Build host: the dev EC2 cannot reach the ECR API (see build_bioc_mofa2_image.sh), so builds run on
# deploy-test (i-0482a6fa98c6f301a, t3.medium) — these are thin layers on existing images.
#
# Usage: scripts/build_nfcore_compat_images.sh [--dry-run]
set -euo pipefail
export PATH="$HOME/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$REPO_ROOT/backend/lib/galaxy/ai/nfcore_compat_images.py"
REGION=us-west-2
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

INSTANCE_ID="${BUILD_INSTANCE_ID:-i-0482a6fa98c6f301a}"
AZ="${BUILD_AZ:-us-west-2a}"
EC2_USER="${BUILD_USER:-ubuntu}"
KEY="/tmp/biomate_ec2_key_sync"
_SSM_PROXY="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${REGION}"
inject_key() {
  aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" --ssh-public-key "file://${KEY}.pub" --region "$REGION" \
    --output text --query Success >/dev/null 2>&1
}
SSH_OPTS=(-i "$KEY" -o "ProxyCommand=$_SSM_PROXY" -o StrictHostKeyChecking=no -o ConnectTimeout=30
          -o IdentitiesOnly=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=120 -o LogLevel=ERROR)
ec2_ssh() { inject_key; ssh "${SSH_OPTS[@]}" "${EC2_USER}@${INSTANCE_ID}" "$@"; }
ec2_scp() { inject_key; scp "${SSH_OPTS[@]}" "$@"; }

[ -f "$KEY" ] || { echo "[compat] ERROR: $KEY missing — run scripts/sync_to_dev.sh once to create it"; exit 1; }

# The config is a plain-literal module; exec it without importing the galaxy package.
cfg_py() { python3 -c 'import sys; ns={}; exec(open(sys.argv[1]).read(), ns); '"$1" "$CFG"; }
REPO=$(cfg_py 'print(ns["REPOSITORY"])')
REPO_NAME="${REPO#*/}"
REGISTRY="${REPO%%/*}"
ENTRIES=$(cfg_py '[print(e["source"], e["fix"], e["tag"]) for e in ns["IMAGES"]]')

if ! aws ecr describe-repositories --region "$REGION" --repository-names "$REPO_NAME" >/dev/null 2>&1; then
  if [ $DRY -eq 1 ]; then echo "[compat] would create ECR repository $REPO_NAME"; else
    aws ecr create-repository --region "$REGION" --repository-name "$REPO_NAME" \
      --image-scanning-configuration scanOnPush=true >/dev/null
    echo "[compat] created ECR repository $REPO_NAME"
  fi
fi

built=0
while read -r SRC FIX TAG; do
  [ -z "$SRC" ] && continue
  if aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
    echo "[compat] $REPO:$TAG present — skip"; continue
  fi
  DF="$REPO_ROOT/infra/nfcore-compat/Dockerfile.$FIX"
  [ -f "$DF" ] || { echo "[compat] ERROR: no $DF for $SRC"; exit 1; }
  if [ $DRY -eq 1 ]; then echo "[compat] would build $REPO:$TAG from $SRC ($FIX)"; continue; fi
  echo "[compat] building $REPO:$TAG from $SRC ($FIX)"
  ec2_ssh "mkdir -p /tmp/nfcore-compat"
  ec2_scp "$DF" "${EC2_USER}@${INSTANCE_ID}:/tmp/nfcore-compat/Dockerfile.$FIX"
  ec2_ssh "set -e; cd /tmp/nfcore-compat
    aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $REGISTRY >/dev/null
    sudo docker build -q --build-arg BASE=$SRC -f Dockerfile.$FIX -t $REPO:$TAG . >/dev/null
    sudo docker push -q $REPO:$TAG >/dev/null
    sudo docker image rm $REPO:$TAG $SRC >/dev/null 2>&1 || true"
  aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" >/dev/null \
    && { echo "[compat] pushed $REPO:$TAG"; built=$((built+1)); } \
    || { echo "[compat] ERROR: $REPO:$TAG not in ECR after push"; exit 1; }
done <<< "$ENTRIES"
echo "[compat] done ($built built)"
