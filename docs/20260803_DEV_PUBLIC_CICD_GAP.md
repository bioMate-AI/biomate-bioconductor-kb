# dev-public (正式 App 环境) 接入 CI/CD — 现状缺口、设计与待决策项

**Date:** 2026-08-03
**Author:** deploy investigation session
**Status:** 设计完成；**待一次生产凭据决策**后可落地（见 §4）

---

## 0. TL;DR

- `dev-public.biomate.ai` 是**正式版 App 环境**（React app + Galaxy 后端，EC2 `i-06696b0d91f4346e0`，tag `Env=dev`）。`biomate.ai` 只是 homepage/营销站（`webpage_design_v2/`，另走 `scripts/deploy_marketing.sh`）。`stage-public.biomate.ai` 是 test 环境（`i-0482…`）。
- **dev-public 从未接入 GHA CI/CD**。现有 CD（`deploy.yml` → `deploy.sh`）只部署 test/stage-public。dev-public 一直靠 `scripts/sync_to_dev.sh`（本地 scp/SSH）人工同步。
- 不能简单给 `deploy.sh` 加个 `dev` 分支：`deploy.sh` 是 **拉 ECR 镜像 + compose** 模型，而 dev-public 是 **机器上从源码 build 前端单容器 + Galaxy 热补丁**，两套模型不兼容。
- 正确架构：**GHA `workflow_dispatch` → OIDC → SSM，在机器上跑"源码 build + 换容器 + 健康门禁 + 回滚"**（此流程已于 2026-08-03 用 SSM 手动实测成功部署 `/security` 页）。
- **唯一阻塞** = GHA runner 如何把源码传到机器。sync 靠 scp(SSH)，GHA 走 SSM 需要一条传输通道，而三条候选通道（S3 / git-SSH / git-HTTPS）**都需要在生产机上一次性配置一个凭据**（当前一个都没有）。这一步涉及生产凭据，需团队**明确决策**，不应被自动化脚本擅自代劳。

---

## 1. 环境与域名映射（务必分清）

| 域名 | 是什么 | 承载 | 部署方式 |
|---|---|---|---|
| `dev-public.biomate.ai` | **正式版 App** | React app + Galaxy，`i-06696b`（`Env=dev`, Name=BioMate-Production） | `sync_to_dev.sh`（人工）/ 本文的 SSM 方案 |
| `stage-public.biomate.ai` | test 环境 | `i-0482…`（`Env=test`） | GHA `deploy.yml`（已通） |
| `biomate.ai` | **homepage/营销站** | `webpage_design_v2/`（独立静态站，有自己的 /privacy /terms） | `scripts/deploy_marketing.sh` |

> ⚠️ App 是 SPA：**任何路径都返 HTTP 200**（不存在的路由由前端渲染 404 组件）。验证某路由是否真部署，不能只看状态码，要查构建产物：
> `docker exec biomate-dev-frontend sh -c "grep -rl '<页面独有字符串>' /app/dist/public/assets/*.js"`

---

## 2. 为什么现有 CD 到不了 dev-public（根因）

1. `deploy.sh` 只有 `test`/`staging`/`production` 三个 env 分支，无 `dev`；且都按 tag 找实例后**拉 ECR 镜像 + compose 重建**。
2. `deploy.yml` 只有 `deploy-test` 一个 job（`environment: test` → stage-public）。
3. 镜像仅在 `release-*`/`beta-*`/`dev-*` tag 或 `workflow_dispatch` 时构建。
4. dev-public 的实际运行模型完全不同：
   - **前端**：`/opt/biomate/frontend_sync/frontend` 源码 → 机器上 `docker build -t biomate-dev-frontend:next` → 单容器 `docker run`（端口 3000，`--network biomate-dev-net`，`--env-file /opt/biomate/.env`）。**不从 ECR 拉**。
   - **后端**：Galaxy 容器**热补丁**（`docker cp` 源码 + gunicorn HUP），非镜像换 tag。
5. 证据：`.github/workflows/ind-pi-suite.yml` 注释明写 "dev-public.biomate.ai already runs the latest **sync**"、"have **synced** the code…" —— CI 设计上就假设 dev-public 是人工 sync 上去的，只对它跑验证。

**结论**：给 `deploy.sh` 加 `dev` 分支会得到一个"看着好了、实则跑不通"的假接线（ECR 模型对不上源码-build 模型）。必须用不同的 CD 路径。

---

## 3. 目标架构：GHA workflow_dispatch → OIDC → SSM 源码部署

复用**已实测成功**的 SSM 部署流程（2026-08-03 用它部署了 `/security`）：

