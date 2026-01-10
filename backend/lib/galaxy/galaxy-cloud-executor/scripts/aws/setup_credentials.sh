#!/bin/bash
#
# AWS凭证设置助手
#

set -e

echo "========================================"
echo "  AWS凭证设置助手"
echo "========================================"
echo ""

echo "你的AWS SSO临时凭证需要包含3个部分:"
echo "  1. AWS_ACCESS_KEY_ID"
echo "  2. AWS_SECRET_ACCESS_KEY"
echo "  3. AWS_SESSION_TOKEN (重要!)"
echo ""

echo "获取临时凭证的步骤:"
echo "  1. 登录 https://console.aws.amazon.com/"
echo "  2. 点击右上角你的用户名"
echo "  3. 选择 'Command line or programmatic access'"
echo "  4. 复制显示的Option 2 (Set AWS environment variables)"
echo ""

echo "请选择设置方式:"
echo "  1) 手动输入凭证 (推荐)"
echo "  2) 使用AWS SSO登录"
echo "  3) 测试当前凭证"
echo ""
read -p "请选择 [1-3]: " choice

case $choice in
    1)
        echo ""
        echo "========== 手动输入凭证 =========="
        echo ""
        echo "请粘贴从AWS Console复制的环境变量命令:"
        echo "(格式: export AWS_ACCESS_KEY_ID=... 等3行)"
        echo ""
        echo "粘贴后按Ctrl+D结束:"
        echo ""

        # 读取多行输入
        creds_input=$(cat)

        # 保存到临时文件
        temp_file=$(mktemp)
        echo "$creds_input" > "$temp_file"

        # 提取凭证
        access_key=$(grep AWS_ACCESS_KEY_ID "$temp_file" | sed 's/.*=//' | tr -d '"' | tr -d "'" | xargs)
        secret_key=$(grep AWS_SECRET_ACCESS_KEY "$temp_file" | sed 's/.*=//' | tr -d '"' | tr -d "'" | xargs)
        session_token=$(grep AWS_SESSION_TOKEN "$temp_file" | sed 's/.*=//' | tr -d '"' | tr -d "'" | xargs)

        rm -f "$temp_file"

        if [ -z "$access_key" ] || [ -z "$secret_key" ] || [ -z "$session_token" ]; then
            echo "❌ 错误: 未能提取完整凭证"
            echo ""
            echo "请确保粘贴的内容包含:"
            echo "  export AWS_ACCESS_KEY_ID=..."
            echo "  export AWS_SECRET_ACCESS_KEY=..."
            echo "  export AWS_SESSION_TOKEN=..."
            exit 1
        fi

        # 导出到当前shell
        export AWS_ACCESS_KEY_ID="$access_key"
        export AWS_SECRET_ACCESS_KEY="$secret_key"
        export AWS_SESSION_TOKEN="$session_token"
        export AWS_DEFAULT_REGION="us-west-2"

        echo ""
        echo "✓ 凭证已设置!"
        echo ""
        echo "验证凭证..."

        if aws sts get-caller-identity &> /dev/null; then
            echo "✓ 凭证有效!"
            aws sts get-caller-identity
            echo ""
            echo "========================================"
            echo "  设置成功!"
            echo "========================================"
            echo ""
            echo "请在当前shell中运行:"
            echo "  export AWS_ACCESS_KEY_ID=\"$access_key\""
            echo "  export AWS_SECRET_ACCESS_KEY=\"$secret_key\""
            echo "  export AWS_SESSION_TOKEN=\"$session_token\""
            echo "  export AWS_DEFAULT_REGION=\"us-west-2\""
            echo ""
            echo "或者保存到文件:"
            echo "  ./setup_aws_credentials.sh > ~/.aws_env"
            echo "  source ~/.aws_env"
            echo ""
            echo "然后运行:"
            echo "  ./run_qiime2_cloud.sh"
        else
            echo "❌ 凭证验证失败"
            exit 1
        fi
        ;;

    2)
        echo ""
        echo "========== AWS SSO登录 =========="
        echo ""

        if ! command -v aws &> /dev/null; then
            echo "❌ 错误: 未安装AWS CLI"
            exit 1
        fi

        # 尝试SSO登录
        profile="AdministratorAccess-399683337364"

        echo "使用SSO profile: $profile"
        echo ""

        if aws sso login --profile "$profile"; then
            export AWS_PROFILE="$profile"
            echo ""
            echo "✓ SSO登录成功!"
            echo ""
            echo "验证凭证..."
            aws sts get-caller-identity --profile "$profile"
            echo ""
            echo "========================================"
            echo "  设置成功!"
            echo "========================================"
            echo ""
            echo "请运行:"
            echo "  export AWS_PROFILE=$profile"
            echo "  ./run_qiime2_cloud.sh"
        else
            echo "❌ SSO登录失败"
            exit 1
        fi
        ;;

    3)
        echo ""
        echo "========== 测试当前凭证 =========="
        echo ""

        if aws sts get-caller-identity 2>&1; then
            echo ""
            echo "✓ 凭证有效!"
        else
            echo ""
            echo "❌ 凭证无效或未配置"
            echo ""
            echo "请重新运行此脚本并选择设置方式"
        fi
        ;;

    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
