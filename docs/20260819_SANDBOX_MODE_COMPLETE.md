# BioMate 沙箱模式完整文档（2026-08-19）

分支 `feat/compute-platform-v2`，已验证于测试实例 `i-0482a6fa98c6f301a`，合并至 `integration/next-phase`。

---

## 1. 目标与动机

BioMate 允许用户上传任意 `.nf` 文件并在服务器本地执行，也允许通过聊天界面执行任意 Python/R 代码（run_code），还支持启动 Jupyter/RStudio 等交互式工具容器（Interactive Tools）。

这三个执行面若无隔离，都能通过 Docker socket 实现宿主机逃逸：

- 挂载 `/var/run/docker.sock` = 等价于 root 权限操控宿主机
- 恶意 `.nf` 可在 Groovy eval 阶段执行任意命令
- run_code 可调用任意 Python/R 库，网络无限制

**沙箱目标：** 在不改变对外功能的前提下，让三个执行面全部走经过验证的受控路径，关闭 raw socket 访问，隔离网络与文件系统，限制资源。

---

## 2. 分层防御架构

```
用户请求
  ↓
App 容器（frontend / backend）
  ├── frontend: 零 docker（无 socket，无 DOCKER_HOST）
  └── backend:  零 raw socket（DOCKER_HOST 指向 proxy，非 /var/run/docker.sock）
  ↓
sandbox-launcher（唯一持有 docker 访问的 app 层服务）
  ├── 对 run_code 请求：验证 baseDir 在 /tmp/biomate_code，镜像白名单，强制 runtime/uid/网络/caps
  ├── 对 .nf head 请求：验证 mount 路径前缀，拒绝 --privileged/host net/socket mount/root uid
  └── 对 IT 容器请求：验证 IT 镜像白名单，跳过 shell 变量 volume，提供 /inspect_it port 查询
  ↓
docker-socket-proxy（endpoint 白名单过滤）
  ├── 允许: CONTAINERS, IMAGES, NETWORKS, EXEC, POST, INFO, VERSION, PING
  └── 拒绝: BUILD, COMMIT, VOLUMES, SECRETS, SWARM, SYSTEM, DISTRIBUTION 等
  ↓
Docker daemon
  ↓
gVisor（runsc）— Tier 3，内核级沙箱
  ├── uname: 4.19.0-gvisor（虚拟内核，不暴露真实宿主内核）
  ├── 网络: none（run_code 和 .nf head；IT 容器在 deploy 网络）
  ├── cap-drop ALL + no-new-privileges
  ├── uid=1000（非 root）
  └── read-only rootfs + tmpfs workdir（run_code 和 .nf）
```

**注意：** IT 容器（Jupyter/RStudio）不使用 gVisor（这些镜像依赖真实内核 ABI），也不强制非 root（Jupyter/RStudio 镜像默认 root）。这是有意识的取舍，通过 launcher 的 argv 验证 + proxy 的 endpoint 过滤 + 镜像白名单来控制。

---

## 3. 三个执行面详情

### 3.1 run_code（Python/R 代码执行）

**入口：** 前端聊天 → `POST /api/code/run` → `frontend/server/code-runner.ts`

**路径：**
```
frontend → HTTP POST /run (sandbox-launcher:8899) → proxy → daemon → gVisor 容器
```

**关键配置（env var 在 frontend-deploy 容器）：**
```
RUN_CODE_BACKEND_URL=http://sandbox-launcher:8899   # 触发 launcher 路径
RUN_CODE_IMAGE=.../biomate-nextflow-sandbox:heavy   # 执行镜像
RUN_CODE_RUNTIME=runsc                               # gVisor
```

**launcher 强制的安全策略（不可被调用方覆盖）：**
- `baseDir` 必须 realpath 解析到 `/tmp/biomate_code` 下（拒绝路径穿越）
- 镜像必须在 `LAUNCHER_ALLOWED_IMAGES` 白名单
- 强制：`--runtime runsc`，`--user 1000:1000`，`--network none`，`--cap-drop ALL`，`--security-opt no-new-privileges`