```
GHA workflow_dispatch(ref/sha)
  → configure-aws-credentials (OIDC, role GitHubActionsDeploy)
  → 把目标 ref 的前端源码送达 i-06696b   ← 【唯一阻塞，见 §4】
  → SSM RunShellScript on i-06696b:
       1. docker tag biomate-dev-frontend:latest :rollback   # 回滚快照
          docker cp <容器>:/app/dist/public/logo.png /tmp/logo_backup.png
       2. docker build -t biomate-dev-frontend:next -f <src>/Dockerfile <src>   # 旧容器仍在服务
          build 失败 → 退出，不 swap
       3. docker tag :next :latest
          docker rm -f biomate-dev-frontend
          docker run -d --name biomate-dev-frontend --network biomate-dev-net \
            -p 3000:3000 --env-file /opt/biomate/.env \
            -e NODE_ENV=production -e PORT=3000 -e FORCE_HTTPS=0 \
            --restart unless-stopped \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /tmp/biomate_code:/tmp/biomate_code \
            biomate-dev-frontend:latest
          docker cp /tmp/logo_backup.png <容器>:/app/dist/public/logo.png
       4. 健康门禁：curl -s -o /dev/null -w '%{http_code}' localhost:3000/ == 200
          不过 → 回滚：rm -f、tag :rollback→:latest、重跑旧镜像
```

**已验证的可行性**：
- `galaxy-dev` 用户有 `ssm:SendCommand`，`i-06696b` 上 SSM agent 以 root 运行 ✅
- 上述 build+swap+health+rollback 流程今天实跑成功（`/security` 已上线并在 bundle 中确认）✅
- 沙箱/CI 环境**不能 SSH**（TCP 连上但握手不返回），但 **SSM 可用** ✅
- SSM 发命令注意：远程是 dash（无 `set -o pipefail`）；用 `base64 → 文件 → bash file` 避免 heredoc/stdin 冲突（inline 多层引号会崩）。

---

## 4. 唯一阻塞：源码传输通道需要一次生产凭据（**待决策**）

GHA runner → 机器的文件传输通道，三条候选**当前都不通**，各需一次性配置：

| 通道 | 现状（已实测 2026-08-03） | 需要配置 | 评价 |
|---|---|---|---|
| **A. S3 中转** | 我方凭据能写 `biomate-nextflow-work`；但**机器实例角色 GetObject 失败** | 给 `i-06696b` 实例角色加一个传输桶的 `s3:GetObject`；OIDC 角色加该桶 `s3:PutObject` | 干净、无长期密钥；**推荐** |
| **B. git SSH deploy key** | 机器能连 github.com，但 `git@github.com: Permission denied (publickey)`，无 key | 在机器装 read-only deploy key + GitHub 仓库加该公钥 | 可行；多一个 key 要管理 |
| **C. git HTTPS PAT** | 机器 `https://github.com` 返 200，但私有仓库需 token，机器无 token | 在机器存一个只读 PAT（私有仓 clone/fetch） | 最简单，但长期存 PAT 在生产机 |

> 另需确认：**OIDC 角色 `GitHubActionsDeploy` 是否已授 `ssm:SendCommand` 到 `i-06696b`**（现只对 test 机用过；可能要把 dev 实例加入其 policy 资源范围）。`galaxy-dev` 无 IAM 读权，未能自查，需有 IAM 权限者确认。

**为什么不在本 session 直接配**：三条通道都要往**生产机/生产 IAM** 塞长期凭据或改角色策略，属于需要明确授权的部署动作。CLAUDE.md 规定 proper fix 若本 session 做不完，**清楚记录、不上 workaround**。故此处停在"设计 + 待决策"，不擅自 provision 生产凭据。

**推荐**：选 **通道 A（S3）**——无长期密钥、最符合最小权限。定了之后，落地约 1–2 小时：加 2 条 IAM 语句 + 写 `.github/workflows/deploy-dev-public.yml`（workflow_dispatch）+ 一次验证 dispatch。

---

## 5. 落地清单（选定通道 A 后）

1. IAM：`i-06696b` 实例角色（`BioMateEc2DeployRole` 或其现用角色）+ `s3:GetObject` on `arn:aws:s3:::<transfer-bucket>/dev-public-deploy/*`；OIDC 角色 `GitHubActionsDeploy` + `s3:PutObject` 同前缀 + `ssm:SendCommand` on `i-06696b`。
2. `.github/workflows/deploy-dev-public.yml`（`workflow_dispatch`，输入 `ref`）：checkout → tar 前端源码 → `aws s3 cp` 到传输桶 → SSM 执行 §3 的 build+swap+health+rollback（源码从 S3 拉取解压到 `/opt/biomate/frontend_sync`）。
3. （可选）后端：若要一并覆盖 Galaxy 热补丁层，追加对应 SSM 步骤；否则保持前端-only。
4. 一次验证 dispatch，确认 `/security` 类改动能端到端上线。

落地后 dev-public 即获得一键 CI/CD 部署，不再依赖本机 `sync_to_dev.sh`。

---

## 6. 立即事项（与本 CD 工作独立，别漏）

- **`/security` 目前是直接 patch 到机器 `frontend_sync` 源码树部署的**。下次谁跑一次完整 `sync_to_dev.sh`（从缺少 security 的分支的完整工作树），会**覆盖掉 `/security`**。
  → **务必尽快把 `feat/security-page` 合入 `integration/next-phase`**（PR: https://github.com/bioMate-AI/biomate/pull/new/feat/security-page ；`gh` token 已失效，需手动点）。
