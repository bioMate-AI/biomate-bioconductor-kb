#!/bin/bash
# 重新创建 Compute Environment（修复 AMI 和配置问题）

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
QUEUE_NAME="${AWS_BATCH_QUEUE:-galaxy-cloud-queue}"

echo "========================================"
echo "重新创建 Compute Environment"
echo "========================================"
echo ""

# 1. 获取正确的 ECS-optimized AMI
echo "📋 1. 获取最新的 ECS-optimized AMI..."
ECS_AMI=$(aws ssm get-parameter \
    --name /aws/service/ecs/optimized-ami/amazon-linux-2/recommended \
    --region "$REGION" \
    --query 'Parameter.Value' --output text | jq -r '.image_id')

echo "  ECS-optimized AMI: $ECS_AMI"
echo ""

# 2. 获取当前的 Compute Environment 配置
echo "📊 2. 获取当前配置..."
QUEUE_INFO=$(aws batch describe-job-queues \
    --job-queues "$QUEUE_NAME" \
    --region "$REGION" \
    --output json)

OLD_CE_ARN=$(echo "$QUEUE_INFO" | jq -r '.jobQueues[0].computeEnvironmentOrder[0].computeEnvironment')
OLD_CE_NAME=$(echo "$OLD_CE_ARN" | awk -F'/' '{print $NF}')

echo "  旧的 Compute Environment: $OLD_CE_NAME"

# 获取详细配置
CE_INFO=$(aws batch describe-compute-environments \
    --compute-environments "$OLD_CE_NAME" \
    --region "$REGION" \
    --output json)

# 提取配置
SERVICE_ROLE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].serviceRole')
MIN_VCPUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.minvCpus')
MAX_VCPUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.maxvCpus')
INSTANCE_TYPES=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.instanceTypes')
SUBNETS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.subnets')
SECURITY_GROUPS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.securityGroupIds')
INSTANCE_ROLE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.instanceRole')
ALLOCATION_STRATEGY=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.allocationStrategy // "BEST_FIT_PROGRESSIVE"')
EC2_KEY_PAIR=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.ec2KeyPair // null')

echo "  Service Role: $SERVICE_ROLE"
echo "  Min vCPUs: $MIN_VCPUS"
echo "  Max vCPUs: $MAX_VCPUS"
echo "  Instance Types: $INSTANCE_TYPES"
echo "  Allocation Strategy: $ALLOCATION_STRATEGY"
echo ""

# 3. 确认操作
echo "⚠️  警告: 这将删除旧的 Compute Environment 并创建新的"
echo ""
read -p "是否继续? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "操作已取消"
    exit 0
fi

# 4. 从 Job Queue 中移除旧的 Compute Environment
echo ""
echo "📤 3. 从 Job Queue 中移除旧的 Compute Environment..."
aws batch update-job-queue \
    --job-queue "$QUEUE_NAME" \
    --compute-environment-order \
    --region "$REGION" || echo "  ⚠️  可能已经移除"

sleep 5

# 5. 禁用旧的 Compute Environment
echo ""
echo "🔴 4. 禁用旧的 Compute Environment..."
aws batch update-compute-environment \
    --compute-environment "$OLD_CE_NAME" \
    --state DISABLED \
    --region "$REGION"

echo "  等待状态变更..."
sleep 30

# 6. 删除旧的 Compute Environment
echo ""
echo "🗑️  5. 删除旧的 Compute Environment..."
aws batch delete-compute-environment \
    --compute-environment "$OLD_CE_NAME" \
    --region "$REGION"

echo "  等待删除完成..."
sleep 30

# 7. 创建新的 Compute Environment
NEW_CE_NAME="galaxy-cloud-compute-v2"

echo ""
echo "🆕 6. 创建新的 Compute Environment: $NEW_CE_NAME..."

# 构建 compute-resources JSON
COMPUTE_RESOURCES=$(cat <<EOF
{
    "type": "EC2",
    "minvCpus": $MIN_VCPUS,
    "maxvCpus": $MAX_VCPUS,
    "desiredvCpus": $MIN_VCPUS,
    "instanceTypes": $INSTANCE_TYPES,
    "imageId": "$ECS_AMI",
    "subnets": $SUBNETS,
    "securityGroupIds": $SECURITY_GROUPS,
    "instanceRole": "$INSTANCE_ROLE",
    "allocationStrategy": "$ALLOCATION_STRATEGY"
}
EOF
)

