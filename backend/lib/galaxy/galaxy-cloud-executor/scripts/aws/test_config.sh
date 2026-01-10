#!/bin/bash
#
# 测试AWS配置
#

echo "========================================"
echo "  测试AWS配置"
echo "========================================"
echo ""

# 检查环境变量
echo "1. 检查环境变量:"
echo "  AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-未设置}"
echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:+已设置}"
echo "  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:+已设置}"
echo ""

# 测试AWS CLI
echo "2. 测试AWS CLI:"
if ! command -v aws &> /dev/null; then
    echo "  ❌ AWS CLI未安装"
    echo "  安装: pip install awscli"
    exit 1
fi
echo "  ✓ AWS CLI已安装"
echo ""

# 测试身份
echo "3. 测试AWS身份:"
if aws sts get-caller-identity 2>&1 | grep -q "UserId"; then
    echo "  ✓ AWS凭证有效"
    aws sts get-caller-identity | grep -E "(UserId|Account|Arn)"
else
    echo "  ❌ AWS凭证无效或未配置"
    echo ""
    echo "  请配置AWS凭证："
    echo "    方法1: aws configure"
    echo "    方法2: export AWS_ACCESS_KEY_ID=..."
    echo "           export AWS_SECRET_ACCESS_KEY=..."
    exit 1
fi
echo ""

# 测试AWS Batch
echo "4. 测试AWS Batch访问:"
BATCH_QUEUE="${GALAXY_AWS_BATCH_QUEUE:-galaxy-cloud-queue}"
if aws batch describe-job-queues --job-queues "$BATCH_QUEUE" 2>&1 | grep -q "jobQueues"; then
    echo "  ✓ 可以访问Batch队列: $BATCH_QUEUE"
    aws batch describe-job-queues --job-queues "$BATCH_QUEUE" --query 'jobQueues[0].{Name:jobQueueName,State:state,Status:status}' --output table
else
    echo "  ⚠️  无法访问Batch队列: $BATCH_QUEUE"
    echo "     队列可能不存在，或者没有权限"
    echo ""
    echo "  可用的队列:"
    aws batch describe-job-queues --query 'jobQueues[*].jobQueueName' --output table 2>/dev/null || echo "     无法列出队列"
fi
echo ""

# 测试S3
echo "5. 测试S3访问:"
S3_BUCKET="${GALAXY_AWS_S3_BUCKET:-galaxy-cloud-data-1760241377}"
if aws s3 ls "s3://$S3_BUCKET" 2>&1 | head -1 | grep -q "PRE\|20"; then
    echo "  ✓ 可以访问S3桶: $S3_BUCKET"
else
    echo "  ⚠️  无法访问S3桶: $S3_BUCKET"
    echo "     桶可能不存在，或者没有权限"
fi
echo ""

echo "========================================"
echo "  测试完成"
echo "========================================"
