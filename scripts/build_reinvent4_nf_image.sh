#!/usr/bin/env bash
# Build & push biomate/reinvent4-nf:x86 from backend/docker/reinvent4-nf/Dockerfile.
# Default BUILD_MODE=spot: one-shot c6i.2xlarge SPOT builder (same pattern as
# scripts/build_mlip_md_image.sh). Context is uploaded to S3 then pulled by the
# builder (Dockerfile COPYs repo-root paths).
#
# Usage:
#   scripts/build_reinvent4_nf_image.sh
#   BUILD_MODE=host scripts/build_reinvent4_nf_image.sh   # deploy-test via SSM
set -euo pipefail

unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy \
  SOCKS_PROXY SOCKS5_PROXY socks_proxy socks5_proxy GIT_HTTP_PROXY GIT_HTTPS_PROXY || true
export NO_PROXY='*' no_proxy='*'
export PATH="${HOME}/bin:/usr/local/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=us-west-2
REGISTRY=399683337364.dkr.ecr.us-west-2.amazonaws.com
REPO_NAME=biomate/reinvent4-nf
TAG="${REINVENT4_TAG:-x86}"
S3_BUCKET="${BUILD_CTX_BUCKET:-biomate-nextflow-work}"
# Must live under nextflow/work/* — BioMateEc2DeployRole S3ReadDevSync grants
# GetObject only for nextflow/work|outputs and dev-sync, NOT reinvent4-nf/*.
# Prior builder i-0fb9f5e51ab242358 died on AccessDenied reading reinvent4-nf/.
S3_KEY="nextflow/work/reinvent4-nf/build-ctx-$(date -u +%Y%m%dT%H%M%SZ).tgz"
INSTANCE_ID="${BUILD_INSTANCE_ID:-i-0482a6fa98c6f301a}"
AZ="${BUILD_AZ:-us-west-2a}"
EC2_USER="${BUILD_USER:-ubuntu}"
KEY=/tmp/biomate_ec2_key_sync
LOG=/tmp/biomate_reinvent4_nf_build_$(date -u +%Y%m%dT%H%M%SZ).log
# Avoid process-substitution tee (fails under some sandboxes); append via shell redirect.
exec >>"$LOG" 2>&1
echo "[reinvent4] log=$LOG started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Also mirror critical lines to a companion status file for the poller.
STATUS=/tmp/biomate_reinvent4_nf_build_status.txt
echo "STARTED $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"

_SSM="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${REGION}"
inject() {
  aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
    --instance-os-user "$EC2_USER" --ssh-public-key "file://${KEY}.pub" --region "$REGION" \
    --output text --query Success >/dev/null 2>&1
}
OPTS=(-i "$KEY" -o "ProxyCommand=$_SSM" -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes -o LogLevel=ERROR)
ssh_() { inject; ssh -n "${OPTS[@]}" "${EC2_USER}@${INSTANCE_ID}" "$@"; }
scp_() { inject; scp "${OPTS[@]}" "$@" < /dev/null; }

[[ -f "$KEY" ]] || ssh-keygen -t ed25519 -f "$KEY" -N '' -q

# Ensure ECR repo exists
aws ecr describe-repositories --region "$REGION" --repository-names "$REPO_NAME" >/dev/null 2>&1 || {
  aws ecr create-repository --region "$REGION" --repository-name "$REPO_NAME" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  echo "[reinvent4] created ECR repository $REPO_NAME"
}

before=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
echo "[reinvent4] before $REPO_NAME:$TAG digest=$before"

# Pack build context (Dockerfile expects repo-root context)
CTX=$(mktemp -d)
trap 'rm -rf "$CTX"' EXIT
mkdir -p "$CTX/backend/docker/reinvent4-nf" "$CTX/backend/lib/galaxy/ai"
cp "$REPO_ROOT/backend/docker/reinvent4-nf/Dockerfile" "$CTX/backend/docker/reinvent4-nf/"
cp "$REPO_ROOT/backend/docker/reinvent4-nf/reinvent_runner.py" "$CTX/backend/docker/reinvent4-nf/"
cp -R "$REPO_ROOT/backend/lib/galaxy/ai/drug_discovery" "$CTX/backend/lib/galaxy/ai/"
# Include reinvent4_runtime.py from WIP stash if missing on disk (do not pop stash)
if [[ ! -f "$CTX/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py" ]]; then
  for i in $(seq 0 30); do
    if git -C "$REPO_ROOT" cat-file -e "stash@{$i}^3:backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py" 2>/dev/null; then
      git -C "$REPO_ROOT" show "stash@{$i}^3:backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py" \
        > "$CTX/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py"
      echo "[reinvent4] packed reinvent4_runtime.py from stash@{$i}"
      break
    fi
  done
