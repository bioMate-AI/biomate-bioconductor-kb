# 环境变量配置与部署流水线(最终架构)

> 创建 2026-06-13 · 修订 2026-06-14(改为反映真实部署拓扑)
> 配套: [ENV_REGISTRY.md](ENV_REGISTRY.md) · [20260613_ENV_FILES_CONFLICT_AUDIT.md](20260613_ENV_FILES_CONFLICT_AUDIT.md)

## 0. 核心结论

- **真实部署走 `scripts/sync_to_dev.sh`**(本地脚本,EC2 Instance Connect + scp/ssh,按实例 ID 直连 dev 机 `i-06696b0d91f4346e0` / `Env=dev`)。
- **runtime env 在 EC2 主机 `/opt/biomate/.env`**(`ubuntu:ubuntu`),容器用 `--env-file` 读;仓库内零密钥值。
- **变量名单一事实源 = `deploy/biomate.env.manifest`**。
- **env 注入由 sync_to_dev.sh 负责**(scp 直传,不需要 S3)。GHA deploy.yml **只负责部署**,不注入 env。

## 1. 两条路径

```
┌─ 真实路径:sync_to_dev.sh(本地 → dev 机,scp/ssh)──────────────────┐
│  代码/镜像同步 + (可选) env 推送:                                    │
│    BIOMATE_PUSH_ENV=1 [BIOMATE_ENV_SOURCE=file] BIOMATE_RESYNC_GALAXY_ENV=1 \│
│      bash scripts/sync_to_dev.sh                                      │
│    → 本地按 manifest 渲染(render_env_manifest.sh,必需缺失即 fail)    │
│    → scp 到 EC2 → 逐 key upsert 进 /opt/biomate/.env(保留主机独有key) │
│    → resync_galaxy_env 应用到容器                                     │
└──────────────────────────────────────────────────────────────────────┘

┌─ 备用路径:GHA deploy.yml(workflow_dispatch / 镜像构建联动)─────────┐
│  仅部署:OIDC 角色 GitHubActionsDeploy → SSM 到 Env=test 实例         │
│  (i-0482a6fa98c6f301a / biomate-deploy-test)→ 拉镜像/重启/健康检查   │
│  env 不注入:沿用主机 /opt/biomate/.env(由上面的路径或人工维护)      │
└──────────────────────────────────────────────────────────────────────┘
```

## 2. 为什么 GHA 不注入 env(2026-06-14 排查结论)

GHA 路径的 env 注入(经 SSM→S3 中转)在当前基础设施下**走不通**:
1. 中转桶 `biomate-deploy-temp` **不存在**(NoSuchBucket)。
2. OIDC 部署角色 `GitHubActionsDeploy` **无 S3 权限**。
3. 关键:**EC2 实例角色读不了任何 S3 桶**(app 在 EC2 上用 galaxy-dev 凭证访问 S3,不是实例角色)→ 即便换现有桶,EC2 端 `aws s3 cp` 下载也会 DENIED。

唯二可行方案是「改实例角色 IAM(需 admin)」或「base64 走 SSM(密钥进 CloudTrail,已否决)」。由于 sync_to_dev.sh 已用 scp 安全地完成 env 注入,**GHA 不重复做** —— 只部署、env 主机托管。

## 3. 本次对 GHA deploy.sh / deploy.yml 的修复

| 问题 | 修复 |
|---|---|
| deploy.sh 按 `biomate:env` 找实例,实例实际用 `Env` 标签 → 永远找不到 | 改为 `Env`(已用真实 AWS 验证:`tag:Env=test` 命中 biomate-deploy-test) |
| deploy.sh Step 2 经不存在的 S3 桶注入 env → 必失败 | 改为「确认主机 .env 存在」,不再注入(env 主机托管) |
| deploy.yml 用 toJSON 渲染+S3 注入(基础设施不支持) | 退回简单部署,用 OIDC 角色(有 SSM/EC2/ECR,够部署) |

## 4. 改动的文件(分支 feat/cicd-env)

| 文件 | 作用 | 谁用 |
|---|---|---|
| `deploy/biomate.env.manifest` | 变量名单一事实源(61 变量,14 required) | sync_to_dev 渲染 |
| `scripts/render_env_manifest.sh` | 渲染 + 必需校验 + 向后兼容 | sync_to_dev |
| `scripts/sync_to_dev.sh` | `BIOMATE_PUSH_ENV=1` 推送钩子 + `push_managed_env()` | **真实部署** |
| `scripts/deploy.sh` | 修标签 + Step 2 主机托管 | GHA(备用) |
| `.github/workflows/deploy.yml` | 简单部署(OIDC 角色) | GHA(备用) |
| `scripts/setup_github_env.sh` | 一键推 GitHub Secrets/Variables(未来若启用 GHA 注入用) | 可选/未来 |
| `.env.ec2.example` | 由 manifest 派生 | 参考 |

## 5. 日常:改一个 env 值

1. 改值的来源(`BIOMATE_ENV_SOURCE`,默认 `env-files/opt-biomate.env`)。
2. `BIOMATE_PUSH_ENV=1 BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh`。
3. 新增变量:先在 `deploy/biomate.env.manifest` 加一行。

## 6. 验证状态(本地 + 真实机器,未做破坏性操作)

- 渲染三场景(完整/缺必需 fail-fast/空向后兼容)✅
- sync_to_dev 推送:本地渲染 44 变量值全对、特殊字符安全 ✅
- **what-if 对最新 live EC2 .env**:0 处变化(幂等)、4 个主机独有 key 全保留 ✅
- GHA 标签修复:`tag:Env=test` 真实命中 biomate-deploy-test 实例 ✅
- 尚未执行:真实 env 推送(scp 写 .env)、真实 GHA 部署
