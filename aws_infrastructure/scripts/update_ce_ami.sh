#!/usr/bin/env bash
# update_ce_ami.sh — Update biomate-nextflow-cpu-v1 to use ami-051fc3d11efefcb16 directly.
#
# The AMI ami-051fc3d11efefcb16 (nextflow-ecs-al2-base-20251127-222233) has AWS CLI
# pre-installed via User Data. No launch template is needed — we specify the AMI
# directly via ec2Configuration.imageIdOverride on the Compute Environment.
#
# AWS Batch does NOT allow in-place AMI updates — you must:
#   1. Disable the CE
#   2. Delete it
#   3. Re-create with the correct AMI
#   4. Re-attach to the job queue
#
# Usage:
#   AWS_PROFILE=AdministratorAccess-399683337364 bash update_ce_ami.sh
#   # dry-run (shows the create-compute-environment JSON, does not apply):
#   DRY_RUN=1 bash update_ce_ami.sh

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
CE_NAME="biomate-nextflow-cpu-v1"
QUEUE_NAME="biomate-nextflow-queue"
AMI_ID="ami-051fc3d11efefcb16"
DRY_RUN="${DRY_RUN:-0}"

echo "============================================================"
echo "  BioMate Compute Environment AMI Update"
echo "  CE:    $CE_NAME"
echo "  Queue: $QUEUE_NAME"
echo "  AMI:   $AMI_ID"
echo "  DRY_RUN: $DRY_RUN"
echo "============================================================"
echo ""

# ── 1. Fetch current CE config ────────────────────────────────────────────────
echo "▶  Fetching current CE config..."
CE_JSON=$(aws batch describe-compute-environments \
    --compute-environments "$CE_NAME" \
    --region "$REGION" \
    --output json)

CE_STATUS=$(echo "$CE_JSON" | jq -r '.computeEnvironments[0].status // "MISSING"')
if [[ "$CE_STATUS" == "MISSING" ]]; then
    echo "CE $CE_NAME not found — will create fresh."
fi

# Extract existing config values (with safe defaults)
MIN_VCPUS=$(echo "$CE_JSON"  | jq -r '.computeEnvironments[0].computeResources.minvCpus    // 0')
MAX_VCPUS=$(echo "$CE_JSON"  | jq -r '.computeEnvironments[0].computeResources.maxvCpus    // 128')
INSTANCE_TYPES=$(echo "$CE_JSON" | jq -r '.computeEnvironments[0].computeResources.instanceTypes // ["m5.large","m5.xlarge","m5.2xlarge"]')
SUBNETS=$(echo "$CE_JSON"    | jq -r '.computeEnvironments[0].computeResources.subnets          // ["subnet-0254e4c3634b41bfc","subnet-03b277a7a08d388c1"]')
SEC_GROUPS=$(echo "$CE_JSON" | jq -r '.computeEnvironments[0].computeResources.securityGroupIds // []')
INSTANCE_ROLE=$(echo "$CE_JSON" | jq -r \
    '.computeEnvironments[0].computeResources.instanceRole // "arn:aws:iam::399683337364:instance-profile/ecsInstanceRole"')
ALLOC_STRATEGY=$(echo "$CE_JSON" | jq -r \
    '.computeEnvironments[0].computeResources.allocationStrategy // "BEST_FIT_PROGRESSIVE"')

# Build new compute-resources block with imageIdOverride (no launch template)
COMPUTE_RESOURCES=$(jq -n \
    --argjson minv "$MIN_VCPUS" \
    --argjson maxv "$MAX_VCPUS" \
    --argjson types "$INSTANCE_TYPES" \
    --argjson subnets "$SUBNETS" \
    --argjson sgs "$SEC_GROUPS" \
    --arg role "$INSTANCE_ROLE" \
    --arg strategy "$ALLOC_STRATEGY" \
    --arg ami "$AMI_ID" \
'{
    type: "EC2",
    minvCpus: $minv,
    maxvCpus: $maxv,
    desiredvCpus: $minv,
    instanceTypes: $types,
    subnets: $subnets,
    securityGroupIds: $sgs,
    instanceRole: $role,
    allocationStrategy: $strategy,
    ec2Configuration: [
        {
            imageType: "ECS_AL2",
            imageIdOverride: $ami
        }
    ]
}')

