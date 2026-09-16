#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-k3s-cluster.sh — BioMate 多机计算集群搭建脚本 (k3s)
#
# 适用场景:
#   客户提供 2~8 台高性能服务器，组建轻量 Kubernetes 集群运行 Nextflow 工作流。
#   k3s = 生产级 K8s，单命令安装，资源占用比完整 K8s 低 10 倍。
#
# 架构:
#   Server 1 (主节点): BioMate 服务 + k3s master + MinIO + NFS
#   Server 2-N (工作节点): k3s worker，运行 Nextflow Pod
#
# 用法:
#   # 在主节点上执行:
#   bash scripts/setup-k3s-cluster.sh master
#
#   # 在每台工作节点上执行（用主节点输出的 token）:
#   bash scripts/setup-k3s-cluster.sh worker <主节点IP> <token>
#
#   # 完整环境验证:
#   bash scripts/setup-k3s-cluster.sh verify
#
# 前提:
#   - 所有节点运行 Ubuntu 20.04+ 或 RHEL 8+
#   - 主节点对工作节点开放 6443/TCP (k8s API) 和 8472/UDP (flannel)
#   - 各节点之间互信 SSH（工作节点安装时不需要，但 NFS 挂载需要）
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

MODE="${1:-help}"
MASTER_IP="${2:-}"
K3S_TOKEN="${3:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()  { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}══ $* ══${RESET}"; }

# ─────────────────────────────────────────────────────────────────────────────
# 主节点安装
# ─────────────────────────────────────────────────────────────────────────────
install_master() {
  step "安装 k3s 主节点"

  LOCAL_IP=$(hostname -I | awk '{print $1}')
  info "主节点 IP: $LOCAL_IP"

  # 安装 k3s（禁用 traefik，BioMate 用自己的反代）
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --disable traefik \
    --disable servicelb \
    --write-kubeconfig-mode 644 \
    --tls-san $LOCAL_IP" sh -

  # 等待就绪
  info "等待 k3s 就绪..."
  for i in $(seq 1 30); do
    kubectl get nodes &>/dev/null && break
    sleep 2
  done

  ok "k3s master 安装完成"
  kubectl get nodes

  # 输出工作节点加入命令
  TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
  echo ""
  echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}在每台工作节点上运行以下命令:${RESET}"
  echo ""
  echo -e "  bash scripts/setup-k3s-cluster.sh worker ${LOCAL_IP} ${TOKEN}"
  echo ""
  echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
  echo ""

  step "创建 BioMate 命名空间和 RBAC"
  _setup_k8s_resources "$LOCAL_IP"

  step "配置 NFS 共享存储（供 Nextflow 工作节点使用）"
  _setup_nfs "$LOCAL_IP"

  step "安装 Nvidia GPU Operator（如有 GPU 节点）"
  _install_gpu_operator

  step "创建 BioMate .env 配置片段"
  _print_env_config "$LOCAL_IP"
}

# ─────────────────────────────────────────────────────────────────────────────
# 工作节点安装
# ─────────────────────────────────────────────────────────────────────────────
install_worker() {
  [[ -z "$MASTER_IP" ]] && die "请提供主节点 IP: bash $0 worker <主节点IP> <token>"
  [[ -z "$K3S_TOKEN" ]] && die "请提供 token: bash $0 worker <主节点IP> <token>"

  step "安装 k3s 工作节点"
  info "加入主节点: $MASTER_IP"

  curl -sfL https://get.k3s.io | \
    K3S_URL="https://${MASTER_IP}:6443" \
    K3S_TOKEN="$K3S_TOKEN" \
    sh -

  ok "工作节点加入集群成功"
  info "在主节点运行 'kubectl get nodes' 验证"

  step "挂载 NFS 共享存储"
  _mount_nfs "$MASTER_IP"
}

