#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# BioMate 远程支持接入脚本
#
# 在客户服务器上运行，让 BioMate 支持工程师能远程接入内网排查问题。
# 支持三种接入方式，根据客户安全策略选择：
#
#   Tailscale（推荐）— 最简单，无需固定公网 IP，穿透性强
#   frp 反向隧道    — 自主可控，适合有安全管控的企业客户
#   Cloudflare 隧道 — 临时使用，无需任何服务端配置
#
# ── 用法 ──────────────────────────────────────────────────────────────────────
#   bash remote-access.sh tailscale --key <auth-key>
#   bash remote-access.sh frp --server frps.biomate.ai --token <token> [--port 16022]
#   bash remote-access.sh cloudflare --token <tunnel-token>
#   bash remote-access.sh cloudflare --quick                # 临时 URL，无需 token
#   bash remote-access.sh status                            # 查看当前接入状态
#   bash remote-access.sh stop                              # 停止所有隧道
#
# ── 安全说明 ──────────────────────────────────────────────────────────────────
#   - Tailscale/frp/Cloudflare 均只转发 SSH 端口（22），不暴露其他端口
#   - 建议支持完成后立即运行 stop 关闭隧道
#   - auth-key / token 请通过安全渠道（加密消息）发送给客户
#   - frp token 由 BioMate 团队控制，每次支持会话使用一次性 token
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

STATE_FILE="/tmp/.biomate-remote-access"
FRP_PID_FILE="/tmp/.biomate-frpc.pid"
FRP_BIN="/tmp/biomate-frpc"
FRP_CFG="/tmp/biomate-frpc.toml"

GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GRN}✓${NC} $*"; }
warn() { echo -e "${YLW}⚠${NC}  $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }
info() { echo -e "${CYN}→${NC} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# 通用工具
# ─────────────────────────────────────────────────────────────────────────────
require_root_or_sudo() {
  if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    warn "部分操作需要 root 权限。如遇权限错误，请用 sudo bash $0 $*"
  fi
}

detect_arch() {
  local arch
  arch=$(uname -m)
  case $arch in
    x86_64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;  # 默认
  esac
}

detect_os() {
  case $(uname -s) in
    Linux)  echo "linux" ;;
    Darwin) echo "darwin" ;;
    *) echo "linux" ;;
  esac
}

write_state() {
  echo "$1" > "$STATE_FILE"
}