**当 `RUN_CODE_BACKEND_URL` 未设置时：** 退回到 `code-runner.ts` 的 `runViaDocker()` 路径（原始行为）。

---

### 3.2 本地 .nf head（用户上传的 Nextflow 工作流）

**入口：** 聊天发送个人 `.nf` 文件 → `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` → `_maybe_sandboxed_launch`

**路径：**
```
backend → HTTP POST /run_head (sandbox-launcher:8899) → proxy → daemon → gVisor 容器
```

launcher 流式返回执行输出，以 `__LAUNCHER_EXIT__:<code>` 结尾。

**关键配置（env var 在 galaxy-backend-deploy 容器）：**
```
SANDBOX_ENABLED=true        # 开启沙箱包装（默认 off）
SANDBOX_TIER=3              # gVisor 级别
SANDBOX_RUN_UID=1000        # 容器内 uid（DooD 场景必须与宿主 bind-mount uid 一致）
SANDBOX_IMAGE=.../biomate-nextflow-sandbox:heavy
NF_HEAD_LAUNCHER_URL=http://sandbox-launcher:8899  # 发送到 launcher（默认 off）
```

**launcher 强制的安全策略：**
- mount 路径必须在 `LAUNCHER_HEAD_PREFIXES`（`/tmp/nextflow_runs,/tmp/biomate_user_nf`）下
- 拒绝：`--privileged`，`--net host`，`-v /var/run/docker.sock`，`--user 0` (root)，`-v /:/host`
- 强制：runsc runtime，cap-drop，no-new-priv，network none

**validator.py 静态预检（上传时）：** 拒绝含以下模式的 `.nf`：
- `privileged: true`，`--privileged`，主机路径挂载（`/etc/`, `/root/`, `/home/`）
- docker-in-docker（`/var/run/docker.sock`），curl|bash 管道，`Runtime.exec`
- 访问元数据服务（`169.254.169.254`）、`/etc/shadow`、AWS 凭证文件

**当 `NF_HEAD_LAUNCHER_URL` 未设置时：** 走原有 `SandboxedHeadLauncher`（直接 subprocess，`SANDBOX_ENABLED` 控制是否套 gVisor 命令）。

---

### 3.3 Interactive Tools（Jupyter/RStudio 等）

**入口：** 聊天 → `_handleInteractiveToolLaunch` → Galaxy API `POST /api/tools` → Galaxy LocalJobRunner → IT job shell script

**路径（Option A，当前激活）：**
```
Galaxy job script → docker run  (IT_LAUNCHER_URL → POST /run_it)  → proxy → daemon → IT 容器
container_monitor.py → docker port (IT_LAUNCHER_URL → GET /inspect_it/<name>) → 返回端口
```

**关键修复（Stage 3 根因）：**
原因：`galaxy.util.commands.new_clean_env()` 剥离了 `DOCKER_HOST`，导致 IT job subprocess 回退到不存在的 `/var/run/docker.sock` → exit 125。  
修复：在 `new_clean_env()` 白名单中加入 `DOCKER_HOST`（[commands.py](../backend/lib/galaxy/util/commands.py)）。

**关键修复（Option A shell 变量 volume）：**
Galaxy 传入含 shell 变量的 volume spec（如 `$_GALAXY_JOB_TMP_DIR:$_GALAXY_JOB_TMP_DIR:rw`），launcher 前缀验证拒绝 → job 失败。  
修复：`_containerize_via_it_launcher()` 过滤任何 str repr 含 `$` 的 volume。

**关键配置：**
```
IT_LAUNCHER_URL=http://sandbox-launcher:8899       # Option A 激活
DOCKER_HOST=tcp://docker-socket-proxy:2375         # backend 访问 daemon 的路径
INTERACTIVETOOLS_PROXY_HOST=interactivetool.<domain>  # IT URL 重写
```

