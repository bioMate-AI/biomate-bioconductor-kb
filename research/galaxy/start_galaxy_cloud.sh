#!/bin/bash

# Galaxy Cloud Execution Startup Script
# 启动 Galaxy 并使用云执行配置

set -e

echo "========================================"
echo "  Galaxy Cloud Execution Setup"
echo "========================================"
echo ""

# 设置 AWS 环境变量
export AWS_PROFILE=AdministratorAccess-399683337364
export AWS_DEFAULT_REGION=us-west-2

# 验证 AWS 配置
echo "验证 AWS 配置..."
if aws sts get-caller-identity &>/dev/null; then
    echo "✓ AWS 认证成功"
    aws sts get-caller-identity | grep -E "UserId|Account|Arn"
else
    echo "❌ AWS 认证失败"
    echo "请运行: aws sso login --profile AdministratorAccess-399683337364"
    exit 1
fi

echo ""
echo "验证配置文件..."
if [ -f "config/job_conf_cloud.yml" ]; then
    echo "✓ job_conf_cloud.yml 存在"
else
    echo "❌ job_conf_cloud.yml 不存在"
    exit 1
fi

if [ -f "config/aws_cloud_config.yaml" ]; then
    echo "✓ aws_cloud_config.yaml 存在"
else
    echo "❌ aws_cloud_config.yaml 不存在"
    exit 1
fi

echo ""
echo "验证 galaxy_cloud 模块..."
if [ -L "lib/galaxy_cloud" ]; then
    echo "✓ galaxy_cloud 软链接存在"
else
    echo "❌ galaxy_cloud 软链接不存在"
    echo "正在创建..."
    cd lib && ln -s galaxy-cloud-executor/galaxy_cloud galaxy_cloud && cd ..
    echo "✓ 创建成功"
fi

echo ""
echo "========================================"
echo "  启动 Galaxy"
echo "========================================"
echo ""
echo "Galaxy 将使用以下配置:"
echo "  - Job Config: config/job_conf_cloud.yml"
echo "  - Cloud Config: config/aws_cloud_config.yaml"
echo "  - AWS Region: us-west-2"
echo "  - Batch Queue: galaxy-cloud-queue"
echo "  - S3 Bucket: galaxy-cloud-data-1760241377"
echo ""
echo "工具将自动路由到云执行:"
echo "  - QIIME2 工具 → cloud_medium"
echo "  - IUC 工具 → cloud_small"
echo "  - 其他 toolshed 工具 → cloud_small"
echo ""
echo "启动 Galaxy..."
echo ""

# 启动 Galaxy
sh run.sh

echo ""
echo "========================================"
echo "  Galaxy 已启动"
echo "========================================"
echo ""
echo "访问 Galaxy UI: http://localhost:8080"
echo ""
echo "现在你可以:"
echo "  1. 打开浏览器访问 http://localhost:8080"
echo "  2. 导入你的 QIIME2 workflow"
echo "  3. 运行 workflow - 工具将自动在 AWS Batch 上执行"
echo "  4. 查看执行状态和结果"
echo ""