echo ""
echo "New computeResources:"
echo "$COMPUTE_RESOURCES" | jq .
echo ""

if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY_RUN=1 — stopping here. Set DRY_RUN=0 to apply."
    exit 0
fi

# ── 2. Detach CE from queue ───────────────────────────────────────────────────
echo "▶  Detaching $CE_NAME from $QUEUE_NAME..."
aws batch update-job-queue \
    --job-queue "$QUEUE_NAME" \
    --compute-environment-order '[]' \
    --region "$REGION" 2>/dev/null || true

echo "   Waiting 10s for queue update..."
sleep 10

# ── 3. Disable the CE ─────────────────────────────────────────────────────────
echo "▶  Disabling $CE_NAME..."
aws batch update-compute-environment \
    --compute-environment "$CE_NAME" \
    --state DISABLED \
    --region "$REGION" 2>/dev/null || true

echo "   Waiting 30s for CE to drain..."
sleep 30

# ── 4. Delete the CE ──────────────────────────────────────────────────────────
echo "▶  Deleting $CE_NAME..."
aws batch delete-compute-environment \
    --compute-environment "$CE_NAME" \
    --region "$REGION" 2>/dev/null || true

echo "   Waiting 30s for deletion..."
sleep 30

# ── 5. Create CE with new AMI ─────────────────────────────────────────────────
echo "▶  Creating $CE_NAME with AMI $AMI_ID..."
aws batch create-compute-environment \
    --compute-environment-name "$CE_NAME" \
    --type MANAGED \
    --state ENABLED \
    --compute-resources "$COMPUTE_RESOURCES" \
    --service-role "AWSServiceRoleForBatch" \
    --region "$REGION"

# ── 6. Wait for VALID ─────────────────────────────────────────────────────────
echo "▶  Waiting for CE to reach VALID state..."
for i in $(seq 1 30); do
    STATUS=$(aws batch describe-compute-environments \
        --compute-environments "$CE_NAME" \
        --region "$REGION" \
        --query 'computeEnvironments[0].status' --output text)
    echo "   [$i/30] status=$STATUS"
    [[ "$STATUS" == "VALID" ]] && break
    [[ "$STATUS" == "INVALID" ]] && { echo "INVALID — check AWS console"; exit 1; }
    sleep 10
done

# ── 7. Re-attach CE to queue ──────────────────────────────────────────────────
echo ""
echo "▶  Re-attaching $CE_NAME to $QUEUE_NAME..."
aws batch update-job-queue \
    --job-queue "$QUEUE_NAME" \
    --compute-environment-order "order=1,computeEnvironment=$CE_NAME" \
    --region "$REGION"

# ── 8. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "▶  Verifying..."
FINAL=$(aws batch describe-compute-environments \
    --compute-environments "$CE_NAME" \
    --region "$REGION" \
    --query 'computeEnvironments[0].{status:status,statusReason:statusReason,amiOverride:computeResources.ec2Configuration[0].imageIdOverride}' \
    --output json)
echo "$FINAL" | jq .

AMI_IN_CE=$(echo "$FINAL" | jq -r '.amiOverride // "not set"')
if [[ "$AMI_IN_CE" == "$AMI_ID" ]]; then
    echo ""
    echo "✅  CE updated successfully. AMI $AMI_ID is live."
else
    echo ""
    echo "⚠️  amiOverride is '$AMI_IN_CE' — check if AWS propagated ec2Configuration correctly."
fi

echo ""
echo "Done. Next run on biomate-nextflow-queue will use $AMI_ID."