read_state() {
  [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "none"
}

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────
cmd_status() {
  echo ""
  echo -e "${CYN}══ BioMate 远程接入状态 ══${NC}"
  echo ""

  local state
  state=$(read_state)
  echo "  当前模式: $state"
  echo ""

  case $state in
    tailscale)
      if command -v tailscale &>/dev/null; then
        echo "  Tailscale 状态:"
        tailscale status 2>/dev/null | head -5 || echo "  (无法获取状态)"
        local ip
        ip=$(tailscale ip -4 2>/dev/null || echo "未知")
        ok "Tailscale IP: $ip"
        info "工程师连接方式: ssh root@$ip"
      else
        warn "Tailscale 未安装"
      fi
      ;;
    frp)
      if [[ -f "$FRP_PID_FILE" ]] && kill -0 "$(cat "$FRP_PID_FILE")" 2>/dev/null; then
        ok "frpc 运行中 (PID $(cat "$FRP_PID_FILE"))"
        [[ -f "$FRP_CFG" ]] && {
          remote_port=$(grep "remotePort" "$FRP_CFG" 2>/dev/null | grep -oE "[0-9]+" || echo "未知")
          server=$(grep "serverAddr" "$FRP_CFG" 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' || echo "未知")
          info "工程师连接方式: ssh root@$server -p $remote_port"
        }
      else
        warn "frpc 未运行（PID 文件存在但进程已退出）"
      fi
      ;;
    cloudflare)
      if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "biomate-cloudflared"; then
        ok "Cloudflare 隧道运行中"
        info "查看隧道 URL: docker logs biomate-cloudflared 2>&1 | grep trycloudflare"
      else
        warn "Cloudflare 容器未运行"
      fi
      ;;
    none|*)
      info "无活跃远程接入会话"
      ;;
  esac
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# STOP
# ─────────────────────────────────────────────────────────────────────────────
cmd_stop() {
  echo ""
  info "停止所有远程接入..."
  local stopped=0

  # 停止 Tailscale
  if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
    info "断开 Tailscale..."
    tailscale down 2>/dev/null && ok "Tailscale 已断开" || warn "Tailscale 断开失败"
    stopped=$((stopped+1))
  fi

  # 停止 frpc
  if [[ -f "$FRP_PID_FILE" ]]; then
    local pid
    pid=$(cat "$FRP_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      ok "frpc (PID $pid) 已停止"
      stopped=$((stopped+1))
    fi
    rm -f "$FRP_PID_FILE" "$FRP_CFG" "$FRP_BIN"
  fi

  # 停止 Cloudflare
  if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "biomate-cloudflared"; then
    docker stop biomate-cloudflared 2>/dev/null && docker rm biomate-cloudflared 2>/dev/null
    ok "Cloudflare 隧道已停止"
    stopped=$((stopped+1))
  fi

  rm -f "$STATE_FILE"

  if [[ $stopped -eq 0 ]]; then
    info "没有运行中的接入会话"
  else
    ok "已停止 $stopped 个接入会话"
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# TAILSCALE
# ─────────────────────────────────────────────────────────────────────────────
cmd_tailscale() {
  local auth_key=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --key|-k) auth_key="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$auth_key" ]] && fail "缺少 --key 参数。获取方式: Tailscale 控制台 → Settings → Keys → Generate auth key（勾选 Ephemeral）"

  echo ""
  echo -e "${CYN}══ 配置 Tailscale 接入 ══${NC}"
  echo ""

  # 安装
  if ! command -v tailscale &>/dev/null; then
    info "安装 Tailscale..."
    local os arch
    os=$(detect_os)
    if [[ "$os" == "linux" ]]; then
      if command -v apt-get &>/dev/null; then
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
          | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" \
          | sudo tee /etc/apt/sources.list.d/tailscale.list
        sudo apt-get update -qq && sudo apt-get install -y tailscale
      elif command -v yum &>/dev/null; then
        sudo yum install -y tailscale 2>/dev/null || \
          curl -fsSL https://tailscale.com/install.sh | sh
      else
        curl -fsSL https://tailscale.com/install.sh | sh
      fi
    fi
  fi

  # 检查 tailscaled 是否运行
  if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    info "启动 tailscaled..."
    sudo systemctl enable --now tailscaled 2>/dev/null || \
      sudo tailscaled --state=/var/lib/tailscale/tailscaled.state &
    sleep 2
  fi

  # 接入网络
  info "接入 Tailscale 网络..."
  sudo tailscale up --authkey="$auth_key" --hostname="biomate-onprem-$(hostname | cut -c1-8)" 2>&1

  # 显示 IP
  sleep 2
  local ip
  ip=$(tailscale ip -4 2>/dev/null || echo "获取中...")
  echo ""
  ok "Tailscale 接入成功！"
  echo ""
  echo -e "  ${GRN}工程师连接命令:${NC}"
  echo -e "  ${CYN}  ssh root@${ip}${NC}"
  echo ""
  echo "  连接后可直接使用 Claude Code:"
  echo "    claude --no-stream   # 建议 no-stream 避免 TTY 问题"
  echo ""
  echo "  支持完成后，在此服务器运行:"
  echo "    bash remote-access.sh stop"
  echo ""

  write_state "tailscale"
}

