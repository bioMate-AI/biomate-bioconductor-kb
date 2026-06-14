# env-files 冲突值对照表 (合并前审计)

> 日期: 2026-06-13 · 配套: [ENV_REGISTRY.md](ENV_REGISTRY.md) · [20260612_EXTERNAL_ENV_CONFIG_PLAN.md](20260612_EXTERNAL_ENV_CONFIG_PLAN.md)
> 来源: `env-files/frontend/.env`、`env-files/backend/.env`、`env-files/.env.production`(=`.secrets-temp/secrets.env`)、`env-files/billing_system/lago/.env`
>
> ⚠️ **本表只用脱敏描述,不含真实密钥值**(避免 docs 成为新泄漏点)。真实值在 `env-files/`(已 gitignore)。
> 已定决策: ① Lago 统一指生产 ② 拆 `dev.env` + `production.env` ③ 合并 `frontend/.env`+`backend/.env`。

图例: ✅同值(可去重) · ⚠️冲突(需裁决) · 🆕单边独有 · 🔧服务相关(合理差异,需保留 per-service)

---

## 1. ⚠️ 真冲突 — 同名不同值,必须裁决

| 变量 | frontend/.env | backend/.env | 裁决(建议) |
|---|---|---|---|
| `LAGO_API_KEY` | 生产 key（`01b71711…`) | **本地 docker key**（`ba049ead…`) | ✅ **取生产**（已定 + CLAUDE.md 强制) |
| `LAGO_API_URL` | `35.86.137.71:3000`（生产) | `localhost:3010`（本地) | ✅ **取生产** |
| `JWT_SECRET` | `a1b2c3d4…`（**假占位符**) | `grhFb+sJ…`（真值) | ⚠️ **见下方专项** — 两者语义可能不同 |
| `AWS_ACCESS_KEY_ID` | 通用 keypair（`…VDET`) | NF 专用 keypair（`…4HQ6`) | ⚠️ **见下方专项** — 一名两钥 |
| `AWS_SECRET_ACCESS_KEY` | 配 `…VDET` 的密钥 | 配 `…4HQ6` 的密钥 | ⚠️ 同上 |
| `GALAXY_CONFIG_FILE` | `../backend/config/galaxy.yml` | `config/galaxy.yml` | 🔧 相对路径因 CWD 不同 — **保留 per-service 或改绝对路径** |

### 专项 A — JWT_SECRET（认证安全)

三个值:
- frontend `JWT_SECRET` = `a1b2c3d4…`(显然是开发占位符,弱)
- frontend `GALAXY_JWT_SECRET` = `grhFb+sJ…`
- backend `JWT_SECRET` = `grhFb+sJ…`（与上一致)

含义:前端用**自己的** `JWT_SECRET` 给用户签发登录 token;billing proxy 转发到 Galaxy 时用 `GALAXY_JWT_SECRET`(=后端 `JWT_SECRET`)**重新签名**。所以这是**两个不同用途的密钥**,本就该不同。

问题:前端用户 token 的签名密钥是 `a1b2c3…`(可被猜测)。**裁决建议**:
- 生成一个真实强密钥作为前端 `JWT_SECRET`(`openssl rand -base64 32`);
- 保持 `GALAXY_JWT_SECRET`（前端) = `JWT_SECRET`（后端) 的耦合不变;
- 合并到单文件后这三个名字共存:`JWT_SECRET`(用户认证)、`GALAXY_JWT_SECRET`(=后端 JWT)。

### 专项 B — AWS 凭证（一名两钥)

| 概念 | frontend/.env | backend/.env |
|---|---|---|
| 通用 S3/ECS（us-west-2） | `AWS_ACCESS_KEY_ID` = `…VDET` | — |
| Nextflow work 桶（us-east-1） | `AWS_NF_ACCESS_KEY_ID` = `…4HQ6` | `AWS_ACCESS_KEY_ID` = `…4HQ6` |

