# 环境变量外部配置 — AWS Secrets Manager(GitLab 式)

> 2026-06-14。这是 BioMate 运行时环境变量的"GitLab 配置变量"等价实现:
> 值存在 AWS Secrets Manager,仓库只放变量名,部署机用 IAM 实例角色拉取。
> **值永不经过 GitHub、仓库或开发者本地文件。**

## 0. 为什么是 Secrets Manager(而不是 GitHub Secrets)

- 你们真实部署走 `sync_to_dev.sh`(本地脚本),不是 GitHub Actions → GitHub Secrets 根本到不了部署机。
- 密钥出于安全不能进 GitHub。
- AWS Secrets Manager 才是 AWS 上"GitLab CI/CD Variables"的对应物:控制台/CLI 配值、加密、审计、可轮换、按环境隔离、IAM 控权。

## 1. 已就绪的基础设施(团队带外搭的)

| 资源 | 说明 |
|---|---|
| Secret `test/biomate/galaxy-env` | JSON,运行时环境变量(当前 18 个核心:JWT_SECRET / DATABASE_URL / AWS 凭证 / LAGO_* / REDIS_URL / BILLING_INTERNAL_KEY / FIELD_ENCRYPTION_SECRET …) |
| Secret `test/biomate/rds-galaxy` | RDS 数据库凭证(host/port/user/password/url) |
| 实例角色 `BioMateEc2DeployRole` | 策略 `test-biomate-secrets-read` 已授 `secretsmanager:GetSecretValue` |
| `test/` 前缀 | 按环境隔离(test/staging/prod) |

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