# ─────────────────────────────────────────────────────────────────────────────
# FRP 反向隧道
# ─────────────────────────────────────────────────────────────────────────────
cmd_frp() {
  local server="frps.biomate.ai"
  local server_port=7000
  local remote_port=16022
  local token=""
  local frp_version="0.61.1"

  while [[ $# -gt 0 ]]; do
    case $1 in
      --server|-s)      server="$2"; shift 2 ;;
      --server-port)    server_port="$2"; shift 2 ;;
      --token|-t)       token="$2"; shift 2 ;;
      --port|--remote-port|-p) remote_port="$2"; shift 2 ;;
      --version)        frp_version="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$token" ]] && fail "缺少 --token 参数。请联系 BioMate 支持团队获取一次性 token。"

  echo ""
  echo -e "${CYN}══ 配置 frp 反向隧道 ══${NC}"
  echo "  服务端: ${server}:${server_port}"
  echo "  远端端口: ${remote_port}"
  echo ""

  # 下载 frpc（如果需要）
  if [[ ! -x "$FRP_BIN" ]]; then
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)
    local frp_pkg="frp_${frp_version}_${os}_${arch}"
    local frp_url="https://github.com/fatedier/frp/releases/download/v${frp_version}/${frp_pkg}.tar.gz"

    info "下载 frpc ${frp_version} (${os}/${arch})..."
    local tmp_tar="/tmp/${frp_pkg}.tar.gz"

    if ! curl -fsSL --connect-timeout 15 --max-time 60 "$frp_url" -o "$tmp_tar"; then
      # 国内镜像备用
      frp_url="https://ghproxy.com/${frp_url}"
      info "主站超时，尝试国内镜像..."
      curl -fsSL --connect-timeout 15 --max-time 60 "$frp_url" -o "$tmp_tar" \
        || fail "frpc 下载失败，请手动下载后放到 $FRP_BIN"
    fi

    tar -xzf "$tmp_tar" -C /tmp "${frp_pkg}/frpc" 2>/dev/null
    mv "/tmp/${frp_pkg}/frpc" "$FRP_BIN"
    chmod +x "$FRP_BIN"
    rm -rf "$tmp_tar" "/tmp/${frp_pkg}"
    ok "frpc 下载完成"
  fi

  # 写配置
  cat > "$FRP_CFG" <<EOF
# BioMate 远程支持隧道配置（自动生成）
serverAddr = "${server}"
serverPort = ${server_port}
auth.method = "token"
auth.token = "${token}"

