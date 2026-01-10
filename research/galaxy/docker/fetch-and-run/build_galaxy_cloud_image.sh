#!/bin/bash
################################################################################
# Galaxy Cloud Executor Docker Image Builder (A+B Solution)
################################################################################
#
# 这个脚本使用AWS Batch自动构建Galaxy云执行容器镜像
#
# A+B方案:
#   A (90%): 预装通用运行环境 (Python, R, Perl) + 常用包
#   B (10%): 运行时动态安装缺失的R包（自动检测BiocManager）
#
# 使用方法:
#   ./build_galaxy_cloud_image.sh
#
# 前置要求:
#   - AWS CLI已配置
#   - 拥有AWS Batch队列和计算环境
#   - 拥有ECR仓库权限
#   - BatchJobRole和ecsTaskExecutionRole IAM角色
#
################################################################################

set -e

# ============================================================================
# 配置参数
# ============================================================================
REGION="us-west-2"
S3_BUCKET="galaxy-cloud-data-1760241377"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run"
BATCH_QUEUE="galaxy-cloud-queue"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "========================================================================"
echo "Galaxy Cloud Executor - Docker Image Builder"
echo "========================================================================"
echo ""
echo "配置:"
echo "  AWS Region: $REGION"
echo "  S3 Bucket: $S3_BUCKET"
echo "  ECR Repository: $ECR_REPO"
echo "  Batch Queue: $BATCH_QUEUE"
echo ""

# ============================================================================
# 步骤 1: 上传构建文件到S3
# ============================================================================
echo "[1/5] 上传构建文件到S3..."

if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
    echo "错误: 找不到 Dockerfile"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/fetch_and_run.sh" ]; then
    echo "错误: 找不到 fetch_and_run.sh"
    exit 1
fi

aws s3 cp "$SCRIPT_DIR/Dockerfile" s3://$S3_BUCKET/build/Dockerfile --region $REGION
aws s3 cp "$SCRIPT_DIR/fetch_and_run.sh" s3://$S3_BUCKET/build/fetch_and_run.sh --region $REGION

echo "  ✓ 构建文件已上传"

# ============================================================================
# 步骤 2: 创建构建脚本并上传到S3
# ============================================================================
echo "[2/5] 创建Docker构建脚本..."

cat > /tmp/docker-build-batch.sh << 'EOF'
#!/bin/bash
set -e
exec > >(tee /var/log/docker-build.log) 2>&1

echo "=== Docker Build on AWS Batch Started ==="
date

REGION="us-west-2"
S3_BUCKET="galaxy-cloud-data-1760241377"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run"

echo "[1/6] Downloading build files..."
mkdir -p /tmp/build
cd /tmp/build
aws s3 cp s3://$S3_BUCKET/build/Dockerfile . --region $REGION
aws s3 cp s3://$S3_BUCKET/build/fetch_and_run.sh . --region $REGION
chmod +x fetch_and_run.sh

echo "[2/6] Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ECR_REPO%%/*}

echo "[3/6] Building Docker image (this may take 20-30 minutes)..."
docker build --platform linux/amd64 -t galaxy-fetch-and-run:ab-full . 2>&1 | tee /tmp/docker-build.log

echo "[4/6] Tagging image..."
docker tag galaxy-fetch-and-run:ab-full $ECR_REPO:latest

echo "[5/6] Pushing to ECR..."
docker push $ECR_REPO:latest 2>&1 | tee /tmp/docker-push.log

echo "[6/6] Getting digest..."
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $ECR_REPO:latest)
echo "SUCCESS: $DIGEST"

# Upload results to S3
echo "$DIGEST" > /tmp/image-digest.txt
aws s3 cp /tmp/image-digest.txt s3://$S3_BUCKET/build/image-digest.txt --region $REGION
aws s3 cp /var/log/docker-build.log s3://$S3_BUCKET/build/docker-build.log --region $REGION 2>/dev/null || true
aws s3 cp /tmp/docker-build.log s3://$S3_BUCKET/build/docker-build-detailed.log --region $REGION 2>/dev/null || true
echo "SUCCESS" | aws s3 cp - s3://$S3_BUCKET/build/build-status.txt --region $REGION

echo "=== Build Complete ==="
date
EOF

aws s3 cp /tmp/docker-build-batch.sh s3://$S3_BUCKET/build/docker-build-batch.sh --region $REGION
echo "  ✓ 构建脚本已上传"

# ============================================================================
# 步骤 3: 注册AWS Batch Job Definition
# ============================================================================
echo "[3/5] 注册AWS Batch Job Definition..."

# 检查是否已存在
EXISTING_JOB_DEF=$(aws batch describe-job-definitions \
    --job-definition-name docker-image-builder-v2 \
    --status ACTIVE \
    --region $REGION \
    --query 'jobDefinitions[0].revision' \
    --output text 2>/dev/null || echo "None")

if [ "$EXISTING_JOB_DEF" != "None" ]; then
    echo "  ℹ Job Definition已存在 (revision: $EXISTING_JOB_DEF)"
    JOB_DEF_ARN="arn:aws:batch:$REGION:$(aws sts get-caller-identity --query Account --output text):job-definition/docker-image-builder-v2:$EXISTING_JOB_DEF"
