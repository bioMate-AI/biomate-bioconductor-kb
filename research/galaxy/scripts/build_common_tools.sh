#!/bin/bash
#
# 批量构建常用的 Galaxy 生物信息学工具容器
#
# 这个脚本会构建并推送常用工具到 ECR
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_conda_tool_image.sh"

echo "========================================="
echo "批量构建 Galaxy 工具容器"
echo "========================================="

# 定义常用工具列表
# 格式: tool_name conda_package version
TOOLS=(
    # Quality Control
    "fastqc fastqc=0.12.1 0.12.1"
    "multiqc multiqc=1.14 1.14"

    # Read Processing
    "trimmomatic trimmomatic=0.39 0.39"
    "cutadapt cutadapt=4.4 4.4"

    # Alignment
    "bowtie2 bowtie2=2.5.0 2.5.0"
    "bwa bwa=0.7.17 0.7.17"
    "hisat2 hisat2=2.2.1 2.2.1"

    # BAM/SAM Processing
    "samtools samtools=1.17 1.17"
    "picard picard=3.0.0 3.0.0"

    # Variant Calling
    "bcftools bcftools=1.17 1.17"
    "freebayes freebayes=1.3.6 1.3.6"

    # RNA-seq
    "star star=2.7.10b 2.7.10b"
    "featurecounts subread=2.0.3 2.0.3"
    "htseq htseq=2.0.2 2.0.2"

    # Assembly
    "spades spades=3.15.5 3.15.5"
    "megahit megahit=1.2.9 1.2.9"
)

# 计数
TOTAL=${#TOOLS[@]}
SUCCESS=0
FAILED=0
SKIPPED=0

echo "发现 ${TOTAL} 个工具需要构建"
echo ""

# 询问用户是否继续
read -p "是否继续？[y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消构建"
    exit 0
fi

echo ""

# 遍历构建
for tool_spec in "${TOOLS[@]}"; do
    read -r tool_name conda_pkg version <<< "$tool_spec"

    echo "========================================="
    echo "[${SUCCESS}/${TOTAL}] 构建工具: ${tool_name}"
    echo "========================================="

    # 检查镜像是否已存在
    IMAGE_TAG="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tools/${tool_name}:${version}"

    if docker manifest inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
        echo "⚠ 镜像已存在，跳过: ${IMAGE_TAG}"
        ((SKIPPED++))
        echo ""
        continue
    fi

    # 构建镜像
    if bash "${BUILD_SCRIPT}" "${tool_name}" "${conda_pkg}" "${version}"; then
        echo "✓ ${tool_name} 构建成功"
        ((SUCCESS++))
    else
        echo "✗ ${tool_name} 构建失败"
        ((FAILED++))
    fi

    echo ""
done

echo "========================================="
echo "批量构建完成"
echo "========================================="
echo "总计: ${TOTAL}"
echo "成功: ${SUCCESS}"
echo "失败: ${FAILED}"
echo "跳过: ${SKIPPED}"
echo "========================================="

if [ ${FAILED} -gt 0 ]; then
    echo "⚠ 有 ${FAILED} 个工具构建失败，请检查日志"
    exit 1
fi

echo ""
echo "下一步："
echo "1. 运行以下命令生成配置文件片段："
echo "   ./scripts/generate_tool_config.sh"
echo ""
echo "2. 将生成的配置添加到 config/tool_containers.yaml"
echo ""
echo "3. 重启 Galaxy"
