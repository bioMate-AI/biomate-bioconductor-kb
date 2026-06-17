# 环境变量外部配置 — AWS Secrets Manager(GitLab 式)

> 2026-06-14。这是 BioMate 运行时环境变量的"GitLab 配置变量"等价实现:
> 值存在 AWS Secrets Manager,仓库只放变量名,部署机用 IAM 实例角色拉取。
> **值永不经过 GitHub、仓库或开发者本地文件。**

## 0. 为什么是 Secrets Manager(而不是 GitHub Secrets)

- 你们真实部署走 `sync_to_dev.sh`(本地脚本),不是 GitHub Actions → GitHub Secrets 根本到不了部署机。
- 密钥出于安全不能进 GitHub。
- AWS Secrets Manager 才是 AWS 上"GitLab CI/CD Variables"的对应物:控制台/CLI 配值、加密、审计、可轮换、按环境隔离、IAM 控权。

## 1. 各环境的 secret(已就绪)

| 环境 | 部署机 | env secret | 说明 |
|---|---|---|---|
| **dev** | i-06696b0d91f4346e0(sync_to_dev) | **`dev/biomate/galaxy-env`**(64 变量) | **2026-06-14 新建并加载** —— dev 机原本 env 主机手管,现已接入 Secrets Manager |
| test | i-0482a6fa98c6f301a(GHA) | `test/biomate/galaxy-env`(18 变量) | 团队原有,值是 test 专属(**勿用别环境的值覆盖**) |
| prod | — | `biomate/production/*`(us-east-1) | 团队原有 |

共用:`test/biomate/rds-galaxy`(RDS 凭证)、`biomate/lago/api-key`。

实例角色 `BioMateEc2DeployRole` 的读权限:
- `test-biomate-secrets-read`(团队原有)→ test 系列
- `dev-biomate-secrets-read`(**2026-06-14 新加**)→ `dev/biomate/galaxy-env-*`

⚠️ **不同环境值不同(AWS key/DB/JWT 都不一样),灌值时务必用对应环境的源,切勿跨环境覆盖。**

### dev 环境落地记录(2026-06-14)
- 用 dev 机当前 .env(48)+ 本地独有(18)= 64 变量 `create-secret dev/biomate/galaxy-env`。
- 给实例角色加 `dev-biomate-secrets-read`。
- 在 dev 机实跑 `load_env_from_secrets.sh`(BIOMATE_ENV=dev):核对 0 值冲突、新增 18、保留 3 主机独有 → `/opt/biomate/.env` 从 49 → 67 变量。**之前"本地有、部署机缺"的变量已全部到位。**
- ⏳ 需重启容器才生效(`docker --env-file` 启动时读)。

## 2. 流程

```
AWS Secrets Manager  test/biomate/galaxy-env   ← 控制台/CLI 配值(GitLab 变量UI 等价)
        │  scripts/load_env_from_secrets.sh(在 EC2 上,用实例角色拉取,无静态密钥)
        ▼  逐 key upsert(保留主机独有 key,先备份)
   /opt/biomate/.env
        │  docker --env-file
        ▼
   容器
```

## 3. 脚本

| 脚本 | 跑在哪 | 作用 | 权限 |
|---|---|---|---|
| `scripts/load_env_from_secrets.sh` | **EC2**(实例角色) | 拉 secret → 写 `/opt/biomate/.env` | `GetSecretValue`(实例角色已有) |
| `scripts/put_env_to_secret.sh` | 有写权限的机器 | 从一份完整 .env 灌进 secret | `PutSecretValue`(需 admin/授权) |
| `deploy/biomate.env.manifest` | 仓库 | 变量名清单(单一事实源/文档) | — |

### 拉取(部署时,推荐)

```bash
# 通过 sync_to_dev 触发(scp 脚本到 EC2 → 用实例角色拉 → 写 .env → 应用)
BIOMATE_LOAD_ENV=1 BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh

# 或直接在 EC2 上跑(SSM / ssh):
BIOMATE_ENV=test bash scripts/load_env_from_secrets.sh
DRY_RUN=1 BIOMATE_ENV=test bash scripts/load_env_from_secrets.sh   # 只预览
```

### 配值(改变量时,需写权限)

```bash
# 在 AWS 控制台直接编辑 secret 的 JSON,或:
BIOMATE_ENV=test bash scripts/put_env_to_secret.sh <complete.env>
DRY_RUN=1 BIOMATE_ENV=test bash scripts/put_env_to_secret.sh <complete.env>   # 只预览
```
默认排除构建期 `VITE_*` 和容器本地的 `GALAXY_CONFIG_FILE`/`PORT`(用 `EXCLUDE=` 覆盖)。

## 4. 待办(完成迁移)

1. **把变量灌全** —— `galaxy-env` 现在只有 18 个核心变量,缺 CRYOSPARC / Nextflow / 模型开关等(本地独有那批)。由有 `PutSecretValue` 权限的人跑 `put_env_to_secret.sh`,源用一份完整 .env(可先用 EC2 当前 `/opt/biomate/.env` 的 48 个,再补本地独有的)。
   - ⚠️ `CRYOSPARC_SSH_KEY` 值是工作站本地路径,放进 secret 前要确认部署机上的对应路径/密钥文件。
2. **(可选)接进容器启动** —— 当前靠 `sync_to_dev.sh BIOMATE_LOAD_ENV=1` 触发。要做到"每次部署/重启自动拉",可把 `load_env_from_secrets.sh` 接进容器 entrypoint 或 EC2 user-data。那才是完全无人值守。
3. **rotate** —— 轮换密钥 = 在 Secrets Manager 改值 + 重新 `BIOMATE_LOAD_ENV=1` 拉一次 + 重启容器。

## 5. 已验证

- `load_env_from_secrets.sh` 在真实 EC2 上 DRY_RUN 实测:用实例角色成功拉取 `test/biomate/galaxy-env`,预览 18 个变量,无静态密钥、无 GitHub。✅
- 语法检查、sync_to_dev 钩子接入。✅
- 未执行:真实写入(DRY_RUN 之外)、灌全 secret(需写权限)。

## 6. 这条 vs 之前的 scp(push_managed_env)

`BIOMATE_PUSH_ENV`(从本地文件 scp)保留作为备用,但 **`BIOMATE_LOAD_ENV`(Secrets Manager)是推荐路径** —— 真正的外部托管、零本地文件、零 GitHub,且无论 sync_to_dev 还是未来 GHA,EC2 都能自己拉。
