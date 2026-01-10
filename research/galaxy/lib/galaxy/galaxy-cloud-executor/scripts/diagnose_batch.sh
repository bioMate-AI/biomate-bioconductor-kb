#!/bin/bash
# AWS Batch 诊断脚本
# 检查为什么作业卡在 RUNNABLE 状态

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
QUEUE_NAME="${AWS_BATCH_QUEUE}"

if [ -z "$QUEUE_NAME" ]; then
    echo "❌ 请设置 AWS_BATCH_QUEUE 环境变量"
    exit 1
fi

echo "========================================"
echo "AWS Batch 配置诊断"
echo "========================================"
echo ""
echo "区域: $REGION"
echo "队列: $QUEUE_NAME"
echo ""

# 1. 检查 Job Queue 状态
echo "📋 1. 检查 Job Queue 状态..."
QUEUE_INFO=$(aws batch describe-job-queues \
    --job-queues "$QUEUE_NAME" \
    --region "$REGION" \
    --output json)

QUEUE_STATE=$(echo "$QUEUE_INFO" | jq -r '.jobQueues[0].state')
QUEUE_STATUS=$(echo "$QUEUE_INFO" | jq -r '.jobQueues[0].status')

echo "  队列状态: $QUEUE_STATE"
echo "  队列状态码: $QUEUE_STATUS"

if [ "$QUEUE_STATE" != "ENABLED" ]; then
    echo "  ❌ 队列未启用！"
    echo "  修复命令:"
    echo "    aws batch update-job-queue --job-queue $QUEUE_NAME --state ENABLED --region $REGION"
    exit 1
fi

if [ "$QUEUE_STATUS" != "VALID" ]; then
    echo "  ⚠️  队列状态不是 VALID"
fi

echo "  ✅ 队列状态正常"
echo ""

# 2. 检查关联的 Compute Environment
echo "📊 2. 检查 Compute Environment..."
CE_ARN=$(echo "$QUEUE_INFO" | jq -r '.jobQueues[0].computeEnvironmentOrder[0].computeEnvironment')
CE_NAME=$(echo "$CE_ARN" | awk -F'/' '{print $NF}')

echo "  计算环境 ARN: $CE_ARN"
echo "  计算环境名称: $CE_NAME"

if [ -z "$CE_NAME" ] || [ "$CE_NAME" = "null" ]; then
    echo "  ❌ 队列没有关联计算环境！"
    exit 1
fi

# 获取 Compute Environment 详情
CE_INFO=$(aws batch describe-compute-environments \
    --compute-environments "$CE_NAME" \
    --region "$REGION" \
    --output json)

CE_STATE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].state')
CE_STATUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].status')
CE_TYPE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].type')

echo ""
echo "  计算环境状态: $CE_STATE"
echo "  计算环境状态码: $CE_STATUS"
echo "  计算环境类型: $CE_TYPE"

if [ "$CE_STATE" != "ENABLED" ]; then
    echo "  ❌ 计算环境未启用！"
    echo "  修复命令:"
    echo "    aws batch update-compute-environment --compute-environment $CE_NAME --state ENABLED --region $REGION"
    exit 1
fi

if [ "$CE_STATUS" != "VALID" ]; then
    echo "  ❌ 计算环境状态不是 VALID！"
    echo "  状态原因:"
    echo "$CE_INFO" | jq -r '.computeEnvironments[0].statusReason'
    exit 1
fi

echo "  ✅ 计算环境状态正常"
echo ""

# 3. 检查 Compute Resources 配置
echo "🖥️  3. 检查 Compute Resources 配置..."
MIN_VCPUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.minvCpus')
MAX_VCPUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.maxvCpus')
DESIRED_VCPUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.desiredvCpus')
INSTANCE_TYPES=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.instanceTypes | join(", ")')
SUBNETS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.subnets | join(", ")')
SECURITY_GROUPS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.securityGroupIds | join(", ")')
INSTANCE_ROLE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].computeResources.instanceRole')

echo "  minvCpus: $MIN_VCPUS"
echo "  maxvCpus: $MAX_VCPUS"
echo "  desiredvCpus: $DESIRED_VCPUS"
echo "  实例类型: $INSTANCE_TYPES"
echo "  子网: $SUBNETS"
echo "  安全组: $SECURITY_GROUPS"
echo "  实例角色: $INSTANCE_ROLE"
echo ""

if [ "$MAX_VCPUS" = "0" ] || [ "$MAX_VCPUS" = "null" ]; then
    echo "  ❌ maxvCpus 为 0 或未设置！"
    echo "  AWS Batch 无法启动任何实例"
    echo "  修复命令:"
    echo "    aws batch update-compute-environment --compute-environment $CE_NAME --compute-resources maxvCpus=256 --region $REGION"
    exit 1
