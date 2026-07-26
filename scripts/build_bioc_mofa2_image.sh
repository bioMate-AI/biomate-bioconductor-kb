#!/usr/bin/env bash
# Build & push the bioc-domain-general:3.20-mofa2 image (MOFA2 + basilisk/mofapy2
# baked in). The heavy image is built ON the dev build EC2 (which has docker + ECR
# access) via SSH-over-SSM, then pushed to ECR. The workflow's container reference
# change is deployed the normal way with scripts/sync_to_dev.sh — this script only
# provisions the registry image.
#
# Connection mechanism mirrors scripts/sync_to_dev.sh (ec2_ssh/ec2_scp): EC2 Instance
# Connect pushes an ephemeral key (60 s), SSH routes through SSM to the INSTANCE ID.
set -e
export PATH="$HOME/bin:$PATH"          # session-manager-plugin lives in ~/bin (sync installs it)

ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general"
TAG="3.20-mofa2"
INSTANCE_ID="i-06696b0d91f4346e0"
AZ="us-west-2a"
EC2_USER="ubuntu"
KEY="/tmp/biomate_ec2_key_sync"
_SSM_PROXY="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2"

if [[ ! -f "$KEY" ]]; then
  echo "[build] ERROR: $KEY not found — run scripts/sync_to_dev.sh first to populate the key"
  exit 1
fi
if ! command -v session-manager-plugin &>/dev/null; then
  echo "[build] ERROR: session-manager-plugin not on PATH — run scripts/sync_to_dev.sh first"
  exit 1
fi
DOCKERFILE="aws_infrastructure/configs/Dockerfile.bioc-general-mofa2"
[[ -f "$DOCKERFILE" ]] || { echo "[build] ERROR: $DOCKERFILE not found"; exit 1; }

inject_key() {
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" \
    --ssh-public-key "file://${KEY}.pub" \
    --region us-west-2 --output text --query 'Success' >/dev/null 2>&1
}
ec2_ssh() {
  inject_key
  ssh -i "$KEY" -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=240 \
    "${EC2_USER}@${INSTANCE_ID}" "$@"
}
ec2_scp() {
  inject_key
  scp -i "$KEY" -o ProxyCommand="$_SSM_PROXY" \
    -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=100 "$@"
}

echo "[build] Copying Dockerfile to build EC2..."
ec2_scp "$DOCKERFILE" "${EC2_USER}@${INSTANCE_ID}:/tmp/Dockerfile.bioc-mofa2"

echo "[build] Building image on EC2 (MOFA2 + basilisk conda env — ~40-60 min)..."
ec2_ssh bash -s << 'REMOTE'
set -e
ECR_REGION="us-west-2"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general"
TAG="3.20-mofa2"
echo "[EC2] Authenticating to ECR..."
aws ecr get-login-password --region "$ECR_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REPO"
docker pull "${ECR_REPO}:3.20-slim" 2>/dev/null || true
echo "[EC2] Building ${ECR_REPO}:${TAG}..."
docker build -t "${ECR_REPO}:${TAG}" -f /tmp/Dockerfile.bioc-mofa2 . 2>&1 | tail -50
echo "[EC2] Pushing ${ECR_REPO}:${TAG}..."
docker push "${ECR_REPO}:${TAG}"
echo "[EC2] Done. Image pushed: ${ECR_REPO}:${TAG}"
REMOTE

echo ""
echo "[build] Image pushed: ${ECR_REPO}:${TAG}"
echo "Next: update mofa2/main.nf container to :3.20-mofa2, commit, and sync_to_dev.sh"
