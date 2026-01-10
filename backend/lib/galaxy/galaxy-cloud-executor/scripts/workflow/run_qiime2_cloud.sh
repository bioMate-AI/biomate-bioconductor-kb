#!/bin/bash
#
# 使用galaxy_cloud通用模块执行QIIME2 Workflow
#

set -e

echo "========================================"
echo "  Galaxy Cloud Workflow Executor"
echo "  (使用通用galaxy_cloud模块)"
echo "========================================"
echo ""

# 检测并使用正确的Python环境
if command -v python &> /dev/null && python -c "import aioboto3" &> /dev/null; then
    PYTHON_CMD="python"
    echo "✓ 使用Python: $(python --version 2>&1)"
elif command -v python3 &> /dev/null && python3 -c "import aioboto3" &> /dev/null; then
    PYTHON_CMD="python3"
    echo "✓ 使用Python: $(python3 --version 2>&1)"
else
    # 尝试使用Anaconda Python
    if [ -f "$HOME/opt/anaconda3/bin/python" ]; then
        PYTHON_CMD="$HOME/opt/anaconda3/bin/python"
        echo "✓ 使用Anaconda Python: $($PYTHON_CMD --version 2>&1)"
    else
        echo "❌ 错误: 找不到安装了aioboto3的Python环境"
        echo ""
        echo "请安装依赖:"
        echo "  pip install boto3 aioboto3"
        echo ""
        exit 1
    fi
fi

echo ""

# 设置环境变量
export GALAXY_AWS_ENABLED=true
export GALAXY_AWS_BATCH_QUEUE=${AWS_BATCH_QUEUE:-galaxy-cloud-queue}
export GALAXY_AWS_S3_BUCKET=${AWS_S3_BUCKET:-galaxy-cloud-data-1760241377}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2}

# 使用SSO profile（如果没有设置AWS_PROFILE的话）
if [ -z "$AWS_PROFILE" ]; then
    # 检查是否有AdministratorAccess profile
    if grep -q "\[AdministratorAccess-" ~/.aws/credentials 2>/dev/null || \
       grep -q "\[profile.*AdministratorAccess-" ~/.aws/config 2>/dev/null; then
        export AWS_PROFILE="AdministratorAccess-399683337364"
        echo "✓ 使用AWS Profile: $AWS_PROFILE"
    fi
fi

echo "✓ 环境配置:"
echo "  AWS Enabled: $GALAXY_AWS_ENABLED"
echo "  Batch Queue: $GALAXY_AWS_BATCH_QUEUE"
echo "  S3 Bucket: $GALAXY_AWS_S3_BUCKET"
echo "  Region: $AWS_DEFAULT_REGION"
echo ""

# 文件路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKFLOW_FILE="$SCRIPT_DIR/../ai/data/workflows/workflow_0dc387dc861bdb61.json"
INPUT_DATA_DIR="$SCRIPT_DIR/test_data/qiime2_demo"
RUNNER_SCRIPT="$SCRIPT_DIR/examples/run_any_galaxy_workflow.py"
GALAXY_LIB="$SCRIPT_DIR/../.."

echo "✓ 文件路径:"
echo "  Workflow: $WORKFLOW_FILE"
echo "  输入数据: $INPUT_DATA_DIR"
echo "  执行脚本: $RUNNER_SCRIPT"
echo ""

# 检查文件
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ 错误: Workflow文件不存在: $WORKFLOW_FILE"
    exit 1
fi

if [ ! -d "$INPUT_DATA_DIR" ]; then
    echo "❌ 错误: 输入数据目录不存在: $INPUT_DATA_DIR"
    exit 1
fi

# 选择执行模式
echo "请选择执行模式:"
echo "  1) 快速验证 (不监控)"
echo "  2) 完整执行 (带监控)"
echo ""
read -p "请输入选择 [1-2]: " choice

case $choice in
    1)
        echo ""
        echo "========== 快速验证模式 =========="
        echo ""
        PYTHONPATH="$GALAXY_LIB" "$PYTHON_CMD" "$RUNNER_SCRIPT" \
            "$WORKFLOW_FILE" \
            --input 0:"$INPUT_DATA_DIR" \
            --provider aws \
            --staging "$GALAXY_AWS_S3_BUCKET/workflows/qiime2-test" \
            --output "$GALAXY_AWS_S3_BUCKET/workflows/qiime2-test/outputs"
        ;;
    2)
        echo ""
        echo "========== 完整执行（带监控） =========="
        echo ""
        PYTHONPATH="$GALAXY_LIB" "$PYTHON_CMD" "$RUNNER_SCRIPT" \
            "$WORKFLOW_FILE" \
            --input 0:"$INPUT_DATA_DIR" \
            --provider aws \
            --staging "$GALAXY_AWS_S3_BUCKET/workflows/qiime2-test" \
            --output "$GALAXY_AWS_S3_BUCKET/workflows/qiime2-test/outputs" \
            --monitor
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  完成！"
echo "=========================================="
echo ""
echo "说明:"
echo "  • 这个脚本使用galaxy_cloud通用模块"
echo "  • 可以执行任何Galaxy workflow"
echo "  • 不需要为每个workflow编写定制代码"
echo ""