[[proxies]]
name = "biomate-ssh-$(hostname | cut -c1-8)"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${remote_port}
EOF

  # 停止已有实例
  if [[ -f "$FRP_PID_FILE" ]] && kill -0 "$(cat "$FRP_PID_FILE")" 2>/dev/null; then
    kill "$(cat "$FRP_PID_FILE")" 2>/dev/null
    sleep 1
  fi

  # 启动 frpc（后台）
  info "启动 frpc..."
  nohup "$FRP_BIN" -c "$FRP_CFG" > /tmp/biomate-frpc.log 2>&1 &
  local pid=$!
  echo "$pid" > "$FRP_PID_FILE"
  sleep 3

  # 检查是否启动成功
  if ! kill -0 "$pid" 2>/dev/null; then
    fail "frpc 启动失败，查看日志: cat /tmp/biomate-frpc.log"
  fi

  if grep -q "login to server success" /tmp/biomate-frpc.log 2>/dev/null; then
    ok "frpc 连接服务端成功！"
  else
    warn "frpc 已启动但尚未确认连接，查看日志: tail -f /tmp/biomate-frpc.log"
  fi

  echo ""
  ok "frp 反向隧道已建立！"
  echo ""
  echo -e "  ${GRN}工程师连接命令:${NC}"
  echo -e "  ${CYN}  ssh root@${server} -p ${remote_port}${NC}"
  echo ""
  echo "  日志: tail -f /tmp/biomate-frpc.log"
  echo ""
  echo "  支持完成后，在此服务器运行:"
  echo "    bash remote-access.sh stop"
  echo ""

  write_state "frp"
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDFLARE TUNNEL
# ─────────────────────────────────────────────────────────────────────────────
cmd_cloudflare() {
  local token=""
  local quick=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --token|-t) token="$2"; shift 2 ;;
      --quick|-q) quick=true; shift ;;
      *) shift ;;
    esac
  done

  echo ""
  echo -e "${CYN}══ 配置 Cloudflare 隧道 ══${NC}"
  echo ""

  if ! command -v docker &>/dev/null; then
    fail "需要 Docker。请先安装 Docker 再运行此脚本。"
  fi

  # 停止已有
  docker stop biomate-cloudflared 2>/dev/null; docker rm biomate-cloudflared 2>/dev/null; true

  if $quick || [[ -z "$token" ]]; then
    # 快速临时隧道（trycloudflare，无需账号）
    # 注意：只能转发 HTTP，不能直接转发 SSH
    # 使用 websocket SSH 代理
    warn "快速模式：通过 Cloudflare trycloudflare 转发 SSH（使用 websocket）"
    warn "适合临时一次性使用，URL 随机，断开后失效"
    echo ""
    info "启动临时隧道（转发 localhost:22 → Cloudflare URL）..."
    docker run -d --name biomate-cloudflared \
      --network host \
      cloudflare/cloudflared:latest \
      tunnel --no-autoupdate \
      --url ssh://localhost:22 \
      2>/dev/null
    sleep 3
    echo ""
    info "获取隧道 URL（稍等 3-5 秒）..."
    sleep 3
    local tunnel_url
    tunnel_url=$(docker logs biomate-cloudflared 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | head -1 || echo "")
    echo ""
    if [[ -n "$tunnel_url" ]]; then
      ok "临时 Cloudflare 隧道已建立！"
      echo ""
      echo -e "  ${GRN}将以下 URL 发给工程师:${NC}"
      echo -e "  ${CYN}  $tunnel_url${NC}"
      echo ""
      echo "  工程师连接方式（需安装 cloudflared）:"
      echo "    ssh -o ProxyCommand='cloudflared access ssh --hostname %h' root@${tunnel_url#https://}"
      echo ""
    else
      warn "未能自动获取 URL，请手动查看:"
      echo "  docker logs biomate-cloudflared 2>&1 | grep trycloudflare"
    fi
  else
    # 正式 token 模式
    info "使用 Cloudflare Tunnel token 启动..."
    docker run -d --name biomate-cloudflared \
      --network host \
      cloudflare/cloudflared:latest \
      tunnel --no-autoupdate \
      run --token "$token" \
      2>/dev/null
    sleep 3
    if docker ps --format "{{.Names}}" | grep -q "biomate-cloudflared"; then
      ok "Cloudflare 隧道已启动！"
      echo ""
      echo "  隧道已连接到您的 Cloudflare 账户"
      echo "  请在 Cloudflare Zero Trust 控制台确认服务在线"
      echo ""
    else
      fail "Cloudflare 容器启动失败，查看日志: docker logs biomate-cloudflared"
    fi
  fi

  echo "  支持完成后，在此服务器运行:"
  echo "    bash remote-access.sh stop"
  echo ""

  write_state "cloudflare"
}

# ─────────────────────────────────────────────────────────────────────────────
# 主入口
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'

BioMate 远程支持接入脚本

用法:
  bash remote-access.sh <命令> [选项]

命令:
  tailscale  --key <auth-key>                   Tailscale 接入（推荐）
  frp        --server <host> --token <token>    frp 反向隧道
  cloudflare --token <token>                    Cloudflare 正式隧道
  cloudflare --quick                            Cloudflare 临时隧道（无需账号）
  status                                        查看当前接入状态
  stop                                          停止所有隧道

示例:
  bash remote-access.sh tailscale --key tskey-auth-xxxxxxxxxxxx
  bash remote-access.sh frp --server frps.biomate.ai --token abc123 --port 16022
  bash remote-access.sh cloudflare --quick
  bash remote-access.sh status
  bash remote-access.sh stop

EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local cmd="$1"; shift

  case $cmd in
    tailscale)  cmd_tailscale "$@" ;;
    frp)        cmd_frp "$@" ;;
    cloudflare|cf) cmd_cloudflare "$@" ;;
    status)     cmd_status ;;
    stop)       cmd_stop ;;
    help|-h|--help) usage ;;
    *) echo "未知命令: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
