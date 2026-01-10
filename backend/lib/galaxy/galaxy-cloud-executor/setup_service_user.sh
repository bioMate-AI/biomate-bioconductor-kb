#!/bin/bash
# 快速设置Galaxy服务用户脚本

set -e

echo "🔐 设置Galaxy Cloud服务认证"
echo "============================="

# 检查AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ 请先安装AWS CLI"
    exit 1
fi

# 确认账户信息
echo "当前AWS账户信息："
aws sts get-caller-identity

read -p "确认在上述账户中创建服务用户？(y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "操作取消"
    exit 0
fi

SERVICE_USER="galaxy-cloud-service"
POLICY_NAME="GalaxyCloudServicePolicy"

echo ""
echo "🚀 步骤1: 创建IAM用户"
if aws iam get-user --user-name $SERVICE_USER &>/dev/null; then
    echo "✅ 用户 $SERVICE_USER 已存在"
else
    aws iam create-user --user-name $SERVICE_USER
    echo "✅ 创建用户: $SERVICE_USER"
fi

echo ""
echo "🚀 步骤2: 创建服务策略"
cat > /tmp/galaxy-service-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "batch:DescribeJobQueues",
                "batch:DescribeJobs",
                "batch:SubmitJob",
                "batch:TerminateJob",
                "batch:CancelJob",
                "batch:DescribeComputeEnvironments"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject", 
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::galaxy-cloud-data-1760241377",
                "arn:aws:s3:::galaxy-cloud-data-1760241377/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:GetLogEvents"
            ],
            "Resource": "arn:aws:logs:us-west-2:399683337364:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "arn:aws:iam::399683337364:role/BatchJobRole"
        }
    ]
}
EOF

# 获取账户ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 检查策略是否存在
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
    echo "✅ 策略 $POLICY_NAME 已存在"
else
    aws iam create-policy \
        --policy-name $POLICY_NAME \
        --policy-document file:///tmp/galaxy-service-policy.json
    echo "✅ 创建策略: $POLICY_NAME"
fi

echo ""
echo "🚀 步骤3: 附加策略到用户"
aws iam attach-user-policy \
    --user-name $SERVICE_USER \
    --policy-arn $POLICY_ARN
echo "✅ 策略已附加到用户"

echo ""
echo "🚀 步骤4: 创建访问密钥"
echo "⚠️  请安全保存以下访问密钥，这是唯一显示机会！"
echo ""

# 创建访问密钥
KEY_OUTPUT=$(aws iam create-access-key --user-name $SERVICE_USER --output json)
ACCESS_KEY_ID=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo "🔑 访问密钥信息："
echo "ACCESS_KEY_ID: $ACCESS_KEY_ID"
echo "SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
echo ""

echo "🚀 步骤5: 创建环境变量文件"
cat > .env.production << EOF
# Galaxy Cloud Executor - 生产环境变量
# 生成时间: $(date)

# AWS 认证配置
AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=us-west-2

# Galaxy配置
GALAXY_AWS_ENABLED=true
GALAXY_AWS_BATCH_QUEUE=galaxy-cloud-queue
GALAXY_AWS_S3_BUCKET=galaxy-cloud-data-1760241377
GALAXY_DEFAULT_CLOUD_PROVIDER=aws
GALAXY_LOG_LEVEL=info
GALAXY_ENABLE_METRICS=true

# 服务配置
PORT=8080
ENVIRONMENT=production
EOF

echo "✅ 已创建 .env.production 文件"

# 清理临时文件
rm /tmp/galaxy-service-policy.json

echo ""
echo "🎉 服务认证设置完成！"
echo ""
echo "下一步："
echo "1. 测试配置: ./deploy_production.sh"
echo "2. 启动服务: source .env.production && python3 -m galaxy_cloud.main"
echo ""
echo "⚠️  安全提醒："
echo "- .env.production 包含敏感信息，不要提交到版本控制"
echo "- 定期轮换访问密钥"
echo "- 监控AWS使用情况"