# 部署会话总结 2026-09-21

## 已完成

### 合并的 PR
| PR | 内容 | 状态 |
|---|---|---|
| #222 | on-prem 部署包 + i18n 中文界面 | ✅ 已合并 |
| #223 | k8s/Slurm 执行器 + admin 仪表板扩展 + 空气隔离部署 | ✅ 已合并 |
| #225 | 42个文件 `/home/yzhang/` 路径修复 + gunicorn-boot 磁盘空间修复（CI L4 lint 全绿）| ✅ 已合并 |
| #229 | GHCR retag workflow（ECR→GHCR 推送工具）| ✅ 已合并 |
| #230 | dev SSM deploy workflow（工具文件）| OPEN，未合并 |

### CI 状态
- 所有检查全绿：Frontend Tests / Backend Tests / Pydantic smoke / Security Scan / Full gunicorn boot
- L4 image lint（no /home/yzhang/ paths）已修复

### TEST 环境
- **✅ 正常，最新代码**
- URL: https://test.stage-public.biomate.ai
- 运行镜像: `sha-73c548652b69`（包含 PR #222/#223/#225 所有改动）

### GHCR 镜像
- 已推送 `ghcr.io/biomate-ai/biomate-backend:latest`
- 已推送 `ghcr.io/biomate-ai/biomate-frontend:latest`
- **问题：包是私有的**，外部拉不到

---

## 未完成 / 待处理

### 1. DEV 环境需要重启 ⚠️
**问题：** 本次会话中用 SSM 在 dev EC2 上执行了大文件下载命令（~100MB+ repo tarball），导致 `/tmp` 磁盘撑满，SSM agent 崩溃，现在所有 SSM 命令立刻失败。

**EC2 实例：** `i-06696b0d91f4346e0`（dev-public.biomate.ai，标签 `BioMate-Production`）

**修复步骤：**
```bash
# 方法1：通过 AWS CLI 重启（需要 ec2:RebootInstances 权限）
aws ec2 reboot-instances --instance-ids i-06696b0d91f4346e0 --region us-west-2

# 方法2：AWS 控制台 → EC2 → i-06696b0d91f4346e0 → Actions → Reboot
```

重启后约 2 分钟服务自动恢复（Docker 配置了 restart:always）。

**重启后更新代码的方法（任选其一）：**

方法 A — SSM 从 GitHub 下载并构建（分步，需要 AWS CLI）：
```bash
# Step 1: 清理 /tmp 并下载（注意加 --parameters executionTimeout）
GH_TOKEN=<zheganjue519 的 token，已有 repo scope>
aws ssm send-command \
  --instance-ids i-06696b0d91f4346e0 \
  --document-name "AWS-RunShellScript" \
  --region us-west-2 \
  --cli-input-json "{
    \"InstanceIds\":[\"i-06696b0d91f4346e0\"],
    \"DocumentName\":\"AWS-RunShellScript\",
    \"Parameters\":{
      \"commands\":[
        \"rm -rf /tmp/biomate-* 2>/dev/null || true\",
        \"df -h /tmp\",
        \"curl -sL -H 'Authorization: token ${GH_TOKEN}' https://api.github.com/repos/bioMate-AI/biomate/tarball/integration%2Fnext-phase -o /tmp/biomate.tar.gz\",
        \"mkdir -p /tmp/bmsrc && tar -xzf /tmp/biomate.tar.gz -C /tmp/bmsrc --strip-components=1\",
        \"rsync -a --delete /tmp/bmsrc/frontend/ /opt/biomate/frontend/ --exclude node_modules --exclude .env --exclude dist\",
        \"rm -rf /tmp/biomate.tar.gz /tmp/bmsrc\",
        \"echo DONE\"
      ]
    }
  }"

# Step 2: 构建前端镜像（单独命令，约10分钟）
aws ssm send-command \
  --instance-ids i-06696b0d91f4346e0 \
  --document-name "AWS-RunShellScript" \
  --region us-west-2 \
  --cli-input-json '{
    "InstanceIds":["i-06696b0d91f4346e0"],
    "DocumentName":"AWS-RunShellScript",
    "Parameters":{"commands":[
      "cd /opt/biomate/frontend && docker build -t biomate-dev-frontend:next -f Dockerfile . 2>&1 | tail -5",
      "docker tag biomate-dev-frontend:next biomate-dev-frontend:latest",
      "docker stop biomate-dev-frontend && docker rm biomate-dev-frontend",
      "cd /opt/biomate && docker compose up -d --no-deps --force-recreate",
      "sleep 15 && curl -sf http://localhost:3000/api/health && echo OK"
    ]}
  }'
```

方法 B — 本机 SSH 跑 sync_to_dev.sh（有 SSH 权限的人）：
```bash
cd /Users/renyuankai/work/biometa/biomate
bash scripts/sync_to_dev.sh
```

### 2. On-prem 私有化部署 GHCR 包需要设为 Public

当前状态：镜像已推到 GHCR 但是私有的，客户拉不到。

**两个方案：**

方案 A（推荐）— 改为 Public：
- GitHub → bioMate-AI org → Packages → `biomate-backend` → Change visibility → Public
- 同样操作 `biomate-frontend`
- 之后客户直接 `docker compose -f docker-compose.onprem.yml up -d` 即可

方案 B — 通过 gh CLI token 更新 scope（需要 `read:packages`）：
- 用有 `read:packages` scope 的 PAT，注入到 dev EC2 docker login
- 每次部署都要这样做，麻烦

---

## 关键资源

| 资源 | 值 |
|---|---|
| Dev EC2 实例 ID | `i-06696b0d91f4346e0` |
| Test EC2 实例 ID | `i-0482a6fa98c6f301a` |
| AWS 区域 | `us-west-2` |
| ECR 注册表 | `399683337364.dkr.ecr.us-west-2.amazonaws.com` |
| 主分支 | `integration/next-phase` |
| Dev URL | https://dev-public.biomate.ai |
| Test URL | https://test.stage-public.biomate.ai |
| On-prem compose 文件 | `docker-compose.onprem.yml` + `.env.onprem.example` |