# 如果有 EC2 Key Pair，添加
if [ "$EC2_KEY_PAIR" != "null" ]; then
    COMPUTE_RESOURCES=$(echo "$COMPUTE_RESOURCES" | jq --arg key "$EC2_KEY_PAIR" '. + {ec2KeyPair: $key}')
fi

echo "  配置:"
echo "$COMPUTE_RESOURCES" | jq .

# 创建
aws batch create-compute-environment \
    --compute-environment-name "$NEW_CE_NAME" \
    --type MANAGED \
    --state ENABLED \
    --compute-resources "$COMPUTE_RESOURCES" \
    --service-role "$SERVICE_ROLE" \
    --region "$REGION"

echo "  ✅ Compute Environment 已创建"
echo ""

# 8. 等待 Compute Environment 变为 VALID
echo "⏳ 7. 等待 Compute Environment 变为 VALID..."

MAX_WAIT=180
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STATUS=$(aws batch describe-compute-environments \
        --compute-environments "$NEW_CE_NAME" \
        --region "$REGION" \
        --query 'computeEnvironments[0].status' \
        --output text 2>/dev/null || echo "CREATING")

    if [ "$STATUS" = "VALID" ]; then
        echo "  ✅ Compute Environment 已就绪"
        break
    elif [ "$STATUS" = "INVALID" ]; then
        echo "  ❌ Compute Environment 状态变为 INVALID"
        REASON=$(aws batch describe-compute-environments \
            --compute-environments "$NEW_CE_NAME" \
            --region "$REGION" \
            --query 'computeEnvironments[0].statusReason' \
            --output text)
        echo "  原因: $REASON"
        exit 1
    fi

    echo "  等待中... ($WAITED 秒, 状态: $STATUS)"
    sleep 10
    WAITED=$((WAITED + 10))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ⚠️  等待超时"
    exit 1
fi

# 9. 将新的 Compute Environment 关联到 Job Queue
echo ""
echo "🔗 8. 将新的 Compute Environment 关联到 Job Queue..."

aws batch update-job-queue \
    --job-queue "$QUEUE_NAME" \
    --compute-environment-order order=1,computeEnvironment="$NEW_CE_NAME" \
    --region "$REGION"

echo "  ✅ 已关联到 Job Queue"
echo ""

# 10. 验证
echo "✅ 9. 验证配置..."

FINAL_QUEUE_INFO=$(aws batch describe-job-queues \
    --job-queues "$QUEUE_NAME" \
    --region "$REGION" \
    --output json)

NEW_CE_IN_QUEUE=$(echo "$FINAL_QUEUE_INFO" | jq -r '.jobQueues[0].computeEnvironmentOrder[0].computeEnvironment')

echo "  Job Queue: $QUEUE_NAME"
echo "  关联的 Compute Environment: $NEW_CE_IN_QUEUE"
echo ""

# 显示新的 Auto Scaling Group
echo "🔍 查找新的 Auto Scaling Group..."
sleep 10

NEW_ASG=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$NEW_CE_NAME')].AutoScalingGroupName" \
    --output text)

if [ -n "$NEW_ASG" ]; then
    echo "  新的 ASG: $NEW_ASG"

    ASG_DETAIL=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$NEW_ASG" \
        --region "$REGION" \
        --output json)

    LT_ID=$(echo "$ASG_DETAIL" | jq -r '.AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId')

    LT_AMI=$(aws ec2 describe-launch-template-versions \
        --launch-template-id "$LT_ID" \
        --region "$REGION" \
        --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' \
        --output text)

    echo "  使用的 AMI: $LT_AMI"

    if [ "$LT_AMI" = "$ECS_AMI" ]; then
        echo "  ✅ AMI 配置正确"
    else
        echo "  ⚠️  AMI 不匹配！"
    fi
fi

echo ""
echo "========================================"
echo "✅ Compute Environment 重建完成！"
echo "========================================"
echo ""
echo "下一步："
echo "1. 重新提交测试作业"
echo "2. 观察 EC2 实例是否成功启动"
echo "3. 首次启动需要 5-10 分钟"
echo ""
echo "测试命令:"
echo "  cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
echo "  python3 testing/test_workflow_simple.py"
echo ""