fi

# 4. 检查 Service Role
echo "🔐 4. 检查 Service Role..."
SERVICE_ROLE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].serviceRole')
echo "  Service Role: $SERVICE_ROLE"

if [ -z "$SERVICE_ROLE" ] || [ "$SERVICE_ROLE" = "null" ]; then
    echo "  ❌ Service Role 未设置！"
    exit 1
fi

# 检查 Service Role 是否存在
ROLE_NAME=$(echo "$SERVICE_ROLE" | awk -F'/' '{print $NF}')
ROLE_CHECK=$(aws iam get-role --role-name "$ROLE_NAME" 2>&1 || echo "NOT_FOUND")

if echo "$ROLE_CHECK" | grep -q "NOT_FOUND\|NoSuchEntity"; then
    echo "  ❌ Service Role 不存在！"
    exit 1
fi

echo "  ✅ Service Role 存在"
echo ""

# 5. 检查 Instance Profile
echo "👤 5. 检查 Instance Profile..."
INSTANCE_ROLE_NAME=$(echo "$INSTANCE_ROLE" | awk -F'/' '{print $NF}')
echo "  Instance Profile: $INSTANCE_ROLE_NAME"

PROFILE_CHECK=$(aws iam get-instance-profile --instance-profile-name "$INSTANCE_ROLE_NAME" 2>&1 || echo "NOT_FOUND")

if echo "$PROFILE_CHECK" | grep -q "NOT_FOUND\|NoSuchEntity"; then
    echo "  ❌ Instance Profile 不存在！"
    echo "  修复命令:"
    echo "    aws iam create-instance-profile --instance-profile-name $INSTANCE_ROLE_NAME"
    echo "    aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_ROLE_NAME --role-name $INSTANCE_ROLE_NAME"
    exit 1
fi

# 检查 Instance Profile 是否关联了 Role
PROFILE_ROLES=$(echo "$PROFILE_CHECK" | jq -r '.InstanceProfile.Roles | length')
if [ "$PROFILE_ROLES" = "0" ]; then
    echo "  ❌ Instance Profile 没有关联 IAM Role！"
    echo "  修复命令:"
    echo "    aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_ROLE_NAME --role-name $INSTANCE_ROLE_NAME"
    exit 1
fi

echo "  ✅ Instance Profile 配置正常"
echo ""

# 6. 检查子网和安全组
echo "🌐 6. 检查网络配置..."

# 检查子网
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS"
for subnet in "${SUBNET_ARRAY[@]}"; do
    subnet=$(echo "$subnet" | xargs)  # trim whitespace
    SUBNET_CHECK=$(aws ec2 describe-subnets --subnet-ids "$subnet" --region "$REGION" 2>&1 || echo "NOT_FOUND")

    if echo "$SUBNET_CHECK" | grep -q "NOT_FOUND\|InvalidSubnetID"; then
        echo "  ❌ 子网 $subnet 不存在或无效！"
        exit 1
    fi

    SUBNET_AZ=$(echo "$SUBNET_CHECK" | jq -r '.Subnets[0].AvailabilityZone')
    SUBNET_AVAILABLE_IPS=$(echo "$SUBNET_CHECK" | jq -r '.Subnets[0].AvailableIpAddressCount')

    echo "  子网 $subnet:"
    echo "    可用区: $SUBNET_AZ"
    echo "    可用 IP: $SUBNET_AVAILABLE_IPS"

    if [ "$SUBNET_AVAILABLE_IPS" = "0" ]; then
        echo "    ⚠️  子网没有可用 IP 地址！"
    fi
done

echo "  ✅ 网络配置正常"
echo ""

# 7. 检查当前运行的实例
echo "🚀 7. 检查当前运行的 EC2 实例..."
ECS_CLUSTER=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].ecsClusterArn' | awk -F'/' '{print $NF}')
echo "  ECS 集群: $ECS_CLUSTER"

