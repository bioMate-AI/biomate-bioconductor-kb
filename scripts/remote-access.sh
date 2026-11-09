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
#   bash remote-access.sh tailscale --key-file /secure/auth-key
#   bash remote-access.sh frp --server <approved-host> --token-file /secure/token
#   bash remote-access.sh cloudflare --token-file /secure/token --image <qualified-digest>
#   cloudflare --quick 未通过 SSH 验证，明确拒绝而不是宣告成功
#   bash remote-access.sh status                            # 查看当前接入状态
#   bash remote-access.sh stop                              # 仅停止已验证归属的会话
#
# ── 安全说明 ──────────────────────────────────────────────────────────────────
#   - Tailscale/frp/Cloudflare 均只转发 SSH 端口（22），不暴露其他端口
#   - 建议支持完成后立即运行 stop 关闭隧道
#   - auth-key / token 请通过安全渠道（加密消息）发送给客户
#   - frp 共享 token 不等于一次性凭据；会后必须按服务端策略撤销/轮换
#   - 客户管理员预装并批准远程客户端；脚本不会自动下载/安装客户端
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
umask 077

REMOTE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/biomate-remote-access"
STATE_FILE="$REMOTE_DIR/state"
FRP_PID_FILE="$REMOTE_DIR/frpc.pid"
FRP_BIN="$REMOTE_DIR/frpc"
FRP_CFG="$REMOTE_DIR/frpc.toml"
FRP_LOG="$REMOTE_DIR/frpc.log"
TAILSCALE_ID_FILE="$REMOTE_DIR/tailscale-node-id"
CF_TOKEN_FILE="$REMOTE_DIR/cloudflare.token"

GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GRN}✓${NC} $*"; }
warn() { echo -e "${YLW}⚠${NC}  $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }
info() { echo -e "${CYN}→${NC} $*"; }

init_state() {
  [[ ! -L "$REMOTE_DIR" ]] || fail "拒绝符号链接状态目录"
  mkdir -p "$REMOTE_DIR"
  [[ -d "$REMOTE_DIR" && -O "$REMOTE_DIR" ]] || fail "状态目录必须归当前用户所有"
  chmod 700 "$REMOTE_DIR"
  mkdir "$REMOTE_DIR/operation.lock" 2>/dev/null || fail "已有操作或未核对的锁；未更改连接，请管理员核对"
  trap 'rmdir "$REMOTE_DIR/operation.lock" 2>/dev/null || true' EXIT
}

tailscale_node_id() {
  tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("ID", ""))'
}

owned_frp_pid() {
  [[ -f "$FRP_PID_FILE" ]] || return 1
  local pid command
  pid=$(cat "$FRP_PID_FILE")
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  command=$(ps -ww -p "$pid" -o command= 2>/dev/null) || return 1
  [[ "$command" == "$FRP_BIN -c $FRP_CFG" ]] || return 1
  printf '%s' "$pid"
}

private_secret_copy() {
  # No secret values in argv, stdout, shell history, or Docker environment.
  # Open the source without following a symlink; check its actual descriptor.
  local source="$1" destination
  destination=$(mktemp "$REMOTE_DIR/credential.XXXXXX")
  if ! python3 - "$source" "$destination" <<'PY'
import os, stat, sys
try:
    descriptor = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as source:
        metadata = os.fstat(source.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid() or metadata.st_mode & 0o077:
            raise ValueError('unsafe source')
        data = source.read(16385)
        if not data.strip() or len(data) > 16384 or b'\0' in data:
            raise ValueError('invalid secret')
    with open(sys.argv[2], 'wb') as target:
        target.write(data.strip())
except Exception:
    sys.exit(1)
PY
  then
    rm -f "$destination"
    fail "凭据文件必须归当前用户所有、仅所有者可读写，且内容有效"
  fi
  printf '%s' "$destination"
}

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
    *) fail "不支持的架构: $arch" ;;
  esac
}

