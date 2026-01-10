#!/bin/bash
#
# 测试真实QIIME2工具执行
# 这个脚本会使用真实的QIIME2 Docker容器来执行workflow
#

set -e

echo "========================================"
echo "  真实QIIME2 Workflow 云执行测试"
echo "========================================"
echo ""

# 1. 检查环境变量
if [ -z "$AWS_BATCH_QUEUE" ] || [ -z "$AWS_S3_BUCKET" ]; then
    echo "❌ 错误: 请先设置环境变量"
    echo ""
    echo "  export AWS_BATCH_QUEUE=your-queue-name"
    echo "  export AWS_S3_BUCKET=your-bucket-name"
    echo "  export AWS_DEFAULT_REGION=us-west-2"
    echo ""
    exit 1
fi

echo "✓ 环境配置:"
echo "  AWS Region: ${AWS_DEFAULT_REGION:-us-west-2}"
echo "  Batch Queue: $AWS_BATCH_QUEUE"
echo "  S3 Bucket: $AWS_S3_BUCKET"
echo ""

# 2. 定位文件
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKFLOW_FILE="/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json"
INPUT_DATA_DIR="$SCRIPT_DIR"
RUNNER_SCRIPT="/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/testing/run_workflow_with_real_data.py"
OUTPUT_DIR="$SCRIPT_DIR/qiime2_real_output"

echo "✓ 文件路径:"
echo "  Workflow: $WORKFLOW_FILE"
echo "  输入数据: $INPUT_DATA_DIR"
echo "  执行脚本: $RUNNER_SCRIPT"
echo "  输出目录: $OUTPUT_DIR"
echo ""

# 3. 检查文件是否存在
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ 错误: Workflow文件不存在: $WORKFLOW_FILE"
    exit 1
fi

if [ ! -f "$RUNNER_SCRIPT" ]; then
    echo "❌ 错误: 执行脚本不存在: $RUNNER_SCRIPT"
    exit 1
fi

# 检查输入数据
FASTQ_COUNT=$(ls -1 "$INPUT_DATA_DIR"/*.fastq.gz 2>/dev/null | wc -l)
if [ "$FASTQ_COUNT" -eq 0 ]; then
    echo "❌ 错误: 没有找到 .fastq.gz 文件"
    echo "   请确保在 $INPUT_DATA_DIR 目录下有测试数据"
    exit 1
fi

echo "✓ 找到 $FASTQ_COUNT 个FASTQ文件:"
ls -1 "$INPUT_DATA_DIR"/*.fastq.gz | xargs -I{} basename {}
echo ""

# 4. 选择执行模式
echo "请选择执行模式:"
echo "  1) 预览模式 (--dry-run，只显示执行计划)"
echo "  2) 真实执行 (使用真实QIIME2容器)"
echo ""
read -p "请输入选择 [1-2]: " choice

case $choice in
    1)
        echo ""
        echo "========== 预览执行计划 =========="
        echo ""
        python3 "$RUNNER_SCRIPT" "$WORKFLOW_FILE" \
            --input "0:$INPUT_DATA_DIR" \
            --output-dir "$OUTPUT_DIR" \
            --dry-run
        ;;
    2)
        echo ""
        echo "========== 开始真实执行 =========="
        echo ""
        echo "⚠️  注意: 这将在AWS上启动真实的QIIME2容器"
        echo "   - 使用QIIME2官方镜像: quay.io/qiime2/core:2023.5"
        echo "   - 每个作业需要 4 vCPUs, 8GB 内存"
        echo "   - 预计执行时间: 5-15分钟"
        echo ""
        read -p "确认执行? [y/N]: " confirm

        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "已取消"
            exit 0
        fi

        echo ""
        python3 "$RUNNER_SCRIPT" "$WORKFLOW_FILE" \
            --input "0:$INPUT_DATA_DIR" \
            --output-dir "$OUTPUT_DIR"

        echo ""
        echo "=========================================="
        echo "  执行完成！"
        echo "=========================================="
        echo ""
        echo "输出文件位置: $OUTPUT_DIR"
        echo ""
        echo "查看输出文件:"
        echo "  ls -lh $OUTPUT_DIR"
        echo ""
        echo "查看QIIME2结果 (.qza/.qzv文件):"
        echo "  find $OUTPUT_DIR -name '*.qza' -o -name '*.qzv'"
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "完成！"
