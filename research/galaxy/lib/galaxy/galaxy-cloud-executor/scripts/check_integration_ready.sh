#!/bin/bash

# ============================================================
# Galaxy Cloud Executor 集成就绪检查脚本
# ============================================================

set -e

echo "======================================================================"
echo "  Galaxy Cloud Executor 集成就绪检查"
echo "======================================================================"
echo ""

GALAXY_ROOT="/Users/renyuankai/work/biometa/galaxy"
CLOUD_EXECUTOR_ROOT="$GALAXY_ROOT/lib/galaxy/galaxy-cloud-executor"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 计数器
PASSED=0
FAILED=0
WARNINGS=0

# 检查函数
check_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

check_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    WARNINGS=$((WARNINGS + 1))
}

# ============================================================
# 1. AWS 基础设施检查
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 检查 1: AWS 基础设施"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# AWS 凭证
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    check_pass "AWS 凭证有效 (Account: $ACCOUNT_ID)"
else
    check_fail "AWS 凭证无效或未配置"
fi

# Batch 队列
QUEUE_NAME="galaxy-cloud-queue"
if aws batch describe-job-queues --job-queues "$QUEUE_NAME" &>/dev/null; then
    QUEUE_STATE=$(aws batch describe-job-queues --job-queues "$QUEUE_NAME" --query 'jobQueues[0].state' --output text)
    if [ "$QUEUE_STATE" == "ENABLED" ]; then
        check_pass "Batch 队列存在且已启用: $QUEUE_NAME"
    else
        check_warn "Batch 队列存在但状态为: $QUEUE_STATE"
    fi
else
    check_fail "Batch 队列不存在: $QUEUE_NAME"
fi

# S3 存储桶
S3_BUCKET="galaxy-cloud-data-1760241377"
if aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
    check_pass "S3 存储桶可访问: $S3_BUCKET"
else
    check_fail "S3 存储桶不可访问: $S3_BUCKET"
fi

# BatchJobRole
if aws iam get-role --role-name BatchJobRole &>/dev/null; then
    JOB_ROLE_ARN=$(aws iam get-role --role-name BatchJobRole --query 'Role.Arn' --output text)
    check_pass "BatchJobRole 存在: $JOB_ROLE_ARN"

    # 检查 S3 策略
    if aws iam list-attached-role-policies --role-name BatchJobRole | grep -q "BatchJobS3Access"; then
        check_pass "BatchJobRole 已附加 S3 访问策略"
    else
        check_warn "BatchJobRole 可能缺少 S3 访问策略"
    fi
else
    check_fail "BatchJobRole 不存在 (运行 scripts/create_job_role.sh)"
fi

echo ""

# ============================================================
# 2. Galaxy 配置文件检查
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 检查 2: Galaxy 配置文件"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# job_conf.yml
JOB_CONF="$GALAXY_ROOT/config/job_conf.yml"
if [ -f "$JOB_CONF" ]; then
    check_pass "job_conf.yml 文件存在"

    # 检查是否包含 galaxy_cloud runner
    if grep -q "galaxy_cloud:" "$JOB_CONF"; then
        check_pass "job_conf.yml 包含 galaxy_cloud runner 配置"
    else
        check_fail "job_conf.yml 缺少 galaxy_cloud runner 配置"
        echo "       提示: 参考 config/job_conf_cloud_addition.yml"
    fi

    # 检查是否有云执行环境
    if grep -q "cloud_default:" "$JOB_CONF" || grep -q "cloud_small:" "$JOB_CONF"; then
        check_pass "job_conf.yml 包含云执行环境配置"
    else
        check_fail "job_conf.yml 缺少云执行环境配置 (cloud_default, cloud_small, 等)"
    fi

    # 检查 YAML 语法
    if python3 -c "import yaml; yaml.safe_load(open('$JOB_CONF'))" 2>/dev/null; then
        check_pass "job_conf.yml YAML 语法正确"
    else
        check_fail "job_conf.yml YAML 语法错误"
    fi
else
    check_fail "job_conf.yml 文件不存在: $JOB_CONF"
fi

# aws_cloud_config.yaml
CLOUD_CONFIG="$GALAXY_ROOT/config/aws_cloud_config.yaml"
if [ -f "$CLOUD_CONFIG" ]; then
    check_pass "aws_cloud_config.yaml 文件存在"

    # 检查关键配置
    if grep -q "batch_queue.*galaxy-cloud-queue" "$CLOUD_CONFIG"; then
        check_pass "aws_cloud_config.yaml 包含正确的 batch_queue"
    else
        check_warn "aws_cloud_config.yaml 的 batch_queue 配置可能不正确"
    fi

    if grep -q "s3_bucket.*galaxy-cloud-data" "$CLOUD_CONFIG"; then
        check_pass "aws_cloud_config.yaml 包含 s3_bucket 配置"
    else
        check_warn "aws_cloud_config.yaml 缺少 s3_bucket 配置"
    fi

    if grep -q "job_role_arn.*BatchJobRole" "$CLOUD_CONFIG"; then
        check_pass "aws_cloud_config.yaml 包含 job_role_arn 配置"
    else
        check_fail "aws_cloud_config.yaml 缺少 job_role_arn 配置 (必须!)"
    fi

    # 检查 YAML 语法
    if python3 -c "import yaml; yaml.safe_load(open('$CLOUD_CONFIG'))" 2>/dev/null; then
        check_pass "aws_cloud_config.yaml YAML 语法正确"
    else
        check_fail "aws_cloud_config.yaml YAML 语法错误"
    fi
