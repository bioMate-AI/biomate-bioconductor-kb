#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# load-biotools-images.sh
# 将生信工具 Docker 镜像导入本地仓库 (registry:5050)
#
# 使用场景:
#   - 纯内网环境，容器无法访问 Docker Hub / ECR
#   - BioMate 团队将镜像打包成 tar.gz 后离线传输给客户
#
# 用法:
#   bash scripts/load-biotools-images.sh <images-dir>
#   bash scripts/load-biotools-images.sh /path/to/biotools-images/
#
# 镜像包说明:
#   - 每个文件对应一个工具: bwa.tar.gz, star.tar.gz, deseq2.tar.gz ...
#   - 文件名去掉 .tar.gz 后就是镜像名（tag 固定为 latest）
#   - 导入后可通过 localhost:5050/<name>:latest 拉取
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGISTRY="${BIOMATE_LOCAL_REGISTRY:-localhost:5050}"
IMAGES_DIR="${1:-./biotools-images}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

[[ -d "$IMAGES_DIR" ]] || die "镜像目录不存在: $IMAGES_DIR"

# 检查本地仓库是否运行
if ! curl -sf "http://${REGISTRY}/v2/" &>/dev/null; then
  die "本地仓库未运行: http://${REGISTRY}/v2/\n请先运行: docker compose -f docker-compose.onprem.yml up -d registry"
fi

TOTAL=0; SUCCESS=0; FAIL=0

for tar_file in "$IMAGES_DIR"/*.tar.gz "$IMAGES_DIR"/*.tar; do
  [[ -f "$tar_file" ]] || continue
  BASENAME=$(basename "$tar_file")
  # 去掉 .tar.gz 或 .tar 扩展名
  IMAGE_NAME="${BASENAME%.tar.gz}"
  IMAGE_NAME="${IMAGE_NAME%.tar}"
  LOCAL_TAG="${REGISTRY}/${IMAGE_NAME}:latest"

  TOTAL=$((TOTAL + 1))
  echo ""
  echo "  [$TOTAL] 导入 $IMAGE_NAME..."

  # 导入镜像
  LOADED=$(docker load -i "$tar_file" 2>&1) || {
    warn "导入失败: $tar_file"
    FAIL=$((FAIL + 1))
    continue
  }

  # 找到实际的镜像名（docker load 输出: "Loaded image: xxx:yyy"）
  SOURCE_TAG=$(echo "$LOADED" | grep "Loaded image" | awk '{print $NF}' | head -1)
  if [[ -z "$SOURCE_TAG" ]]; then
    warn "无法解析镜像 tag: $LOADED"
    FAIL=$((FAIL + 1))
    continue
  fi

  # 推送到本地仓库
  docker tag "$SOURCE_TAG" "$LOCAL_TAG"
  if docker push "$LOCAL_TAG" 2>&1 | tail -1; then
    ok "$LOCAL_TAG"
    SUCCESS=$((SUCCESS + 1))
  else
    warn "推送失败: $LOCAL_TAG"
    FAIL=$((FAIL + 1))
  fi

  # 清理临时 tag（保留本地仓库 tag）
  docker rmi "$SOURCE_TAG" 2>/dev/null || true
done

echo ""
echo "────────────────────────────────────────"
echo "  共 $TOTAL 个镜像  成功: $SUCCESS  失败: $FAIL"
echo ""
if [[ $SUCCESS -gt 0 ]]; then
  echo "  已推送到: http://${REGISTRY}/v2/_catalog"
  echo "  Nextflow 配置: 设置 BIOMATE_LOCAL_REGISTRY=${REGISTRY}"
fi
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
