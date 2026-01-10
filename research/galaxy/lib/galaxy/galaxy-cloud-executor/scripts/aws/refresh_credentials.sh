#!/bin/bash
#
# AWS SSO 凭证刷新脚本
#

set -e

echo "========================================"
echo "  刷新AWS SSO凭证"
echo "========================================"
echo ""

echo "检查当前凭证..."
if aws sts get-caller-identity 2>/dev/null; then
    echo "✓ 当前凭证有效"
    echo ""
    exit 0
fi

echo "❌ 当前凭证无效或已过期"
echo ""

# 检查是否配置了SSO
if grep -q "sso_" ~/.aws/config 2>/dev/null; then
    echo "检测到SSO配置，使用SSO登录..."
    echo ""

    # 获取profile名称
    PROFILE=$(grep -A 10 "\[profile.*\]" ~/.aws/config | grep "sso_" -B 1 | head -1 | sed 's/\[profile \(.*\)\]/\1/')

    if [ -z "$PROFILE" ]; then
        PROFILE="AdministratorAccess-399683337364"
    fi

    echo "使用profile: $PROFILE"
    echo ""
    echo "正在启动SSO登录..."
    echo "将在浏览器中打开AWS SSO登录页面"
    echo ""

    aws sso login --profile "$PROFILE"

    echo ""
    echo "✓ SSO登录成功"
    echo ""
    echo "测试凭证..."

    export AWS_PROFILE="$PROFILE"
    aws sts get-caller-identity

    echo ""
    echo "========================================"
    echo "✓ 凭证刷新成功！"
    echo "========================================"
    echo ""
    echo "请在运行脚本前设置环境变量:"
    echo "  export AWS_PROFILE=$PROFILE"
    echo ""

else
    echo "未检测到SSO配置"
    echo ""
    echo "请选择登录方式:"
    echo "  1) 配置AWS SSO"
    echo "  2) 使用Access Key"
    echo ""
    read -p "选择 [1-2]: " choice

    case $choice in
        1)
            echo ""
            echo "请运行以下命令配置SSO:"
            echo "  aws configure sso"
            echo ""
            ;;
        2)
            echo ""
            echo "请运行以下命令配置Access Key:"
            echo "  aws configure"
            echo ""
            echo "或者从AWS Console获取临时凭证:"
            echo "  1. 登录AWS Console"
            echo "  2. 点击右上角用户名"
            echo "  3. 选择 'Command line or programmatic access'"
            echo "  4. 复制临时凭证"
            echo ""
            ;;
        *)
            echo "无效选择"
            exit 1
            ;;
    esac
fi