else
    JOB_DEF_ARN=$(aws batch register-job-definition \
        --job-definition-name docker-image-builder-v2 \
        --type container \
        --region $REGION \
        --platform-capabilities EC2 \
        --container-properties '{
            "image": "docker:24-dind",
            "vcpus": 4,
            "memory": 8192,
            "command": [
                "sh", "-c",
                "apk add --no-cache aws-cli bash && aws s3 cp s3://galaxy-cloud-data-1760241377/build/docker-build-batch.sh /tmp/build.sh && bash /tmp/build.sh"
            ],
            "jobRoleArn": "arn:aws:iam::399683337364:role/BatchJobRole",
            "privileged": true
        }' \
        --query 'jobDefinitionArn' \
        --output text)
    echo "  ✓ Job Definition已创建: $JOB_DEF_ARN"
fi

# ============================================================================
# 步骤 4: 提交AWS Batch任务
# ============================================================================
echo "[4/5] 提交AWS Batch构建任务..."

# 清理旧的digest文件
aws s3 rm s3://$S3_BUCKET/build/image-digest.txt --region $REGION 2>/dev/null || true
aws s3 rm s3://$S3_BUCKET/build/build-status.txt --region $REGION 2>/dev/null || true

JOB_ID=$(aws batch submit-job \
    --job-name "galaxy-docker-build-$(date +%s)" \
    --job-queue $BATCH_QUEUE \
    --job-definition docker-image-builder-v2 \
    --region $REGION \
    --query 'jobId' \
    --output text)

echo "  ✓ 任务已提交"
echo "  Job ID: $JOB_ID"
echo ""

# ============================================================================
# 步骤 5: 监控构建进度
# ============================================================================
echo "[5/5] 监控构建进度 (预计20-30分钟)..."
echo ""

MAX_ATTEMPTS=60  # 30分钟 (每次30秒)
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # 获取任务状态
    STATUS=$(aws batch describe-jobs --jobs $JOB_ID --region $REGION --query 'jobs[0].status' --output text 2>/dev/null)

    echo -n "  [$ATTEMPT/$MAX_ATTEMPTS] $(date +%H:%M:%S) - 状态: $STATUS"

    # 检查S3中的digest文件（构建完成标志）
    if aws s3 ls s3://$S3_BUCKET/build/image-digest.txt --region $REGION 2>/dev/null; then
        echo ""
        echo ""
        echo "========================================================================"
        echo "✅ 构建成功！"
        echo "========================================================================"
        echo ""

        DIGEST=$(aws s3 cp s3://$S3_BUCKET/build/image-digest.txt - --region $REGION)
        DIGEST_HASH=$(echo $DIGEST | grep -oE 'sha256:[a-f0-9]{64}')

        echo "镜像已推送:"
        echo "  完整路径: $DIGEST"
        echo "  Digest: $DIGEST_HASH"
        echo ""
        echo "下一步操作:"
        echo "  1. 更新 galaxy_job_runner.py 中的 fetch_and_run_image 参数"
        echo "     旧值: sha256:20282443ceee0d912c91a0b83408106d9e273f09d9a88e0a20bff234a7fd916a"
        echo "     新值: $DIGEST_HASH"
        echo ""
        echo "  2. 重启Galaxy服务"
        echo "     pkill -f 'python.*run.py'"
        echo "     PYTHONPATH=lib sh run.sh --daemon"
        echo ""
        echo "  3. 测试DESeq2 workflow"
        echo ""

        # 保存digest到本地文件
        echo "$DIGEST_HASH" > "$SCRIPT_DIR/latest-digest.txt"
        echo "Digest已保存到: $SCRIPT_DIR/latest-digest.txt"

        exit 0
    fi

    # 检查任务是否失败
    if [ "$STATUS" == "FAILED" ]; then
        echo ""
        echo ""
        echo "========================================================================"
        echo "❌ 构建失败"
        echo "========================================================================"
        echo ""

        REASON=$(aws batch describe-jobs --jobs $JOB_ID --region $REGION --query 'jobs[0].statusReason' --output text)
        echo "失败原因: $REASON"
        echo ""
        echo "查看详细日志:"
        echo "  aws batch describe-jobs --jobs $JOB_ID --region $REGION"
        echo ""

        # 尝试下载日志
        if aws s3 ls s3://$S3_BUCKET/build/docker-build.log --region $REGION 2>/dev/null; then
            echo "构建日志 (最后50行):"
            aws s3 cp s3://$S3_BUCKET/build/docker-build.log - --region $REGION | tail -50
        fi

        exit 1
    fi

    echo ""
    sleep 30
done

echo ""
echo "========================================================================"
echo "⚠️ 构建超时 (30分钟)"
echo "========================================================================"
echo ""
echo "任务可能仍在运行，请手动检查:"
echo "  aws batch describe-jobs --jobs $JOB_ID --region $REGION"
echo ""
echo "或等待并检查S3中的digest文件:"
echo "  aws s3 cp s3://$S3_BUCKET/build/image-digest.txt -"
echo ""

exit 1
