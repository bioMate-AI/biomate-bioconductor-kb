#!/usr/bin/env bash
# Build & push biomate/mlip-md:x86 (infra/docker/mlip-md/Dockerfile) for the MLIP MD workflow
# (nextflow_nfcore/subworkflows/molecular_dynamics/mlip_md_simulation). The workflow referenced
# this ECR image but it was never built, so every run failed CannotPullImageManifestError.
#
# Builds on deploy-test (the dev EC2 cannot reach the ECR API). The conda solve + pip installs are
# long, so the build runs DETACHED on the host and this script polls ECR for the pushed tag
# (pattern from build_bioc_mofa2_image.sh). The Dockerfile's last RUN is an energy smoke test for
# both potentials, so a broken install fails the build instead of a user run.
#
# Usage: scripts/build_mlip_md_image.sh            (start build, then poll up to ~90 min)
set -euo pipefail
export PATH="$HOME/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=us-west-2
REGISTRY=399683337364.dkr.ecr.us-west-2.amazonaws.com
REPO_NAME=biomate/mlip-md
TAG=x86
INSTANCE_ID="${BUILD_INSTANCE_ID:-i-0482a6fa98c6f301a}"; AZ="${BUILD_AZ:-us-west-2a}"; EC2_USER="${BUILD_USER:-ubuntu}"
KEY=/tmp/biomate_ec2_key_sync
_SSM="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${REGION}"
inject() { aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
  --instance-os-user "$EC2_USER" --ssh-public-key "file://${KEY}.pub" --region "$REGION" --output text --query Success >/dev/null 2>&1; }
OPTS=(-i "$KEY" -o "ProxyCommand=$_SSM" -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes -o LogLevel=ERROR)
ssh_() { inject; ssh -n "${OPTS[@]}" "${EC2_USER}@${INSTANCE_ID}" "$@"; }
scp_() { inject; scp "${OPTS[@]}" "$@" < /dev/null; }

aws ecr describe-repositories --region "$REGION" --repository-names "$REPO_NAME" >/dev/null 2>&1 || {
  aws ecr create-repository --region "$REGION" --repository-name "$REPO_NAME" --image-scanning-configuration scanOnPush=true >/dev/null
  echo "[mlip] created ECR repository $REPO_NAME"; }
before=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)

ssh_ "mkdir -p /tmp/mlip-md"
scp_ "$REPO_ROOT/infra/docker/mlip-md/Dockerfile" "${EC2_USER}@${INSTANCE_ID}:/tmp/mlip-md/Dockerfile"
ssh_ "cd /tmp/mlip-md && nohup bash -c 'aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $REGISTRY >/dev/null \
  && sudo docker build -t $REGISTRY/$REPO_NAME:$TAG . && sudo docker push $REGISTRY/$REPO_NAME:$TAG && echo BUILD_PUSH_OK' > build.log 2>&1 &"
echo "[mlip] build started on $INSTANCE_ID (log: /tmp/mlip-md/build.log); polling ECR"

for i in $(seq 1 90); do
  sleep 60
  now=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
  if [ "$now" != "none" ] && [ "$now" != "$before" ]; then echo "[mlip] pushed $REPO_NAME:$TAG $now"; exit 0; fi
  if [ $((i % 5)) -eq 0 ]; then
    tail_=$(ssh_ "tail -3 /tmp/mlip-md/build.log" 2>/dev/null || true)
    echo "[mlip] ${i} min: $(echo "$tail_" | tail -1 | cut -c1-140)"
    echo "$tail_" | grep -qiE "error|failed|AssertionError" && { echo "[mlip] BUILD FAILED:"; ssh_ "tail -40 /tmp/mlip-md/build.log"; exit 1; }
  fi
done
echo "[mlip] timed out waiting for the push"; exit 1
