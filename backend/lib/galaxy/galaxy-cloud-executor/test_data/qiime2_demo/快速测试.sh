#!/bin/bash
# QIIME2 Workflow 快速测试脚本
# 使用 run_workflow_with_real_data.py 和测试数据

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}║    QIIME2 Workflow 真实数据云测试                             ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查环境变量
echo -e "${YELLOW}1. 检查环境配置...${NC}"
if [ -z "$AWS_BATCH_QUEUE" ]; then
    echo "❌ 错误: 未设置 AWS_BATCH_QUEUE"
    echo "请运行: export AWS_BATCH_QUEUE=galaxy-cloud-queue"
    exit 1
fi

if [ -z "$AWS_S3_BUCKET" ]; then
    echo "❌ 错误: 未设置 AWS_S3_BUCKET"
    echo "请运行: export AWS_S3_BUCKET=your-bucket-name"
    exit 1
fi

echo -e "${GREEN}✓${NC} AWS_BATCH_QUEUE: $AWS_BATCH_QUEUE"
echo -e "${GREEN}✓${NC} AWS_S3_BUCKET: $AWS_S3_BUCKET"
echo ""

# 设置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTING_DIR="$(cd "$SCRIPT_DIR/../../testing" && pwd)"
WORKFLOW_JSON="/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json"

echo -e "${YELLOW}2. 路径信息...${NC}"
echo "测试数据目录: $SCRIPT_DIR"
echo "Testing 目录: $TESTING_DIR"
echo "Workflow JSON: $WORKFLOW_JSON"
echo ""

# 检查文件
echo -e "${YELLOW}3. 检查测试数据...${NC}"
if [ ! -f "$SCRIPT_DIR/sample1_R1.fastq.gz" ]; then
    echo "❌ 错误: 测试数据不存在"
    exit 1
fi
ls -lh "$SCRIPT_DIR"/*.fastq.gz
echo ""

# 询问测试模式
echo -e "${YELLOW}4. 选择测试模式${NC}"
echo "  1) Dry-run (预览执行计划，不实际运行)"
echo "  2) 单个文件测试"
echo "  3) 完整测试 (3个文件)"
echo ""
read -p "请选择 [1-3]: " choice

cd "$TESTING_DIR"

case $choice in
    1)
        echo ""
        echo -e "${BLUE}运行 Dry-run 模式...${NC}"
        python3 run_workflow_with_real_data.py \
            "$WORKFLOW_JSON" \
            --input 0:"$SCRIPT_DIR/sample1_R1.fastq.gz" \
            --dry-run
        ;;
    2)
        echo ""
        echo -e "${BLUE}运行单个文件测试...${NC}"
        python3 run_workflow_with_real_data.py \
            "$WORKFLOW_JSON" \
            --input 0:"$SCRIPT_DIR/sample1_R1.fastq.gz" \
            --output-dir ./results_single
        ;;
    3)
        echo ""
        echo -e "${BLUE}运行完整测试 (3个文件)...${NC}"
        python3 run_workflow_with_real_data.py \
            "$WORKFLOW_JSON" \
            --input 0:"$SCRIPT_DIR/sample1_R1.fastq.gz" \
            --input 0:"$SCRIPT_DIR/sample2_R1.fastq.gz" \
            --input 0:"$SCRIPT_DIR/sample3_R1.fastq.gz" \
            --output-dir ./results_full
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                         完成!                                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
