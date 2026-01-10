#!/bin/bash
# 检查 AWS 凭证配置

echo "========================================"
echo "AWS 凭证诊断"
echo "========================================"
echo ""

# 1. 检查环境变量
echo "📋 1. 检查环境变量..."
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "  ✅ AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
else
    echo "  ⚠️  AWS_ACCESS_KEY_ID 未设置"
fi

if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "  ✅ AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:10}..."
else
    echo "  ⚠️  AWS_SECRET_ACCESS_KEY 未设置"
fi

if [ -n "$AWS_SESSION_TOKEN" ]; then
    echo "  ⚠️  AWS_SESSION_TOKEN 已设置（临时凭证）"
    echo "     这可能已过期"
else
    echo "  ℹ️  AWS_SESSION_TOKEN 未设置（使用长期凭证）"
fi

if [ -n "$AWS_DEFAULT_REGION" ]; then
    echo "  ✅ AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
else
    echo "  ⚠️  AWS_DEFAULT_REGION 未设置"
fi

if [ -n "$AWS_PROFILE" ]; then
    echo "  ✅ AWS_PROFILE: $AWS_PROFILE"
fi

echo ""

# 2. 检查 AWS CLI 配置文件
echo "📁 2. 检查 AWS CLI 配置文件..."

if [ -f ~/.aws/credentials ]; then
    echo "  ✅ ~/.aws/credentials 存在"
    echo ""
    echo "  配置的 Profile:"
    grep '^\[' ~/.aws/credentials | sed 's/\[//g' | sed 's/\]//g' | while read profile; do
        echo "    - $profile"
    done
    echo ""

    # 检查默认 profile
    if grep -q '^\[default\]' ~/.aws/credentials; then
        echo "  检查 [default] profile:"

        # 读取 access key（不显示完整内容）
        ACCESS_KEY=$(awk '/^\[default\]/,/^\[/ {if ($1 == "aws_access_key_id") print $3}' ~/.aws/credentials)
        if [ -n "$ACCESS_KEY" ]; then
            echo "    aws_access_key_id: ${ACCESS_KEY:0:10}..."
        else
            echo "    ❌ aws_access_key_id 未设置"
        fi

        SECRET_KEY=$(awk '/^\[default\]/,/^\[/ {if ($1 == "aws_secret_access_key") print $3}' ~/.aws/credentials)
        if [ -n "$SECRET_KEY" ]; then
            echo "    aws_secret_access_key: ${SECRET_KEY:0:10}..."
        else
            echo "    ❌ aws_secret_access_key 未设置"
        fi
    else
        echo "  ⚠️  没有 [default] profile"
    fi
else
    echo "  ⚠️  ~/.aws/credentials 不存在"
fi

echo ""

if [ -f ~/.aws/config ]; then
    echo "  ✅ ~/.aws/config 存在"

    # 检查默认区域
    DEFAULT_REGION=$(awk '/^\[default\]/,/^\[/ {if ($1 == "region") print $3}' ~/.aws/config)
    if [ -n "$DEFAULT_REGION" ]; then
        echo "    默认区域: $DEFAULT_REGION"
    else
        echo "    ⚠️  默认区域未设置"
    fi
else
    echo "  ⚠️  ~/.aws/config 不存在"
fi

echo ""

# 3. 测试凭证
echo "🔐 3. 测试凭证有效性..."

# 测试不同的凭证来源
echo ""
echo "  尝试使用当前配置调用 AWS API..."

# 保存当前环境变量
OLD_AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
OLD_AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
OLD_AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"

# 清除环境变量，使用配置文件
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

echo "  测试 AWS CLI (使用 ~/.aws/credentials):"
AWS_RESULT=$(aws sts get-caller-identity 2>&1)

if echo "$AWS_RESULT" | grep -q "UserId"; then
    echo "    ✅ 凭证有效"
    echo "$AWS_RESULT" | grep -E "UserId|Account|Arn" | sed 's/^/    /'
else
    echo "    ❌ 凭证无效"
    echo "$AWS_RESULT" | head -3 | sed 's/^/    /'
fi

# 恢复环境变量
export AWS_ACCESS_KEY_ID="$OLD_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$OLD_AWS_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$OLD_AWS_SESSION_TOKEN"

echo ""

# 4. 诊断建议
echo "========================================"
echo "📋 诊断结果和建议"
echo "========================================"
echo ""

if echo "$AWS_RESULT" | grep -q "InvalidClientTokenId\|UnrecognizedClientException\|InvalidAccessKeyId"; then
    echo "❌ 凭证无效或已过期"
    echo ""
    echo "可能的原因:"
    echo "1. Access Key 已被删除或禁用"
    echo "2. Secret Key 不正确"
    echo "3. 临时凭证（Session Token）已过期"
    echo "4. 凭证文件格式错误"
    echo ""
    echo "解决方案:"
    echo ""
    echo "方法 1: 重新配置 AWS CLI（推荐）"
    echo "  aws configure"
    echo "  # 输入新的 Access Key 和 Secret Key"
    echo ""
    echo "方法 2: 手动编辑配置文件"
    echo "  vi ~/.aws/credentials"
    echo "  # 更新 aws_access_key_id 和 aws_secret_access_key"
    echo ""
    echo "方法 3: 使用环境变量"
    echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
    echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
    echo "  export AWS_DEFAULT_REGION='us-west-2'"
    echo ""
    echo "如何获取新的凭证:"
    echo "1. 登录 AWS Console: https://console.aws.amazon.com/"
    echo "2. 进入 IAM → Users → 你的用户名"
    echo "3. Security credentials → Create access key"
    echo "4. 下载或复制凭证"
    echo ""
elif echo "$AWS_RESULT" | grep -q "ExpiredToken"; then
    echo "⚠️  临时凭证已过期"
    echo ""
    echo "你正在使用临时凭证（Session Token），已过期。"
    echo ""
    echo "解决方案:"
    echo "1. 如果使用 AWS SSO/IAM Identity Center:"
    echo "   aws sso login"
    echo ""
    echo "2. 或者改用长期凭证:"
    echo "   aws configure"
    echo "   # 使用长期的 Access Key 和 Secret Key"
    echo ""
elif echo "$AWS_RESULT" | grep -q "UserId"; then
    echo "✅ 凭证有效！"
    echo ""
    echo "当前使用的凭证:"
    echo "$AWS_RESULT" | grep -E "UserId|Account|Arn" | sed 's/^/  /'
    echo ""
    echo "如果测试脚本仍然失败，可能是:"
    echo "1. Python 脚本使用了不同的凭证源"
    echo "2. 区域设置不正确"
    echo "3. 网络连接问题"
else
    echo "⚠️  未知错误"
    echo ""
    echo "错误信息:"
    echo "$AWS_RESULT" | sed 's/^/  /'
    echo ""
    echo "建议:"
    echo "1. 检查网络连接"
    echo "2. 确认 AWS 服务状态: https://status.aws.amazon.com/"
    echo "3. 重新配置凭证: aws configure"
fi

echo ""
