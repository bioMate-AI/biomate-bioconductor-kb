#!/bin/bash
#
# 从 Conda 依赖构建 Galaxy 工具容器镜像
#
# 用法:
#   ./build_conda_tool_image.sh <tool_name> <conda_package> [version]
#
# 示例:
#   ./build_conda_tool_image.sh trimmomatic "trimmomatic=0.38" 0.38
#   ./build_conda_tool_image.sh fastqc "fastqc=0.12.1" 0.12.1
#

set -e

# 参数检查
if [ $# -lt 2 ]; then
    echo "用法: $0 <tool_name> <conda_package> [version]"
    echo ""
    echo "示例:"
    echo "  $0 trimmomatic 'trimmomatic=0.38' 0.38"
    echo "  $0 fastqc 'fastqc=0.12.1' 0.12.1"
    echo "  $0 multiqc 'multiqc=1.14' 1.14"
    exit 1
fi

TOOL_NAME="$1"
CONDA_PACKAGE="$2"
VERSION="${3:-latest}"

# AWS 配置
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-399683337364}"
ECR_REPO="galaxy-tools"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 镜像标签
IMAGE_TAG="${ECR_REGISTRY}/${ECR_REPO}/${TOOL_NAME}:${VERSION}"

echo "========================================="
echo "构建 Galaxy 工具容器镜像"
echo "========================================="
echo "工具名称: ${TOOL_NAME}"
echo "Conda 包: ${CONDA_PACKAGE}"
echo "版本: ${VERSION}"
echo "目标镜像: ${IMAGE_TAG}"
echo "========================================="

# 1. 创建临时目录
BUILD_DIR=$(mktemp -d)
cd "${BUILD_DIR}"
echo "✓ 创建构建目录: ${BUILD_DIR}"

# 2. 生成 Dockerfile
cat > Dockerfile << EOF
# Galaxy Tool Container - ${TOOL_NAME}
# Auto-generated from conda package: ${CONDA_PACKAGE}

FROM continuumio/miniconda3:latest

# 标签信息
LABEL maintainer="Galaxy Cloud Executor"
LABEL tool="${TOOL_NAME}"
LABEL version="${VERSION}"
LABEL conda_package="${CONDA_PACKAGE}"

# 安装工具
RUN conda install -c bioconda -c conda-forge ${CONDA_PACKAGE} && \\
    conda clean -afy

# 工作目录
WORKDIR /data

# 默认命令
CMD ["/bin/bash"]
EOF

echo "✓ 生成 Dockerfile"
cat Dockerfile
echo ""

# 3. 检查 ECR 仓库是否存在
echo "检查 ECR 仓库..."
if ! aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "创建 ECR 仓库: ${ECR_REPO}"
    aws ecr create-repository \
        --repository-name "${ECR_REPO}" \
        --region "${AWS_REGION}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    echo "✓ ECR 仓库创建成功"
else
    echo "✓ ECR 仓库已存在"
fi

# 4. 登录 ECR
echo "登录到 ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"
echo "✓ ECR 登录成功"

# 5. 构建镜像
echo "构建 Docker 镜像..."
docker build --platform linux/amd64 -t "${IMAGE_TAG}" .
echo "✓ 镜像构建成功"

# 6. 推送到 ECR
echo "推送镜像到 ECR..."
docker push "${IMAGE_TAG}"
echo "✓ 镜像推送成功"

# 7. 清理
cd /
rm -rf "${BUILD_DIR}"
echo "✓ 清理临时文件"

echo ""
echo "========================================="
echo "✓ 镜像构建完成！"
echo "========================================="
echo "镜像 URI: ${IMAGE_TAG}"
echo ""
echo "下一步："
echo "1. 更新 config/tool_containers.yaml 添加此工具映射："
echo ""
cat << YAML_EXAMPLE
  "toolshed.g2.bx.psu.edu/repos/.../$(echo ${TOOL_NAME} | tr '-' '_')/...":
    image: "${ECR_REGISTRY}/${ECR_REPO}/${TOOL_NAME}"
    tag: "${VERSION}"
    registry: "${ECR_REGISTRY}"
YAML_EXAMPLE
echo ""
echo "2. 重启 Galaxy 使配置生效"
echo "========================================="
