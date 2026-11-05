# BioMate 本地部署指南

> 适用版本：`docker-compose.onprem.yml`  
> 目标读者：现场实施工程师  
> 前置要求：Docker ≥ 24、Docker Compose v2、≥ 16 GB RAM（Ollama 离线模式需要 ≥ 32 GB）

---

## 目录

0. [硬件与架构兼容性](#0-硬件与架构兼容性)
1. [快速启动](#1-快速启动)
2. [LLM 提供商配置](#2-llm-提供商配置)
3. [系统管理面板](#3-系统管理面板)
4. [存储配置](#4-存储配置)
5. [计算资源配置](#5-计算资源配置)
6. [工作流数据库更新](#6-工作流数据库更新)
7. [Ollama 离线模式](#7-ollama-离线模式)
8. [反向代理（HTTPS）](#8-反向代理https)
9. [备份与恢复](#9-备份与恢复)
10. [日常维护命令](#10-日常维护命令)
11. [国内环境特殊配置](#11-国内环境特殊配置)
12. [故障排查](#12-故障排查)

---

## 0. 硬件与架构兼容性

### 0.1 架构支持矩阵

| CPU 架构 | 典型机型 | Docker 镜像 | `uname -m` | 状态 |
|---------|---------|------------|------------|------|
| **海光 C86**（优先） | 海光 7285、7265 | `linux/amd64`（原生） | `x86_64` | ✅ 完整支持 |
| **标准 x86-64** | Intel/AMD | `linux/amd64`（原生） | `x86_64` | ✅ 完整支持 |
| **飞腾 FT-2000+/S2500** | 飞腾服务器 | `linux/arm64`（原生） | `aarch64` | ✅ 完整支持 |
| **华为鲲鹏 920** | TaiShan 200 | `linux/arm64`（原生） | `aarch64` | ✅ 完整支持 |
| **龙芯 LoongArch** | 龙芯 3A5000 | 无镜像 | `loongarch64` | ❌ 暂不支持 |

**部署建议：优先选择海光 C86。** 它完全兼容 `linux/amd64` 镜像，无需 QEMU 转译，性能与标准 x86 相同；ARM64（鲲鹏/飞腾）同样完整支持，但需按第 0.3 节额外配置。

---

### 0.2 海光 C86 部署注意事项

海光 C86 基于 AMD Zen 1 授权，`uname -m` 返回 `x86_64`，**直接走标准 x86 部署流程，无需任何额外配置**。

**验证是否为海光 C86：**

```bash
grep -m1 "model name" /proc/cpuinfo
# 海光输出示例: model name : Hygon C86 7285 32-core Processor
```

**潜在兼容性问题（Hygon Zen 1 特有）：**

Zen 1 支持 SSE4.2 / AVX / AVX2，但**不支持 AVX-512**。若工作流容器内的某个二进制文件是在 Intel 机器上以 `-march=native`（有 AVX-512）编译的，在 C86 上会崩溃并报 `Illegal instruction`。

**检测方法：**

```bash
# 看容器崩溃日志里是否有 "Illegal instruction" 或 signal 4 (SIGILL)
docker logs biomate-galaxy 2>&1 | grep -i "illegal\|SIGILL\|signal 4"

# 检查是否有 AVX-512 指令
grep -c "avx512" /proc/cpuinfo   # 返回 0 = 无 AVX-512，C86 正常
```

**缓解方案（若出现 SIGILL）：**

在 `.env` 中加入以下变量，限制数值计算库只使用 AVX2：

```bash
# 限制 OpenBLAS 不使用 AVX-512（numpy/scipy 相关）
OPENBLAS_CORETYPE=SANDYBRIDGE

# 限制 Intel MKL 不使用 AVX-512（部分 ML 库用 MKL）
MKL_ENABLE_INSTRUCTIONS=AVX2
MKL_CBWR=AVX2

# 禁用 Intel MKL 自动 CPU 检测（有时 MKL 会误判）
MKL_DEBUG_CPU_TYPE=5
```

然后在 `docker-compose.onprem.yml` 的 `galaxy-backend` 服务 `environment:` 块中追加这些变量（或在 `install.sh` 运行后通过 `docker restart biomate-galaxy` 应用）。

**实际情况：** BioMate 官方镜像（`ghcr.io/biomate-ai/biomate-backend`、`biomate/biomni-tools`）在构建时使用通用 `linux/amd64` 目标，不开 `-march=native`，**正常情况下不会触发 SIGILL**。上述配置仅在遇到问题时才需要。

---

### 0.3 ARM64（鲲鹏/飞腾）部署注意事项

ARM64 主机（`uname -m` = `aarch64`）需要以下额外步骤：

**0.3.1 `install.sh` 自动处理（无需手动操作）：**

`install.sh` 检测到 ARM64 后会自动：
1. 移除 `docker-compose.onprem.yml` 中所有 `platform: linux/amd64` 限制
2. 设置 `DOCKER_DEFAULT_PLATFORM=linux/arm64`（写入 `.env`）
3. 安装 `amd64` QEMU binfmt（作为备用，处理少数仅有 x86 版本的工具镜像）

**0.3.2 工作流任务容器（Nextflow）：**

在 `.env` 中必须设置：

```bash
DOCKER_DEFAULT_PLATFORM=linux/arm64
```

BioMate 工作流的核心任务容器（`biomni-tools`、`biomni-admet`）均已发布 ARM64 原生版本，Nextflow 执行器会自动拉取对应架构的镜像。

**0.3.3 Bioconductor R 容器（RNA-seq / scRNA-seq）：**

Bioconductor 镜像（ECR `bioc-domain-transcriptomics:3.20-slim` 等）**目前仅有 x86_64 版本**。在 ARM64 主机上将通过 QEMU 以模拟模式运行——功能正常，但速度会慢 2～4 倍。如果对性能有要求，可以联系 BioMate 团队获取 ARM64 版本。

**0.3.4 gunicorn 冷启动时间：**

ARM64 主机在 QEMU 模拟模式下（如旧版未迁移镜像），Galaxy 后端冷启动可能需要 20～30 分钟。`docker-compose.onprem.yml` 已将 `start_period` 设为 `1800s`，健康检查不会误报。**只要 `docker logs biomate-galaxy` 中出现 `Booting worker`，即表示正在正常启动，无需干预。**

**0.3.5 ARM64 快速诊断：**

```bash
# 确认 Galaxy 容器以 ARM64 原生运行（应返回 aarch64）
docker exec biomate-galaxy uname -m

# 确认 MinIO 是 ARM64 原生（日志里应有 linux/arm64）
docker logs biomate-minio 2>&1 | grep -i "version\|arch"

# 确认 ADMET 任务容器用的是 ARM64 镜像
docker exec biomate-galaxy printenv BIOMATE_ADMET_CONTAINER
```

---

### 0.4 最低硬件要求

| 配置 | 最低 | 推荐（生产） |
|------|------|------------|
| CPU | 8 核 x86-64 / ARM64 | 32 核 |
| 内存 | 16 GB | 64 GB |
| 磁盘 | 200 GB SSD | 500 GB NVMe |
| GPU | 无需（CPU 推理） | NVIDIA A100（批量 AI 分析） |
| 网络 | 内网 1Gbps | 内网 10Gbps |

> **注：** Ollama 本地大模型需要 ≥ 32 GB 内存（32B 参数模型），推荐 ≥ 24 GB 显存的 GPU。

---

## 1. 快速启动

```bash
# 1. 克隆代码
git clone <your-repo-url> biomate && cd biomate

# 2. 生成 .env 文件
cp .env.onprem.example .env
# 编辑 .env，至少填写以下必填项（见下方说明）
nano .env

# 3. 启动
docker compose -f docker-compose.onprem.yml up -d

# 4. 查看启动日志
docker compose -f docker-compose.onprem.yml logs -f

# 5. 访问
# 浏览器打开 http://<服务器IP>:5000
```

### .env 必填项

```bash
# 数据库密码（自行设置，复杂度要够）
POSTGRES_PASSWORD=your_strong_password

# JWT / Session 密钥（随机生成，不要用简单字符串）
JWT_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)

# LLM 提供商 API Key（根据下面第2节选择一个）
ANTHROPIC_API_KEY=sk-ant-...
# 或
DEEPSEEK_API_KEY=sk-...
```

---

## 2. LLM 提供商配置

BioMate 支持多种 LLM 提供商，无需翻墙的推荐使用 DeepSeek / 智谱 GLM / Ollama。

| 提供商 | 环境变量 | 国内直连 | 说明 |
|--------|----------|----------|------|
| Anthropic Claude | `ANTHROPIC_API_KEY` | 需要 VPN | 默认，效果最好 |
| DeepSeek | `DEEPSEEK_API_KEY` | ✅ | 国内直连，性价比高 |
| 智谱 GLM | `ZHIPU_API_KEY` | ✅ | 国内直连 |
| OpenRouter | `OPENROUTER_API_KEY` | 部分需要 VPN | 支持多种模型中转 |
| Ollama | 无需 Key | ✅ 完全离线 | 需要本地 GPU/大内存 |

### 切换提供商

**方法一：通过管理面板（推荐）**

1. 用 admin 账号登录 → 侧边栏点击「系统管理」
2. 在「系统 LLM 配置」中选择提供商
3. 点击「保存配置」，复制输出的环境变量
4. 更新 `.env` 文件，然后重启后端：

```bash
docker restart biomate-galaxy
```

**方法二：直接编辑 .env**

```bash
# 切换到 DeepSeek
GALAXY_AI_LLM_PROVIDER=deepseek
GALAXY_AI_LLM_MODEL=deepseek-chat
DEEPSEEK_API_KEY=sk-your-deepseek-key

# 应用配置
docker restart biomate-galaxy
```

支持的 `GALAXY_AI_LLM_PROVIDER` 值：`anthropic` / `deepseek` / `zhipu` / `openrouter` / `ollama`

---

## 3. 系统管理面板

管理面板位于 `http://<服务器>:5000/admin`，需要 admin 账号登录。

**创建 admin 账号：**

```bash
# 方法：在 PostgreSQL 中将现有用户升级为 admin
docker exec -it biomate-postgres psql -U biomate -d biomate -c \
  "UPDATE users SET subscription_tier = 'admin' WHERE email = 'your@email.com';"
```

**管理面板功能：**

- **服务健康状态**：实时查看各服务是否正常，自动标红异常服务
- **LLM 配置**：选择提供商、填写模型名，保存后自动生成需要配置的环境变量

---

## 4. 存储配置

### 对象存储：MinIO（默认，本机自带）

本地部署自带 **MinIO**（S3 兼容对象存储，`docker-compose.onprem.yml` 中的 `minio` 服务），用于存放
**工作流的输入（上传的数据集）和输出**。后端通过 `S3_ENDPOINT_URL=http://minio:9000` 接入——所有 S3 调用
被透明地路由到本机 MinIO，无需 AWS、不出网。

- **上传的数据集** → MinIO bucket `biomate-data`
- **工作流输出** → MinIO：`s3://biomate-data/nextflow/outputs/<user_id>/<run_id>/`
  （项目运行为 `s3://biomate-data/projects/<project_id>/runs/<run_id>/output`）
- **Nextflow 工作目录（中间文件）** → `NEXTFLOW_WORK_DIR`（默认 `/app/nf-work`，宿主机绑定挂载）
- **持久化**：MinIO 数据保存在 `biomate-minio-data` Docker volume（宿主机磁盘），容器重启后保留

管理界面：`http://<服务器IP>:9001`（用 `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` 登录）。

```bash
# 查看卷/存储占用
docker system df -v
```

### 可配置项

| 变量 | 作用 | 默认 |
|---|---|---|
| `S3_ENDPOINT_URL` | 对象存储端点——指向自带 MinIO，或**客户自有的 S3 兼容存储 / NAS-S3 网关** | `http://minio:9000` |
| `S3_BUCKET_NAME` | bucket 名称 | `biomate-data` |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | 对象存储访问凭证（即 S3 access key / secret） | `biomate` /（必填） |
| `NEXTFLOW_WORK_DIR` | Nextflow 工作目录（宿主机路径） | `/app/nf-work` |

要把输入/输出改存到客户**已有的对象存储**，只需把 `S3_ENDPOINT_URL`、`S3_BUCKET_NAME` 和凭证指向该存储即可，
无需改动代码。

### 可选：真实 AWS S3

如果客户有 AWS 账号且希望用真实 S3（而非本机 MinIO），**留空 `S3_ENDPOINT_URL`** 并填写 AWS 凭证：

```bash
# S3_ENDPOINT_URL=            # 留空 → 使用真实 AWS S3（而非本机 MinIO）
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=cn-northwest-1     # 国内用宁夏区域
S3_BUCKET_NAME=biomate-data
```

---

## 5. 计算资源配置

工作流在何处运行由 `.env` 的 `NEXTFLOW_EXECUTOR` 决定（默认 `local`）。

| 取值 | 说明 | GPU 支持 |
|---|---|---|
| `local`（默认） | 本机 Docker 单节点执行 | ⚠️ 见 §5.1 |
| `slurm` | 提交到已有 Slurm HPC 集群 | ✅ |
| `k8s` | 提交到 Kubernetes 集群 | ✅ |
| `awsbatch` | AWS Batch（SaaS 用） | ✅ |

**CPU 资源档位**（自动注入，所有执行器一致）：

| 标签 | CPU | 内存 | 适用场景 |
|---|---|---|---|
| `process_low` | 4 核 | 12 GB | 轻量分析、格式转换 |
| `process_medium` | 16 核 | 72 GB | 标准 RNA-seq、ADMET |
| `process_high` | 32 核 | 200 GB | WGS、全基因组分析 |
| `process_gpu` | 8 核 | 32 GB | 深度学习、CryoEM（见 §5.1）|

---

### 5.1 GPU 支持说明

**当前阶段：CPU-only，GPU 预留接入方案。**

BioMate 工作流通过 `label 'process_gpu'` 标记需要 GPU 的进程（Cryo-EM、结构预测、分子动力学、ML 训练等，共 30+ 个工作流）。在 **local 执行器模式**（本地/阿里云部署默认）下，这些工作流会**以 CPU 模式降级运行**——功能可用，速度较慢。

#### 现阶段（CPU）——无需配置

`.env` 保持默认即可：

```bash
NEXTFLOW_EXECUTOR=local
NEXTFLOW_USE_AWS=false
```

带 `process_gpu` 标签的工作流会忽略 GPU 请求，直接用 CPU 容器运行。对于 ADMET、BOIN、RNA-seq、WGS 等主要工作流没有影响。

#### 后续阶段（GPU 接入）——三种方案按需选择

**方案 A：单节点本地 GPU（单台服务器带 NVIDIA 卡）**

前提：宿主机已安装 NVIDIA 驱动 + `nvidia-container-toolkit`。

1. 在 `docker-compose.onprem.yml` 的 `galaxy-backend` 服务块中追加：

   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: all
             capabilities: [gpu]
   ```

2. 在 `.env` 中追加：

   ```bash
   NEXTFLOW_DOCKER_GPU_OPTIONS=--gpus all
   ```

   executor 会将此值注入 Nextflow 的 `docker { runOptions }` 块，使 `process_gpu` 任务容器能访问 GPU 设备。

3. 重启服务：`docker compose -f docker-compose.onprem.yml up -d --force-recreate galaxy-backend`

**方案 B：Slurm GPU 集群**

```bash
NEXTFLOW_EXECUTOR=slurm
SLURM_PARTITION=compute          # CPU 分区
# GPU 任务自动路由到 --partition=gpu --gres=gpu:1（无需额外配置）
SLURM_WORK_DIR=/scratch/biomate
```

**方案 C：Kubernetes GPU 集群**

```bash
NEXTFLOW_EXECUTOR=k8s
NXF_K8S_NAMESPACE=biomate-jobs
NXF_K8S_STORAGE_CLAIM=biomate-work-pvc
NXF_K8S_STORAGE_MOUNT=/nf-work
NXF_K8S_SERVICE_ACCOUNT=nextflow
NXF_K8S_GPU_RESOURCE=nvidia.com/gpu    # 国产 GPU 可改为 hygon.com/dcu 等
```

> **国产 GPU 适配说明：** 海光 DCU（K100、Z100L）在 K8s 中的资源名为 `hygon.com/dcu`，需将 `NXF_K8S_GPU_RESOURCE` 设为对应值，并确保集群已安装对应的 device plugin。

---

### 接入 Slurm 集群（CPU 场景）

```bash
NEXTFLOW_EXECUTOR=slurm
SLURM_PARTITION=compute          # 可选，默认 compute
# SLURM_QOS=                     # 可选
# SLURM_ACCOUNT=                 # 可选
SLURM_WORK_DIR=/scratch/biomate  # 集群共享文件系统上的工作/输出目录
```

### 接入 Kubernetes 集群（CPU 场景）

```bash
NEXTFLOW_EXECUTOR=k8s
NXF_K8S_NAMESPACE=biomate-jobs
NXF_K8S_STORAGE_CLAIM=biomate-work-pvc   # 需预先创建的 PVC（建议 ReadWriteMany）
NXF_K8S_STORAGE_MOUNT=/nf-work
NXF_K8S_SERVICE_ACCOUNT=nextflow
```

> 说明：当前支持 `local` / `slurm` / `k8s` / `awsbatch`；PBS/SGE/LSF 暂不支持。

---

## 6. 工作流数据库更新

BioMate 的工作流目录存储在 `backend/database/galaxy_ai_tools.db`（279 MB SQLite 文件，2600+ 工作流）。

**更新方法：**

```bash
# 停止后端
docker stop biomate-galaxy

# 备份旧版本
docker cp biomate-galaxy:/app/database/galaxy_ai_tools.db ./backups/galaxy_ai_tools_$(date +%Y%m%d).db

# 从新版代码中复制最新数据库
# （当收到 BioMate 团队的新版本包时，解压后运行）
docker cp ./backend/database/galaxy_ai_tools.db biomate-galaxy:/app/database/galaxy_ai_tools.db

# 重启
docker start biomate-galaxy
```

**接收更新包：**

BioMate 团队会定期提供包含最新工作流库的更新包（`.tar.gz`）。解压后按上述步骤替换数据库文件即可，无需完整重新构建镜像。

---

## 7. Ollama 离线模式

适用于：**完全内网、不允许任何外部 API 调用** 的场景。

**要求：** ≥ 32 GB RAM，推荐 NVIDIA GPU（≥ 24 GB 显存用于 qwen3:32b）

**启用步骤：**

```bash
# 1. 在 docker-compose.onprem.yml 中取消 ollama 服务的注释（约第100行）

# 2. 在 .env 中设置
GALAXY_AI_LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://ollama:11434

# 3. 启动（包含 Ollama）
docker compose -f docker-compose.onprem.yml up -d

# 4. 拉取模型（首次需要下载，约 20 GB）
docker exec biomate-ollama ollama pull qwen3:32b

# 5. 重启后端使配置生效
docker restart biomate-galaxy
```

**无 GPU 时的替代模型（CPU 推理，较慢）：**

```bash
docker exec biomate-ollama ollama pull qwen3:8b   # 需要约 8 GB RAM
# 然后设置
GALAXY_AI_LLM_MODEL=qwen3:8b
```

---

## 8. 反向代理（HTTPS）

生产环境建议在 `biomate-frontend:5000` 前面加 Nginx 或 Caddy 做 SSL 终止。

**Caddy 示例（最简单）：**

```
biomate.your-company.com {
    reverse_proxy localhost:5000
}
```

**Nginx 示例：**

```nginx
server {
    listen 443 ssl;
    server_name biomate.your-company.com;
    ssl_certificate /etc/ssl/certs/your.crt;
    ssl_certificate_key /etc/ssl/private/your.key;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 600s;
    }
}
```

启用 HTTPS 后，在 `.env` 中设置：

```bash
FORCE_HTTPS=1
ENABLE_HSTS=1
```

---

## 9. 备份与恢复

### 备份

```bash
#!/bin/bash
# backup.sh — 建议每天定时执行
BACKUP_DIR=/opt/biomate/backups/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# PostgreSQL（用户数据、项目、历史）
docker exec biomate-postgres pg_dump -U biomate biomate | gzip > $BACKUP_DIR/postgres.sql.gz

# 工作流数据库
docker cp biomate-galaxy:/app/database/galaxy_ai_tools.db $BACKUP_DIR/

# 保留最近 30 天
find /opt/biomate/backups -maxdepth 1 -mtime +30 -type d -exec rm -rf {} +
echo "Backup done: $BACKUP_DIR"
```

### 恢复

```bash
# 恢复 PostgreSQL
gunzip -c /opt/biomate/backups/20260101/postgres.sql.gz | \
  docker exec -i biomate-postgres psql -U biomate -d biomate

# 恢复工作流数据库
docker stop biomate-galaxy
docker cp /opt/biomate/backups/20260101/galaxy_ai_tools.db \
  biomate-galaxy:/app/database/galaxy_ai_tools.db
docker start biomate-galaxy
```

---

## 10. 日常维护命令

```bash
# 查看所有服务状态
docker compose -f docker-compose.onprem.yml ps

# 查看日志（实时）
docker logs -f biomate-galaxy   # AI 后端
docker logs -f biomate-frontend # Node 前端
docker logs -f biomate-postgres # 数据库

# 重启单个服务（改完配置后）
docker restart biomate-galaxy
docker restart biomate-frontend

# 升级（拉取新镜像后）
docker compose -f docker-compose.onprem.yml pull
docker compose -f docker-compose.onprem.yml up -d

# 停止所有服务
docker compose -f docker-compose.onprem.yml down

# 彻底清除（包括数据库，慎用！）
docker compose -f docker-compose.onprem.yml down -v
```

---

## 11. 国内环境特殊配置

以下问题在国内（包括阿里云 ECS 和客户内网）环境中均可能遇到。**所有问题在阿里云 Demo 实例（`101.201.107.126`）的 CI 流程中已自动修复**，但在新客户环境首次部署时仍需手动检查。

---

### 11.1 DaoCloud 镜像加速拦截本地镜像（P1）

**现象：** 工作流任务报 `Unable to find image 'X' locally`，但 `docker images` 确认镜像存在。

**根因：** ECS 或客户机器的 `/etc/docker/daemon.json` 配置了 DaoCloud（或其他）加速器 `registry-mirrors`，Docker 会拦截**所有** `docker pull`，包括本地已有的镜像，路由到加速器——加速器没有私有镜像 → 失败。

**修复（Nextflow executor 注入 `--pull never`）：**

```bash
docker exec biomate-galaxy grep "pull.never" \
  /app/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
# 若无输出，说明未注入，需要执行以下修复

docker exec biomate-galaxy python3 -c "
import re, pathlib
p = pathlib.Path('/app/lib/galaxy/webapps/galaxy/api/nextflow_executor.py')
old = '--user root'
new = '--user root --pull never'
content = p.read_text()
if new not in content:
    p.write_text(content.replace(old, new, 1))
    print('已注入 --pull never')
else:
    print('已存在，无需修改')
"
docker restart biomate-galaxy
```

> `--pull never` 告诉 Nextflow Docker 执行器：只使用本地缓存，永不尝试远程拉取。

---

### 11.2 Google CDN 导致页面空白（P6）

**现象：** 浏览器打开后白屏，F12 看到 `fonts.googleapis.com` 或 `googletagmanager.com` 请求一直 pending。

**修复（无需重启，原地 patch `index.html`）：**

```bash
# 找到前端构建产物里的 index.html
docker exec biomate-frontend find /app/dist -name "index.html" 2>/dev/null | head -1
# 通常是 /app/dist/public/index.html

docker exec biomate-frontend sed -i \
  '/fonts\.googleapis\.com/d; /fonts\.gstatic\.com/d; /googletagmanager\.com/d' \
  /app/dist/public/index.html

# 验证
docker exec biomate-frontend grep -c "googleapis" /app/dist/public/index.html
# 期望输出: 0
```

---

### 11.3 CORS 拒绝 IP 访问（P7）

**现象：** 浏览器控制台报 `CORS error`，API 调用返回 403。常见于使用 IP 直接访问（无域名）的场景。

**修复（`.env` + 重启前端）：**

```bash
# 获取机器 IP
PUBLIC_IP=$(curl -s --max-time 5 http://100.100.100.200/latest/meta-data/eip/public-ip 2>/dev/null \
         || ip route get 1 | awk '{print $7; exit}')

# 写入 CORS 配置（多个 Origin 用逗号分隔）
sed -i "s|^CORS_ORIGINS=.*|CORS_ORIGINS=http://${PUBLIC_IP}:5000|" .env

docker restart biomate-frontend
```

---

### 11.4 工作流数据库下载慢（P3，仅首次）

**现象：** `db-init` 容器长时间卡住，`galaxy_ai_tools.db` 只有几十 MB（损坏）。

**根因：** `galaxy_ai_tools.db` 约 303 MB，从 AWS S3 下载到国内网速很慢（50 KB/s）。

**修复（让 ECS 直接从 S3 下载，绕过 GHA/SSH 管道）：**

```bash
# 找到 db volume 挂载路径
VOL=$(docker inspect biomate-galaxy \
  --format '{{range .Mounts}}{{if eq .Destination "/app/database"}}{{.Source}}{{end}}{{end}}')

# 直接 curl 下载（S3 → 国内 ECS，走阿里云 S3 Gateway，比 GitHub Actions SSH 管道快 10 倍）
curl -fL --retry 3 --retry-delay 10 \
  "https://biomate-onprem-assets.s3.us-west-2.amazonaws.com/onprem/galaxy_ai_tools.db" \
  -o "${VOL}/galaxy_ai_tools.db.tmp" \
  && mv "${VOL}/galaxy_ai_tools.db.tmp" "${VOL}/galaxy_ai_tools.db"

docker restart biomate-galaxy
```

---

### 11.5 Involucro 锁文件死锁（P8）

**现象：** `biomate-galaxy` 容器每隔约 60 秒重启，日志显示 `Acquiring lock on involucro`，退出码 0。

**修复：**

```bash
VOL=$(docker inspect biomate-galaxy \
  --format '{{range .Mounts}}{{if eq .Destination "/app/database"}}{{.Source}}{{end}}{{end}}')
rm -f "${VOL}/dependencies/involucro.lock"
docker restart biomate-galaxy
```

---

### 11.6 轮询状态的正确 API 端点（P5）

若自定义脚本需要轮询工作流状态，**必须使用以下端点**，否则状态会一直显示 `running`：

```bash
# ✅ 正确（同步 Galaxy 实时状态）
GET /api/workflows/runs/<run_id>/status

# ❌ 错误（只读 DB 缓存，不同步实时状态）
GET /api/runs/<run_id>/meta
```

---

### 11.7 国内镜像加速配置（Docker daemon）

如果从 GHCR（`ghcr.io`）拉取镜像太慢，可以配置阿里云镜像加速（需要登录阿里云控制台获取个人专属地址）：

```bash
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://<your-id>.mirror.aliyuncs.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
systemctl reload docker
```

> **注意：** 配置 `registry-mirrors` 后，请务必参考 11.1 节注入 `--pull never`，否则工作流任务容器会通过加速器尝试拉取本地私有镜像导致失败。

---

## 12. 故障排查

### 服务启动慢（Galaxy 后端 120 秒才 healthy）

正常现象。Galaxy 启动时需要加载 AI 嵌入模型（约 500 MB）。等待即可。如果超过 3 分钟仍未 healthy：

```bash
docker logs biomate-galaxy 2>&1 | tail -50
```

### 工作流搜索不返回结果

```bash
# 检查工作流索引是否加载
curl http://localhost:8081/api/admin/index-health
# 或通过管理面板查看「工作流索引」状态
```

### LLM 调用失败（中国网络）

1. 先确认 API Key 是否正确：`docker exec biomate-galaxy printenv DEEPSEEK_API_KEY`
2. 如果使用 Anthropic，需要确认服务器能访问 `api.anthropic.com`（境外需要 VPN）
3. 国内推荐切换到 DeepSeek 或 智谱 GLM（见第2节）

### 数据库连接失败（Frontend 启动报错）

```bash
# 确认 PostgreSQL 已就绪
docker exec biomate-postgres pg_isready -U biomate -d biomate

# 确认 DATABASE_URL 格式正确
docker exec biomate-frontend printenv DATABASE_URL
```

### 磁盘空间不足

```bash
# 查看 Docker 占用
docker system df

# 清理无用镜像和容器（不影响运行中的服务）
docker system prune -f

# 查看工作流运行产生的文件
docker exec biomate-galaxy du -sh /app/logs /app/database
```

### 海光 C86 Illegal instruction 崩溃

```bash
# 确认是 AVX-512 问题
docker logs biomate-galaxy 2>&1 | grep -i "illegal\|SIGILL\|signal 4"

# 如确认是 AVX-512，在 .env 中加入以下变量后重启
echo "OPENBLAS_CORETYPE=SANDYBRIDGE" >> .env
echo "MKL_ENABLE_INSTRUCTIONS=AVX2" >> .env
docker restart biomate-galaxy
```

### ARM64 容器启动极慢（30 分钟+）

原因是某个镜像以 QEMU 模拟 x86 运行。检查：

```bash
docker exec biomate-galaxy uname -m   # 应为 aarch64
docker exec biomate-galaxy file /usr/bin/python3  # 应含 ARM aarch64

# 若返回 x86-64，说明镜像用了错误的架构，需要强制重拉 ARM64 版本
docker compose -f docker-compose.onprem.yml pull --no-parallel
docker compose -f docker-compose.onprem.yml up -d --force-recreate galaxy-backend
```

### 工作流运行结果文件预览 / 下载返回 403

**现象：** 工作流运行完成后，在「After Run → Outputs」面板点击文件预览弹出
`Preview unavailable (HTTP 403)`，或点击下载按钮也报 403。

**根本原因（三个）：**

| 场景 | 原因 |
|------|------|
| 文件路径是裸文件名（无目录分隔符） | 前端回落到文件名，`resolve()` 后路径不在允许目录内 |
| `work_dir` 未写入 DB（快速缓存命中的跑） | `allowedRoots` 检查失去依据，拒绝所有本地路径 |
| MinIO bucket 名不在内置白名单 | 旧版 `ALLOWED_BUCKETS` 白名单仅含固定几个名字 |

**排查步骤：**

```bash
# 1. 查看 Node.js 前端日志中 step-file 的 403 详情
docker logs biomate-frontend 2>&1 | grep "\[step-file\]"

# 典型输出（本地路径不在允许目录）：
# [step-file] 403 allowedRoots: resolved=/app/nf-work/xxx/file.txt roots=["/tmp/nextflow_runs"]

# 典型输出（MinIO bucket 名不在白名单 — 旧版镜像）：
# [step-file] S3 bucket not allowed: my-bucket

# 典型输出（裸文件名被解析到正确 S3 路径）：
# [step-file] Resolved bare filename "predict_admet_properties_output.txt" → s3://biomate-data/...
```

**修复方案（已在 v0.9.1+ 内置）：**

新版镜像已修复：MinIO 模式跳过白名单、自动查找裸文件名的 S3 URI、扩展允许目录至 `/app/nf-work`。若使用旧镜像，可在 `.env` 中临时添加环境变量并重启前端：

```bash
# 对旧镜像的临时绕过（新镜像无需此项）
echo "NEXTFLOW_WORK_DIR=/app/nf-work" >> .env
docker restart biomate-frontend

# 确认修复生效：访问一个已完成的工作流，点击 Outputs 中的文件
# 日志中应看到 "Resolved bare filename" 或直接输出文件内容（无 403）
```

**仍无法访问文件时的兜底排查：**

```bash
# 确认 MinIO 健康
docker exec biomate-minio mc alias set local http://localhost:9000 \
  ${MINIO_ROOT_USER:-biomate} ${MINIO_ROOT_PASSWORD} 2>/dev/null || \
  docker exec biomate-minio curl -sf http://localhost:9000/minio/health/live && echo OK

# 确认文件确实上传到 MinIO（替换 <user_id>/<run_id>）
docker exec biomate-minio mc ls local/biomate-data/nextflow/outputs/<user_id>/<run_id>/ --recursive

# 确认前端容器能访问 MinIO（同一 Docker 网络）
docker exec biomate-frontend curl -sf http://minio:9000/minio/health/live && echo "MinIO reachable"
```

---

## 联系支持

- 技术问题：联系 BioMate 工程团队
- 更新包申请：请求最新 `galaxy_ai_tools.db` 和 Docker 镜像
