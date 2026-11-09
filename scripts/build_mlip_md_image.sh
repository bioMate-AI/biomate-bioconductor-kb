#!/usr/bin/env bash
# Build & push biomate/mlip-md:cuda12.4-x86 (infra/docker/mlip-md/Dockerfile) for the MLIP MD workflow
# (nextflow_nfcore/subworkflows/molecular_dynamics/mlip_md_simulation). The workflow referenced
# this ECR image but it was never built, so every run failed CannotPullImageManifestError.
#
# Default (BUILD_MODE=spot): a one-shot c6i.2xlarge SPOT builder (16 GB RAM, 100 GB gp3) builds and
# pushes, reports status + log over SSM (stays up 20 min on failure), and terminates itself (hard stop after 2 h). The CUDA PyTorch image
# is several GB and the conda solve needs memory; deploy-test (t3.medium, 4 GB, a ~97 GB disk shared
# with other work) went unresponsive building even the CPU variant. Cost: ~$0.13/h spot, ~1 h build.
# BUILD_MODE=host keeps the old path: detached build on deploy-test (the dev EC2 cannot reach the ECR
# API). Either way this script polls ECR for the pushed tag. The Dockerfile's last RUN is an energy
# smoke test for both potentials, so a broken install fails the build instead of a user run.
#
# Usage: scripts/build_mlip_md_image.sh            (start build, then poll up to ~90 min)
#        BUILD_MODE=host scripts/build_mlip_md_image.sh
set -euo pipefail
export PATH="$HOME/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=us-west-2
REGISTRY=399683337364.dkr.ecr.us-west-2.amazonaws.com
REPO_NAME=biomate/mlip-md
TAG="${MLIP_TAG:-cuda12.4-x86}"   # the workflow pins this tag; bump both together when the CUDA build changes
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