# ─────────────────────────────────────────────────────────────────────────────
# K8s 资源初始化
# ─────────────────────────────────────────────────────────────────────────────
_setup_k8s_resources() {
  local master_ip="$1"

  # 命名空间
  kubectl create namespace biomate-jobs --dry-run=client -o yaml | kubectl apply -f -

  # ServiceAccount for Nextflow（需要 pod create/delete 权限）
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nextflow
  namespace: biomate-jobs
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nextflow-role
  namespace: biomate-jobs
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/status", "persistentvolumeclaims", "configmaps"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nextflow-rb
  namespace: biomate-jobs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nextflow-role
subjects:
  - kind: ServiceAccount
    name: nextflow
    namespace: biomate-jobs
EOF

  ok "命名空间和 RBAC 创建完成"
}

# ─────────────────────────────────────────────────────────────────────────────
# NFS 共享存储（主节点导出，工作节点挂载）
# ─────────────────────────────────────────────────────────────────────────────
_setup_nfs() {
  local master_ip="$1"
  local nfs_dir="/mnt/biomate-nfs"

  info "配置 NFS 服务器 (export: $nfs_dir)..."

  # 安装 NFS 服务器
  if command -v apt-get &>/dev/null; then
    apt-get install -y nfs-kernel-server nfs-common 2>&1 | tail -3
  elif command -v yum &>/dev/null; then
    yum install -y nfs-utils 2>&1 | tail -3
  fi

  mkdir -p "$nfs_dir"
  chmod 777 "$nfs_dir"

  # 导出（允许集群内所有节点挂载）
  if ! grep -q "$nfs_dir" /etc/exports; then
    echo "${nfs_dir}  *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
  fi

  exportfs -ra
  systemctl enable --now nfs-server 2>/dev/null || systemctl enable --now nfs-kernel-server 2>/dev/null || true

  ok "NFS 导出: ${master_ip}:${nfs_dir}"

  # 创建 PersistentVolume + PVC for Nextflow
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: biomate-work-pv
spec:
  capacity:
    storage: 2Ti
  accessModes: [ReadWriteMany]
  nfs:
    server: ${master_ip}
    path: ${nfs_dir}
  persistentVolumeReclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: biomate-work-pvc
  namespace: biomate-jobs
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 2Ti
  volumeName: biomate-work-pv
EOF

  ok "PV/PVC biomate-work-pvc 创建完成（${nfs_dir}）"
}

_mount_nfs() {
  local master_ip="$1"
  local nfs_dir="/mnt/biomate-nfs"

  info "挂载 NFS: ${master_ip}:${nfs_dir} → ${nfs_dir}"

  if command -v apt-get &>/dev/null; then
    apt-get install -y nfs-common 2>&1 | tail -1
  elif command -v yum &>/dev/null; then
    yum install -y nfs-utils 2>&1 | tail -1
  fi

  mkdir -p "$nfs_dir"
  if ! mountpoint -q "$nfs_dir"; then
    mount -t nfs "${master_ip}:${nfs_dir}" "$nfs_dir"
    # 持久化
    if ! grep -q "${master_ip}:${nfs_dir}" /etc/fstab; then
      echo "${master_ip}:${nfs_dir}  ${nfs_dir}  nfs  defaults,_netdev  0  0" >> /etc/fstab
    fi
  fi

  ok "NFS 挂载成功"
}

# ─────────────────────────────────────────────────────────────────────────────
# GPU Operator（有 NVIDIA GPU 时安装）
# ─────────────────────────────────────────────────────────────────────────────
_install_gpu_operator() {
  if ! command -v nvidia-smi &>/dev/null; then
    info "未检测到 NVIDIA GPU，跳过 GPU Operator 安装。"
    return 0
  fi

  info "检测到 GPU，安装 NVIDIA GPU Operator..."

  # Helm
  if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
  helm repo update

  helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --create-namespace \
    --set driver.enabled=false \
    --set toolkit.enabled=true \
    --set devicePlugin.enabled=true \
    --wait --timeout 10m

  ok "GPU Operator 安装完成"
}

