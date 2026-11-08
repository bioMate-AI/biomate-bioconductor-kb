#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# BioMate 阿里云 Demo 一键部署脚本
# 适用：阿里云 ECS Spot 实例（8 vCPU / 16GB+，Alibaba Cloud Linux / Ubuntu 22.04+）
# 用法：bash scripts/setup_aliyun_demo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo -e "${BLUE}"
echo "  ██████╗ ██╗ ██████╗ ███╗   ███╗ █████╗ ████████╗███████╗"
echo "  ██╔══██╗██║██╔═══██╗████╗ ████║██╔══██╗╚══██╔══╝██╔════╝"
echo "  ██████╔╝██║██║   ██║██╔████╔██║███████║   ██║   █████╗  "
echo "  ██╔══██╗██║██║   ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══╝  "
echo "  ██████╔╝██║╚██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ███████╗"
echo "  ╚═════╝ ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝"
echo -e "${NC}"
echo "  阿里云 Demo 部署脚本  •  $(date '+%Y-%m-%d %H:%M')"
echo "──────────────────────────────────────────────────────────────"

# ── 1. 检查 .env ──────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
    if [[ -f .env.aliyun.example ]]; then
        cp .env.aliyun.example .env
        warn ".env 不存在，已从 .env.aliyun.example 复制，请先填写必填项后重新运行本脚本"
        echo ""
        echo "  必填项:"
        echo "    POSTGRES_PASSWORD  — 数据库密码"
        echo "    JWT_SECRET         — JWT 密钥（openssl rand -hex 32）"
        echo "    SESSION_SECRET     — Session 密钥（openssl rand -hex 32）"
        echo "    GALAXY_API_KEY     — 内部 API 密钥（openssl rand -hex 32）"
        echo "    MINIO_ROOT_PASSWORD — MinIO 密码"
        echo "    LLM_API_KEY        — 千问 DashScope API Key"
        echo ""
        echo "  编辑命令: nano .env"
        exit 0
    else
        die ".env 文件不存在，请先执行: cp .env.aliyun.example .env 并填写必填项"
    fi
fi

# 校验必填项
check_env() {
    local key="$1"
    local val
    val=$(grep "^${key}=" .env | cut -d= -f2- | tr -d '"' | xargs 2>/dev/null || true)
    if [[ -z "$val" ]]; then
        die ".env 中 ${key} 未填写，请编辑 .env 后重新运行"
    fi
}

check_env POSTGRES_PASSWORD
check_env JWT_SECRET
check_env SESSION_SECRET
check_env GALAXY_API_KEY
check_env MINIO_ROOT_PASSWORD
check_env LLM_API_KEY
ok ".env 校验通过"

# ── 2. 安装 Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    info "安装 Docker..."
    # 配置阿里云 Docker 镜像加速（需要替换为自己的加速地址）
    if command -v apt-get &>/dev/null; then
        # Ubuntu
        apt-get update -q
        apt-get install -y -q ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -q
        apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif command -v yum &>/dev/null; then
        # Alibaba Cloud Linux / CentOS
        yum install -y -q yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        die "不支持的发行版，请手动安装 Docker"
    fi
    systemctl enable --now docker
    ok "Docker 安装完成"
else
    ok "Docker 已安装: $(docker --version)"
fi

# 配置 Docker 镜像加速（阿里云加速器，拉取 GHCR/DockerHub 更快）
DAEMON_JSON=/etc/docker/daemon.json
if ! grep -q "registry-mirrors" "$DAEMON_JSON" 2>/dev/null; then
    info "配置 Docker 镜像加速..."
    mkdir -p /etc/docker
    cat > "$DAEMON_JSON" <<'DOCKEREOF'
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
DOCKEREOF
    systemctl reload docker || systemctl restart docker
    ok "Docker 镜像加速配置完成"
fi

# ── 3. 获取 Docker GID 并更新 .env ───────────────────────────────────────────
DOCKER_GID=$(stat -c %g /var/run/docker.sock)
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=${DOCKER_GID}/" .env
ok "Docker GID = ${DOCKER_GID}"

# ── 4. 创建必要目录 ───────────────────────────────────────────────────────────
info "创建工作目录..."
mkdir -p /app/nf-work /app/biomate-data
chmod 777 /app/nf-work
ok "目录创建完成"