fi
# Prefer already-exported copy if present
if [[ -f /tmp/reinvent4-nf-build-ctx/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py ]] && \
   [[ ! -f "$CTX/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py" ]]; then
  cp /tmp/reinvent4-nf-build-ctx/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py \
    "$CTX/backend/lib/galaxy/ai/drug_discovery/reinvent4_runtime.py"
fi
TGZ=/tmp/reinvent4-nf-build-ctx-live.tgz
# Pack the `backend/` tree (not `.`) so member names are
# `backend/docker/reinvent4-nf/Dockerfile` — macOS bsdtar of `.` stores
# `./backend/...`, which makes naive `tarfile.getmember('backend/...')`
# post-launch checks raise KeyError even though docker extract is fine.
# COPYFILE_DISABLE=1 drops AppleDouble `._*` junk that also pollutes the ctx.
COPYFILE_DISABLE=1 tar -czf "$TGZ" -C "$CTX" backend
# Hard gate: Dockerfile must be addressable at the path docker -f expects.
python3 - "$TGZ" <<'PY'
import sys, tarfile
tgz = sys.argv[1]
need = "backend/docker/reinvent4-nf/Dockerfile"
with tarfile.open(tgz) as tf:
    try:
        m = tf.getmember(need)
    except KeyError as e:
        names = [n for n in tf.getnames() if "Dockerfile" in n]
        raise SystemExit(f"[reinvent4] FATAL: {e}; Dockerfile members={names!r}") from e
    if m.size < 100:
        raise SystemExit(f"[reinvent4] FATAL: {need} too small ({m.size} bytes)")
    data = tf.extractfile(m).read().decode()
    if "micromamba install" not in data or "python=3.11" not in data or "pip" not in data:
        raise SystemExit(f"[reinvent4] FATAL: {need} missing micromamba python+pip layer")
    if "scipy" not in data:
        raise SystemExit(f"[reinvent4] FATAL: {need} missing scipy pin (CLI import dep)")
print(f"[reinvent4] verified {need} ({m.size} bytes, micromamba/pip+scipy present)")
PY
echo "[reinvent4] context $(du -h "$TGZ" | awk '{print $1}')"

aws s3 cp "$TGZ" "s3://${S3_BUCKET}/${S3_KEY}" --region "$REGION"
echo "[reinvent4] uploaded s3://${S3_BUCKET}/${S3_KEY}"