if [ "$ECS_CLUSTER" != "null" ] && [ -n "$ECS_CLUSTER" ]; then
    CONTAINER_INSTANCES=$(aws ecs list-container-instances \
        --cluster "$ECS_CLUSTER" \
        --region "$REGION" \
        --output json 2>/dev/null || echo '{"containerInstanceArns":[]}')

    INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCES" | jq -r '.containerInstanceArns | length')
    echo "  容器实例数量: $INSTANCE_COUNT"

    if [ "$INSTANCE_COUNT" = "0" ]; then
        echo "  ⚠️  当前没有运行的 EC2 实例"
        echo "  这是正常的（minvCpus=0 时）"
        echo "  提交作业后，AWS Batch 应该会自动启动实例"
    else
        echo "  ✅ 有 $INSTANCE_COUNT 个运行中的实例"

        # 显示实例详情
        if [ "$INSTANCE_COUNT" -gt 0 ]; then
            echo ""
            echo "  实例详情:"
            INSTANCE_ARNS=$(echo "$CONTAINER_INSTANCES" | jq -r '.containerInstanceArns[]')
            aws ecs describe-container-instances \
                --cluster "$ECS_CLUSTER" \
                --container-instances $INSTANCE_ARNS \
                --region "$REGION" \
                --output json | jq -r '.containerInstances[] | "    - EC2: \(.ec2InstanceId), 状态: \(.status), 注册资源: \(.registeredResources[] | select(.name=="CPU") | .integerValue) vCPUs"'
        fi
    fi
else
    echo "  ⚠️  无法获取 ECS 集群信息"
fi

echo ""

# 8. 检查最近的作业状态
echo "📝 8. 检查最近的作业..."
RECENT_JOBS=$(aws batch list-jobs \
    --job-queue "$QUEUE_NAME" \
    --job-status RUNNABLE \
    --region "$REGION" \
    --max-items 5 \
    --output json)

RUNNABLE_COUNT=$(echo "$RECENT_JOBS" | jq -r '.jobSummaryList | length')
echo "  RUNNABLE 状态作业数: $RUNNABLE_COUNT"

if [ "$RUNNABLE_COUNT" -gt 0 ]; then
    echo ""
    echo "  作业列表:"
    echo "$RECENT_JOBS" | jq -r '.jobSummaryList[] | "    - \(.jobName) (ID: \(.jobId))"'

    # 获取第一个作业的详细信息
    FIRST_JOB_ID=$(echo "$RECENT_JOBS" | jq -r '.jobSummaryList[0].jobId')
    echo ""
    echo "  检查作业详情: $FIRST_JOB_ID"
    JOB_DETAIL=$(aws batch describe-jobs \
        --jobs "$FIRST_JOB_ID" \
        --region "$REGION" \
        --output json)

    STATUS_REASON=$(echo "$JOB_DETAIL" | jq -r '.jobs[0].statusReason // "无"')
    echo "    状态原因: $STATUS_REASON"
fi

echo ""
echo "========================================"
echo "诊断总结"
echo "========================================"
echo ""

# 生成诊断报告
if [ "$CE_STATE" = "ENABLED" ] && [ "$CE_STATUS" = "VALID" ] && [ "$QUEUE_STATE" = "ENABLED" ]; then
    if [ "$RUNNABLE_COUNT" -gt 0 ]; then
        echo "⚠️  配置看起来正常，但有作业卡在 RUNNABLE 状态"
        echo ""
        echo "可能的原因:"
        echo ""
        echo "1. 冷启动延迟（正常情况）"
        echo "   - 如果刚提交作业，等待 5-10 分钟"
        echo "   - AWS Batch 正在启动 EC2 实例"
        echo ""
        echo "2. 资源限制"
        echo "   - 检查 AWS 账户的 EC2 实例限额"
        echo "   - 检查子网是否有足够的 IP 地址"
        echo ""
        echo "3. Service-Linked Role 问题"
        echo "   - 可能缺少 AWSServiceRoleForBatch"
        echo "   - 修复命令: aws iam create-service-linked-role --aws-service-name batch.amazonaws.com"
        echo ""
        echo "4. Launch Template 或 AMI 问题"
        echo "   - 检查 Launch Template 是否有效"
        echo "   - 检查 AMI 是否在当前区域可用"
        echo ""

        echo "🔍 建议操作:"
        echo ""
        echo "1. 检查 CloudWatch Logs 是否有错误:"
        echo "   aws logs tail /aws/batch/job --follow --region $REGION"
        echo ""
        echo "2. 检查 AWS 个人健康仪表板:"
        echo "   https://phd.aws.amazon.com/"
        echo ""
        echo "3. 手动触发扩容测试:"
        echo "   aws batch update-compute-environment \\"
        echo "     --compute-environment $CE_NAME \\"
        echo "     --compute-resources desiredvCpus=2 \\"
        echo "     --region $REGION"
        echo ""
        echo "4. 查看 EC2 Auto Scaling 组:"
        echo "   aws autoscaling describe-auto-scaling-groups --region $REGION | grep -A 10 $CE_NAME"
    else
        echo "✅ 配置正常，没有卡住的作业"
    fi
else
    echo "❌ 发现配置问题，请检查上面的错误信息"
fi

echo ""
