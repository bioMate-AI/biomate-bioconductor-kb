#!/bin/bash
# 检查 Auto Scaling Group 启动失败原因

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"

echo "========================================"
echo "检查 ASG 实例启动失败原因"
echo "========================================"
echo ""

# 1. 找到 Batch 相关的 ASG
echo "📋 1. 查找 Auto Scaling Groups..."
ASG_INFO=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'galaxy-cloud-compute')]" \
    --output json)

ASG_COUNT=$(echo "$ASG_INFO" | jq '. | length')

if [ "$ASG_COUNT" = "0" ]; then
    echo "  ❌ 未找到 galaxy-cloud-compute 相关的 ASG"
    exit 1
fi

echo "  找到 $ASG_COUNT 个 ASG"
echo ""

# 遍历每个 ASG
for i in $(seq 0 $((ASG_COUNT - 1))); do
    ASG_NAME=$(echo "$ASG_INFO" | jq -r ".[$i].AutoScalingGroupName")
    MIN_SIZE=$(echo "$ASG_INFO" | jq -r ".[$i].MinSize")
    MAX_SIZE=$(echo "$ASG_INFO" | jq -r ".[$i].MaxSize")
    DESIRED=$(echo "$ASG_INFO" | jq -r ".[$i].DesiredCapacity")
    INSTANCES=$(echo "$ASG_INFO" | jq -r ".[$i].Instances | length")

    echo "📊 ASG: $ASG_NAME"
    echo "  MinSize: $MIN_SIZE"
    echo "  MaxSize: $MAX_SIZE"
    echo "  DesiredCapacity: $DESIRED"
    echo "  当前实例数: $INSTANCES"
    echo ""

    # 2. 检查 Scaling Activities（最近的启动尝试）
    echo "🔍 2. 检查最近的 Scaling Activities..."
    ACTIVITIES=$(aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "$ASG_NAME" \
        --max-records 10 \
        --region "$REGION" \
        --output json)

    echo "  最近 10 次活动:"
    echo "$ACTIVITIES" | jq -r '.Activities[] | "  [\(.StartTime)] \(.StatusCode): \(.Description)"' | head -20
    echo ""

    # 检查是否有失败的活动
    FAILED_COUNT=$(echo "$ACTIVITIES" | jq '[.Activities[] | select(.StatusCode == "Failed")] | length')

    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo "  ⚠️  发现 $FAILED_COUNT 个失败的活动"
        echo ""
        echo "  失败详情:"
        echo "$ACTIVITIES" | jq -r '.Activities[] | select(.StatusCode == "Failed") | "  时间: \(.StartTime)\n  原因: \(.Cause)\n"'
    fi

    # 3. 检查 Launch Template
    echo "🚀 3. 检查 Launch Template..."
    LT_ID=$(echo "$ASG_INFO" | jq -r ".[$i].LaunchTemplate.LaunchTemplateId")
    LT_VERSION=$(echo "$ASG_INFO" | jq -r ".[$i].LaunchTemplate.Version")

    echo "  Launch Template ID: $LT_ID"
    echo "  Version: $LT_VERSION"

    if [ "$LT_ID" != "null" ]; then
        LT_INFO=$(aws ec2 describe-launch-template-versions \
            --launch-template-id "$LT_ID" \
            --versions "$LT_VERSION" \
            --region "$REGION" \
            --output json)

        AMI_ID=$(echo "$LT_INFO" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId')
        INSTANCE_TYPE=$(echo "$LT_INFO" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType')
        IAM_PROFILE=$(echo "$LT_INFO" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Arn // .LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name // "未设置"')
        SECURITY_GROUPS=$(echo "$LT_INFO" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.SecurityGroupIds[]?' | tr '\n' ',' || echo "未设置")
        SUBNET=$(echo "$LT_INFO" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.NetworkInterfaces[0].SubnetId // "未设置"')

        echo "  AMI ID: $AMI_ID"
        echo "  Instance Type: $INSTANCE_TYPE"
        echo "  IAM Instance Profile: $IAM_PROFILE"
        echo "  Security Groups: $SECURITY_GROUPS"
        echo "  Subnet: $SUBNET"
        echo ""

        # 4. 检查 AMI 是否存在
        echo "🖼️  4. 检查 AMI..."
        AMI_CHECK=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" 2>&1 || echo "NOT_FOUND")

        if echo "$AMI_CHECK" | grep -q "NOT_FOUND\|InvalidAMIID"; then
            echo "  ❌ AMI 不存在或无效！"
            echo "  这是最常见的问题原因"
            echo ""
            echo "  解决方案："
            echo "  1. 找到正确的 ECS-optimized AMI："
            echo "     aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2/recommended --region $REGION"
            echo ""
            echo "  2. 更新 Launch Template 使用正确的 AMI"
        else
            AMI_NAME=$(echo "$AMI_CHECK" | jq -r '.Images[0].Name')
            AMI_STATE=$(echo "$AMI_CHECK" | jq -r '.Images[0].State')
            echo "  ✅ AMI 存在"
            echo "  AMI Name: $AMI_NAME"
            echo "  AMI State: $AMI_STATE"
        fi
        echo ""

        # 5. 检查 IAM Instance Profile
        echo "👤 5. 检查 IAM Instance Profile..."
        PROFILE_NAME=$(echo "$IAM_PROFILE" | awk -F'/' '{print $NF}')

        if [ "$PROFILE_NAME" != "未设置" ] && [ -n "$PROFILE_NAME" ]; then
            PROFILE_CHECK=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" 2>&1 || echo "NOT_FOUND")

            if echo "$PROFILE_CHECK" | grep -q "NOT_FOUND\|NoSuchEntity"; then
                echo "  ❌ Instance Profile 不存在！"
            else
                ROLES_COUNT=$(echo "$PROFILE_CHECK" | jq -r '.InstanceProfile.Roles | length')
                echo "  ✅ Instance Profile 存在"
                echo "  关联的 Role 数量: $ROLES_COUNT"

                if [ "$ROLES_COUNT" = "0" ]; then
                    echo "  ⚠️  Instance Profile 没有关联任何 Role！"
                fi
            fi
        else
            echo "  ⚠️  Launch Template 未设置 IAM Instance Profile"
        fi
        echo ""

        # 6. 检查子网
        echo "🌐 6. 检查子网配置..."
        if [ "$SUBNET" != "未设置" ]; then
            SUBNET_CHECK=$(aws ec2 describe-subnets --subnet-ids "$SUBNET" --region "$REGION" 2>&1 || echo "NOT_FOUND")

            if echo "$SUBNET_CHECK" | grep -q "NOT_FOUND\|InvalidSubnetID"; then
                echo "  ❌ 子网不存在或无效！"
            else
                AVAILABLE_IPS=$(echo "$SUBNET_CHECK" | jq -r '.Subnets[0].AvailableIpAddressCount')
                SUBNET_AZ=$(echo "$SUBNET_CHECK" | jq -r '.Subnets[0].AvailabilityZone')
                echo "  ✅ 子网存在"
                echo "  可用区: $SUBNET_AZ"
                echo "  可用 IP 数: $AVAILABLE_IPS"

                if [ "$AVAILABLE_IPS" = "0" ]; then
                    echo "  ❌ 子网没有可用 IP 地址！"
                fi
            fi
        else
            echo "  ⚠️  未在 Launch Template 中指定子网"
            echo "  将使用 ASG 的子网配置"
        fi
        echo ""
    fi

    # 7. 检查是否有 EC2 实例在运行
    echo "💻 7. 检查 EC2 实例状态..."
    INSTANCE_IDS=$(echo "$ASG_INFO" | jq -r ".[$i].Instances[].InstanceId" 2>/dev/null || echo "")

    if [ -z "$INSTANCE_IDS" ]; then
        echo "  ⚠️  ASG 中没有实例"
        echo "  这意味着实例启动失败或被终止"
    else
        echo "  找到实例: $INSTANCE_IDS"

        for INSTANCE_ID in $INSTANCE_IDS; do
            INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" 2>/dev/null || echo "{}")

            if [ "$INSTANCE_INFO" != "{}" ]; then
                STATE=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].State.Name')
                STATE_REASON=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].StateTransitionReason // "无"')

                echo "  实例 $INSTANCE_ID:"
                echo "    状态: $STATE"
                echo "    状态原因: $STATE_REASON"
            fi
        done
    fi
    echo ""

    # 8. 检查 Service Limits
    echo "📊 8. 检查 EC2 Service Limits..."

    # 检查 vCPU 限额
    SPOT_VCPU_LIMIT=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-34B43A08 \
        --region "$REGION" 2>/dev/null | jq -r '.Quota.Value' || echo "未知")

    echo "  Spot 实例 vCPU 限额: $SPOT_VCPU_LIMIT"

    # 检查按需实例限额
    ONDEMAND_VCPU_LIMIT=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --region "$REGION" 2>/dev/null | jq -r '.Quota.Value' || echo "未知")

    echo "  按需实例 vCPU 限额: $ONDEMAND_VCPU_LIMIT"
    echo ""
done

# 9. 总结和建议
echo "========================================"
echo "📋 诊断总结"
echo "========================================"
echo ""

# 分析最可能的问题
if echo "$ACTIVITIES" | jq -e '.Activities[] | select(.StatusCode == "Failed")' >/dev/null 2>&1; then
    echo "⚠️  发现实例启动失败"
    echo ""
    echo "最常见的失败原因："
    echo ""
    echo "1️⃣  AMI 不存在或无效 (最常见)"
    echo "   • Launch Template 中的 AMI ID 不正确"
    echo "   • AMI 在当前区域不可用"
    echo "   • 解决: 更新 Launch Template 使用正确的 ECS-optimized AMI"
    echo ""
    echo "2️⃣  IAM Instance Profile 问题"
    echo "   • Instance Profile 不存在"
    echo "   • Instance Profile 没有关联 Role"
    echo "   • 解决: bash scripts/fix_auto_scaling.sh"
    echo ""
    echo "3️⃣  子网没有可用 IP"
    echo "   • 子网 IP 地址耗尽"
    echo "   • 解决: 添加更多子网到 Compute Environment"
    echo ""
    echo "4️⃣  达到 EC2 实例限额"
    echo "   • AWS 账户的 vCPU 配额不足"
    echo "   • 解决: 申请提额"
    echo ""
    echo "5️⃣  安全组规则问题"
    echo "   • 安全组不存在或规则不正确"
    echo "   • 解决: 检查安全组配置"
    echo ""
else
    echo "ℹ️  未发现明显的启动失败记录"
    echo ""
    echo "可能的情况："
    echo "• 实例正在启动中（首次启动需要 5-10 分钟）"
    echo "• ASG 还没有尝试启动实例"
    echo "• 实例启动后立即被终止（查看 Scaling Activities）"
fi

echo ""
echo "🔍 获取更详细的 AMI 信息："
echo "   aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2/recommended --region $REGION"
echo ""
echo "🔧 如果是 AMI 问题，需要更新 Launch Template"
echo "   详见文档: TROUBLESHOOT_RUNNABLE_STUCK.md"