**公开 URL 链路：**
```
JupyterLab 容器（172.x.x.x:8888）
  → gx-it-proxy（:8910，SQLite 路由表，2s loop 改写 host→127.0.0.1）
  → Caddy（on-demand TLS，*.ep.interactivetool.<domain>）
  → 用户浏览器（HTTPS）
```

**前端 URL 重写：** `rewriteInteractiveToolUrl()`（[routes.ts:100](../frontend/server/routes.ts)），由 `INTERACTIVETOOLS_PROXY_HOST` 驱动，作用于：
- `GET /api/interactive/sessions`（`target` 字段，客户端轮询的就绪 URL）
- `POST /api/interactive/launch`（返回的 IT URL）
- `POST /api/interactive-tools/launch`（遗留路径）

---

## 4. 完整环境变量参考

### frontend-deploy 容器

| 变量 | 含义 | 未设置时的行为 |
|---|---|---|
| `RUN_CODE_BACKEND_URL` | 指向 launcher 的 HTTP 地址 | 直接调 docker（原行为） |
| `RUN_CODE_IMAGE` | run_code 执行镜像 | `biomate-biotools:1` |
| `RUN_CODE_RUNTIME` | 容器 runtime（`runsc`=gVisor） | docker 默认 runtime |
| `INTERACTIVETOOLS_PROXY_HOST` | IT URL 重写目标域名 | 不重写，保持 Galaxy 内部 URL |

### galaxy-backend-deploy 容器

| 变量 | 含义 | 未设置时的行为 |
|---|---|---|
| `SANDBOX_ENABLED` | 开启 .nf 沙箱包装 | **off（默认关闭）** |
| `SANDBOX_TIER` | 隔离等级 1/2/3 | 1（仅 cap-drop，无 gVisor） |
| `SANDBOX_IMAGE` | .nf 执行镜像 | ECR latest |
| `SANDBOX_RUN_UID` | 容器内 uid | 由 run_id sha256 动态生成（20000-29999） |
| `SANDBOX_TIER` | Tier 3 → 自动设 gVisor runtime | — |
| `SANDBOX_GVISOR_RUNTIME` | gVisor 可执行名 | `runsc` |
| `SANDBOX_NETWORK_MODE` | 容器网络模式 | Tier1=bridge，Tier2+=none |
| `SANDBOX_SECCOMP_PROFILE` | 自定义 seccomp 路径 | runtime 默认 |
| `SANDBOX_VALIDATE_UPLOADS` | 上传时静态预检 | true |
| `SANDBOX_REJECT_ON_VIOLATION` | 预检失败阻断执行 | true |
| `NF_HEAD_LAUNCHER_URL` | .nf head 走 launcher | **off（默认关闭）** |
| `IT_LAUNCHER_URL` | IT 容器走 launcher（Option A） | 走 DOCKER_HOST proxy |
| `DOCKER_HOST` | 指向 docker-socket-proxy | 系统默认 socket |
| `COMPUTE_BACKEND_V2` | 调度器 v2 shadow mode（观测） | off |

### sandbox-launcher 容器

| 变量 | 含义 |
|---|---|
| `DOCKER_HOST` | launcher 访问 daemon 的路径（指向 docker-socket-proxy） |
| `LAUNCHER_WORKDIR_PREFIX` | run_code workdir 合法前缀（默认 `/tmp/biomate_code`） |
| `LAUNCHER_HEAD_PREFIXES` | .nf head mount 合法前缀（逗号分隔） |
| `LAUNCHER_ALLOWED_IMAGES` | run_code + .nf 允许的镜像（逗号分隔） |
| `LAUNCHER_IT_ALLOWED_IMAGES` | IT 容器允许的镜像（逗号分隔） |
| `LAUNCHER_RUNTIME` | 强制使用的 container runtime（`runsc`） |
| `LAUNCHER_UID` / `LAUNCHER_GID` | 强制的非 root uid/gid |

---

## 5. ECR 镜像清单

