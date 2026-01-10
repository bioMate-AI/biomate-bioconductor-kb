#!/bin/bash
#
# 查看AWS Batch作业日志
#

set -e

echo "========================================"
echo "  AWS Batch日志查看工具"
echo "========================================"
echo ""

# 检查参数
if [ -z "$1" ]; then
    echo "用法: $0 [作业ID|最近作业]"
    echo ""
    echo "示例:"
    echo "  $0 <job-id>                  # 查看特定作业"
    echo "  $0 latest                    # 查看最近的作业"
    echo ""
    exit 1
fi

JOB_QUEUE="${AWS_BATCH_QUEUE:-galaxy-cloud-queue}"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

echo "配置:"
echo "  Queue: $JOB_QUEUE"
echo "  Region: $REGION"
echo ""

# 获取作业ID
if [ "$1" == "latest" ]; then
    echo "获取最新作业..."
    JOB_ID=$(aws batch list-jobs \
        --job-queue "$JOB_QUEUE" \
        --region "$REGION" \
        --max-results 1 \
        --query 'jobSummaryList[0].jobId' \
        --output text)

    if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "None" ]; then
        echo "❌ 队列中没有作业"
        exit 1
    fi

    echo "✓ 最新作业ID: $JOB_ID"
    echo ""
else
    JOB_ID="$1"
fi

# 1. 查看作业详情
echo "========================================"
echo "1. 作业详情"
echo "========================================"
aws batch describe-jobs \
    --jobs "$JOB_ID" \
    --region "$REGION" \
    --query 'jobs[0].{
        JobName: jobName,
        Status: status,
        CreatedAt: createdAt,
        StartedAt: startedAt,
        StoppedAt: stoppedAt,
        StatusReason: statusReason,
        JobDefinition: jobDefinition,
        Container: container
    }' \
    --output json

echo ""

# 2. 获取日志流名称
echo "========================================"
echo "2. CloudWatch日志"
echo "========================================"

LOG_STREAM=$(aws batch describe-jobs \
    --jobs "$JOB_ID" \
    --region "$REGION" \
    --query 'jobs[0].container.logStreamName' \
    --output text)

if [ -z "$LOG_STREAM" ] || [ "$LOG_STREAM" == "None" ]; then
    echo "⚠️  日志流尚未创建（作业可能还未开始运行）"
    echo ""
    echo "当前状态:"
    aws batch describe-jobs \
        --jobs "$JOB_ID" \
        --region "$REGION" \
        --query 'jobs[0].status' \
        --output text
    exit 0
fi

echo "✓ 日志流: $LOG_STREAM"
echo ""

# 3. 获取日志组
LOG_GROUP="/aws/batch/job"

# 4. 显示日志
echo "========================================"
echo "3. 容器日志输出"
echo "========================================"
echo ""

aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LOG_STREAM" \
    --region "$REGION" \
    --query 'events[*].[timestamp,message]' \
    --output text | \
    while IFS=$'\t' read -r timestamp message; do
        # 转换时间戳为可读格式
        if [ "$(uname)" == "Darwin" ]; then
            # macOS
            time_str=$(date -r $((timestamp/1000)) '+%Y-%m-%d %H:%M:%S')
        else
            # Linux
            time_str=$(date -d @$((timestamp/1000)) '+%Y-%m-%d %H:%M:%S')
        fi
        echo "[$time_str] $message"
    done

echo ""
echo "========================================"
echo "完成！"
echo "========================================"
echo ""
echo "其他有用命令:"
echo ""
echo "# 列出所有作业"
echo "aws batch list-jobs --job-queue $JOB_QUEUE --region $REGION"
echo ""
echo "# 查看作业状态"
echo "aws batch describe-jobs --jobs $JOB_ID --region $REGION --query 'jobs[0].status'"
echo ""
echo "# 实时跟踪日志 (需要作业运行中)"
echo "aws logs tail $LOG_GROUP --log-stream-names $LOG_STREAM --region $REGION --follow"
echo ""
