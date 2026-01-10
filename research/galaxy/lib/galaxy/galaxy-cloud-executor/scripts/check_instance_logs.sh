#!/bin/bash
# 检查 EC2 实例的详细状态和日志

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
INSTANCE_ID="${1}"

if [ -z "$INSTANCE_ID" ]; then
    echo "用法: $0 <instance-id>"
    exit 1
fi

echo "========================================"
echo "检查 EC2 实例详细状态"
echo "========================================"
echo "实例 ID: $INSTANCE_ID"
echo ""

# 1. 获取实例详情
echo "📊 1. 实例基本信息..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --output json)

STATE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].State.Name')
LAUNCH_TIME=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].LaunchTime')
INSTANCE_TYPE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].InstanceType')
AZ=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')
SUBNET=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].SubnetId')
PRIVATE_IP=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "无"')
IAM_PROFILE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].IamInstanceProfile.Arn // "未设置"')

echo "  状态: $STATE"
echo "  启动时间: $LAUNCH_TIME"
echo "  实例类型: $INSTANCE_TYPE"
echo "  可用区: $AZ"
echo "  子网: $SUBNET"
echo "  私有 IP: $PRIVATE_IP"
echo "  公共 IP: $PUBLIC_IP"
echo "  IAM Profile: $IAM_PROFILE"
echo ""

# 计算运行时间
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    LAUNCH_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAUNCH_TIME%.*}" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S.%Z" "$LAUNCH_TIME" "+%s" 2>/dev/null || echo "0")
else
    # Linux
    LAUNCH_EPOCH=$(date -d "$LAUNCH_TIME" "+%s" 2>/dev/null || echo "0")
fi

NOW_EPOCH=$(date "+%s")
UPTIME=$((NOW_EPOCH - LAUNCH_EPOCH))

echo "  运行时间: $UPTIME 秒 ($(($UPTIME / 60)) 分钟)"
echo ""

if [ "$UPTIME" -lt 180 ]; then
    echo "  💡 实例刚启动，ECS Agent 需要 2-5 分钟初始化和注册"
    echo "     建议再等待 $((180 - UPTIME)) 秒"
    echo ""
fi

# 2. 检查用户数据（User Data）
echo "📝 2. 检查用户数据（User Data）..."
USER_DATA=$(aws ec2 describe-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --attribute userData \
    --region "$REGION" \
    --query 'UserData.Value' \
    --output text 2>/dev/null | base64 -d 2>/dev/null || echo "无法获取")

if [ "$USER_DATA" != "无法获取" ]; then
    echo "  用户数据内容:"
    echo "$USER_DATA" | head -20
    echo ""

    # 检查 ECS 集群配置
    if echo "$USER_DATA" | grep -q "ECS_CLUSTER"; then
        CLUSTER_IN_USERDATA=$(echo "$USER_DATA" | grep "ECS_CLUSTER" | head -1)
        echo "  ✅ 用户数据包含 ECS 集群配置: $CLUSTER_IN_USERDATA"
    else
        echo "  ⚠️  用户数据中未找到 ECS_CLUSTER 配置"
    fi
else
    echo "  ⚠️  无法获取用户数据"
fi
echo ""

# 3. 检查系统状态
echo "🔍 3. 检查系统状态..."
STATUS_CHECKS=$(aws ec2 describe-instance-status \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{"InstanceStatuses":[]}')

if [ "$(echo "$STATUS_CHECKS" | jq '.InstanceStatuses | length')" -gt 0 ]; then
    SYSTEM_STATUS=$(echo "$STATUS_CHECKS" | jq -r '.InstanceStatuses[0].SystemStatus.Status')
    INSTANCE_STATUS=$(echo "$STATUS_CHECKS" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')

    echo "  系统状态检查: $SYSTEM_STATUS"
    echo "  实例状态检查: $INSTANCE_STATUS"

    if [ "$SYSTEM_STATUS" != "ok" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
        echo "  ⚠️  状态检查未通过，实例可能还在初始化中"
    else
        echo "  ✅ 状态检查通过"
    fi
else
    echo "  ⏳ 状态检查数据尚未可用（实例刚启动）"
fi
echo ""

# 4. 检查标签
echo "🏷️  4. 检查实例标签..."
TAGS=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].Tags[]? | "\(.Key)=\(.Value)"')

if [ -n "$TAGS" ]; then
    echo "$TAGS" | while read tag; do
        echo "  $tag"
    done
else
    echo "  无标签"
fi
echo ""

# 5. 尝试获取系统日志（Console Output）
echo "📜 5. 获取系统控制台日志（最后 50 行）..."
CONSOLE_OUTPUT=$(aws ec2 get-console-output \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --output text 2>/dev/null || echo "")

if [ -n "$CONSOLE_OUTPUT" ]; then
    echo "$CONSOLE_OUTPUT" | tail -50
    echo ""

    # 检查关键信息
    if echo "$CONSOLE_OUTPUT" | grep -q "ecs-init"; then
        echo "  ✅ ECS Agent 初始化脚本已运行"
    fi

    if echo "$CONSOLE_OUTPUT" | grep -q "ECS agent"; then
        echo "  ✅ ECS Agent 相关日志已出现"
    fi

    if echo "$CONSOLE_OUTPUT" | grep -qi "error\|fail"; then
        echo "  ⚠️  控制台日志中发现错误信息"
        echo "$CONSOLE_OUTPUT" | grep -i "error\|fail" | tail -10
    fi
else
    echo "  ⏳ 控制台日志尚未可用（实例太新）"
fi
echo ""

# 6. 建议
echo "========================================"
echo "📋 诊断建议"
echo "========================================"
echo ""

if [ "$STATE" != "running" ]; then
    echo "❌ 实例状态不是 running: $STATE"
    echo "   等待实例启动完成"
elif [ "$UPTIME" -lt 180 ]; then
    echo "⏳ 实例刚启动 ($UPTIME 秒)"
    echo "   ECS Agent 初始化需要 2-5 分钟"
    echo "   建议："
    echo "   1. 等待 $((300 - UPTIME)) 秒"
    echo "   2. 重新运行: bash scripts/check_ecs_instance.sh"
elif [ "$UPTIME" -gt 600 ]; then
    echo "⚠️  实例已运行超过 10 分钟，但未注册到 ECS"
    echo "   可能的问题："
    echo "   1. ECS Agent 启动失败"
    echo "   2. 实例无法访问 ECS API（网络/安全组问题）"
    echo "   3. IAM Instance Profile 权限不足"
    echo "   4. 用户数据中的 ECS_CLUSTER 配置错误"
    echo ""
    echo "   建议："
    echo "   1. 检查安全组是否允许出站 HTTPS (443)"
    echo "   2. 检查 IAM Instance Profile 权限"
    echo "   3. 查看完整的控制台日志："
    echo "      aws ec2 get-console-output --instance-id $INSTANCE_ID --region $REGION --output text"
else
    echo "⏳ 实例运行中，继续等待 ECS Agent 注册"
    echo "   建议 1-2 分钟后重新检查"
fi

echo ""
echo "🔄 重新检查命令:"
echo "   bash scripts/check_ecs_instance.sh $INSTANCE_ID"
echo ""
