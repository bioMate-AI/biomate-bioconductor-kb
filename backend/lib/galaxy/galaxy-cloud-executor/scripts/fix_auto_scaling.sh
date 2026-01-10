#!/bin/bash
# 快速修复 AWS Batch 自动扩容问题

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
QUEUE_NAME="${AWS_BATCH_QUEUE:-galaxy-cloud-queue}"

echo "========================================"
echo "AWS Batch 自动扩容修复脚本"
echo "========================================"
echo ""
echo "区域: $REGION"
echo "队列: $QUEUE_NAME"
echo ""

# 1. 修复 Instance Profile
echo "📌 步骤 1/5: 修复 Instance Profile..."

echo "  检查 Instance Profile 是否存在..."
if aws iam get-instance-profile --instance-profile-name ecsInstanceRole >/dev/null 2>&1; then
    echo "  ✅ Instance Profile 存在"
else
    echo "  ⚠️  Instance Profile 不存在，创建中..."
    aws iam create-instance-profile --instance-profile-name ecsInstanceRole
    echo "  ✅ 已创建"
fi

echo "  检查 Role 关联..."
ROLES_COUNT=$(aws iam get-instance-profile --instance-profile-name ecsInstanceRole \
    --query 'InstanceProfile.Roles | length(@)' --output text)

if [ "$ROLES_COUNT" = "0" ]; then
    echo "  ⚠️  未关联 Role，添加中..."
    aws iam add-role-to-instance-profile \
        --instance-profile-name ecsInstanceRole \
        --role-name ecsInstanceRole
    echo "  ✅ 已关联 Role"
else
    echo "  ✅ Role 已关联"
fi

# 2. 确保 Service-Linked Role 存在
echo ""
echo "📌 步骤 2/5: 检查 Service-Linked Role..."

if aws iam get-role --role-name AWSServiceRoleForBatch >/dev/null 2>&1; then
    echo "  ✅ AWSServiceRoleForBatch 存在"
else
    echo "  ⚠️  AWSServiceRoleForBatch 不存在，创建中..."
    aws iam create-service-linked-role --aws-service-name batch.amazonaws.com
    echo "  ✅ 已创建"
fi

# 3. 获取 Compute Environment 名称
echo ""
echo "📌 步骤 3/5: 获取 Compute Environment 信息..."

CE_NAME=$(aws batch describe-job-queues \
    --job-queues "$QUEUE_NAME" \
    --region "$REGION" \
    --query 'jobQueues[0].computeEnvironmentOrder[0].computeEnvironment' \
    --output text 2>/dev/null | awk -F'/' '{print $NF}')

if [ -z "$CE_NAME" ] || [ "$CE_NAME" = "None" ]; then
    echo "  ❌ 无法找到 Compute Environment"
    echo "  请检查队列名称是否正确: $QUEUE_NAME"
    exit 1
fi

echo "  计算环境: $CE_NAME"

# 检查当前状态
CE_INFO=$(aws batch describe-compute-environments \
    --compute-environments "$CE_NAME" \
    --region "$REGION" \
    --output json)

CE_STATE=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].state')
CE_STATUS=$(echo "$CE_INFO" | jq -r '.computeEnvironments[0].status')

echo "  当前状态: $CE_STATE"
echo "  状态码: $CE_STATUS"

# 4. 触发配置重新加载
echo ""
echo "📌 步骤 4/5: 触发 Compute Environment 重新加载配置..."

echo "  等待 IAM 变更传播..."
sleep 20

echo "  禁用 Compute Environment..."
aws batch update-compute-environment \
    --compute-environment "$CE_NAME" \
    --state DISABLED \
    --region "$REGION" >/dev/null

echo "  等待状态变更..."
sleep 15

echo "  重新启用 Compute Environment..."
aws batch update-compute-environment \
    --compute-environment "$CE_NAME" \
    --state ENABLED \
    --region "$REGION" >/dev/null

echo "  等待 Compute Environment 更新完成..."

# 轮询状态直到变为 VALID
MAX_WAIT=120
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STATUS=$(aws batch describe-compute-environments \
        --compute-environments "$CE_NAME" \
        --region "$REGION" \
        --query 'computeEnvironments[0].status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$STATUS" = "VALID" ]; then
        echo "  ✅ Compute Environment 已就绪 (VALID)"
        break
    elif [ "$STATUS" = "INVALID" ]; then
        echo "  ❌ Compute Environment 状态变为 INVALID"
        REASON=$(aws batch describe-compute-environments \
            --compute-environments "$CE_NAME" \
            --region "$REGION" \
            --query 'computeEnvironments[0].statusReason' \
            --output text)
        echo "  原因: $REASON"
        exit 1
    fi

    echo "  ⏳ 等待中... ($WAITED 秒, 状态: $STATUS)"
    sleep 10
    WAITED=$((WAITED + 10))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ⚠️  等待超时，但继续执行"
fi

# 5. 验证配置
echo ""
echo "📌 步骤 5/5: 验证配置..."

# 检查最终状态
FINAL_INFO=$(aws batch describe-compute-environments \
    --compute-environments "$CE_NAME" \
    --region "$REGION" \
    --output json)

FINAL_STATE=$(echo "$FINAL_INFO" | jq -r '.computeEnvironments[0].state')
FINAL_STATUS=$(echo "$FINAL_INFO" | jq -r '.computeEnvironments[0].status')
MIN_VCPUS=$(echo "$FINAL_INFO" | jq -r '.computeEnvironments[0].computeResources.minvCpus')
MAX_VCPUS=$(echo "$FINAL_INFO" | jq -r '.computeEnvironments[0].computeResources.maxvCpus')

echo "  最终状态: $FINAL_STATE"
echo "  状态码: $FINAL_STATUS"
echo "  minvCpus: $MIN_VCPUS"
echo "  maxvCpus: $MAX_VCPUS"
echo ""

# 总结
if [ "$FINAL_STATE" = "ENABLED" ] && [ "$FINAL_STATUS" = "VALID" ] && [ "$MAX_VCPUS" != "0" ]; then
    echo "========================================"
    echo "✅ 修复成功！"
    echo "========================================"
    echo ""
    echo "配置已更新，AWS Batch 现在应该能够自动启动 EC2 实例。"
    echo ""
    echo "下一步："
    echo "1. 重新提交测试作业"
    echo "2. 观察作业是否从 RUNNABLE 进入 STARTING/RUNNING"
    echo "3. 首次启动需要 5-10 分钟（冷启动）"
    echo ""
    echo "测试命令:"
    echo "  cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
    echo "  python3 testing/test_workflow_simple.py"
    echo ""
else
    echo "========================================"
    echo "⚠️  配置可能仍有问题"
    echo "========================================"
    echo ""
    echo "当前状态不是完全正常，请运行详细诊断:"
    echo "  bash scripts/diagnose_batch.sh"
    echo ""
fi
