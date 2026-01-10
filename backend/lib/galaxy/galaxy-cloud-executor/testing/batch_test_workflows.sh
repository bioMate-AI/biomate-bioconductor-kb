#!/bin/bash
# 批量测试多个 Galaxy workflows

set -e

# 配置
WORKFLOW_DIR="../../ai/data/workflows"
export AWS_DEFAULT_REGION="us-west-2"
export AWS_BATCH_QUEUE="galaxy-cloud-queue"
export AWS_S3_BUCKET="galaxy-cloud-data-1760241377"
export AWS_BATCH_JOB_ROLE_ARN="arn:aws:iam::399683337364:role/BatchJobRole"

echo "======================================================================"
echo "批量 Workflow 云执行测试"
echo "======================================================================"
echo ""
echo "Workflow 目录: $WORKFLOW_DIR"
echo "AWS Region: $AWS_DEFAULT_REGION"
echo "Batch Queue: $AWS_BATCH_QUEUE"
echo "S3 Bucket: $AWS_S3_BUCKET"
echo ""

# 检查目录
if [ ! -d "$WORKFLOW_DIR" ]; then
    echo "❌ 错误: Workflow 目录不存在: $WORKFLOW_DIR"
    exit 1
fi

# 统计
total=0
success=0
failed=0

# 结果日志
LOG_DIR="./test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "结果将保存到: $LOG_DIR"
echo ""

# 如果提供了参数，只测试指定数量的 workflows
MAX_TESTS=${1:-5}

echo "将测试最多 $MAX_TESTS 个 workflows"
echo ""

# 遍历所有 workflow 文件
for workflow in $(ls $WORKFLOW_DIR/workflow_*.json | head -n $MAX_TESTS); do
    total=$((total + 1))
    filename=$(basename "$workflow")

    echo "======================================================================"
    echo "[$total/$MAX_TESTS] 测试: $filename"
    echo "======================================================================"

    log_file="$LOG_DIR/${filename%.json}.log"

    # 运行测试
    if python3 run_any_workflow.py "$workflow" 2>&1 | tee "$log_file"; then
        success=$((success + 1))
        echo "✅ $filename 测试通过"
    else
        failed=$((failed + 1))
        echo "❌ $filename 测试失败"
    fi

    echo ""
    echo "当前进度: 成功 $success / 失败 $failed / 总计 $total"
    echo ""

    # 短暂休息，避免过载
    if [ $total -lt $MAX_TESTS ]; then
        echo "等待 10 秒后继续..."
        sleep 10
    fi
done

# 汇总
echo ""
echo "======================================================================"
echo "测试汇总"
echo "======================================================================"
echo "总计: $total"
echo "成功: $success"
echo "失败: $failed"
echo "成功率: $(awk "BEGIN {printf \"%.1f%%\", ($success/$total)*100}")"
echo ""
echo "详细日志保存在: $LOG_DIR"
echo ""

if [ $failed -eq 0 ]; then
    echo "🎉 所有测试通过！"
    exit 0
else
    echo "⚠️  部分测试失败"
    exit 1
fi