if [ "${BUILD_MODE:-spot}" = spot ]; then
  AMI=$(aws ssm get-parameter --region "$REGION" --query Parameter.Value --output text \
    --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id)
  UD=$(mktemp); trap 'rm -f "$UD"' EXIT
  {
    echo '#!/bin/bash'
    echo 'shutdown -h +120   # hard stop: the instance terminates on shutdown'
    echo 'exec > /var/log/mlip-build.log 2>&1; set -x'
    # On failure stay up 20 min so the poller can read the log over SSM (the serial console does not
    # carry it); /var/log/mlip-build.status tells the poller the build has ended. grep -x: under set -x
    # this trap's own text is traced into the log, so a substring match always read as success (two
    # failed builds shut down as 'ok').
    echo "trap 'if grep -qx BUILD_PUSH_OK /var/log/mlip-build.log; then echo ok > /var/log/mlip-build.status; shutdown -h now; else echo failed > /var/log/mlip-build.status; shutdown -h +20; fi' EXIT"
    echo 'apt-get update -qq && apt-get install -y -qq docker.io docker-buildx unzip curl'
    echo 'curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && unzip -q /tmp/a.zip -d /tmp && /tmp/aws/install'
    echo 'mkdir -p /build && cd /build && base64 -d > Dockerfile <<"B64"'
    base64 < "$REPO_ROOT/infra/docker/mlip-md/Dockerfile"
    echo 'B64'
    echo "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY"
    # The unique build-<instance-id> tag is this build's receipt: the poller accepts :$TAG only when
    # it carries the same digest (the serial console is not a reliable channel for the log).
    echo "TOKEN=\$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')"
    echo "BT=build-\$(curl -s -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/instance-id)"
    echo "DOCKER_BUILDKIT=1 docker build -t $REGISTRY/$REPO_NAME:$TAG . && docker tag $REGISTRY/$REPO_NAME:$TAG $REGISTRY/$REPO_NAME:\$BT \\"
    echo "  && docker push $REGISTRY/$REPO_NAME:\$BT && docker push $REGISTRY/$REPO_NAME:$TAG && echo BUILD_PUSH_OK"
  } > "$UD"
  BUILDER=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --instance-type c6i.2xlarge \
    --subnet-id "${BUILD_SUBNET:-subnet-09e4dce46682a6c60}" --security-group-ids "${BUILD_SG:-sg-0a70bb26e47332c55}" \
    --iam-instance-profile Name=BioMateEc2DeployProfile \
    --instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}' \
    --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=100,VolumeType=gp3,DeleteOnTermination=true}' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=biomate-mlip-md-builder}]' \
    --user-data "file://$UD" --query 'Instances[0].InstanceId' --output text)
  echo "[mlip] spot builder $BUILDER started (status + log over SSM); polling ECR"
  builder_gone() { st=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$BUILDER" \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null); [ "$st" = terminated ] || [ "$st" = shutting-down ]; }
else
  ssh_ "mkdir -p /tmp/mlip-md"
  scp_ "$REPO_ROOT/infra/docker/mlip-md/Dockerfile" "${EC2_USER}@${INSTANCE_ID}:/tmp/mlip-md/Dockerfile"
  ssh_ "cd /tmp/mlip-md && nohup bash -c 'aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $REGISTRY >/dev/null \
    && sudo DOCKER_BUILDKIT=1 docker build -t $REGISTRY/$REPO_NAME:$TAG . && sudo docker push $REGISTRY/$REPO_NAME:$TAG && echo BUILD_PUSH_OK' > build.log 2>&1 &"
  echo "[mlip] build started on $INSTANCE_ID (log: /tmp/mlip-md/build.log); polling ECR"
  builder_gone() { false; }
fi

for i in $(seq 1 125); do   # spot builder self-terminates at 120 min
  sleep 60
  now=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="$TAG" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
  if [ "${BUILD_MODE:-spot}" != spot ] && [ "$now" != "none" ] && [ "$now" != "$before" ]; then
    echo "[mlip] pushed $REPO_NAME:$TAG $now"; exit 0; fi
  if [ "${BUILD_MODE:-spot}" = spot ] && [ $((i % 3)) -eq 0 ] && ! builder_gone; then
    cid=$(aws ssm send-command --region "$REGION" --instance-ids "$BUILDER" --document-name AWS-RunShellScript \
      --parameters 'commands=["cat /var/log/mlip-build.status 2>/dev/null || echo running","tail -c 6000 /var/log/mlip-build.log"]' \
      --query Command.CommandId --output text 2>/dev/null || true)
    if [ -n "$cid" ]; then
      sleep 15
      out=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cid" --instance-id "$BUILDER" \
        --query StandardOutputContent --output text 2>/dev/null || true)
      echo "[mlip] ${i} min: $(printf '%s\n' "$out" | grep -v '^\s*$' | tail -1 | cut -c1-160)"
      if [ "$(printf '%s\n' "$out" | head -1)" = failed ]; then
        echo "[mlip] BUILD FAILED on $BUILDER; log tail:"; printf '%s\n' "$out" | tail -n +2 | tail -60
        aws ec2 terminate-instances --region "$REGION" --instance-ids "$BUILDER" >/dev/null; exit 1
      fi
    fi
  fi
  if builder_gone; then
    # Spot mode judges by this build's receipt tag, not the ECR digest alone: another build pushing
    # the same tag (e.g. a host-mode run still going) must not read as this build's success.
    receipt=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" --image-ids imageTag="build-$BUILDER" \
      --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo none)
    if [ "$receipt" != none ] && [ "$receipt" = "$now" ]; then
      echo "[mlip] pushed $REPO_NAME:$TAG $now (receipt tag build-$BUILDER)"; exit 0
    fi
    echo "[mlip] builder terminated without pushing $REPO_NAME:$TAG (receipt=$receipt, $TAG=$now) — spot interruption or hard stop"
    exit 1
  fi
  if [ "${BUILD_MODE:-spot}" != spot ] && [ $((i % 5)) -eq 0 ]; then
    tail_=$(ssh_ "tail -3 /tmp/mlip-md/build.log" 2>/dev/null || true)
    echo "[mlip] ${i} min: $(echo "$tail_" | tail -1 | cut -c1-140)"
    echo "$tail_" | grep -qiE "error|failed|AssertionError" && { echo "[mlip] BUILD FAILED:"; ssh_ "tail -40 /tmp/mlip-md/build.log"; exit 1; }
  fi
done
echo "[mlip] timed out waiting for the push"; exit 1
