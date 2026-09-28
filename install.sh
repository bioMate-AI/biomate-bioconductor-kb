#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# BioMate On-Premises Installer
# 版本: 1.0.0
# 用法: bash install.sh [--non-interactive] [--env-file /path/to/.env]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.onprem.yml"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="/tmp/biomate-install.log"
BIOMATE_VERSION="${BIOMATE_VERSION:-latest}"

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}══ $* ══${RESET}"; }
die()     { error "$*"; exit 1; }

NON_INTERACTIVE=false
for arg in "$@"; do
  case $arg in
    --non-interactive) NON_INTERACTIVE=true ;;
    --env-file=*)      ENV_FILE="${arg#*=}" ;;
    --env-file)        shift; ENV_FILE="$1" ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# 0. 欢迎语
# ─────────────────────────────────────────────────────────────────────────────
clear
cat <<'BANNER'
  ____  _       __  __       _
 | __ )(_) ___ |  \/  | __ _| |_ ___
 |  _ \| |/ _ \| |\/| |/ _` | __/ _ \
 | |_) | | (_) | |  | | (_| | ||  __/
 |____/|_|\___/|_|  |_|\__,_|\__\___|

 BioMate On-Premises Installer v1.0.0
 ─────────────────────────────────────
BANNER
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. 预检 (Pre-flight checks)
# ─────────────────────────────────────────────────────────────────────────────
step "预检 / Pre-flight checks"

# Docker
if ! command -v docker &>/dev/null; then
  die "未找到 Docker。请先安装 Docker Engine 24+: https://docs.docker.com/engine/install/"
fi
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
if [[ "$DOCKER_MAJOR" -lt 24 ]]; then
  warn "Docker 版本 $DOCKER_VERSION 较旧，建议升级到 24+。"
else
  ok "Docker $DOCKER_VERSION"
fi

# Docker Compose
if ! docker compose version &>/dev/null; then
  die "未找到 docker compose (v2)。请升级 Docker 或安装 docker-compose-plugin。"
fi
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'v2')"

# Docker 可以访问
if ! docker info &>/dev/null; then
  die "无法连接 Docker daemon。请检查 Docker 是否在运行，或当前用户是否在 docker 组。"
fi
ok "Docker daemon 可访问"

# 磁盘空间 (至少 50GB)
DISK_FREE_GB=$(df -BG "$SCRIPT_DIR" | awk 'NR==2{print $4}' | tr -d 'G')
if [[ "$DISK_FREE_GB" -lt 50 ]]; then
  warn "磁盘剩余空间 ${DISK_FREE_GB}GB，建议至少 50GB（生信工具镜像较大）。"
else
  ok "磁盘剩余 ${DISK_FREE_GB}GB"
fi

# 内存 (至少 16GB)
if [[ "$(uname)" == "Linux" ]]; then
  MEM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
  if [[ "$MEM_GB" -lt 16 ]]; then
    warn "内存 ${MEM_GB}GB，建议至少 16GB（32B 模型需要更多）。"
  else
    ok "内存 ${MEM_GB}GB"
  fi
fi

# 必要端口检查
for PORT in 5000 8081 9000 9001 5050; do
  if ss -tuln 2>/dev/null | grep -q ":$PORT " || \
     netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
    warn "端口 $PORT 已被占用，可能冲突。"
  fi
done

ok "预检完成"

# ─────────────────────────────────────────────────────────────────────────────
# _setenv KEY VALUE — safely write KEY=VALUE into $ENV_FILE.
# Uses pure bash so passwords / URLs containing sed metacharacters (|, &, \, /)
# are written verbatim without corrupting the file.
# ─────────────────────────────────────────────────────────────────────────────
_setenv() {
  local key="$1" val="$2"
  local tmp
  tmp=$(mktemp "${ENV_FILE}.tmp.XXXXXX")
  local found=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$val"
      found=true
    else
      printf '%s\n' "$line"
    fi
  done < "$ENV_FILE" > "$tmp"
  # If the key didn't exist, append it
  if ! $found; then
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# 交互式配置向导 (must be defined before it is called below)
# ─────────────────────────────────────────────────────────────────────────────
_wizard() {
  echo ""
  echo "请根据提示填写配置（直接回车使用默认值）。"
  echo ""

  # 许可证
  read -rp "  许可证 Key [${BIOMATE_LICENSE_KEY:-BMOP-DEMO-DEMO-DEMO-DEMO}]: " _lic
  _lic="${_lic:-${BIOMATE_LICENSE_KEY:-BMOP-DEMO-DEMO-DEMO-DEMO}}"
  _setenv BIOMATE_LICENSE_KEY "$_lic"

  # 数据库密码
  _pg_pass=""
  while [[ -z "$_pg_pass" ]]; do
    read -rsp "  PostgreSQL 密码 (必填，至少8位): " _pg_pass; echo ""
    [[ ${#_pg_pass} -lt 8 ]] && { warn "密码太短，请重新输入。"; _pg_pass=""; }
  done
  _setenv POSTGRES_PASSWORD "$_pg_pass"

  # MinIO 密码
  _minio_pass=""
  while [[ -z "$_minio_pass" ]]; do
    read -rsp "  MinIO 密码 (必填，至少8位): " _minio_pass; echo ""
    [[ ${#_minio_pass} -lt 8 ]] && { warn "密码太短，请重新输入。"; _minio_pass=""; }
  done
  _setenv MINIO_ROOT_PASSWORD "$_minio_pass"

  # JWT/Session/Galaxy API 密钥 — 自动生成
  if command -v openssl &>/dev/null; then
    _jwt=$(openssl rand -hex 32)
    _sess=$(openssl rand -hex 32)
    _api_key=$(openssl rand -hex 32)
    _setenv JWT_SECRET "$_jwt"
    _setenv SESSION_SECRET "$_sess"
    _setenv GALAXY_API_KEY "$_api_key"
    ok "JWT/Session/Galaxy API 密钥已自动生成"
  else
    warn "openssl 未找到，请手动设置 JWT_SECRET、SESSION_SECRET 和 GALAXY_API_KEY。"
  fi

  # LLM 选择
  echo ""
  echo "  LLM 提供商选择:"
  echo "    1) 本地大模型 (vLLM/LMDeploy, 推荐内网部署)"
  echo "    2) DeepSeek API (国内直连)"
  echo "    3) 智谱 GLM (国内直连)"
  echo "    4) Anthropic Claude (需境外网络)"
  echo "    5) Ollama (本机 GPU)"
  read -rp "  选择 [1-5, 默认 1]: " _llm_choice
  _llm_choice="${_llm_choice:-1}"
  case "$_llm_choice" in
    1)
      read -rp "  本地模型 API URL [http://192.168.1.100:8000/v1]: " _url
      _url="${_url:-http://192.168.1.100:8000/v1}"
      read -rp "  模型名称 [qwen2.5-32b-instruct]: " _model
      _model="${_model:-qwen2.5-32b-instruct}"
      _setenv LLM_API_URL "$_url"
      _setenv LLM_MODEL "$_model"
      _setenv GALAXY_AI_LLM_PROVIDER openai_compatible
      ;;
    2)
      read -rsp "  DeepSeek API Key: " _key; echo ""
      _setenv DEEPSEEK_API_KEY "$_key"
      _setenv GALAXY_AI_LLM_PROVIDER deepseek
      ;;
    3)
      read -rsp "  智谱 GLM API Key: " _key; echo ""
      _setenv ZHIPU_API_KEY "$_key"
      _setenv GALAXY_AI_LLM_PROVIDER zhipu
      ;;
    4)
      read -rsp "  Anthropic API Key: " _key; echo ""
      _setenv ANTHROPIC_API_KEY "$_key"
      _setenv GALAXY_AI_LLM_PROVIDER anthropic
      ;;
    5)
      _setenv GALAXY_AI_LLM_PROVIDER ollama
      warn "Ollama 服务默认已注释，请手动取消 docker-compose.onprem.yml 中的注释。"
      ;;
  esac

  ok "配置已保存到 $ENV_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. 环境配置 (.env)
# ─────────────────────────────────────────────────────────────────────────────
step "环境配置 / Environment setup"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    die ".env 文件不存在。请先: cp .env.onprem.example .env 并填写必填项。"
  fi
  info "未找到 .env 文件，开始交互式配置向导..."
  cp "$SCRIPT_DIR/.env.onprem.example" "$ENV_FILE"
  _wizard
else
  ok "找到 .env 文件: $ENV_FILE"
fi

# 加载 .env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ── 校验必填项 ────────────────────────────────────────────────────────────────
_check_required() {
  local var="$1" val="${!1:-}"
  if [[ -z "$val" ]]; then
    die "必填项 $var 未设置。请编辑 $ENV_FILE 并填写。"
  fi
}
_check_required POSTGRES_PASSWORD
_check_required JWT_SECRET
_check_required SESSION_SECRET
_check_required MINIO_ROOT_PASSWORD
_check_required GALAXY_API_KEY

ok "必填项校验通过"

# ─────────────────────────────────────────────────────────────────────────────
# 3. 拉取镜像
# ─────────────────────────────────────────────────────────────────────────────
step "拉取服务镜像 / Pulling images"

# ── GHCR 认证（如果 BioMate 镜像是私有包，需要提供 Token）──────────────────────
# GHCR_TOKEN: GitHub Personal Access Token (read:packages 权限)
# 如果 BioMate 团队已将镜像设为公开，无需此步骤。
# 如果拉取失败报 401，请在 .env 中添加: GHCR_TOKEN=ghp_xxxx 并重新运行 install.sh
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  _ghcr_user="${GHCR_USER:-${GHCR_TOKEN_USER:-biomate-deploy}}"
  info "使用 GHCR Token 登录 ghcr.io (用户: ${_ghcr_user})..."
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$_ghcr_user" --password-stdin 2>&1 \
    && ok "GHCR 登录成功" \
    || warn "GHCR 登录失败，将尝试匿名拉取"
fi

info "拉取基础服务镜像（postgres, redis, minio, registry）..."
docker pull postgres:15 2>&1 | tail -1
docker pull redis:7-alpine 2>&1 | tail -1
docker pull minio/minio:latest 2>&1 | tail -1
docker pull minio/mc:latest 2>&1 | tail -1
docker pull registry:2 2>&1 | tail -1
ok "基础镜像就绪"

# BioMate 镜像（如果是离线包，已经 docker load 好了）
# Variable names match docker-compose.onprem.yml so offline installs work.
GALAXY_IMAGE="${BIOMATE_BACKEND_IMAGE:-ghcr.io/biomate-ai/biomate-backend:latest}"
FRONTEND_IMAGE="${BIOMATE_FRONTEND_IMAGE:-ghcr.io/biomate-ai/biomate-frontend:latest}"

for _img in "$GALAXY_IMAGE" "$FRONTEND_IMAGE"; do
  if docker image inspect "$_img" &>/dev/null; then
    ok "镜像已存在（离线包）: $_img"
  else
    info "拉取 BioMate 镜像: $_img ..."
    if ! docker pull "$_img" 2>&1; then
      error "镜像拉取失败: $_img"
      echo ""
      echo "  可能原因:"
      echo "    1. 网络问题（检查是否能访问 ghcr.io）"
      echo "    2. 镜像为私有包，需要认证（在 .env 中设置 GHCR_TOKEN=ghp_xxxx）"
      echo "    3. 离线部署：将 docker 镜像 tar 包传入并 docker load"
      echo ""
      die "请解决上述问题后重新运行 install.sh"
    fi
    ok "镜像拉取成功: $_img"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# 4. 创建 Nextflow 工作目录
# ─────────────────────────────────────────────────────────────────────────────
step "准备 Nextflow 工作目录 / Nextflow work directory"

# /app/nf-work is bind-mounted into the galaxy container AND into every
# Docker task container launched via DinD.  Both host and container paths
# MUST be identical (/app/nf-work:/app/nf-work) — this is enforced by
# docker-compose.onprem.yml.  If we let Docker create the directory on
# first mount it will be owned by root; the galaxy user (uid=1000) would
# then get "Permission denied" writing the Nextflow work files.
NF_WORK_DIR="${NEXTFLOW_WORK_DIR:-/app/nf-work}"
if [[ ! -d "$NF_WORK_DIR" ]]; then
  info "创建 $NF_WORK_DIR ..."
  mkdir -p "$NF_WORK_DIR"
fi
chmod 777 "$NF_WORK_DIR"
ok "Nextflow 工作目录已就绪: $NF_WORK_DIR (权限: 777)"

# ─────────────────────────────────────────────────────────────────────────────
# 4a. 生成 backend/config/galaxy.yml（从模板；不覆盖已有文件）
# ─────────────────────────────────────────────────────────────────────────────
# docker-compose.onprem.yml bind-mounts ./backend/config:/app/config.
# galaxy.yml is gitignored (it contains dev secrets); install.sh must generate
# it from galaxy.yml.template before composing up, otherwise the bind mount
# hides the image-baked config and Galaxy fails to start.
_GALAXY_YML="$SCRIPT_DIR/backend/config/galaxy.yml"
_GALAXY_TMPL="$SCRIPT_DIR/backend/config/galaxy.yml.template"
if [[ ! -f "$_GALAXY_YML" ]]; then
  if [[ -f "$_GALAXY_TMPL" ]]; then
    cp "$_GALAXY_TMPL" "$_GALAXY_YML"
    ok "backend/config/galaxy.yml 已从模板生成"
  else
    warn "未找到 galaxy.yml.template — Galaxy 可能无法正常启动"
  fi
else
  ok "backend/config/galaxy.yml 已存在，跳过生成"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4b. 检测 Docker socket GID（Nextflow 本地执行器必须）
# ─────────────────────────────────────────────────────────────────────────────
# galaxy-backend 以 uid=1000 (galaxy user) 运行，需要访问宿主机 Docker socket。
# group_add 配置的 GID 必须与 /var/run/docker.sock 的实际 GID 一致，否则
# local Nextflow 任务容器无法启动 (Permission denied on docker.sock)。
if [[ -e /var/run/docker.sock ]]; then
  _detected_gid=$(stat -c %g /var/run/docker.sock 2>/dev/null || echo "999")
  _current_gid="${DOCKER_GID:-999}"
  if [[ "$_detected_gid" != "$_current_gid" ]]; then
    info "检测到 Docker socket GID: $_detected_gid（当前 .env 配置: $_current_gid），自动更新..."
    sed -i.bak "s|^DOCKER_GID=.*|DOCKER_GID=$_detected_gid|" "$ENV_FILE" 2>/dev/null || true
    rm -f "$ENV_FILE.bak"
    export DOCKER_GID="$_detected_gid"
    ok "DOCKER_GID 已更新为 $_detected_gid"
  else
    ok "Docker socket GID: $_detected_gid（与 .env 一致）"
  fi
else
  warn "/var/run/docker.sock 未找到，将使用 DOCKER_GID=${DOCKER_GID:-999}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. 启动服务
# ─────────────────────────────────────────────────────────────────────────────
step "启动服务 / Starting services"

info "启动所有服务 (后台)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d \
  --remove-orphans 2>&1 | tee -a "$LOG_FILE"

ok "服务已启动"

# ─────────────────────────────────────────────────────────────────────────────
# 6. 等待健康检查
# ─────────────────────────────────────────────────────────────────────────────
step "等待服务就绪 / Waiting for health checks"

_wait_healthy() {
  local container="$1" max_wait="${2:-120}" interval=5
  local elapsed=0
  info "等待 $container 就绪..."
  while true; do
    local status
    status=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    case "$status" in
      healthy)
        ok "$container 已就绪"
        return 0
        ;;
      unhealthy)
        error "$container 健康检查失败"
        docker logs --tail 30 "$container" 2>&1 || true
        return 1
        ;;
      missing|"")
        # 容器不存在或没有健康检查
        if docker inspect "$container" &>/dev/null; then
          ok "$container 运行中（无健康检查）"
          return 0
        fi
        ;;
    esac
    if [[ "$elapsed" -ge "$max_wait" ]]; then
      error "$container 在 ${max_wait}s 内未就绪，状态: $status"
      docker logs --tail 30 "$container" 2>&1 || true
      return 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    printf "  ."
  done
}

_wait_healthy biomate-postgres 60
_wait_healthy biomate-redis   30
_wait_healthy biomate-minio   60
# Galaxy backend starts AFTER db-init completes. db-init downloads the
# 280MB workflow catalog, which can take 5-10 min on a slow link. Use a
# 600s (10 min) timeout so fresh installs do not show a spurious error.
_wait_healthy biomate-galaxy  600
_wait_healthy biomate-frontend 60

# ─────────────────────────────────────────────────────────────────────────────
# 7. 初始化数据库
# ─────────────────────────────────────────────────────────────────────────────
step "初始化数据库 / Database initialization"

# Migrations run automatically inside the frontend container at startup
# (server/migrate.ts → applyPendingMigrations called in server/index.ts before
# registerRoutes). The healthcheck above already confirmed the frontend is
# healthy, so all pending migrations have been applied.
ok "数据库迁移已在服务启动时自动完成"

# ─────────────────────────────────────────────────────────────────────────────
# 8. 创建管理员账号
# ─────────────────────────────────────────────────────────────────────────────
step "创建管理员账号 / Admin account setup"

if [[ "$NON_INTERACTIVE" == "true" ]]; then
  info "非交互模式，跳过管理员账号创建。请手动运行: biomate create-admin"
else
  echo ""
  echo "  请设置管理员账号（首次登录使用）:"
  read -rp "  管理员邮箱: " ADMIN_EMAIL
  _admin_pass=""
  while [[ -z "$_admin_pass" ]]; do
    read -rsp "  管理员密码 (至少8位): " _admin_pass; echo ""
    [[ ${#_admin_pass} -lt 8 ]] && { warn "密码太短。"; _admin_pass=""; }
  done

  if [[ -n "$ADMIN_EMAIL" && -n "$_admin_pass" ]]; then
    _FE_PORT="${FRONTEND_PORT:-5000}"
    _API="http://localhost:${_FE_PORT}"
    # Encode values as JSON strings to handle special characters.
    _json_email=$(printf '%s' "$ADMIN_EMAIL" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    _json_pass=$(printf '%s'  "$_admin_pass"  | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    # Escape single quotes for SQL (double them: standard SQL literal escaping).
    _sql_email="${ADMIN_EMAIL//\'/\'\'}"

    # Step 1: register (bcrypt is handled server-side; no-SMTP returns verificationToken)
    _REG=$(curl -sf -X POST "$_API/api/auth/register" \
      -H "Content-Type: application/json" \
      --data-binary "{\"email\":${_json_email},\"password\":${_json_pass},\"acceptTerms\":true}" 2>&1 || true)
    _VER_TOKEN=$(echo "$_REG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('verificationToken',''))" 2>/dev/null || true)

    # Step 2: verify email (token returned when SMTP not configured)
    if [[ -n "$_VER_TOKEN" ]]; then
      curl -sf -X POST "$_API/api/auth/verify-email" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$_VER_TOKEN\"}" >/dev/null 2>&1 || true
    fi

    # Step 3: promote to admin via direct SQL on postgres container
    docker exec biomate-postgres psql -U "${POSTGRES_USER:-biomate}" "${POSTGRES_DB:-biomate}" \
      -t -c "UPDATE users SET subscription_tier='admin', email_verified=true WHERE email='${_sql_email}'" \
      >/dev/null 2>&1 || true

    # Verify the user exists
    _USER_EXISTS=$(docker exec biomate-postgres psql -U "${POSTGRES_USER:-biomate}" "${POSTGRES_DB:-biomate}" \
      -t -c "SELECT COUNT(*) FROM users WHERE email='${_sql_email}'" 2>&1 | tr -d ' ' || echo "0")

    if [[ "$_USER_EXISTS" -gt 0 ]]; then
      ok "管理员账号已创建: $ADMIN_EMAIL"
    else
      warn "管理员账号创建遇到问题，请稍后运行: bash scripts/biomate create-admin"
      info "手动创建: curl -X POST http://localhost:${_FE_PORT}/api/auth/register -H 'Content-Type: application/json' -d '{\"email\":\"admin@example.com\",\"password\":\"yourpass\",\"acceptTerms\":true}'"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 9. 验证部署
# ─────────────────────────────────────────────────────────────────────────────
step "验证部署 / Deployment verification"

FRONTEND_PORT="${FRONTEND_PORT:-5000}"
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

_check_endpoint() {
  local name="$1" url="$2"
  if curl -sf --max-time 10 "$url" &>/dev/null; then
    ok "$name → $url"
  else
    warn "$name → $url (未响应，服务可能还在启动)"
  fi
}

_check_endpoint "前端"         "http://localhost:${FRONTEND_PORT}/api/health"
_check_endpoint "Galaxy API"   "http://localhost:8081/api/version"
_check_endpoint "MinIO API"    "http://localhost:9000/minio/health/ready"
_check_endpoint "许可证 API"   "http://localhost:8081/api/license/status"

# ─────────────────────────────────────────────────────────────────────────────
# 10. 完成
# ─────────────────────────────────────────────────────────────────────────────
step "安装完成 / Installation complete"

cat <<EOF

  ${GREEN}${BOLD}BioMate 已成功部署！${RESET}

  访问地址:
    • 前端界面:     http://${HOST_IP}:${FRONTEND_PORT}
    • MinIO 管理:   http://${HOST_IP}:9001  (用户名: ${MINIO_ROOT_USER:-biomate})
    • Galaxy API:   http://localhost:8081/api/version

  常用命令:
    查看状态:       bash scripts/biomate status
    查看日志:       bash scripts/biomate logs [service]
    创建管理员:     bash scripts/biomate create-admin
    检查许可证:     bash scripts/biomate license
    停止所有服务:   docker compose -f docker-compose.onprem.yml down
    更新到新版本:   bash scripts/onprem-update.sh

  安装日志: $LOG_FILE

EOF