# BUILD_MODE=spot|ondemand|host — ondemand avoids spot immediate-reclaim races while debugging.
if [ "${BUILD_MODE:-ondemand}" = spot ] || [ "${BUILD_MODE:-ondemand}" = ondemand ]; then
  AMI=$(aws ssm get-parameter --region "$REGION" --query Parameter.Value --output text \
    --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id)
  UD=$(mktemp)
  # Unique success token (avoid set -x / trap string false positives on BUILD_PUSH_OK).
  OK_TOKEN="BIOMATE_REINVENT4_BUILD_PUSH_OK_$(date -u +%Y%m%d%H%M%S)"
  {
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo 'exec > /var/log/reinvent4-build.log 2>&1'
    echo 'echo reinvent4-build-start "$(date -u -Iseconds)"'
    echo "OK_TOKEN=${OK_TOKEN}"
    echo "S3_LOG=s3://${S3_BUCKET}/nextflow/work/reinvent4-nf/build-log-\$(date -u +%Y%m%dT%H%M%SZ).txt"
    # Hard stop at 120m; on failure keep instance 30m so SSM can read the log.
    echo 'shutdown -h +120'
    # Upload log to S3 (allowed under nextflow/work/*) so failures are diagnosable after terminate.
    echo "trap 'aws s3 cp /var/log/reinvent4-build.log \"\$S3_LOG\" --region ${REGION} >/dev/null 2>&1 || true; if grep -qx \"\$OK_TOKEN\" /var/log/reinvent4-build.log; then echo ok > /var/log/reinvent4-build.status; shutdown -h now; else echo failed > /var/log/reinvent4-build.status; shutdown -h +30; fi' EXIT"
    echo 'export DEBIAN_FRONTEND=noninteractive'
    echo 'apt-get update -qq'
    echo 'apt-get install -y -qq docker.io docker-buildx unzip curl ca-certificates'
    echo 'systemctl start docker || service docker start || true'
    echo 'curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip'
    echo 'unzip -q /tmp/a.zip -d /tmp && /tmp/aws/install'
    echo "aws s3 cp s3://${S3_BUCKET}/${S3_KEY} /tmp/ctx.tgz --region ${REGION}"
    echo 'mkdir -p /build && tar -xzf /tmp/ctx.tgz -C /build && cd /build'
    echo "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${REGISTRY}"
    echo "TOKEN=\$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')"
    echo "BT=build-\$(curl -s -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/instance-id)"
    echo "DOCKER_BUILDKIT=1 docker build --platform linux/amd64 -t ${REGISTRY}/${REPO_NAME}:${TAG} -f backend/docker/reinvent4-nf/Dockerfile ."
    echo "docker tag ${REGISTRY}/${REPO_NAME}:${TAG} ${REGISTRY}/${REPO_NAME}:\$BT"
    echo "docker tag ${REGISTRY}/${REPO_NAME}:${TAG} ${REGISTRY}/${REPO_NAME}:latest"
    echo "docker push ${REGISTRY}/${REPO_NAME}:\$BT"
    echo "docker push ${REGISTRY}/${REPO_NAME}:${TAG}"
    echo "docker push ${REGISTRY}/${REPO_NAME}:latest"
    echo 'echo "$OK_TOKEN"'
  } > "$UD"
  RUN_ARGS=(
    --region "$REGION" --image-id "$AMI" --instance-type "${BUILD_INSTANCE_TYPE:-c6i.2xlarge}"
    --subnet-id "${BUILD_SUBNET:-subnet-09e4dce46682a6c60}" --security-group-ids "${BUILD_SG:-sg-0a70bb26e47332c55}"
    --iam-instance-profile Name=BioMateEc2DeployProfile
    --instance-initiated-shutdown-behavior terminate
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=100,VolumeType=gp3,DeleteOnTermination=true}'
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=biomate-reinvent4-nf-builder}]'
    --user-data "file://$UD"
    --query 'Instances[0].InstanceId' --output text
  )
  if [ "${BUILD_MODE:-ondemand}" = spot ]; then
    RUN_ARGS+=(--instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}')
  fi
  BUILDER=$(aws ec2 run-instances "${RUN_ARGS[@]}")
  rm -f "$UD"
  echo "[reinvent4] ${BUILD_MODE:-ondemand} builder $BUILDER started (ok_token=$OK_TOKEN); polling ECR"
  echo "$BUILDER" > /tmp/biomate_reinvent4_nf_builder_id.txt
  builder_gone() {
    st=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$BUILDER" \
      --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
    [ "$st" = terminated ] || [ "$st" = shutting-down ]
  }
else
  ssh_ "mkdir -p /tmp/reinvent4-nf && sudo rm -rf /tmp/reinvent4-nf/*"
  scp_ "$TGZ" "${EC2_USER}@${INSTANCE_ID}:/tmp/reinvent4-nf/ctx.tgz"
  ssh_ "cd /tmp/reinvent4-nf && tar -xzf ctx.tgz && nohup bash -c 'aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $REGISTRY >/dev/null \
    && sudo DOCKER_BUILDKIT=1 docker build --platform linux/amd64 -t $REGISTRY/$REPO_NAME:$TAG -f backend/docker/reinvent4-nf/Dockerfile . \
    && sudo docker tag $REGISTRY/$REPO_NAME:$TAG $REGISTRY/$REPO_NAME:latest \
    && sudo docker push $REGISTRY/$REPO_NAME:$TAG \
    && sudo docker push $REGISTRY/$REPO_NAME:latest \
    && echo BUILD_PUSH_OK' > build.log 2>&1 &"
  echo "[reinvent4] host build started on $INSTANCE_ID (log /tmp/reinvent4-nf/build.log)"
  builder_gone() { false; }
  BUILDER=""
fi

