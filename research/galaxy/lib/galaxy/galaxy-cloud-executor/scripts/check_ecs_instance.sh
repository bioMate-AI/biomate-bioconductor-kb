#!/bin/bash
# 检查 ECS 实例是否成功注册

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
INSTANCE_ID="${1:-}"

echo "========================================"
echo "检查 ECS 实例注册状态"
echo "========================================"
echo ""

# 1. 获取 ECS 集群名称
echo "📋 1. 获取 ECS 集群..."
ECS_CLUSTER=$(aws batch describe-compute-environments --region "$REGION" \
    --query 'computeEnvironments[0].ecsClusterArn' --output text | awk -F'/' '{print $NF}')

echo "  ECS 集群: $ECS_CLUSTER"
echo ""

# 2. 列出容器实例
echo "💻 2. 检查容器实例..."
CONTAINER_INSTANCES=$(aws ecs list-container-instances \
    --cluster "$ECS_CLUSTER" \
    --region "$REGION" \
    --output json)

INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCES" | jq -r '.containerInstanceArns | length')

echo "  容器实例数量: $INSTANCE_COUNT"
echo ""

if [ "$INSTANCE_COUNT" = "0" ]; then
    echo "  ⚠️  没有注册的容器实例"
    echo ""
    echo "  可能的原因："
    echo "  1. 实例刚启动，ECS Agent 还在注册中（等待 2-3 分钟）"
    echo "  2. ECS Agent 启动失败"
    echo "  3. 实例无法访问 ECS API"
    echo ""

    # 检查 EC2 实例状态
    if [ -n "$INSTANCE_ID" ]; then
        echo "  检查 EC2 实例 $INSTANCE_ID..."
        INSTANCE_INFO=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")

        if [ "$INSTANCE_INFO" != "{}" ]; then
            STATE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].State.Name')
            LAUNCH_TIME=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].LaunchTime')

            echo "    EC2 状态: $STATE"
            echo "    启动时间: $LAUNCH_TIME"

            # 计算运行时间
            LAUNCH_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAUNCH_TIME%.*}" "+%s" 2>/dev/null || echo "0")
            NOW_EPOCH=$(date "+%s")
            UPTIME=$((NOW_EPOCH - LAUNCH_EPOCH))

            echo "    运行时间: $UPTIME 秒"

            if [ "$UPTIME" -lt 180 ]; then
                echo ""
                echo "  💡 实例刚启动 ($UPTIME 秒)，ECS Agent 需要 2-3 分钟注册"
                echo "     请等待后重新检查"
            fi
        fi
    fi

    exit 0
fi

# 3. 显示容器实例详情
echo "📊 3. 容器实例详情..."

INSTANCE_ARNS=$(echo "$CONTAINER_INSTANCES" | jq -r '.containerInstanceArns[]')

INSTANCE_DETAILS=$(aws ecs describe-container-instances \
    --cluster "$ECS_CLUSTER" \
    --container-instances $INSTANCE_ARNS \
    --region "$REGION" \
    --output json)

echo "$INSTANCE_DETAILS" | jq -r '.containerInstances[] |
    "
    实例 ARN: \(.containerInstanceArn | split("/") | last)
    EC2 实例 ID: \(.ec2InstanceId)
    状态: \(.status)
    Agent 连接状态: \(.agentConnected)
    运行任务数: \(.runningTasksCount)
    待处理任务数: \(.pendingTasksCount)
    注册资源:
      - CPU: \(.registeredResources[] | select(.name=="CPU") | .integerValue) vCPUs
      - 内存: \(.registeredResources[] | select(.name=="MEMORY") | .integerValue) MB
    剩余资源:
      - CPU: \(.remainingResources[] | select(.name=="CPU") | .integerValue) vCPUs
      - 内存: \(.remainingResources[] | select(.name=="MEMORY") | .integerValue) MB
    "
'

# 4. 检查实例是否可以运行任务
echo ""
echo "✅ 4. 实例注册状态总结..."

AGENT_CONNECTED=$(echo "$INSTANCE_DETAILS" | jq -r '.containerInstances[0].agentConnected')
STATUS=$(echo "$INSTANCE_DETAILS" | jq -r '.containerInstances[0].status')

if [ "$AGENT_CONNECTED" = "true" ] && [ "$STATUS" = "ACTIVE" ]; then
    echo "  ✅ ECS Agent 已连接且实例状态正常"
    echo "  ✅ 实例可以接受任务"
    echo ""
    echo "  现在可以提交作业测试了！"
    echo ""
    echo "  测试命令:"
    echo "    cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
    echo "    python3 testing/test_workflow_simple.py"
else
    echo "  ⚠️  实例状态异常"
    echo "  Agent 连接: $AGENT_CONNECTED"
    echo "  实例状态: $STATUS"
fi

echo ""
echo "========================================"