| 镜像 | Tag | 内容 |
|---|---|---|
| `biomate/dev-backend` | `sandbox-v5` | 基础镜像 + 4 补丁文件（nextflow_executor.py, head_client.py, compute/sandbox/launcher.py, util/commands.py） |
| `biomate/sandbox-launcher` | `3` | docker:27-cli + python3 + launcher.py（含 /run, /run_head, /run_it, /inspect_it, /stop_it, /health） |
| `biomate-nextflow-sandbox` | `heavy` | Bioconductor 3.20 + R + python + java + Nextflow，可执行所有 bioc/R 工作流 |

---

## 6. 部署方式

### 开启沙箱（在现有部署基础上叠加）

```bash
docker compose \
  -f deploy/docker-compose.deploy.yml \
  -f deploy/docker-compose.sandbox.yml \
  up -d
```

这会启动 `docker-socket-proxy` 和 `sandbox-launcher` 两个新服务，并为 frontend/backend 注入沙箱 env vars。

**前置要求：**
1. 宿主机安装 gVisor：
   ```bash
   # 下载 runsc（参考 https://gvisor.dev/docs/user_guide/install/）
   curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc -o /usr/local/sbin/runsc
   chmod a+x /usr/local/sbin/runsc
   runsc install
   systemctl reload docker  # reload 不 restart，避免容器被清除
   ```
2. 共享 workdir 目录存在：
   ```bash
   mkdir -p /tmp/biomate_code /tmp/nextflow_runs /tmp/biomate_user_nf
   ```
3. IT 功能还需宿主机额外配置（见下方 Interactive Tools 部署）。

### 不开启沙箱（默认行为）

```bash
docker compose -f deploy/docker-compose.deploy.yml up -d
```
合并后主分支行为不变，所有沙箱代码均不执行。

---

## 7. Interactive Tools 宿主机依赖配置

IT 功能需要宿主机上额外准备（不在 overlay 文件内，需手动操作）：

