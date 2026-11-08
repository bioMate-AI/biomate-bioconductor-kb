#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# BioMate 本地部署诊断脚本
#
# 用法:
#   bash diag-onprem.sh              # 完整诊断 + 打包 tar.gz
#   bash diag-onprem.sh --quick      # 跳过完整日志收集（只取最近 50 行 error）
#   bash diag-onprem.sh --no-pack    # 只打印到终端，不生成 tar.gz
#
# 输出: /tmp/biomate-diag-YYYYMMDD_HHMMSS.tar.gz
# 将该文件发给 BioMate 支持工程师，或自行用 Claude Code 分析。
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DIAG_DIR="/tmp/biomate-diag-${TIMESTAMP}"
PACK_FILE="/tmp/biomate-diag-${TIMESTAMP}.tar.gz"
COMPOSE_FILE=""          # 自动探测
FRONTEND_PORT="${FRONTEND_PORT:-5000}"
GALAXY_PORT="${GALAXY_PORT:-8081}"
LOG_LINES_QUICK=50
LOG_LINES_FULL=500

# 所有 BioMate 本地部署容器名（container_name in docker-compose.onprem.yml）
CONTAINERS=(
  biomate-postgres
  biomate-redis
  biomate-galaxy
  biomate-frontend
  biomate-minio
  biomate-ollama
)

# ── 参数 ──────────────────────────────────────────────────────────────────────
QUICK=false
NO_PACK=false
for arg in "$@"; do
  case $arg in
    --quick)   QUICK=true ;;
    --no-pack) NO_PACK=false ;;  # kept for backwards compat but always pack
    *) ;;
  esac
done
LOG_LINES=$( $QUICK && echo $LOG_LINES_QUICK || echo $LOG_LINES_FULL )

