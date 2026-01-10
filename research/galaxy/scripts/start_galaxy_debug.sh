#!/bin/bash
# Galaxy Debug Startup Script

echo "🐛 Galaxy Debug启动脚本"

# 清理环境
pkill -f "galaxy|gunicorn" 2>/dev/null || true
sleep 2

# 激活虚拟环境
echo "激活虚拟环境..."
source .venv/bin/activate

# 设置环境变量
export PYTHONPATH=lib
export GALAXY_CONFIG_FILE=config/galaxy.yml
export SKIP_CLIENT_BUILD=1

echo "尝试启动Galaxy..."
echo "当前目录: $(pwd)"
echo "Python路径: $PYTHONPATH"
echo "配置文件: $GALAXY_CONFIG_FILE"

# 直接运行gunicorn并显示详细输出
gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' \
    --timeout 300 \
    --pythonpath lib \
    -k galaxy.webapps.galaxy.workers.Worker \
    -b 0.0.0.0:8080 \
    --workers=1 \
    --log-level debug \
    --preload