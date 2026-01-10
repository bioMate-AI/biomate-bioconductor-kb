#!/bin/bash
# 快速测试脚本 - 自动获取或创建API key并运行测试

set -e

GALAXY_URL="http://localhost:8080"
API_KEY_FILE="$HOME/.galaxy_api_key"

echo "========================================"
echo "  增强版云Workflow快速测试"
echo "========================================"
echo ""

# 检查Galaxy是否运行
echo "1. 检查Galaxy服务..."
if ! curl -s "${GALAXY_URL}/api/version" > /dev/null; then
    echo "   ✗ Galaxy未运行，请先启动: sh run.sh --daemon"
    exit 1
fi
echo "   ✓ Galaxy正在运行"
echo ""

# 检查是否有API key
if [ -f "$API_KEY_FILE" ]; then
    API_KEY=$(cat "$API_KEY_FILE")
    echo "2. 使用已保存的API key"
else
    echo "2. 需要Galaxy API key"
    echo ""
    echo "   请访问: ${GALAXY_URL}"
    echo "   然后: User -> Preferences -> Manage API keys -> Create"
    echo ""
    read -p "   请粘贴API key: " API_KEY
    echo "$API_KEY" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    echo "   ✓ API key已保存到 $API_KEY_FILE"
fi
echo ""

# 安装依赖
echo "3. 检查Python依赖..."
if ! python3 -c "import bioblend" 2>/dev/null; then
    echo "   安装 bioblend..."
    pip3 install bioblend > /dev/null 2>&1 || {
        echo "   ✗ 无法安装bioblend，请手动运行: pip3 install bioblend"
        exit 1
    }
fi
echo "   ✓ 依赖已满足"
echo ""

# 启动日志监控（后台）
echo "4. 启动日志监控..."
tail -f database/gravity/log/gunicorn.log 2>/dev/null | grep -E "(GalaxyCloudJobRunner|prepared with file transfers|Uploaded|Downloaded)" &
LOG_PID=$!
echo "   ✓ 日志监控已启动 (PID: $LOG_PID)"
echo ""

# 运行测试
echo "5. 运行完整测试..."
echo ""
echo "========================================"
echo ""

export GALAXY_API_KEY="$API_KEY"
python3 test_enhanced_cloud_workflow.py

# 保存退出码
EXIT_CODE=$?

# 停止日志监控
kill $LOG_PID 2>/dev/null || true

echo ""
echo "========================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✓✓✓ 测试成功完成 ✓✓✓"
else
    echo "  ✗ 测试失败"
fi
echo "========================================"

exit $EXIT_CODE