detect_os() {
  case $(uname -s) in
    Linux)  echo "linux" ;;
    Darwin) echo "darwin" ;;
    *) fail "不支持的操作系统" ;;
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
    tailscale|tailscale_pending)
      if command -v tailscale &>/dev/null; then
        echo "  Tailscale 状态:"
        tailscale status 2>/dev/null | head -5 || echo "  (无法获取状态)"
        local ip
        ip=$(tailscale ip -4 2>/dev/null || echo "未知")
        ok "Tailscale IP: $ip"
        info "工程师使用客户批准的最小权限账号连接: ssh <获准账号>@$ip"
      else
        warn "Tailscale 未安装"
      fi
      ;;
    frp)
      if owned_frp_pid >/dev/null; then
        ok "frpc 运行中 (PID $(cat "$FRP_PID_FILE"))"
        [[ -f "$FRP_CFG" ]] && {
          remote_port=$(grep "remotePort" "$FRP_CFG" 2>/dev/null | grep -oE "[0-9]+" || echo "未知")
          server=$(grep "serverAddr" "$FRP_CFG" 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' || echo "未知")
          info "工程师使用客户批准的账号连接: ssh <获准账号>@$server -p $remote_port"
        }
      else
        warn "frpc 未运行（PID 文件存在但进程已退出）"
      fi
      ;;
    cloudflare)
      if docker ps --format "{{.Names}}" 2>/dev/null | grep -qx "biomate-cloudflared"; then
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
  info "仅停止本脚本记录的远程接入..."
  local stopped=0
  local state
  state=$(read_state)
  [[ "$state" != none ]] || { info "无本脚本管理的会话；未更改主机连接"; return 0; }

  # 停止 Tailscale
  if [[ "$state" == tailscale || "$state" == tailscale_pending ]]; then
    [[ -s "$TAILSCALE_ID_FILE" ]] || fail "缺少节点所有权记录；请管理员核对后手动处理"
    local expected current
    expected=$(cat "$TAILSCALE_ID_FILE")
    current=$(tailscale_node_id) || fail "无法验证当前节点；未断开连接"
    [[ -n "$current" && "$current" == "$expected" ]] || fail "节点与本会话不匹配；未断开连接"
    info "断开 Tailscale..."
    sudo tailscale down >/dev/null 2>&1 || fail "Tailscale 断开失败；保留所有权记录"
    rm -f "$TAILSCALE_ID_FILE"
    ok "Tailscale 已断开"
    stopped=$((stopped+1))
  fi

  # 停止 frpc
  if [[ "$state" == frp ]]; then
    [[ -f "$FRP_PID_FILE" ]] || fail "缺少 frpc 所有权记录；未终止任何进程"
    local pid
    if pid=$(owned_frp_pid); then
      kill "$pid" 2>/dev/null
      ok "frpc (PID $pid) 已停止"
      stopped=$((stopped+1))
    else
      fail "无法验证 frpc 进程所有权；未终止任何进程"
    fi
    rm -f "$FRP_PID_FILE" "$FRP_CFG" "$FRP_BIN"
  fi

  # 停止 Cloudflare
  if [[ "$state" == cloudflare ]]; then
    local owner
    owner=$(docker inspect --format '{{index .Config.Labels "biomate.remote-support-owner"}}' biomate-cloudflared 2>/dev/null) || fail "无法验证容器所有权"
    [[ "$owner" == "$(id -u):$REMOTE_DIR" ]] || fail "容器不属于本脚本会话；未停止容器"
    docker stop biomate-cloudflared >/dev/null 2>&1 && docker rm biomate-cloudflared >/dev/null 2>&1 || fail "容器停止失败；保留会话记录"
    rm -f "$CF_TOKEN_FILE"
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
  local auth_file=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --key-file) auth_file="$2"; shift 2 ;;
      --key|-k) fail "请改用 --key-file；不接受命令行明文凭据" ;;
      *) fail "未知 Tailscale 参数" ;;
    esac
  done

  [[ -n "$auth_file" ]] || fail "缺少 --key-file 参数"

  echo ""
  echo -e "${CYN}══ 配置 Tailscale 接入 ══${NC}"
  echo ""

  # Installation and daemon configuration belong to the customer's administrator.
  # Never silently install packages or start a shared host daemon here.
  if ! command -v tailscale &>/dev/null; then
    fail "请管理员按已批准流程安装并启动 Tailscale；脚本不会自动安装或修改系统服务"
  fi
  command -v python3 >/dev/null || fail "需要 Python 3 验证节点状态"
  local backend_state
  backend_state=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState", ""))') || fail "无法验证 Tailscale 状态"
  case "$backend_state" in
    NeedsLogin|Stopped) ;;
    Running) fail "已有主机 Tailscale 会话；本脚本不会接管或替换" ;;
    *) fail "节点状态不适合自动接入；请管理员核对" ;;
  esac
  local private_key
  private_key=$(private_secret_copy "$auth_file") || fail "无法读取受保护的授权文件"

  # 接入网络
  info "接入 Tailscale 网络..."
  if ! sudo tailscale up --auth-key="file:$private_key" --hostname="biomate-onprem-$(hostname | cut -c1-8)" > "$REMOTE_DIR/tailscale.log" 2>&1; then
    rm -f "$private_key"
    fail "Tailscale 接入失败；未记录成功，日志仅保存在私有状态目录"
  fi
  rm -f "$private_key"

  # 显示 IP
  sleep 2
  local ip
  ip=$(tailscale ip -4 2>/dev/null) || fail "无法获取节点地址；请管理员检查实际连接状态"
  local node_id
  node_id=$(tailscale_node_id) || fail "无法验证节点身份；请管理员检查实际连接状态"
  [[ -n "$node_id" && -n "$ip" ]] || fail "节点身份或地址为空；未记录成功"
  printf '%s\n' "$node_id" > "$TAILSCALE_ID_FILE"
  write_state "tailscale_pending"
  backend_state=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState", ""))') || fail "无法确认接入状态；已记录待确认会话以便停止"
  [[ "$backend_state" == Running ]] || fail "节点尚未接入；已记录待确认会话，不代表连接成功"
  write_state "tailscale"
  echo ""
  ok "Tailscale 接入成功！"
  echo ""
  echo -e "  ${GRN}工程师连接命令:${NC}"
  echo -e "  ${CYN}  ssh <获准账号>@${ip}${NC}"
  echo ""
  echo "  使用已授权的最小权限账号；外部 AI/数据传输必须另行获得客户批准。"
  echo ""
  echo "  支持完成后，在此服务器运行:"
  echo "    bash remote-access.sh stop"
  echo ""

}