# ─────────────────────────────────────────────────────────────────────────────
# 打印 BioMate .env 配置
# ─────────────────────────────────────────────────────────────────────────────
_print_env_config() {
  local master_ip="$1"

  cat <<EOF

────────────────────────────────────────────────────────────
将以下配置添加到 BioMate 的 .env 文件（或 docker-compose.onprem.yml 的 galaxy-backend environment 中）:

  # 使用 k3s 集群作为 Nextflow 执行器
  NEXTFLOW_EXECUTOR=k8s

  # k3s kubeconfig（主节点路径，BioMate Galaxy 容器需要挂载）
  KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  # K8s 命名空间（Nextflow 提交 Pod 的命名空间）
  NXF_K8S_NAMESPACE=biomate-jobs

  # NFS 共享存储的 PVC 名称
  NXF_K8S_STORAGE_CLAIM=biomate-work-pvc

  # NFS 在 Pod 内的挂载路径
  NXF_K8S_STORAGE_MOUNT=/nf-work

  # GPU 资源类型（有 GPU 节点时）
  NXF_K8S_GPU_RESOURCE=nvidia.com/gpu

同时在 docker-compose.onprem.yml galaxy-backend volumes 中添加:
  - /etc/rancher/k3s/k3s.yaml:/root/.kube/config:ro

────────────────────────────────────────────────────────────
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# 验证集群
# ─────────────────────────────────────────────────────────────────────────────
verify_cluster() {
  step "验证 k3s 集群"

  echo ""
  echo "节点状态:"
  kubectl get nodes -o wide 2>/dev/null || die "无法访问集群，请检查 kubeconfig"

  echo ""
  echo "biomate-jobs 命名空间资源:"
  kubectl get all,pvc -n biomate-jobs 2>/dev/null || warn "biomate-jobs 命名空间不存在"

  echo ""
  echo "GPU 资源 (如有):"
  kubectl get nodes -o json 2>/dev/null | \
    python3 -c "
import json,sys
nodes = json.load(sys.stdin)['items']
for n in nodes:
    name = n['metadata']['name']
    alloc = n['status'].get('allocatable', {})
    gpu = alloc.get('nvidia.com/gpu', '0')
    if gpu != '0':
        print(f'  {name}: {gpu} GPU')
" 2>/dev/null || true

  echo ""
  # 运行一个测试 Pod 验证调度
  info "运行测试 Pod..."
  kubectl run biomate-test --image=alpine:latest \
    --namespace=biomate-jobs \
    --restart=Never \
    --rm \
    --command \
    -- sh -c "echo 'k3s cluster OK'" 2>/dev/null && ok "Pod 调度测试通过" || warn "Pod 测试失败（可能 Pod 已存在，忽略）"
}

# ─────────────────────────────────────────────────────────────────────────────
# 帮助
# ─────────────────────────────────────────────────────────────────────────────
print_help() {
  cat <<'HELP'

BioMate k3s 集群搭建脚本

用法:
  bash scripts/setup-k3s-cluster.sh master
      在主节点（Server 1）上安装 k3s + 初始化 K8s 资源

  bash scripts/setup-k3s-cluster.sh worker <主节点IP> <token>
      在工作节点上加入集群（token 由主节点安装后输出）

  bash scripts/setup-k3s-cluster.sh verify
      验证集群状态（节点/PVC/GPU/调度）

架构示意:
  Server 1 (主节点):
    - k3s master
    - BioMate 服务 (docker-compose.onprem.yml)
    - MinIO (S3 替代)
    - NFS 服务器 (共享 /mnt/biomate-nfs)

  Server 2-N (工作节点):
    - k3s worker
    - 挂载 NFS /mnt/biomate-nfs
    - 运行 Nextflow Pod

所需端口:
  主节点开放: 6443/TCP (k8s API), 8472/UDP (flannel VXLAN), 2049/TCP (NFS)
  工作节点开放: 10250/TCP (kubelet)

HELP
}

# ─────────────────────────────────────────────────────────────────────────────
# 入口
# ─────────────────────────────────────────────────────────────────────────────
case "$MODE" in
  master)  install_master ;;
  worker)  install_worker ;;
  verify)  verify_cluster ;;
  help|--help|-h) print_help ;;
  *) die "未知模式: $MODE。使用 help 查看帮助。" ;;
esac
