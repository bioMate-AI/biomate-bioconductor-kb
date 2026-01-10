#!/bin/bash
# 修复 Launch Template - 添加 IAM Instance Profile

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"

echo "========================================"
echo "修复 Launch Template IAM Profile"
echo "========================================"
echo ""

# 1. 查找 Launch Template
echo "📋 1. 查找 Launch Template..."

ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'galaxy-cloud-compute')].AutoScalingGroupName" \
    --output text)

if [ -z "$ASG_NAME" ]; then
    echo "  ❌ 未找到 Auto Scaling Group"
    exit 1
fi

echo "  ASG: $ASG_NAME"

ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --output json)

LT_ID=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId')
LT_VERSION=$(echo "$ASG_INFO" | jq -r '.AutoScalingGroups[0].LaunchTemplate.Version')

echo "  Launch Template ID: $LT_ID"
echo "  当前版本: $LT_VERSION"
echo ""

# 2. 获取当前 Launch Template 配置
echo "📊 2. 获取当前配置..."

LT_DATA=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LT_ID" \
    --versions "$LT_VERSION" \
    --region "$REGION" \
    --output json)

CURRENT_IAM=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Arn // .LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name // "未设置"')

echo "  当前 IAM Instance Profile: $CURRENT_IAM"

if [ "$CURRENT_IAM" != "未设置" ]; then
    echo "  ⚠️  Launch Template 已经有 IAM Profile，但可能没有生效"
    echo "     检查 Instance Profile 是否存在和有效..."
fi
echo ""

# 3. 确保 Instance Profile 存在并关联 Role
echo "🔧 3. 确保 Instance Profile 配置正确..."

# 检查 Instance Profile
if aws iam get-instance-profile --instance-profile-name ecsInstanceRole >/dev/null 2>&1; then
    echo "  ✅ Instance Profile 存在"
else
    echo "  ⚠️  Instance Profile 不存在，创建中..."
    aws iam create-instance-profile --instance-profile-name ecsInstanceRole
    echo "  ✅ 已创建"
fi

# 检查 Role 关联
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

# 检查 Role 的策略
echo "  检查 Role 策略..."
POLICIES=$(aws iam list-attached-role-policies --role-name ecsInstanceRole --output json)
HAS_ECS_POLICY=$(echo "$POLICIES" | jq -r '.AttachedPolicies[] | select(.PolicyArn | contains("AmazonEC2ContainerServiceforEC2Role")) | .PolicyArn')

if [ -z "$HAS_ECS_POLICY" ]; then
    echo "  ⚠️  缺少 ECS 策略，附加中..."
    aws iam attach-role-policy \
        --role-name ecsInstanceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
    echo "  ✅ 已附加策略"
else
    echo "  ✅ ECS 策略已附加"
fi

echo ""

# 4. 创建新版本的 Launch Template
echo "🆕 4. 创建新版本的 Launch Template..."

# 获取 Instance Profile ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile \
    --instance-profile-name ecsInstanceRole \
    --query 'InstanceProfile.Arn' \
    --output text)

echo "  Instance Profile ARN: $INSTANCE_PROFILE_ARN"

# 提取当前配置
AMI_ID=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId')
INSTANCE_TYPE=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType')
USER_DATA=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')
SECURITY_GROUP_IDS=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.SecurityGroupIds // empty')
KEY_NAME=$(echo "$LT_DATA" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.KeyName // empty')

echo "  AMI: $AMI_ID"
echo "  Instance Type: $INSTANCE_TYPE"

# 构建新的 Launch Template Data
LT_NEW_DATA=$(cat <<EOF
{
  "ImageId": "$AMI_ID",
  "InstanceType": "$INSTANCE_TYPE",
  "IamInstanceProfile": {
    "Arn": "$INSTANCE_PROFILE_ARN"
  },
  "SecurityGroupIds": $SECURITY_GROUP_IDS
EOF
)

# 添加 UserData 如果存在
if [ -n "$USER_DATA" ]; then
    LT_NEW_DATA="$LT_NEW_DATA, \"UserData\": \"$USER_DATA\""
fi

# 添加 KeyName 如果存在
if [ -n "$KEY_NAME" ] && [ "$KEY_NAME" != "null" ]; then
    LT_NEW_DATA="$LT_NEW_DATA, \"KeyName\": \"$KEY_NAME\""
fi

LT_NEW_DATA="$LT_NEW_DATA }"

echo "  新配置:"
echo "$LT_NEW_DATA" | jq .

# 创建新版本
NEW_VERSION_RESPONSE=$(aws ec2 create-launch-template-version \
    --launch-template-id "$LT_ID" \
    --launch-template-data "$LT_NEW_DATA" \
    --region "$REGION" \
    --output json)

NEW_VERSION=$(echo "$NEW_VERSION_RESPONSE" | jq -r '.LaunchTemplateVersion.VersionNumber')

echo ""
echo "  ✅ 新版本已创建: $NEW_VERSION"
echo ""

# 5. 更新 Auto Scaling Group 使用新版本
echo "🔄 5. 更新 Auto Scaling Group..."

aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --launch-template LaunchTemplateId="$LT_ID",Version="$NEW_VERSION" \
    --region "$REGION"

echo "  ✅ ASG 已更新为使用新版本"
echo ""

# 6. 等待 IAM 传播
echo "⏳ 6. 等待 IAM 变更传播..."
sleep 20
echo "  ✅ 完成"
echo ""

# 7. 验证
echo "✅ 7. 验证修复..."

UPDATED_ASG=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --output json)

UPDATED_LT_VERSION=$(echo "$UPDATED_ASG" | jq -r '.AutoScalingGroups[0].LaunchTemplate.Version')

echo "  ASG 使用的 Launch Template 版本: $UPDATED_LT_VERSION"

if [ "$UPDATED_LT_VERSION" = "$NEW_VERSION" ]; then
    echo "  ✅ ASG 已更新到新版本"
else
    echo "  ⚠️  ASG 版本未更新，可能需要手动刷新"
fi

echo ""
echo "========================================"
echo "✅ Launch Template 修复完成！"
echo "========================================"
echo ""
echo "现在 Launch Template 包含正确的 IAM Instance Profile。"
echo ""
echo "下一步："
echo "1. 终止所有旧实例（如果还在运行）"
echo "2. 重新提交作业，让 AWS Batch 启动新实例"
echo "3. 新实例应该能够正确注册到 ECS"
echo ""
echo "测试命令:"
echo "  cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor"
echo "  python3 testing/test_workflow_simple.py"
echo ""
