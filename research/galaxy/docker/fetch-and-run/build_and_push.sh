#!/bin/bash
################################################################################
# Galaxy Cloud Executor - 本地构建并推送脚本
################################################################################
#
# A+B方案:
#   A (90%): 预装通用运行环境 (Python, R, Perl) + BiocManager + getopt
#   B (10%): 运行时动态安装缺失的R包（自动检测并安装BiocManager）
#
# 使用方法:
#   cd docker/fetch-and-run
#   ./build_and_push.sh
#
################################################################################

set -e

REGION="us-west-2"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run"
IMAGE_TAG="latest"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "========================================================================"
echo "Galaxy Cloud Executor - Docker Image Builder"
echo "========================================================================"
echo ""

# 步骤 1: 验证文件
echo "[1/5] 验证构建文件..."
if [ ! -f "$SCRIPT_DIR/Dockerfile" ] || [ ! -f "$SCRIPT_DIR/fetch_and_run.sh" ]; then
    echo "❌ 错误: 找不到Dockerfile或fetch_and_run.sh"
    exit 1
fi
echo "  ✓ 文件验证通过"
echo ""

# 步骤 2: 构建镜像
echo "[2/5] 构建Docker镜像 (预计5-10分钟)..."
cd "$SCRIPT_DIR"
docker build --platform linux/amd64 -t galaxy-fetch-and-run:ab-minimal .
echo "  ✓ 构建完成"
echo ""

# 步骤 3: 登录ECR
echo "[3/5] 登录ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ECR_REPO%%/*}
echo "  ✓ 登录成功"
echo ""

# 步骤 4: 推送镜像
echo "[4/5] 推送镜像到ECR..."
docker tag galaxy-fetch-and-run:ab-minimal $ECR_REPO:$IMAGE_TAG
docker push $ECR_REPO:$IMAGE_TAG | tee /tmp/docker-push.log
echo "  ✓ 推送完成"
echo ""

# 步骤 5: 获取digest
echo "[5/5] 获取镜像digest..."
DIGEST=$(grep "digest:" /tmp/docker-push.log | tail -1 | grep -oE 'sha256:[a-f0-9]{64}')
echo "$DIGEST" > "$SCRIPT_DIR/latest-digest.txt"

echo ""
echo "========================================================================"
echo "✅ 构建成功！"
echo "========================================================================"
echo ""
echo "Digest: $DIGEST"
echo ""
echo "下一步:"
echo "  1. 更新 galaxy_job_runner.py (~行1304) 中的digest"
echo "  2. 重启Galaxy: pkill -f 'python.*run.py' && PYTHONPATH=lib sh run.sh --daemon"
echo "  3. 测试workflow"
echo ""
