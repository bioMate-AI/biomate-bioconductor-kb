#!/bin/bash

# Galaxy 云执行测试脚本
# 用于快速测试和验证云端执行功能

set -e

# 设置AWS配置
export AWS_PROFILE=${AWS_PROFILE:-"AdministratorAccess-399683337364"}

# 验证AWS Profile
if [ -n "$AWS_PROFILE" ]; then
    echo "🔧 使用AWS Profile: $AWS_PROFILE"
    # 检查profile是否存在
    if aws configure list-profiles | grep -q "^$AWS_PROFILE$"; then
        echo "✅ AWS Profile存在"
        
        # 检查SSO token是否有效
        if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
            echo "⚠️  SSO token已过期，尝试自动登录..."
            if aws sso login --profile "$AWS_PROFILE"; then
                echo "✅ SSO登录成功"
            else
                echo "❌ SSO登录失败，请手动登录"
                echo "运行: aws sso login --profile $AWS_PROFILE"
                exit 1
            fi
        else
            echo "✅ SSO token有效"
        fi
    else
        echo "❌ AWS Profile '$AWS_PROFILE' 不存在"
        echo "请运行: aws configure list-profiles 查看可用的profiles"
        exit 1
    fi
else
    echo "🔧 使用默认AWS凭证"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║       Galaxy 云执行完整测试                                   ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_command() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
    else
        echo -e "${RED}❌ $1${NC}"
        return 1
    fi
}

# ============================================================
# 步骤1: 前置条件检查
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤1: 前置条件检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🔍 检查AWS凭证..."

# 尝试获取身份信息
if aws sts get-caller-identity > /dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    echo -e "${GREEN}✅ AWS凭证有效${NC}"
    echo "   账户ID: $ACCOUNT_ID"
    echo "   用户ARN: $USER_ARN"
    
    # 检查是否是SSO用户
    if echo "$USER_ARN" | grep -q "assumed-role.*SSO"; then
        echo "   认证方式: SSO ✅"
    elif echo "$USER_ARN" | grep -q "assumed-role"; then
        echo "   认证方式: AssumeRole ✅"
    else
        echo "   认证方式: IAM用户/密钥 ✅"
    fi
else
    echo -e "${RED}❌ AWS凭证无效或已过期${NC}"
    echo ""
    echo "可能的解决方案："
    if [ -n "$AWS_PROFILE" ]; then
        echo "1. 重新进行SSO登录: aws sso login --profile $AWS_PROFILE"
        echo "2. 检查Profile配置: aws configure list --profile $AWS_PROFILE"
    else
        echo "1. 重新进行SSO登录: aws sso login"
        echo "2. 设置环境变量: export AWS_PROFILE=AdministratorAccess-399683337364"
    fi
    exit 1
fi