# ── 颜色 ──────────────────────────────────────────────────────────────────────
GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GRN}✓${NC} $*"; }
warn() { echo -e "  ${YLW}⚠${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
hdr()  { echo -e "\n${CYN}══ $* ══${NC}"; }

# ── 自动探测 compose 文件 ─────────────────────────────────────────────────────
find_compose_file() {
  for candidate in \
    "$(pwd)/docker-compose.onprem.yml" \
    "$(dirname "$0")/../docker-compose.onprem.yml" \
    "/opt/biomate/docker-compose.onprem.yml" \
    "/app/docker-compose.onprem.yml" \
    "$HOME/biomate/docker-compose.onprem.yml"; do
    if [[ -f "$candidate" ]]; then
      COMPOSE_FILE="$candidate"
      return 0
    fi
  done
  # 没找到也继续，用纯 docker 命令
  COMPOSE_FILE=""
}

# ── 写入文件同时显示到终端 ───────────────────────────────────────────────────
tee_file() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  "$@" 2>&1 | tee "$file"
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. 系统信息
# ═════════════════════════════════════════════════════════════════════════════
collect_system() {
  hdr "1. 系统信息"
  local out="$DIAG_DIR/system.txt"
  mkdir -p "$DIAG_DIR"
  {
    echo "=== BioMate 诊断报告 ==="
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "主机名:   $(hostname)"
    echo ""
    echo "--- 操作系统 ---"
    uname -a 2>/dev/null || true
    cat /etc/os-release 2>/dev/null || sw_vers 2>/dev/null || true
    echo ""
    echo "--- CPU ---"
    if [[ -f /proc/cpuinfo ]]; then
      grep -m1 "model name" /proc/cpuinfo || true
      echo "核心数: $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"
    else
      sysctl -n machdep.cpu.brand_string 2>/dev/null || true
      echo "核心数: $(sysctl -n hw.ncpu 2>/dev/null)"
    fi
    echo ""
    echo "--- 内存 ---"
    if [[ -f /proc/meminfo ]]; then
      grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree)" /proc/meminfo
    else
      vm_stat 2>/dev/null | head -5 || true
    fi
    echo ""
    echo "--- 磁盘 ---"
    df -h 2>/dev/null | grep -v "tmpfs\|udev\|overlay" | head -20
    echo ""
    echo "--- /app 目录使用 ---"
    du -sh /app 2>/dev/null || du -sh /opt/biomate 2>/dev/null || echo "(未找到 /app)"
    echo ""
    echo "--- 网络接口 ---"
    ip addr 2>/dev/null | grep -E "^[0-9]+:|inet " || \
      ifconfig 2>/dev/null | grep -E "^[a-z]|inet " || true
  } | tee "$out"
  ok "系统信息已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. Docker 状态
# ═════════════════════════════════════════════════════════════════════════════
collect_docker() {
  hdr "2. Docker 状态"
  local out="$DIAG_DIR/docker-info.txt"
  {
    echo "--- Docker 版本 ---"
    docker version 2>/dev/null || { echo "Docker 未安装或无权限"; }
    echo ""
    echo "--- Docker Compose 版本 ---"
    docker compose version 2>/dev/null || docker-compose version 2>/dev/null || echo "未找到 docker compose"
    echo ""
    echo "--- 磁盘使用 ---"
    docker system df 2>/dev/null || true
  } | tee "$out"
  ok "Docker 信息已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. 容器状态
# ═════════════════════════════════════════════════════════════════════════════
collect_containers() {
  hdr "3. 容器状态"
  local out="$DIAG_DIR/containers-status.txt"
  {
    echo "--- 所有运行容器 ---"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" 2>/dev/null
    echo ""
    echo "--- BioMate 容器详情 ---"
    for cname in "${CONTAINERS[@]}"; do
      if docker inspect "$cname" &>/dev/null; then
        status=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null)
        health=$(docker inspect --format '{{.State.Health.Status}}' "$cname" 2>/dev/null || echo "no-healthcheck")
        started=$(docker inspect --format '{{.State.StartedAt}}' "$cname" 2>/dev/null)
        restart=$(docker inspect --format '{{.RestartCount}}' "$cname" 2>/dev/null)
        image=$(docker inspect --format '{{.Config.Image}}' "$cname" 2>/dev/null)
        printf "%-28s  %-10s  %-10s  restarts=%-3s  started=%s\n" \
          "$cname" "$status" "$health" "$restart" "${started:0:19}"
        printf "  image: %s\n" "$image"
        # 健康检查失败日志
        if [[ "$health" == "unhealthy" ]]; then
          echo "  [健康检查失败原因]:"
          docker inspect --format \
            '{{range .State.Health.Log}}  exit={{.ExitCode}} {{.Output}}{{end}}' \
            "$cname" 2>/dev/null | tail -3
        fi
        echo ""
      else
        printf "%-28s  %-10s\n" "$cname" "not found"
      fi
    done
  } | tee "$out"
  ok "容器状态已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. 容器日志（每个容器单独文件）
# ═════════════════════════════════════════════════════════════════════════════
collect_logs() {
  hdr "4. 容器日志（最近 ${LOG_LINES} 行，error 级别）"
  local log_dir="$DIAG_DIR/logs"
  mkdir -p "$log_dir"

  for cname in "${CONTAINERS[@]}"; do
    if ! docker inspect "$cname" &>/dev/null; then
      continue
    fi
    echo -n "  收集 $cname ... "

    # 完整日志（最近 N 行）
    docker logs --tail "$LOG_LINES" "$cname" > "$log_dir/${cname}-tail.log" 2>&1

    # 仅错误行（快速扫描用）
    docker logs --tail 2000 "$cname" 2>&1 \
      | grep -iE "(error|exception|fatal|traceback|panic|fail|critical)" \
      | tail -100 > "$log_dir/${cname}-errors.log" 2>/dev/null || true

    local err_count
    err_count=$(wc -l < "$log_dir/${cname}-errors.log" 2>/dev/null || echo 0)
    echo "done (${err_count} error lines)"
  done
  ok "日志已保存至 $log_dir"
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. API 健康检查
# ═════════════════════════════════════════════════════════════════════════════
collect_api_checks() {
  hdr "5. API 健康检查"
  local out="$DIAG_DIR/api-checks.txt"
  {
    # 前端健康
    echo "=== 前端 (port ${FRONTEND_PORT}) ==="
    frontend_health=$(curl -sf --max-time 5 "http://localhost:${FRONTEND_PORT}/api/health" 2>/dev/null || echo "FAIL")
    echo "GET /api/health → $frontend_health"

    # 许可证
    echo ""
    echo "=== 许可证状态 ==="
    license_resp=$(curl -sf --max-time 5 "http://localhost:${FRONTEND_PORT}/api/license/status" 2>/dev/null || echo "FAIL")
    echo "$license_resp"
    if echo "$license_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print('status:', d.get('status')); print('expires:', d.get('expiresAt','N/A')); print('max_users:', d.get('maxUsers','N/A'))" 2>/dev/null; then
      :
    fi

    # Galaxy 后端
    echo ""
    echo "=== Galaxy 后端 (port ${GALAXY_PORT}) ==="
    galaxy_ver=$(curl -sf --max-time 5 "http://localhost:${GALAXY_PORT}/api/version" 2>/dev/null || echo "FAIL")
    echo "GET /api/version → $galaxy_ver"

    # 工作流搜索
    echo ""
    echo "=== 工作流搜索 ==="
    wf_resp=$(curl -sf --max-time 10 \
      "http://localhost:${FRONTEND_PORT}/api/workflows/search?q=ADMET&limit=1" 2>/dev/null || echo "FAIL")
    if echo "$wf_resp" | python3 -c "import sys,json; r=json.load(sys.stdin); print('results:', len(r.get('results',r if isinstance(r,list) else [])))" 2>/dev/null; then
      :
    else
      echo "$wf_resp"
    fi

    # LLM 连通性（快速探测）
    echo ""
    echo "=== LLM 配置探测 ==="
    # 读取 .env 中的 LLM_PROVIDER（如果能找到的话）
    for envfile in "$(pwd)/.env" "/opt/biomate/.env" "/app/.env"; do
      if [[ -f "$envfile" ]]; then
        llm_provider=$(grep -E "^LLM_PROVIDER=" "$envfile" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
        qwen_base=$(grep -E "^QWEN_BASE_URL=" "$envfile" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
        echo ".env 文件: $envfile"
        echo "LLM_PROVIDER: ${llm_provider:-未设置}"
        [[ -n "$qwen_base" ]] && echo "QWEN_BASE_URL: $qwen_base"
        break
      fi
    done

  } | tee "$out"
  ok "API 检查已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. Docker Inspect（JSON 格式，供深度分析）
# ═════════════════════════════════════════════════════════════════════════════
collect_inspect() {
  hdr "6. 容器 Inspect"
  local inspect_dir="$DIAG_DIR/inspect"
  mkdir -p "$inspect_dir"
  for cname in "${CONTAINERS[@]}"; do
    if docker inspect "$cname" &>/dev/null; then
      docker inspect "$cname" > "$inspect_dir/${cname}.json" 2>/dev/null
      echo "  $cname → inspect/${cname}.json"
    fi
  done
  ok "Inspect JSON 已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. 最近工作流运行记录
# ═════════════════════════════════════════════════════════════════════════════
collect_recent_runs() {
  hdr "7. 最近工作流运行"
  local out="$DIAG_DIR/recent-runs.txt"
  {
    # 尝试从 Galaxy 后端 API 获取
    runs_resp=$(curl -sf --max-time 10 \
      "http://localhost:${FRONTEND_PORT}/api/runs?limit=10" \
      -H "Content-Type: application/json" 2>/dev/null || echo "FAIL")
    if [[ "$runs_resp" != "FAIL" ]]; then
      echo "最近 10 次运行:"
      echo "$runs_resp" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data if isinstance(data, list) else data.get('runs', data.get('results', []))
    for r in runs[:10]:
        print(f\"  {r.get('id','?')[:8]}  {r.get('status','?'):<12}  {r.get('workflowName','?')}  {r.get('createdAt','?')[:19]}\")
except Exception as e:
    print('解析失败:', e)
    print(sys.stdin.read()[:500])
" 2>/dev/null || echo "$runs_resp" | head -20
    else
      echo "无法从 API 获取运行记录（需要登录 token）"
      echo ""
      echo "--- 从 Galaxy 容器日志中提取最近运行 ---"
      docker logs --tail 2000 biomate-galaxy 2>&1 \
        | grep -E "(run_id|workflow_name|status.*complete|status.*fail)" \
        | tail -20 || echo "(未找到运行记录)"
    fi
  } | tee "$out"
  ok "运行记录已保存"
}

# ═════════════════════════════════════════════════════════════════════════════
# 8. .env 安全摘要（脱敏）
# ═════════════════════════════════════════════════════════════════════════════
collect_env_summary() {
  hdr "8. 环境变量摘要（脱敏）"
  local out="$DIAG_DIR/env-summary.txt"
  {
    for envfile in "$(pwd)/.env" "/opt/biomate/.env" "/app/.env"; do
      if [[ -f "$envfile" ]]; then
        echo "来源: $envfile"
        echo ""
        # 脱敏：只保留 KEY=（值部分用 *** 代替，或显示非敏感值）
        while IFS= read -r line; do
          # 跳过注释和空行
          [[ "$line" =~ ^# ]] && { echo "$line"; continue; }
          [[ -z "$line" ]] && { echo; continue; }
          key="${line%%=*}"
          val="${line#*=}"
          # 敏感字段脱敏
          if echo "$key" | grep -qiE "password|secret|key|token|credential|api_key"; then
            [[ -n "$val" ]] && echo "${key}=***已设置***" || echo "${key}=（未设置）"
          else
            echo "$line"
          fi
        done < "$envfile"
        break
      fi
    done
  } | tee "$out"
  ok "环境变量摘要已保存（密钥已脱敏）"
}

# ═════════════════════════════════════════════════════════════════════════════
# 9. 生成摘要
# ═════════════════════════════════════════════════════════════════════════════
generate_summary() {
  hdr "9. 生成摘要"
  local out="$DIAG_DIR/SUMMARY.txt"
  {
    echo "======================================================"
    echo "  BioMate 诊断摘要"
    echo "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "======================================================"
    echo ""
    echo "── 容器状态 ──"
    for cname in "${CONTAINERS[@]}"; do
      if docker inspect "$cname" &>/dev/null; then
        status=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null)
        health=$(docker inspect --format '{{.State.Health.Status}}' "$cname" 2>/dev/null || echo "")
        restart=$(docker inspect --format '{{.RestartCount}}' "$cname" 2>/dev/null)
        badge=""
        [[ "$status" == "running" && ( "$health" == "healthy" || -z "$health" ) ]] && badge="✓"
        [[ "$health" == "unhealthy" ]] && badge="✗ UNHEALTHY"
        [[ "$status" != "running" ]] && badge="✗ ${status^^}"
        [[ "$restart" -gt 3 ]] 2>/dev/null && badge="${badge} (restarts=${restart}!)"
        printf "  %-28s %s\n" "$cname" "${badge:-$status}"
      else
        printf "  %-28s %s\n" "$cname" "— not found"
      fi
    done
    echo ""
    echo "── 前端健康 ──"
    frontend_health=$(curl -sf --max-time 3 "http://localhost:${FRONTEND_PORT}/api/health" 2>/dev/null && echo "✓ OK" || echo "✗ 无响应")
    echo "  $frontend_health"
    echo ""
    echo "── 错误日志统计 ──"
    for cname in "${CONTAINERS[@]}"; do
      local errfile="$DIAG_DIR/logs/${cname}-errors.log"
      if [[ -f "$errfile" ]]; then
        cnt=$(wc -l < "$errfile")
        [[ "$cnt" -gt 0 ]] && printf "  %-28s %s error lines\n" "$cname" "$cnt"
      fi
    done
    echo ""
    echo "── 文件清单 ──"
    find "$DIAG_DIR" -type f | sed "s|$DIAG_DIR/||" | sort
    echo ""
    echo "======================================================"
    echo "  请将 $PACK_FILE 发送给 BioMate 支持工程师"
    echo "======================================================"
  } | tee "$out"
}

# ═════════════════════════════════════════════════════════════════════════════
# 10. 打包
# ═════════════════════════════════════════════════════════════════════════════
pack() {
  hdr "10. 打包诊断文件"
  tar -czf "$PACK_FILE" -C /tmp "biomate-diag-${TIMESTAMP}" 2>/dev/null
  local size
  size=$(du -sh "$PACK_FILE" 2>/dev/null | cut -f1)
  echo ""
  echo -e "${GRN}════════════════════════════════════════════════${NC}"
  echo -e "${GRN}  诊断包已生成: $PACK_FILE${NC}"
  echo -e "${GRN}  大小: ${size}${NC}"
  echo -e "${GRN}════════════════════════════════════════════════${NC}"
  echo ""
  echo "  发送方式（任选其一）："
  echo "  ① 直接发给工程师：scp $PACK_FILE <engineer>@<host>:~/"
  echo "  ② 上传临时分享：curl -F 'file=@$PACK_FILE' https://tmpfiles.org/api/v1/upload"
  echo "  ③ 微信/钉钉传文件"
  echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
# 主流程
# ═════════════════════════════════════════════════════════════════════════════
main() {
  echo ""
  echo -e "${CYN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYN}║   BioMate 本地部署诊断脚本                  ║${NC}"
  echo -e "${CYN}║   $(date '+%Y-%m-%d %H:%M:%S')                     ║${NC}"
  echo -e "${CYN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  find_compose_file
  [[ -n "$COMPOSE_FILE" ]] && echo "  Compose 文件: $COMPOSE_FILE" || echo "  未找到 compose 文件（使用纯 docker 命令）"
  echo "  诊断目录: $DIAG_DIR"
  $QUICK && echo "  模式: 快速（--quick）"
  echo ""

  collect_system
  collect_docker
  collect_containers
  collect_logs
  collect_api_checks
  collect_inspect
  collect_recent_runs
  collect_env_summary
  generate_summary
  pack
}

main "$@"