else
    check_fail "aws_cloud_config.yaml 文件不存在: $CLOUD_CONFIG"
    echo "       提示: 从模板复制: cp lib/galaxy/galaxy-cloud-executor/config/aws_cloud_config.yaml config/"
fi

echo ""

# ============================================================
# 3. Python 模块检查
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 检查 3: Python 模块"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$CLOUD_EXECUTOR_ROOT"

# 检查 Python 路径
if python3 -c "import sys; sys.path.append('$CLOUD_EXECUTOR_ROOT'); import galaxy_cloud" 2>/dev/null; then
    check_pass "galaxy_cloud 模块可导入"
else
    check_warn "galaxy_cloud 模块导入失败 (需要设置 PYTHONPATH)"
    echo "       提示: export PYTHONPATH=\"\$PYTHONPATH:$CLOUD_EXECUTOR_ROOT\""
fi

# 检查依赖
DEPS=("boto3" "botocore" "pyyaml")
for dep in "${DEPS[@]}"; do
    if python3 -c "import $dep" 2>/dev/null; then
        check_pass "Python 依赖已安装: $dep"
    else
        check_fail "Python 依赖缺失: $dep (运行: pip install $dep)"
    fi
done

echo ""

# ============================================================
# 4. Galaxy 运行状态检查
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 检查 4: Galaxy 运行状态"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查 Galaxy 进程
if pgrep -f "python.*galaxy" > /dev/null; then
    check_pass "Galaxy 进程正在运行"

    # 检查日志文件
    GALAXY_LOG="$GALAXY_ROOT/galaxy.log"
    if [ -f "$GALAXY_LOG" ]; then
        # 检查是否加载了 galaxy_cloud runner
        if grep -q "Loading job runner plugin: galaxy_cloud" "$GALAXY_LOG"; then
            check_pass "Galaxy 日志显示 galaxy_cloud runner 已加载"
        else
            check_warn "Galaxy 日志中未找到 galaxy_cloud runner 加载记录"
            echo "       提示: 可能需要重启 Galaxy 或检查配置"
        fi

        # 检查是否有错误
        ERROR_COUNT=$(grep -c "ERROR.*galaxy_cloud\|Exception.*galaxy_cloud" "$GALAXY_LOG" 2>/dev/null || echo "0")
        if [ "$ERROR_COUNT" -eq 0 ]; then
            check_pass "Galaxy 日志中没有 galaxy_cloud 相关错误"
        else
            check_warn "Galaxy 日志中发现 $ERROR_COUNT 个 galaxy_cloud 相关错误"
            echo "       提示: 查看详情: grep -i 'error.*galaxy_cloud' galaxy.log"
        fi
    else
        check_warn "Galaxy 日志文件不存在: $GALAXY_LOG"
    fi
else
    check_warn "Galaxy 进程未运行 (启动后再检查集成状态)"
fi

# 检查 Galaxy 端口
if lsof -i :8080 &>/dev/null; then
    check_pass "Galaxy Web 服务正在监听端口 8080"
else
    check_warn "端口 8080 未被监听 (Galaxy 可能使用其他端口)"
fi

echo ""

# ============================================================
# 5. 连接测试
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 检查 5: 连接测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$CLOUD_EXECUTOR_ROOT"

# 运行 AWS 连接测试
if [ -f "testing/test_aws_connection.py" ]; then
    echo "正在运行 AWS 连接测试..."
    if python3 testing/test_aws_connection.py &>/dev/null; then
        check_pass "AWS 连接测试通过"
    else
        check_fail "AWS 连接测试失败"
        echo "       提示: 运行详细测试: python3 testing/test_aws_connection.py"
    fi
else
    check_warn "AWS 连接测试脚本不存在"
fi

echo ""

# ============================================================
# 总结
# ============================================================

echo "======================================================================"
echo "  检查总结"
echo "======================================================================"
echo ""
echo -e "${GREEN}✅ 通过: $PASSED${NC}"
echo -e "${RED}❌ 失败: $FAILED${NC}"
echo -e "${YELLOW}⚠️  警告: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 集成就绪! 可以开始使用 Galaxy Cloud Executor${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "下一步:"
    echo "  1. 如果 Galaxy 未运行，启动它: sh run.sh"
    echo "  2. 访问 Galaxy UI: http://localhost:8080"
    echo "  3. 运行一个配置为云执行的工具 (如 FastQC)"
    echo "  4. 监控作业执行并查看 AWS Batch 控制台"
    echo ""
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}⚠️  集成尚未就绪，请修复上述失败项${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "修复步骤:"
    echo "  1. 参考 GALAXY_INTEGRATION_GUIDE.md 完成配置"
    echo "  2. 如果 AWS 基础设施有问题，运行: bash scripts/diagnose_batch.sh"
    echo "  3. 如果配置文件有问题，参考: config/job_conf_cloud_addition.yml"
    echo "  4. 修复后重新运行此脚本验证"
    echo ""
fi

echo "详细文档:"
echo "  - 集成指南: lib/galaxy/galaxy-cloud-executor/GALAXY_INTEGRATION_GUIDE.md"
echo "  - 故障排查: lib/galaxy/galaxy-cloud-executor/TROUBLESHOOT_RUNNABLE_STUCK.md"
echo "  - 生产部署: lib/galaxy/galaxy-cloud-executor/PRODUCTION_DEPLOYMENT_GUIDE.md"
echo ""

exit $FAILED
