#!/bin/bash

echo "🚀 Starting Galaxy with debug logging..."
echo ""

# 创建日志目录
mkdir -p logs

# 清空旧的Python缓存
echo "🧹 Clearing Python cache..."
find lib/galaxy_cloud -name "*.pyc" -delete 2>/dev/null
find lib/galaxy_cloud -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
echo "✅ Cache cleared"
echo ""

# 设置日志文件
LOG_FILE="logs/galaxy_debug_$(date +%Y%m%d_%H%M%S).log"

echo "📝 Logs will be written to: $LOG_FILE"
echo "📍 Galaxy will be available at: http://localhost:8080"
echo ""
echo "按 Ctrl+C 停止 Galaxy"
echo "========================================="
echo ""

# 启动 Galaxy 并将输出同时写入文件和终端
sh run.sh 2>&1 | tee "$LOG_FILE"