```bash
# 1. 宿主机路径与容器内路径保持一致（identity mount）
mkdir -p /app/database/jobs_directory /app/database/files /app/tools/interactive
chown -R 1000:1000 /app/database/jobs_directory /app/database/files
# /app/tools/interactive 内容从容器复制：
docker exec biomate-galaxy-deploy tar -c /app/tools/interactive | tar -x -C /

# 2. gx-it-proxy 容器（持久，--network host）
docker run -d --name biomate-gxit \
  --network host \
  --restart unless-stopped \
  -v /opt/biomate/it_state:/data \
  biomate-gxit-proxy:1 \
  gx-it-proxy --sessions /data/interactivetools_map.sqlite --port 8910

# 3. 通配符 DNS（在 Route53 或 DNS 供应商）
# *.ep.interactivetool.<domain> → 服务器 IP

# 4. Caddy on-demand TLS 配置（/opt/biomate/Caddyfile，追加）
# *.ep.interactivetool.<domain> {
#     encode gzip
#     tls { on_demand }
#     reverse_proxy 127.0.0.1:8910
# }

# 5. 重载 Caddy
docker exec biomate-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

---

## 8. launcher.py 端点接口

```
POST /run          run_code 执行，返回 {stdout, stderr, exit_code}
POST /run_head     .nf head 执行，流式输出，以 __LAUNCHER_EXIT__:<code> 结尾
POST /run_it       IT 容器启动（docker run -d），返回 {container_name}
GET  /inspect_it/<name>   docker port <name> 输出（给 container_monitor.py 用）
POST /stop_it      停止并删除 IT 容器
GET  /health       {"ok": true}
```

所有写操作都有完整 argv 验证（镜像白名单、mount 前缀检查、危险标志拒绝）。

---

## 9. 安全边界与已知取舍

| 项目 | 状态 | 说明 |
|---|---|---|
| run_code 网络隔离 | ✅ `--network none` | 代码无法访问外网/内网 |
| .nf head 网络隔离 | ✅ `--network none` | Groovy eval 阶段无网络 |
| IT 容器网络 | ⚠️ `biomate-deploy-net` | 需要访问 Galaxy API，不能 none |
| run_code 非 root | ✅ uid=1000 | |
| .nf head 非 root | ✅ uid=1000 | |
| IT 容器非 root | ⚠️ 默认关闭 | Jupyter/RStudio 镜像默认 root；`IT_ENFORCE_NON_ROOT` 可开启 |
| gVisor（run_code） | ✅ runsc，验证通过 | `uname: 4.19.0-gvisor` |
| gVisor（.nf head） | ✅ runsc，验证通过 | 同上 |
| gVisor（IT 容器） | ❌ 未启用 | IT 镜像依赖真实内核 ABI |
| 静态 .nf 预检 | ✅ validator.py | 上传时运行，15 类危险模式 |
| AWS/LLM 凭证泄漏 | ✅ filter_container_env() | `SECRET_ENV_MARKERS` + `IMAGE_OWNED_ENV` 过滤 |
| docker socket 直接访问 | ✅ 全部移除 | frontend/backend 均无 raw socket |
| create+bind body 注入 | ✅ launcher 验证 | endpoint-level proxy 无法过滤 body |
| 自定义 seccomp | 待完成 | `SANDBOX_SECCOMP_PROFILE` 接口已有，profile 文件未制作 |

---

## 10. 待完成项

1. **GHA CI 集成**：将 `docker-compose.sandbox.yml` 加入 GHA deploy matrix，部署 test/prod 时自动激活。目前受 GHA 计费限制阻塞，需人工触发。
2. **自定义 seccomp profile**：`SANDBOX_SECCOMP_PROFILE` 接口已就绪，profile 文件未制作（可选加固项）。
3. **M0.2 调度器 v2**：将 COMPUTE_BACKEND_V2 从 shadow-mode 切换为 active routing，通过 `Scheduler.select_backend` 统一调度。需要 4 域（ADMET/RNA-seq/WGS/CryoEM）E2E 验证。

---

## 11. 各阶段提交记录

| Stage | 核心提交 | 内容 |
|---|---|---|
| Phase 0 | eb7c19a2b | ComputeBackend/Scheduler 抽象骨架，shadow mode |
| ① sandbox 核心 | ba569d327 | SandboxConfig + SandboxedHeadLauncher，gVisor Tier 1-3 |
| ① 镜像验证 | 0fd32030e, d8cb35a41 | sandbox 镜像构建+测试，gVisor runsc 安装验证 |
| ① run_code 加固 | fd3e60925 | code-runner.ts cap-drop+readonly+gVisor |
| ① 全链路 LIVE | 12b0abdb8 | test 实例沙箱完整部署验证 |
| ① socket-proxy | 426a5b8d8 | docker-socket-proxy 引入，frontend 脱离 raw socket |
| ① narrow launcher | e6bc7bb27 | sandbox-launcher，frontend 零 docker |
| ① .nf → launcher | c6792a3db | /run_head，NF_HEAD_LAUNCHER_URL flag-gated |
| Stage 2 验证 | 78a7ff8d8 | .nf head 经 launcher 运行，test 验证通过 |
| Stage 3 | 4fa2c2f96 | new_clean_env() DOCKER_HOST 修复，backend 零 raw socket，IT 走 proxy |
| Stage 4 IT smoke | 09f2a6273 | IT exit_code=125→running，entry_point active，target URL populated |
| Option A IT | 1480c594f | /run_it + /inspect_it，IT 走 narrow launcher body 验证 |
| shell-var fix | 97edc26aa | 过滤含 $ 的 volume spec |
| ECR 烘焙 | 5aa7f288b | sandbox-v5 + sandbox-launcher:3，零 bind-mount 补丁 |
| IT URL 修复 | 242595f01 | mine?.target \|\| mine?.entry_point_url（Galaxy 返回 target 非 entry_point_url） |