# ── 5. 生成 galaxy.yml（必须存在，compose bind-mount 会覆盖镜像内配置）────────
GALAXY_YML=backend/config/galaxy.yml
if [[ ! -f "$GALAXY_YML" ]]; then
    if [[ -f backend/config/galaxy.yml.template ]]; then
        cp backend/config/galaxy.yml.template "$GALAXY_YML"
        ok "galaxy.yml 从模板生成"
    else
        die "找不到 backend/config/galaxy.yml.template"
    fi
fi

# ── 6. 拉取镜像 ───────────────────────────────────────────────────────────────
info "拉取 BioMate 镜像（GHCR，首次约 3-5 分钟）..."

BACKEND_IMAGE=$(grep "^BIOMATE_BACKEND_IMAGE=" .env | cut -d= -f2-)
FRONTEND_IMAGE=$(grep "^BIOMATE_FRONTEND_IMAGE=" .env | cut -d= -f2-)

pull_with_retry() {
    local image="$1"
    local max_attempts=3
    for i in $(seq 1 $max_attempts); do
        if docker pull "$image"; then
            return 0
        fi
        warn "拉取失败（第 ${i}/${max_attempts} 次），5 秒后重试..."
        sleep 5
    done
    die "无法拉取镜像: $image （请检查网络或 GHCR Token）"
}

pull_with_retry "$BACKEND_IMAGE"
pull_with_retry "$FRONTEND_IMAGE"
ok "镜像拉取完成"

# ── 7. 设置公网 IP ────────────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s --max-time 5 http://100.100.100.200/latest/meta-data/eip/public-ip 2>/dev/null \
         || curl -s --max-time 5 ifconfig.me 2>/dev/null \
         || echo "")

if [[ -n "$PUBLIC_IP" ]]; then
    CURRENT_URL=$(grep "^FRONTEND_URL=" .env | cut -d= -f2- | xargs || true)
    if [[ -z "$CURRENT_URL" ]]; then
        sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=http://${PUBLIC_IP}:5000|" .env
        sed -i "s|^APP_URL=.*|APP_URL=http://${PUBLIC_IP}:5000|" .env
        ok "公网 IP 自动设置: $PUBLIC_IP"
    fi
fi

# ── 8. 启动服务 ───────────────────────────────────────────────────────────────
info "启动 BioMate 服务..."
docker compose -f docker-compose.onprem.yml --env-file .env up -d

# ── 9. 等待健康检查 ───────────────────────────────────────────────────────────
info "等待服务就绪（最多 3 分钟）..."
MAX_WAIT=180
ELAPSED=0
while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    FRONTEND_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' biomate-onprem-frontend 2>/dev/null || echo "starting")
    if [[ "$FRONTEND_HEALTH" == "healthy" ]]; then
        break
    fi
    printf "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""

if [[ "$FRONTEND_HEALTH" != "healthy" ]]; then
    warn "前端服务尚未就绪，可能仍在下载工作流数据库（~280MB），请稍等 1-2 分钟"
    warn "查看日志: docker compose -f docker-compose.onprem.yml logs -f"
fi

# ── 10. 创建管理员账号 ────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
echo "  下一步: 创建管理员账号"
echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
echo ""
read -r -p "  是否现在创建管理员账号？[Y/n] " CREATE_ADMIN
if [[ "${CREATE_ADMIN:-Y}" =~ ^[Yy]$ ]]; then
    bash scripts/biomate create-admin
fi

# ── 完成 ──────────────────────────────────────────────────────────────────────
FINAL_IP=${PUBLIC_IP:-"<ECS公网IP>"}
echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────${NC}"
echo -e "${GREEN}  BioMate Demo 部署完成！${NC}"
echo -e "${GREEN}────────────────────────────────────────────────────────────${NC}"
echo ""
echo "  访问地址:    http://${FINAL_IP}:5000"
echo "  MinIO 管理:  http://${FINAL_IP}:9001  （用户名/密码同 .env）"
echo ""
echo "  常用命令:"
echo "    查看日志:  docker compose -f docker-compose.onprem.yml logs -f"
echo "    停止服务:  docker compose -f docker-compose.onprem.yml stop"
echo "    重启服务:  docker compose -f docker-compose.onprem.yml restart"
echo "    关闭节省费用（ECS停机前）: docker compose -f docker-compose.onprem.yml down"
echo ""
echo "  LLM: 千问 API (${LLM_MODEL:-qwen-plus}) • 按量计费，不演示时可关 ECS 省钱"
echo ""
