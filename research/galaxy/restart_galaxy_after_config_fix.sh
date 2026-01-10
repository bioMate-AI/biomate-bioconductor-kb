#!/bin/bash

# Galaxy 重启脚本 - 修复上传工具配置后使用

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║   重启 Galaxy - 应用上传工具配置修复                          ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤1: 验证配置文件"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查配置文件
if [ ! -f "config/job_conf_cloud.yml" ]; then
    echo -e "${RED}❌ 错误: 配置文件不存在${NC}"
    exit 1
fi

# 验证YAML语法
python3 << 'EOF'
import yaml
import sys

try:
    with open('config/job_conf_cloud.yml', 'r') as f:
        config = yaml.safe_load(f)

    # 检查本地工具
    local_tools = [t for t in config.get('tools', []) if t.get('environment') == 'local']

    print(f"✅ 配置文件语法正确")
    print(f"✅ 找到 {len(local_tools)} 个本地工具例外:")
    for tool in local_tools:
        print(f"   - {tool['id']}")

    # 检查是否包含upload1
    has_upload = any(t['id'] == 'upload1' for t in local_tools)
    if has_upload:
        print("\n✅ upload1 工具已配置为本地执行（修复成功）")
    else:
        print("\n⚠️  警告: upload1 未配置为本地执行")
        sys.exit(1)

except Exception as e:
    print(f"❌ 配置文件错误: {e}")
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 配置文件验证失败${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤2: 停止Galaxy服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查是否运行
if ps aux | grep gunicorn | grep -v grep > /dev/null; then
    echo "正在停止 Galaxy..."

    # 停止gunicorn
    pkill -f gunicorn
    echo "✅ gunicorn 已停止"

    # 停止celery
    pkill -f celery
    echo "✅ celery 已停止"

    # 等待进程完全停止
    echo "等待进程完全停止..."
    sleep 5

    # 验证停止
    if ps aux | grep gunicorn | grep -v grep > /dev/null; then
        echo -e "${YELLOW}⚠️  gunicorn 仍在运行，强制停止...${NC}"
        pkill -9 -f gunicorn
        sleep 2
    fi

    echo -e "${GREEN}✅ Galaxy 服务已停止${NC}"
else
    echo "Galaxy 未运行，跳过停止步骤"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤3: 启动Galaxy服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "启动 Galaxy（使用更新后的配置）..."
nohup bash start_galaxy_cloud.sh > galaxy_startup.log 2>&1 &

echo -e "${GREEN}✅ Galaxy 正在启动...${NC}"
echo ""
echo "日志文件: galaxy_startup.log"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤4: 等待启动完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "等待 Galaxy 启动（约2-3分钟）..."
echo "你可以运行以下命令查看启动日志:"
echo "  tail -f galaxy_startup.log"
echo ""

# 等待一段时间
for i in {1..30}; do
    sleep 2
    if curl -s http://localhost:8080/api/version > /dev/null 2>&1; then
        echo -e "\n${GREEN}✅ Galaxy 已启动并可访问！${NC}"
        break
    fi
    echo -n "."
done

echo ""

# 检查是否成功启动
if curl -s http://localhost:8080/api/version > /dev/null 2>&1; then
    VERSION=$(curl -s http://localhost:8080/api/version 2>/dev/null | grep -o '"version_major":"[^"]*"' | cut -d'"' -f4)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 启动成功！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Galaxy 版本: $VERSION"
    echo "访问地址: http://localhost:8080"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "下一步: 测试上传功能"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. 访问 http://localhost:8080"
    echo "2. 点击 'Upload Data'"
    echo "3. 选择一个测试文件上传"
    echo "4. 上传应该成功，不再报错 ✅"
    echo ""
    echo "5. 验证上传工具在本地执行:"
    echo "   - 查看历史记录中的上传作业"
    echo "   - 作业详情中 'Job Destination' 应显示: local ✅"
    echo ""
    echo "6. 测试云端工具:"
    echo "   - 运行任意计算工具（如 'cat', 'Concatenate'）"
    echo "   - 'Job Destination' 应显示: cloud_small ✅"
    echo ""
else
    echo ""
    echo -e "${YELLOW}⚠️  Galaxy 可能还在启动中...${NC}"
    echo ""
    echo "请等待几分钟，然后运行:"
    echo "  curl -s http://localhost:8080/api/version"
    echo ""
    echo "或查看启动日志:"
    echo "  tail -f galaxy_startup.log"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎊 重启完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
