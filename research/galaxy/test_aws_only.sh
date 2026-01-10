#!/bin/bash

# Galaxy AWS连接快速测试脚本

set -e

# 设置AWS配置
export AWS_PROFILE=${AWS_PROFILE:-"AdministratorAccess-399683337364"}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Galaxy AWS连接快速测试"
echo "========================"
echo ""

# 验证AWS Profile
if [ -n "$AWS_PROFILE" ]; then
    echo "🔧 使用AWS Profile: $AWS_PROFILE"
    
    # 检查SSO token是否有效
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
        echo "⚠️  SSO token已过期，尝试自动登录..."
        if aws sso login --profile "$AWS_PROFILE"; then
            echo "✅ SSO登录成功"
        else
            echo "❌ SSO登录失败"
            exit 1
        fi
    else
        echo "✅ SSO token有效"
    fi
fi

echo ""
echo "🔍 检查AWS凭证..."
if aws sts get-caller-identity > /dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    echo -e "${GREEN}✅ AWS凭证有效${NC}"
    echo "   账户ID: $ACCOUNT_ID"
    echo "   用户ARN: $USER_ARN"
else
    echo -e "${RED}❌ AWS凭证无效${NC}"
    exit 1
fi

echo ""
echo "🔍 检查AWS Batch Queue..."
QUEUE_STATE=$(aws batch describe-job-queues \
  --job-queues galaxy-cloud-queue \
  --query 'jobQueues[0].state' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$QUEUE_STATE" = "ENABLED" ]; then
    echo -e "${GREEN}✅ Batch Queue状态: ENABLED${NC}"
else
    echo -e "${RED}❌ Batch Queue状态: $QUEUE_STATE${NC}"
    exit 1
fi

echo ""
echo "🔍 检查S3 Bucket..."
if aws s3 ls s3://galaxy-cloud-data-1760241377/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ S3 Bucket可访问${NC}"
else
    echo -e "${RED}❌ S3 Bucket不可访问${NC}"
    exit 1
fi

echo ""
echo "🔍 运行连接测试..."
if python3 lib/galaxy/galaxy-cloud-executor/testing/test_aws_connection.py; then
    echo ""
    echo -e "${GREEN}🎉 所有AWS连接测试通过！${NC}"
else
    echo ""
    echo -e "${RED}❌ AWS连接测试失败${NC}"
    exit 1
fi

echo ""
echo "✅ AWS配置完全正常，可以进行Galaxy云执行！"