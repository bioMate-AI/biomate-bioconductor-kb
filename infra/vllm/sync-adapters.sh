#!/bin/bash
# Sync LoRA adapters from S3 to EFS.
#
# Called from a CI job (or manually) whenever a new adapter trains. EFS is
# mounted on every vLLM ASG node, so `start-vllm.sh` discovers the new
# adapter on the next container restart.
#
# Triggers an ASG instance refresh after the sync so the new adapter
# starts serving traffic within ~5 minutes (rolling).

set -euo pipefail

S3_BUCKET="${S3_BUCKET:-biomate-models}"
S3_PREFIX="${S3_PREFIX:-regulatory_llm/}"
EFS_MOUNT="${EFS_MOUNT:-/mnt/efs/biomate-adapters}"
ASG_NAME="${ASG_NAME:-biomate-vllm-asg}"
AWS_REGION="${AWS_REGION:-us-west-2}"

if [[ ! -d "$EFS_MOUNT" ]]; then
  echo "ERROR: EFS mount not present at $EFS_MOUNT — is mnt-efs.mount active?"
  exit 1
fi

echo "[sync-adapters] s3://$S3_BUCKET/$S3_PREFIX -> $EFS_MOUNT"
aws s3 sync "s3://$S3_BUCKET/$S3_PREFIX" "$EFS_MOUNT" \
  --region "$AWS_REGION" \
  --exclude "*" \
  --include "regulatory_llm_*/lora_adapter/*" \
  --delete

echo "[sync-adapters] EFS state after sync:"
ls -la "$EFS_MOUNT"

# Rolling restart so the new adapters start serving.
echo "[sync-adapters] triggering ASG instance refresh"
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --strategy Rolling \
  --preferences "MinHealthyPercentage=66,InstanceWarmup=120" \
  --region "$AWS_REGION" \
  --query 'InstanceRefreshId' --output text)
echo "[sync-adapters] instance refresh id: $REFRESH_ID"
echo "[sync-adapters] watch with:"
echo "  aws autoscaling describe-instance-refreshes --auto-scaling-group-name $ASG_NAME --region $AWS_REGION"
