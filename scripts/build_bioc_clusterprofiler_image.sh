#!/usr/bin/env bash
# Build the bioc-domain-genomics:3.20-clusterprofiler image on the dev EC2
# and push to ECR. Run from the repo root.
#
# Usage:
#   bash scripts/build_bioc_clusterprofiler_image.sh
#
# After this completes, update clusterprofiler/main.nf container tag and sync.
set -e

ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics"
TAG="3.20-clusterprofiler"
EC2_IP="52.42.49.175"
KEY="/tmp/biomate_ec2_key_sync"
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
  -o ProxyCommand='aws ssm start-session --target i-06696b0d91f4346e0 --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2'"

# Ensure SSH key exists (sync_to_dev.sh writes it)
if [[ ! -f "$KEY" ]]; then
  echo "[build] ERROR: $KEY not found — run scripts/sync_to_dev.sh first to populate the key"
  exit 1
fi

DOCKERFILE="aws_infrastructure/configs/Dockerfile.bioc-genomics-clusterprofiler"
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "[build] ERROR: $DOCKERFILE not found"
  exit 1
fi

echo "[build] Copying Dockerfile to dev EC2..."
scp $SSH_OPTS "$DOCKERFILE" "ubuntu@$EC2_IP:/tmp/Dockerfile.bioc-clusterprofiler"

echo "[build] Building image on dev EC2 (this takes ~20-30 min)..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" bash -s << 'REMOTE'
set -e
ECR_REGION="us-west-2"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics"
TAG="3.20-clusterprofiler"

echo "[EC2] Authenticating to ECR..."
aws ecr get-login-password --region "$ECR_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

# Pull the base image if not cached
docker pull "${ECR_REPO}:3.20-slim" 2>/dev/null || true

echo "[EC2] Building ${ECR_REPO}:${TAG}..."
docker build -t "${ECR_REPO}:${TAG}" -f /tmp/Dockerfile.bioc-clusterprofiler . 2>&1 | tail -20

echo "[EC2] Pushing ${ECR_REPO}:${TAG}..."
docker push "${ECR_REPO}:${TAG}"
echo "[EC2] Done. Image pushed: ${ECR_REPO}:${TAG}"
REMOTE

echo ""
echo "[build] Image pushed: ${ECR_REPO}:${TAG}"
echo ""
echo "Next steps:"
echo "  1. Update container in backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/clusterprofiler/main.nf"
echo "     Change: bioc-domain-genomics:3.20-slim"
echo "     To:     bioc-domain-genomics:3.20-clusterprofiler"
echo "  2. Commit and sync:  git add ... && git commit && bash scripts/sync_to_dev.sh"
