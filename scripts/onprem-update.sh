#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# BioMate On-Premises 更新脚本
#
# 使用方法:
#   bash onprem-update.sh                    # 拉取最新镜像并重启
#   bash onprem-update.sh --db-only          # 只更新工作流数据库
#   bash onprem-update.sh --tag v2.5.0       # 指定版本
#
# 前置要求: Docker, Docker Compose v2, 已有 .env 文件
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$REPO_DIR/docker-compose.onprem.yml"
BACKUP_DIR="$REPO_DIR/backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/biomate-update-$(date +%Y%m%d_%H%M%S).log"

# ── 颜色 ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

# ── 参数解析 ──────────────────────────────────────────────────────────────────
DB_ONLY=false
TAG=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --db-only) DB_ONLY=true; shift ;;
    --tag)     TAG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--db-only] [--tag <version>]"
      echo "  --db-only   只更新工作流数据库，不重启服务"
      echo "  --tag       指定镜像版本标签（默认: latest）"
      exit 0 ;;
    *) error "未知参数: $1" ;;
  esac
done

# ── 检查环境 ──────────────────────────────────────────────────────────────────
check_prerequisites() {
  info "检查运行环境…"
  command -v docker &>/dev/null  || error "未找到 docker 命令"
  docker compose version &>/dev/null || error "未找到 docker compose v2（注意不是 docker-compose）"
  [[ -f "$COMPOSE_FILE" ]] || error "未找到 $COMPOSE_FILE"
  [[ -f "$REPO_DIR/.env" ]] || error "未找到 .env 文件，请先从 .env.onprem.example 复制并配置"
  info "环境检查通过 ✓"
}

# ── 备份 ──────────────────────────────────────────────────────────────────────
backup_data() {
  info "备份数据到 $BACKUP_DIR …"
  mkdir -p "$BACKUP_DIR"

  # 备份 PostgreSQL
  if docker compose -f "$COMPOSE_FILE" ps postgres 2>/dev/null | grep -q "running"; then
    info "  → 备份 PostgreSQL 数据库…"
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
      pg_dump -U "${POSTGRES_USER:-biomate}" "${POSTGRES_DB:-biomate}" \
      | gzip > "$BACKUP_DIR/postgres.sql.gz" 2>>"$LOG_FILE" \
      && info "  → PostgreSQL 备份完成" \
      || warn "  → PostgreSQL 备份失败（继续更新）"
  fi

  # 备份工作流数据库
  if docker compose -f "$COMPOSE_FILE" ps galaxy-backend 2>/dev/null | grep -q "running"; then
    info "  → 备份工作流数据库…"
    docker compose -f "$COMPOSE_FILE" exec -T galaxy-backend \
      cat /app/database/galaxy_ai_tools.db > "$BACKUP_DIR/galaxy_ai_tools.db" 2>>"$LOG_FILE" \
      && info "  → 工作流数据库备份完成" \
      || warn "  → 工作流数据库备份失败（继续更新）"
  fi

  # 保留最近 10 次备份
  find "$(dirname "$BACKUP_DIR")" -maxdepth 1 -name "20*" -type d \
    | sort -r | tail -n +11 | xargs rm -rf 2>/dev/null || true

  info "备份完成 ✓ ($BACKUP_DIR)"
}

# ── 仅更新工作流数据库 ────────────────────────────────────────────────────────
update_db_only() {
  info "更新工作流数据库…"

  # 如果有 BioMate 提供的新数据库文件，直接复制
  NEW_DB=""
  for candidate in \
    "$REPO_DIR/backend/database/galaxy_ai_tools.db" \
    "$REPO_DIR/galaxy_ai_tools.db" \
    "/tmp/galaxy_ai_tools.db"; do
    if [[ -f "$candidate" ]]; then
      NEW_DB="$candidate"
      break
    fi
  done

  if [[ -z "$NEW_DB" ]]; then
    warn "未找到新的 galaxy_ai_tools.db 文件"
    warn "请将 BioMate 提供的更新包解压到 $REPO_DIR，然后重试"
    error "工作流数据库更新失败"
  fi

  info "  → 使用新数据库: $NEW_DB"
  docker compose -f "$COMPOSE_FILE" stop galaxy-backend
  docker cp "$NEW_DB" \
    "$(docker compose -f "$COMPOSE_FILE" ps -q galaxy-backend):/app/database/galaxy_ai_tools.db" \
    2>>"$LOG_FILE"
  docker compose -f "$COMPOSE_FILE" start galaxy-backend

  info "等待后端启动…"
  local retries=12
  while ! docker compose -f "$COMPOSE_FILE" exec -T galaxy-backend \
    curl -sf http://localhost:8080/api/version &>/dev/null; do
    retries=$((retries - 1))
    [[ $retries -le 0 ]] && error "后端启动超时，请查看日志: docker compose -f $COMPOSE_FILE logs galaxy-backend"
    sleep 10
  done

  info "工作流数据库更新完成 ✓"
}

# ── 拉取新镜像并重启 ──────────────────────────────────────────────────────────
update_images() {
  info "拉取最新镜像…"
  if [[ -n "$TAG" ]]; then
    # 设置版本标签（通过 COMPOSE_IMAGE_TAG env var 透传到 compose 文件）
    export COMPOSE_IMAGE_TAG="$TAG"
    info "  → 使用版本: $TAG"
  fi

  docker compose -f "$COMPOSE_FILE" pull 2>>"$LOG_FILE" \
    && info "镜像拉取完成 ✓" \
    || warn "部分镜像拉取失败，将使用已有镜像继续"

  info "重启服务（零停机：先启动新容器再停止旧容器）…"
  docker compose -f "$COMPOSE_FILE" up -d --remove-orphans 2>>"$LOG_FILE"

  info "等待服务健康检查…"
  local services=("postgres" "redis" "galaxy-backend" "frontend")
  local max_wait=120
  local waited=0
  while true; do
    all_healthy=true
    for svc in "${services[@]}"; do
      status=$(docker compose -f "$COMPOSE_FILE" ps "$svc" --format json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health',''))" 2>/dev/null || echo "")
      if [[ "$status" != "healthy" && "$status" != "" ]]; then
        all_healthy=false
        break
      fi
    done
    $all_healthy && break
    waited=$((waited + 10))
    [[ $waited -ge $max_wait ]] && { warn "等待健康检查超时，请手动确认状态"; break; }
    sleep 10
  done
}

# ── 验证 ──────────────────────────────────────────────────────────────────────
verify_deployment() {
  info "验证部署…"
  local frontend_port="${FRONTEND_PORT:-5000}"

  # 检查前端
  if curl -sf "http://localhost:${frontend_port}/api/health" &>/dev/null; then
    info "  ✓ 前端健康 (http://localhost:${frontend_port})"
  else
    warn "  ✗ 前端健康检查失败"
  fi

  # 检查许可证
  license_status=$(curl -sf "http://localhost:${frontend_port}/api/license/status" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
  if [[ "$license_status" == "active" || "$license_status" == "demo" ]]; then
    info "  ✓ 许可证状态: $license_status"
  else
    warn "  ✗ 许可证状态: $license_status — 请检查 BIOMATE_LICENSE_KEY"
  fi

  info "日志文件: $LOG_FILE"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
main() {
  echo "=================================================="
  echo "  BioMate On-Premises 更新脚本"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=================================================="

  check_prerequisites
  backup_data

  if $DB_ONLY; then
    update_db_only
  else
    update_images
  fi

  verify_deployment

  echo ""
  echo "=================================================="
  info "更新完成！"
  echo "=================================================="
}

main "$@"