MODE="${BUILD_MODE:-ondemand}"
for i in $(seq 1 125); do
  sleep 60
  now=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
  if [ "$MODE" = host ] && [ "$now" != "none" ] && [ "$now" != "$before" ]; then
    echo "[reinvent4] PUSHED $REGISTRY/$REPO_NAME:$TAG $now"
    echo "DIGEST=$now" > /tmp/biomate_reinvent4_nf_push_result.txt
    echo "URI=$REGISTRY/$REPO_NAME:$TAG" >> /tmp/biomate_reinvent4_nf_push_result.txt
    echo "PUSHED $(date -u -Iseconds) $now" > "$STATUS"
    exit 0
  fi
  if [ "$MODE" != host ] && [ $((i % 2)) -eq 0 ] && ! builder_gone; then
    cid=$(aws ssm send-command --region "$REGION" --instance-ids "$BUILDER" --document-name AWS-RunShellScript \
      --parameters 'commands=["cat /var/log/reinvent4-build.status 2>/dev/null || echo running","tail -c 8000 /var/log/reinvent4-build.log"]' \
      --query Command.CommandId --output text 2>/dev/null || true)
    if [ -n "$cid" ]; then
      sleep 15
      out=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cid" --instance-id "$BUILDER" \
        --query StandardOutputContent --output text 2>/dev/null || true)
      echo "[reinvent4] ${i} min: $(printf '%s\n' "$out" | grep -v '^\s*$' | tail -1 | cut -c1-180)"
      if [ "$(printf '%s\n' "$out" | head -1)" = failed ]; then
        echo "[reinvent4] BUILD FAILED on $BUILDER; log tail:"
        printf '%s\n' "$out" | tail -n +2 | tail -80
        aws ec2 terminate-instances --region "$REGION" --instance-ids "$BUILDER" >/dev/null || true
        exit 1
      fi
      if [ "$(printf '%s\n' "$out" | head -1)" = ok ] && [ "$now" != "none" ] && [ "$now" != "$before" ]; then
        echo "[reinvent4] PUSHED $REGISTRY/$REPO_NAME:$TAG $now"
        echo "DIGEST=$now" > /tmp/biomate_reinvent4_nf_push_result.txt
        echo "URI=$REGISTRY/$REPO_NAME:$TAG" >> /tmp/biomate_reinvent4_nf_push_result.txt
        echo "RECEIPT=build-$BUILDER" >> /tmp/biomate_reinvent4_nf_push_result.txt
        echo "PUSHED $(date -u -Iseconds) $now" > "$STATUS"
        exit 0
      fi
    fi
  fi
  # Do not judge "gone" in the first 5 minutes (cloud-init + apt still booting).
  if [ "$MODE" != host ] && [ "$i" -ge 5 ] && builder_gone; then
    receipt=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="build-$BUILDER" \
      --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
    if [ "$receipt" != none ] && [ "$receipt" = "$now" ]; then
      echo "[reinvent4] PUSHED $REGISTRY/$REPO_NAME:$TAG $now (receipt build-$BUILDER)"
      echo "DIGEST=$now" > /tmp/biomate_reinvent4_nf_push_result.txt
      echo "URI=$REGISTRY/$REPO_NAME:$TAG" >> /tmp/biomate_reinvent4_nf_push_result.txt
      echo "RECEIPT=build-$BUILDER" >> /tmp/biomate_reinvent4_nf_push_result.txt
      echo "PUSHED $(date -u -Iseconds) $now" > "$STATUS"
      exit 0
    fi
    echo "[reinvent4] builder terminated without push (receipt=$receipt, $TAG=$now)"
    exit 1
  fi
  if [ "$MODE" = host ] && [ $((i % 5)) -eq 0 ]; then
    tail_=$(ssh_ "tail -5 /tmp/reinvent4-nf/build.log" 2>/dev/null || true)
    echo "[reinvent4] ${i} min: $(echo "$tail_" | tail -1 | cut -c1-160)"
    echo "$tail_" | grep -qiE "error|failed|FATAL" && { echo "[reinvent4] BUILD FAILED:"; ssh_ "tail -60 /tmp/reinvent4-nf/build.log"; exit 1; }
  fi
  # Digest change alone is success for ondemand/spot too (Batch pulls :x86).
  if [ "$MODE" != host ] && [ "$now" != "none" ] && [ "$now" != "$before" ]; then
    echo "[reinvent4] PUSHED $REGISTRY/$REPO_NAME:$TAG $now (digest changed)"
    echo "DIGEST=$now" > /tmp/biomate_reinvent4_nf_push_result.txt
    echo "URI=$REGISTRY/$REPO_NAME:$TAG" >> /tmp/biomate_reinvent4_nf_push_result.txt
    echo "PUSHED $(date -u -Iseconds) $now" > "$STATUS"
    exit 0
  fi
done
echo "[reinvent4] timed out waiting for $REPO_NAME:$TAG"
exit 1