echo ""
echo "🔍 检查AWS Batch Queue..."
QUEUE_STATE=$(aws batch describe-job-queues \
  --job-queues galaxy-cloud-queue \
  --query 'jobQueues[0].state' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$QUEUE_STATE" = "ENABLED" ]; then
    echo -e "${GREEN}✅ Batch Queue状态: ENABLED${NC}"
else
    echo -e "${YELLOW}⚠️  Batch Queue状态: $QUEUE_STATE${NC}"
    echo "   你可能需要检查AWS Batch配置"
fi

echo ""
echo "🔍 检查S3 Bucket..."
aws s3 ls s3://galaxy-cloud-data-1760241377/ > /dev/null 2>&1
check_command "S3 Bucket可访问"

echo ""
echo "🔍 检查Galaxy配置..."
if grep -q "default: cloud_small" config/job_conf_cloud.yml; then
    echo -e "${GREEN}✅ Galaxy默认执行环境: cloud_small${NC}"
else
    echo -e "${YELLOW}⚠️  Galaxy配置可能不是完全云端${NC}"
    grep "default:" config/job_conf_cloud.yml
fi

echo ""
echo "🔍 检查Galaxy服务..."
if ps aux | grep gunicorn | grep -v grep > /dev/null; then
    echo -e "${GREEN}✅ Galaxy服务运行中${NC}"

    # 尝试访问API（超时10秒）
    if timeout 10 curl -s http://localhost:8080/api/version > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Galaxy API可访问${NC}"
        VERSION=$(curl -s http://localhost:8080/api/version 2>/dev/null | grep -o '"version_major":"[^"]*"' | cut -d'"' -f4)
        echo "   版本: $VERSION"
    else
        echo -e "${YELLOW}⚠️  Galaxy API暂时无法访问（可能还在启动中）${NC}"
    fi
else
    echo -e "${RED}❌ Galaxy服务未运行${NC}"
    echo ""
    read -p "是否启动Galaxy服务？ (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "启动Galaxy服务..."
        nohup bash start_galaxy_cloud.sh > galaxy_startup.log 2>&1 &
        echo -e "${GREEN}✅ Galaxy正在后台启动${NC}"
        echo "   日志文件: galaxy_startup.log"
        echo "   等待约2-3分钟后，Galaxy将可用"
        echo ""
        echo "你可以运行: tail -f galaxy_startup.log 查看启动日志"
        exit 0
    else
        echo "请先启动Galaxy服务，然后重新运行此脚本"
        exit 1
    fi
fi

# ============================================================
# 步骤2: 获取或检查API Key
# ============================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤2: API Key检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -z "$GALAXY_API_KEY" ]; then
    echo -e "${YELLOW}⚠️  未设置GALAXY_API_KEY环境变量${NC}"
    echo ""
    echo "请按以下步骤获取API Key:"
    echo "1. 访问 http://localhost:8080"
    echo "2. 登录或注册账号"
    echo "3. 右上角用户名 → Preferences"
    echo "4. 左侧菜单 → Manage API Key"
    echo "5. 点击 'Create a new key'"
    echo ""
    read -p "请输入你的API Key: " API_KEY
    export GALAXY_API_KEY="$API_KEY"
    echo ""
    echo -e "${GREEN}✅ API Key已设置${NC}"
    echo "   提示: 将以下命令添加到 ~/.bashrc 以永久保存:"
    echo "   export GALAXY_API_KEY='$API_KEY'"
else
    echo -e "${GREEN}✅ GALAXY_API_KEY已设置${NC}"
    echo "   Key: ${GALAXY_API_KEY:0:8}..."
fi

# ============================================================
# 步骤3: 测试选择
# ============================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤3: 选择测试类型"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "请选择测试类型:"
echo "1) 快速测试（简单workflow，5分钟）"
echo "2) 完整测试（真实workflow，需先安装工具，30分钟+）"
echo "3) 只验证配置（不运行workflow）"
echo "4) 查看AWS资源状态"
echo ""
read -p "请选择 (1-4): " -n 1 -r
echo
echo ""

case $REPLY in
    1)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "快速测试 - 使用简单工具验证云执行"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # 创建测试文件
        echo "创建测试数据..."
        echo "This is a test file for cloud execution verification" > test_cloud_data.txt
        echo -e "${GREEN}✅ 测试文件创建成功: test_cloud_data.txt${NC}"

        echo ""
        echo "📋 下一步操作:"
        echo "1. 访问 http://localhost:8080"
        echo "2. 点击左侧 'Upload Data' 上传 test_cloud_data.txt"
        echo "3. 在工具面板搜索 'cat' 或 'Concatenate'"
        echo "4. 选择上传的文件，运行工具"
        echo "5. 点击历史记录中的作业"
        echo "6. 查看 'Job Information' → 'Job Destination'"
        echo ""
        echo -e "${GREEN}✅ 如果显示 'cloud_small' 或 'cloud_medium' 或 'cloud_large'${NC}"
        echo "   说明云执行配置成功！"
        echo ""
        echo "🔍 你也可以运行以下命令查看AWS Batch作业:"
        echo "   aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING"
        ;;

    2)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "完整测试 - 真实Workflow测试"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        echo "📦 检查测试文件..."
        if [ -f "real_complex_workflow.ga" ]; then
            echo -e "${GREEN}✅ Workflow文件存在: real_complex_workflow.ga${NC}"
        else
            echo -e "${RED}❌ 找不到 real_complex_workflow.ga${NC}"
            echo "请确保文件存在"
            exit 1
        fi

        if [ -d "real_test_data" ] && [ -f "real_test_data/sample_reads.fastq.gz" ]; then
            echo -e "${GREEN}✅ 测试数据存在: real_test_data/sample_reads.fastq.gz${NC}"
        else
            echo -e "${RED}❌ 找不到测试数据文件${NC}"
            echo "请确保 real_test_data/sample_reads.fastq.gz 存在"
            exit 1
        fi

        echo ""
        echo "📋 完整测试步骤:"
        echo ""
        echo "步骤1: 安装工具（首次需要，约20-30分钟）"
        echo "   如果工具已安装，可以跳过此步骤"
        echo ""
        read -p "是否需要安装workflow所需工具？(y/n): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo "创建工具安装脚本..."
            cat > /tmp/install_tools.py << 'PYEOF'
import os
import requests
import time
import sys

GALAXY_URL = "http://localhost:8080"
API_KEY = os.environ.get("GALAXY_API_KEY","cf77c3d29b11d3fe1389600995adad8d")

if not API_KEY:
    print("❌ 请设置GALAXY_API_KEY环境变量")
    sys.exit(1)