# ─────────────────────────────────────────────────────────────────────────────
# FRP 反向隧道
# ─────────────────────────────────────────────────────────────────────────────
cmd_frp() {
  local server="frps.biomate.ai"
  local server_port=7000
  local remote_port=16022
  local token=""
  local token_file=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --server|-s)      server="$2"; shift 2 ;;
      --server-port)    server_port="$2"; shift 2 ;;
      --token-file)     token_file="$2"; shift 2 ;;
      --token|-t)       fail "请改用 --token-file；不接受命令行明文凭据" ;;
      --port|--remote-port|-p) remote_port="$2"; shift 2 ;;
      --version)        fail "frpc 版本由管理员预装和验证；不支持脚本自动安装版本" ;;
      *) fail "未知 frp 参数" ;;
    esac
  done

  [[ -n "$token_file" ]] || fail "缺少 --token-file 参数"
  [[ "$server" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail "服务端名称格式无效"
  [[ "$server_port" =~ ^[0-9]{1,5}$ && "$remote_port" =~ ^[0-9]{1,5}$ ]] || fail "端口格式无效"
  (( 10#$server_port >= 1 && 10#$server_port <= 65535 && 10#$remote_port >= 1 && 10#$remote_port <= 65535 )) || fail "端口超出范围"

  echo ""
  echo -e "${CYN}══ 配置 frp 反向隧道 ══${NC}"
  echo "  服务端: ${server}:${server_port}"
  echo "  远端端口: ${remote_port}"
  echo ""

  # The administrator supplies a verified executable. Do not execute an
  # unchecked release tarball or fall back to a third-party download proxy.
  if [[ ! -x "$FRP_BIN" ]]; then
    command -v frpc >/dev/null || fail "请管理员预装经过校验的 frpc；脚本不会下载未校验的可执行文件"
    install -m 700 "$(command -v frpc)" "$FRP_BIN"
  fi

  [[ ! -f "$FRP_PID_FILE" ]] || fail "已有 frpc 所有权记录；请先检查并停止原会话"
  local private_token
  private_token=$(private_secret_copy "$token_file") || fail "无法读取受保护的凭据文件"
  token=$(cat "$private_token")
  rm -f "$private_token"
  [[ "$token" != *\"* && "$token" != *\\* && "$token" != *$'\n'* && "$token" != *$'\r'* ]] || fail "凭据包含不支持的配置字符"

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

  # 启动 frpc（后台）
  info "启动 frpc..."
  nohup "$FRP_BIN" -c "$FRP_CFG" > "$FRP_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$FRP_PID_FILE"
  sleep 3

  # 检查是否启动成功
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$FRP_PID_FILE" "$FRP_CFG"
    fail "frpc 启动失败；请在私有状态目录检查日志"
  fi

  if grep -q "login to server success" "$FRP_LOG" 2>/dev/null; then
    ok "frpc 连接服务端成功！"
  else
    # A live process is not proof of an established tunnel.
    if pid=$(owned_frp_pid); then kill "$pid" 2>/dev/null || true; fi
    rm -f "$FRP_PID_FILE" "$FRP_CFG"
    fail "frpc 尚未确认连接；未记录成功。请在私有目录中检查日志"
  fi

  echo ""
  ok "frpc 已通过服务端登录；SSH 端到端访问仍须验证"
  echo ""
  echo -e "  ${GRN}工程师连接命令:${NC}"
  echo -e "  ${CYN}  ssh <获准账号>@${server} -p ${remote_port}${NC}"
  echo ""
  echo "  日志位于私有状态目录；未经审核不要传输原始日志"
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
  local token_file=""
  local image=""
  local quick=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --token-file) token_file="$2"; shift 2 ;;
      --image) image="$2"; shift 2 ;;
      --token|-t) fail "请改用 --token-file；不接受命令行明文凭据" ;;
      --quick|-q) quick=true; shift ;;
      *) fail "未知 Cloudflare 参数" ;;
    esac
  done

  echo ""
  echo -e "${CYN}══ 配置 Cloudflare 隧道 ══${NC}"
  echo ""

  if ! command -v docker &>/dev/null; then
    fail "需要 Docker。请先安装 Docker 再运行此脚本。"
  fi

  # Never remove a pre-existing container just because its name matches.
  if docker inspect biomate-cloudflared >/dev/null 2>&1; then
    fail "已有同名容器；请先核对其归属，脚本不会接管或删除"
  fi
  if $quick || [[ -z "$token_file" ]]; then
    fail "临时 SSH 模式尚未验证；请使用经客户批准并配置 Access 的正式隧道"
  fi
  [[ "$image" =~ ^cloudflare/cloudflared@sha256:[0-9a-f]{64}$ ]] || fail "需要已批准的 cloudflare/cloudflared 不可变镜像摘要"
  [[ ! -e "$CF_TOKEN_FILE" ]] || fail "已有凭据文件；请管理员核对上次会话后处理"
  local private_token
  private_token=$(private_secret_copy "$token_file") || fail "无法读取受保护的凭据文件"
  mv "$private_token" "$CF_TOKEN_FILE"

    # 正式 token 模式
    info "使用 Cloudflare Tunnel token 启动..."
    if ! docker run -d --pull never --name biomate-cloudflared \
      --label "biomate.remote-support-owner=$(id -u):$REMOTE_DIR" \
      --user "$(id -u):$(id -g)" \
      --cap-drop ALL --security-opt no-new-privileges --read-only \
      --mount "type=bind,src=$CF_TOKEN_FILE,dst=/run/biomate-support-token,readonly" \
      --network host \
      "$image" \
      tunnel --no-autoupdate \
      run --token-file /run/biomate-support-token \
      > "$REMOTE_DIR/cloudflare-start.log" 2>&1; then
      rm -f "$CF_TOKEN_FILE"
      fail "Cloudflare 启动失败；镜像必须预先校验并支持 token-file，详见私有日志"
    fi
    sleep 3
    if docker ps --format "{{.Names}}" | grep -qx "biomate-cloudflared"; then
      ok "Cloudflare 进程已启动；尚不代表 SSH 或 Access 验证通过"
      echo ""
      echo "  请管理员在 Zero Trust 控制台验证连接、Access 策略及 SSH 最小权限"
      echo ""
    else
      fail "Cloudflare 容器未运行；请管理员核对本次创建的容器及私有凭据文件"
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
  tailscale  --key-file <owner-only-file>        Tailscale 接入
  frp        --server <host> --token-file <file> frp 反向隧道（管理员预装 frpc）
  cloudflare --token-file <file> --image <digest> 正式隧道（预装已验证镜像）
  cloudflare --quick                            未验证的 SSH 模式，明确拒绝
  status                                        查看当前接入状态
  stop                                          仅停止已验证归属的会话

示例:
  bash remote-access.sh tailscale --key-file /secure/tailscale-auth
  bash remote-access.sh frp --server approved.example --token-file /secure/frp-token --port 16022
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

  init_state
  case "$cmd" in
    tailscale|frp|cloudflare|cf)
      [[ "$(read_state)" == none ]] || fail "已有本脚本会话；请先核对并停止，不会自动接管"
      ;;
  esac
  case $cmd in
    tailscale)  cmd_tailscale "$@" ;;
    frp)        cmd_frp "$@" ;;
    cloudflare|cf) cmd_cloudflare "$@" ;;
    status)     [[ $# == 0 ]] || fail "status 不接受额外参数"; cmd_status ;;
    stop)       [[ $# == 0 ]] || fail "stop 不接受额外参数"; cmd_stop ;;
    help|-h|--help) usage ;;
    *) echo "未知命令: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
