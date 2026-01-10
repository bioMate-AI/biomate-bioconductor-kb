#!/bin/bash
# 创建 AWS Batch Job Role（容器 IAM 角色）

set -e

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
ROLE_NAME="BatchJobRole"
S3_BUCKET="${AWS_S3_BUCKET}"

echo "========================================"
echo "创建 AWS Batch Job Role"
echo "========================================"
echo ""

# 1. 创建信任策略
echo "📋 1. 创建 IAM 角色..."

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# 检查角色是否已存在
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "  ✅ 角色 $ROLE_NAME 已存在"
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
else
    # 创建角色
    ROLE_ARN=$(aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "IAM role for AWS Batch job containers to access S3 and CloudWatch" \
        --query 'Role.Arn' \
        --output text)
    echo "  ✅ 角色创建成功: $ROLE_ARN"
fi

echo ""

# 2. 附加 S3 访问策略
echo "📦 2. 配置 S3 访问权限..."

S3_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    }
  ]
}
EOF
)

S3_POLICY_NAME="BatchJobS3Access"

# 检查策略是否已存在
POLICY_ARN=$(aws iam list-policies \
    --scope Local \
    --query "Policies[?PolicyName=='${S3_POLICY_NAME}'].Arn" \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY_ARN" ]; then
    echo "  ✅ 策略 $S3_POLICY_NAME 已存在"
else
    # 创建策略
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$S3_POLICY_NAME" \
        --policy-document "$S3_POLICY" \
        --description "Allow Batch jobs to access S3 bucket" \
        --query 'Policy.Arn' \
        --output text)
    echo "  ✅ 策略创建成功: $POLICY_ARN"
fi

# 附加策略到角色
if aws iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "$S3_POLICY_NAME"; then
    echo "  ✅ S3 策略已附加到角色"
else
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    echo "  ✅ S3 策略已附加"
fi

echo ""

# 3. 附加 CloudWatch Logs 策略
echo "📝 3. 配置 CloudWatch Logs 权限..."

# 使用 AWS 托管策略
CLOUDWATCH_POLICY_ARN="arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

if aws iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "CloudWatchLogsFullAccess"; then
    echo "  ✅ CloudWatch Logs 策略已附加"
else
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$CLOUDWATCH_POLICY_ARN"
    echo "  ✅ CloudWatch Logs 策略已附加"
fi

echo ""

# 4. 等待 IAM 传播
echo "⏳ 4. 等待 IAM 变更传播..."
sleep 10
echo "  ✅ 完成"

echo ""
echo "========================================"
echo "✅ Job Role 创建完成！"
echo "========================================"
echo ""
echo "角色 ARN: $ROLE_ARN"
echo ""
echo "下一步:"
echo "1. 在提交作业时使用这个角色:"
echo "   jobRoleArn='$ROLE_ARN'"
echo ""
echo "2. 或者设置环境变量:"
echo "   export AWS_BATCH_JOB_ROLE_ARN='$ROLE_ARN'"
echo ""
echo "3. 重新运行测试:"
echo "   python3 testing/test_workflow_simple.py"
echo ""

# 保存到环境变量文件
echo "export AWS_BATCH_JOB_ROLE_ARN='$ROLE_ARN'" > scripts/job_role_config.env
echo "配置已保存到: scripts/job_role_config.env"
echo ""