TOOLS = [
    {"name": "fastqc", "owner": "devteam", "changeset": "5ec9f6bceaee"},
    {"name": "trimmomatic", "owner": "pjbriggs", "changeset": "d94aff5ee623"},
    {"name": "bowtie2", "owner": "devteam", "changeset": "a9d4f71dbfb0"},
]

headers = {"x-api-key": API_KEY}

print("开始安装工具...")
for tool in TOOLS:
    print(f"\n📦 安装: {tool['name']}")
    data = {
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "name": tool['name'],
        "owner": tool['owner'],
        "changeset_revision": tool['changeset'],
    }

    resp = requests.post(f"{GALAXY_URL}/api/tool_shed_repositories", json=data, headers=headers)
    if resp.status_code in [200, 201]:
        print(f"✅ {tool['name']} - 安装请求已提交")
    else:
        print(f"⚠️  {tool['name']} - 状态: {resp.status_code}")

print("\n⏳ 工具安装需要20-30分钟")
print("💡 在Galaxy UI查看进度: Admin → Manage installed tools")
PYEOF

            python3 /tmp/install_tools.py
            echo ""
            echo "工具安装已开始，请在Galaxy UI监控进度"
            echo "访问: http://localhost:8080/admin/toolshed"
        fi

        echo ""
        echo "步骤2: 导入Workflow"
        echo "   1. 访问 http://localhost:8080"
        echo "   2. 顶部菜单 → Workflow"
        echo "   3. 点击 'Import'"
        echo "   4. 上传文件: real_complex_workflow.ga"
        echo ""

        echo "步骤3: 上传测试数据"
        echo "   1. 左侧 'Upload Data'"
        echo "   2. 上传文件: real_test_data/sample_reads.fastq.gz"
        echo ""

        echo "步骤4: 运行Workflow"
        echo "   1. Workflow → Real Bioinformatics Pipeline → 运行"
        echo "   2. 选择上传的FASTQ文件作为输入"
        echo "   3. 点击 'Run Workflow'"
        echo ""

        echo "步骤5: 验证云执行"
        echo "   1. 查看历史记录中的作业"
        echo "   2. 点击作业 → 查看 'Job Destination'"
        echo "   3. 应该显示: cloud_small/medium/large ✅"
        echo ""

        echo "详细步骤请参考: 完整云运行测试流程.md"
        ;;

    3)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "配置验证"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        echo "📝 Galaxy云执行配置:"
        echo ""
        echo "默认执行环境:"
        grep -A 2 "^execution:" config/job_conf_cloud.yml | head -3

        echo ""
        echo "本地执行的工具（例外）:"
        grep -B 1 "environment: local" config/job_conf_cloud.yml | grep "id:" | awk '{print "  -", $3}'

        echo ""
        echo "云端执行规则:"
        grep -A 1 'id: ".*"' config/job_conf_cloud.yml | tail -2

        echo ""
        echo "📊 配置总结:"
        if grep -q "default: cloud_small" config/job_conf_cloud.yml; then
            echo -e "${GREEN}✅ 默认执行环境: cloud_small (云端)${NC}"
        else
            echo -e "${YELLOW}⚠️  默认执行环境不是cloud_small${NC}"
        fi

        echo ""
        echo "详细配置说明: all_docs/CLOUD_CONFIG_SUMMARY.md"
        ;;

    4)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "AWS资源状态"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        echo "🔍 AWS账号信息:"
        aws sts get-caller-identity

        echo ""
        echo "🔍 Batch Queue状态:"
        aws batch describe-job-queues --job-queues galaxy-cloud-queue \
          --query 'jobQueues[0].[jobQueueName,state,status]' \
          --output table

        echo ""
        echo "🔍 最近的Batch作业:"
        for status in RUNNING SUCCEEDED FAILED; do
            echo ""
            echo "状态: $status"
            aws batch list-jobs \
              --job-queue galaxy-cloud-queue \
              --job-status $status \
              --max-items 5 \
              --query 'jobSummaryList[*].[jobName,status,createdAt]' \
              --output table || echo "  无作业"
        done

        echo ""
        echo "🔍 S3 Bucket内容:"
        echo "Jobs目录:"
        aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | tail -10 || echo "  空"

        echo ""
        echo "Workflows目录:"
        aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive | tail -10 || echo "  空"
        ;;

    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📚 参考文档"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "完整测试流程: 完整云运行测试流程.md"
echo "云执行原理: all_docs/HOW_CLOUD_EXECUTION_WORKS.md"
echo "配置总结: all_docs/CLOUD_CONFIG_SUMMARY.md"
echo "快速开始: all_docs/QUICK_START.txt"
echo ""
echo "🎊 测试完成！"