后端把 `AWS_ACCESS_KEY_ID` 当成 NF keypair 用,前端把它当通用 keypair 用。**合并裁决(两选一)**:
- **(推荐)统一语义**:`AWS_ACCESS_KEY_ID`=通用,`AWS_NF_ACCESS_KEY_ID`=NF 专用。改后端代码读 `AWS_NF_*` 作 NF 用途。需确认后端哪些路径在用这对凭证。
- **(保守)** 暂时给后端容器单独的 overlay,保留它的 `AWS_ACCESS_KEY_ID`=NF 值,不动代码。

> 这对凭证是否**有意权限隔离**(通用 key 无 NF 桶权限 / 反之)需你确认 —— 决定是合并还是保留两对。

---

## 2. ✅ 重复 — 同名同值,合并后去重为一处

这些在 frontend 和 backend 各存一份且值相同,合并后只保留一处即可(轮换时少改一个地方):

| 变量 | 值类型 |
|---|---|
| `ANTHROPIC_API_KEY` | 真实 Claude key（两文件一致) |
| `OPENAI_API_KEY` | 真实 OpenAI key |
| `GEMINI_API_KEY` | 真实 Gemini key |
| `BILLING_INTERNAL_KEY` | `w498JF…` |
| `LAGO_WEBHOOK_SECRET` | `9ef2c8b4…` |
| `REDIS_URL` | `redis://localhost:6379`(dev 值;prod 见 §4) |
| `BIOMATE_NF_PROFILE` | `aws` |

---

## 3. 🆕 单边独有 — 直接归位,无冲突

**仅 frontend/.env**: `DATABASE_URL`(localhost dev)· `GALAXY_JWT_SECRET` · `JWT_EXPIRY` · `E2E_TEST_TOKEN` · `AWS_NF_ACCESS_KEY_ID` · `AWS_NF_SECRET_ACCESS_KEY` · `AWS_S3_NEXTFLOW_BUCKET` · `S3_BUCKET_NAME` · `AWS_REGION` · `EMAIL_*`(6) · `APP_URL` · `GOOGLE_CLIENT_*`/`GITHUB_CLIENT_*`(空) · `REDIS_PORT` · `JAVA_BILLING_SERVICE_URL` · `JAVA_BILLING_ENABLED` · `STRIPE_*`(空) · `GALAXY_URL` · `GALAXY_API_URL` · `GALAXY_API_KEY` · `VITE_*` · `CRYOSPARC_AMI_ID`

**仅 backend/.env**: `DATABASE_PATH` · `BILLING_DEV_MODE` · `NEXTFLOW_USE_AWS` · `AWS_BATCH_QUEUE` · `GPU_BATCH_QUEUE` · `AWS_S3_BUCKET` · `AWS_DEFAULT_REGION` · `CRYOSPARC_*`(host/port/email/password/license/ssh/project/region/type/movie_dir/movies_s3) · `ALPHAFOLD3_DOCKER_*`(空) · `NVIDIA_NIM_API_KEY`(空) · `GOOGLE_API_KEY`

> 注意 §3 里也藏着两组**潜在重复概念**(命名不一,值实际相同/相关):
> - `AWS_S3_NEXTFLOW_BUCKET`（FE) ≈ `AWS_S3_BUCKET`（BE) = 都是 `biomate-nextflow-work`
> - `AWS_REGION`（FE,us-west-2) vs `AWS_DEFAULT_REGION`（BE,us-west-2) — SDK 两个名都认,建议都设
> - `GALAXY_URL` ≈ `GALAXY_API_URL`（FE 内部就重复,都 `localhost:8081`)
> - `GEMINI_API_KEY` = `GOOGLE_API_KEY`（同一个 Google key,两个名)

---

## 4. 🔧 服务相关 / 环境相关 — 不能简单共享一份

即便前后端读同一份文件,以下变量天然按服务或环境不同,需用 per-service overlay 或在 `dev.env`/`production.env` 间分别取值:

| 变量 | 差异原因 | 处理 |
|---|---|---|
| `NODE_ENV` | FE=`development`(dev) / `production`(prod) | 按环境文件 |
| `PORT` | FE=5000;BE gunicorn=8081(不在 .env) | per-service |
| `GALAXY_CONFIG_FILE` | 相对路径随 CWD | per-service 或改绝对 |
| `APP_URL` | dev=`localhost:5000` / prod=`dev-public.biomate.ai` | 按环境文件 |
| `DATABASE_URL` | dev=localhost / prod=RDS | 按环境文件 |
| `REDIS_URL` | dev=localhost / **prod=ElastiCache(目前只硬编码在 start_backend.sh!)** | 按环境文件 |
| `LAGO_API_*` | dev 也指生产(已定) | 一致 |

> ⚠️ **prod `REDIS_URL` 当前不在任何 env 文件里** —— 只在 `start_backend.sh` 硬编码。`production.env` 必须把它显式写出来,否则"外置配置"对 Redis 不成立。

---

## 5. 废件 — 直接删

| 文件 | 理由 |
|---|---|
| `.env.production` | 13 个独有变量(`DB_HOST`/`REDIS_HOST`/`S3_DATA_BUCKET`/`CORS_ORIGIN`/`API_KEY`/`WEBHOOK_SECRET`/`METRICS_API_KEY`/`BACKUP_ENCRYPTION_KEY`/`ADMIN_INITIAL_PASSWORD`/`BCRYPT_ROUNDS`…)**代码全不读**;host=占位符 `xxxx`;region 错(us-east-1)。从未接入。 |
| `.secrets-temp/secrets.env` | 与 `.env.production` 字节相同。 |
| `.env.production.template` | 同上 schema 的模板,误导。 |

> 删前若想保留里面的真随机密钥备用,可单独存档;但当前代码不消费这些变量名,留着只会让人以为它是生产源。

---

## 6. 合并后的目标结构(供下一步生成)

```
仓库内(提交,仅变量名+占位符):
  .env.example            ← §1-§4 全集,每个变量名+注释+占位符
  frontend/client/.env.example  ← 仅 VITE_*

env-files/(gitignore,真实值):
  dev.env                 ← §2 去重 + §3 dev 值 + §4 dev 列 + Lago 取生产
  production.env          ← 同 schema,§4 取 prod 值(RDS / ElastiCache / 域名)
  overlays/
    frontend.env          ← PORT=5000, NODE_ENV, GALAXY_CONFIG_FILE(FE 路径)
    backend.env           ← GALAXY_CONFIG_FILE(BE 路径), AWS overlay(若选保守方案)
  lago/lago.env           ← Lago 自身 crypto/db(独立,不并入)
  ci/secrets.env          ← GitHub Secrets 子集来源
```

docker-compose: 前后端容器 `env_file: [dev.env, overlays/<svc>.env]`(后者覆盖前者)。

---

## 7. 待裁决项汇总(进入生成前)

1. **AWS 凭证(专项 B)**:统一语义(改后端代码用 `AWS_NF_*`)还是保守 overlay? → 取决于两对 key 是否有意权限隔离。
2. **JWT_SECRET(专项 A)**:确认生成新的强前端 `JWT_SECRET`(替换 `a1b2c3…` 占位符)。
3. **概念去重(§3 注)**:`AWS_S3_NEXTFLOW_BUCKET`/`AWS_S3_BUCKET`、`GALAXY_URL`/`GALAXY_API_URL`、`GEMINI_API_KEY`/`GOOGLE_API_KEY` 是否收敛为单一规范名?(收敛需同步改代码读取点)
4. **prod 值来源**:`production.env` 的 RDS `DATABASE_URL`、ElastiCache `REDIS_URL`、域名 `APP_URL` 真实值从哪取?(目前仓库里没有真实 prod host)
