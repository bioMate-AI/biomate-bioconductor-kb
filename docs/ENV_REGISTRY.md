# BioMate 环境变量权威清单 (ENV Registry)

> 创建: 2026-06-12 · 配套方案: [20260612_EXTERNAL_ENV_CONFIG_PLAN.md](20260612_EXTERNAL_ENV_CONFIG_PLAN.md)
> 用途: 全项目环境变量的**单一事实源**。任何对 env 的改动(代码引用、模板、CI、部署)都以此表为准。
>
> 扫描范围: `frontend/**`(`process.env` / `import.meta.env`)+ `backend/**`(`os.environ` / `os.getenv`)
> + `start_backend.sh` + `docker-compose*.yml` + `.github/workflows/**`。已排除 Galaxy 上游框架的测试内部变量
> (`GALAXY_TEST_*`、`GALAXY_SLOTS`、`OAUTHLIB_*` 等)——那些由 `galaxy.yml` / 测试驱动管理,不属于外部配置范畴。

## 图例

- **scope**: `secret`(敏感,→ GitHub Secrets)· `public`(非敏感,→ GitHub Variables)· `dev`(仅本地/CI)
- **set_in**: `GH-S`=GitHub Secret · `GH-V`=GitHub Variable · `EC2`=主机 `/opt/biomate/shared/.env.ec2` · `dev`=本地 `.env` · `CI`=GitHub Actions 测试用
- **req**: ✅ 生产必需 · ⬜ 可选(按功能启用) · 🧪 仅测试/开发
- **consumer**: FE=前端 Node 服务 · BE=后端 Galaxy · λ=Lambda · ⚙️=部署脚本

---

## 1. 生产必需 — 核心密钥 (secret → GH-S + EC2)

| 变量名 | req | consumer | 说明 / 主要读取点 |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | ✅ | FE, BE | Claude API,主 LLM。`routes.ts`, `ai/config.py`, `ai_assistant.py` |
| `JWT_SECRET` | ✅ | FE, BE | 用户 JWT 签名。`auth-service.ts`, `billing_router.py` |
| `SESSION_SECRET` | ✅ | FE | Express session。`index.ts` |
| `BILLING_INTERNAL_KEY` | ✅ | FE, BE | Galaxy↔Lago 内部鉴权。⚠️ **已泄漏待轮换** |
| `DATABASE_URL` | ✅ | FE, BE | PostgreSQL 连接串。`db.ts`, `agentic_memory.py` |
| `AWS_ACCESS_KEY_ID` | ✅ | FE, BE | S3/Batch 通用凭证。`s3-client.ts`, `fix_applier.py` |
| `AWS_SECRET_ACCESS_KEY` | ✅ | FE, BE | 同上 |
| `GALAXY_API_KEY` | ✅ | FE | 调用 Galaxy 后端 API。`routes.ts`(21 处) |
| `LAGO_API_KEY` | ✅ | FE, BE | Lago 计费 API key。⚠️ **已泄漏待轮换** |
| `REDIS_URL` | ✅ | FE, BE, λ | 计费实时累加器 / session。`realtime_cost_service.py` |
| `ENCRYPTION_KEY` | ✅ | FE | 字段级加密。`encryption.ts` |
| `CSRF_SECRET` | ⬜ | FE | CSRF 防护(deploy.sh 注入项) |
| `OPENAI_API_KEY` | ⬜ | FE, BE | LLM fallback。`ai_config.py` |
| `GEMINI_API_KEY` | ⬜ | FE, BE | Gemini Flash 意图分类。`gemini_flash.py` |

---

## 2. 生产必需 — 非敏感配置 (public → GH-V + EC2)

| 变量名 | req | consumer | 说明 |
|---|---|---|---|
| `GALAXY_URL` | ✅ | FE, BE | Galaxy 后端地址。`routes.ts`(59 处,最高频) |
| `AWS_REGION` | ✅ | FE, BE | 主区域(`us-west-2`) |
| `S3_BUCKET_NAME` | ✅ | FE | 主存储桶。`s3-client.ts` |
| `LAGO_API_URL` | ✅ | FE, BE | Lago 地址。⚠️ **规范名,见 §6 冲突** |
| `NODE_ENV` | ✅ | FE | `production` / `development` |
| `PORT` | ⬜ | FE | 服务端口(默认 5000) |
| `CORS_ORIGINS` | ⬜ | FE | 允许的跨域来源 |
| `FORCE_HTTPS` / `ENABLE_HSTS` | ⬜ | FE | HTTPS 安全开关(EC2 Nginx 终止 TLS 时设 0) |
| `JAVA_BILLING_SERVICE_URL` | ⬜ | FE, BE | Java 计费服务地址 |
| `JAVA_BILLING_ENABLED` | ⬜ | FE, BE | 是否启用 Java 计费 |
| `VCPU_HOUR_QUOTA` | ⬜ | FE | 配额阈值 |
| `LAGO_WEBHOOK_SECRET` | ⬜ | BE | Lago webhook 校验 |
| `LAGO_PLAN_CODE` | ⬜ | FE | 默认订阅 plan code |

---

## 3. 生产运行时契约 — docker-compose.ec2.yml 实际注入

> 这是**生产容器真正收到**的变量集(`${VAR}` 形式从 EC2 `.env.ec2` 取)。是 §1/§2 的落地校验基准。

```
ANTHROPIC_API_KEY  OPENAI_API_KEY  JWT_SECRET  SESSION_SECRET  BILLING_INTERNAL_KEY
DATABASE_URL  AWS_ACCESS_KEY_ID  AWS_SECRET_ACCESS_KEY  AWS_REGION  S3_BUCKET_NAME
GALAXY_URL  GALAXY_API_KEY  REDIS_URL  CORS_ORIGINS  FORCE_HTTPS  ENABLE_HSTS
POSTGRES_DB  POSTGRES_USER  POSTGRES_PASSWORD
```

> ⚠️ 差异:`docker-compose.ec2.yml` 注入了 `POSTGRES_*`(bundled PG)但**没注入** `LAGO_API_KEY` / `LAGO_API_URL` / `JAVA_BILLING_*` —— 这些计费变量目前靠 `start_backend.sh` 硬编码兜底(待修)。三处清单需在 Phase 4 对齐。

---

## 4. 可选功能模块 (⬜ 按需启用)

### 4.1 计费 / Lambda (secret 多)
`BILLING_API_KEY`(=`BILLING_INTERNAL_KEY` 同值别名)· `BILLING_API_URL` · `BILLING_DEV_MODE` · `NOTIFY_URL` · `USER_TAG_NAME` · `LANGSMITH_API_KEY` · `LANGSMITH_PROJECT` · `LANGCHAIN_TRACING_V2`

### 4.2 Nextflow / AWS Batch
`AWS_S3_NEXTFLOW_BUCKET` · `AWS_NF_ACCESS_KEY_ID` 🔑 · `AWS_NF_SECRET_ACCESS_KEY` 🔑 · `NEXTFLOW_USE_AWS` · `NEXTFLOW_WORK_DIR` · `NEXTFLOW_S3_BUCKET` · `NEXTFLOW_DEFAULT_EXECUTOR` · `AWS_S3_BUCKET` · `AWS_BATCH_QUEUE` · `AWS_BATCH_JOB_ROLE_ARN` · `AWS_BATCH_EXECUTION_ROLE_ARN` · `AWS_DEFAULT_REGION` · `AWS_PROFILE` · `AWS_MAX_CPUS` · `AWS_MAX_MEMORY` · `AWS_INSTANCE_TYPE` · `AWS_ECR_REGISTRY` · `GALAXY_TOOL_RUNNER_IMAGE` · `GALAXY_TOOL_RUNNER_DIGEST` · `GPU_BATCH_QUEUE` · `BIOMATE_NF_PROFILE` · `NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER`

### 4.3 CryoEM / CryoSPARC
`CRYOSPARC_AMI_ID` · `CRYOSPARC_LICENSE` 🔑 · `CRYOSPARC_HOST` · `CRYOSPARC_PORT` · `CRYOSPARC_EMAIL` · `CRYOSPARC_PASSWORD` 🔑 · `CRYOSPARC_SSH_USER` · `CRYOSPARC_SSH_KEY` 🔑 · `CRYOSPARC_INSTANCE_ID` · `CRYOSPARC_INSTANCE_TYPE` · `CRYOSPARC_INSTANCE_REGION` · `CRYOSPARC_PROJECT_DIR` · `CRYOSPARC_DEFAULT_MOVIE_DIR` · `CRYOSPARC_MOVIES_S3` · `CRYOSPARC_DIRECT_PORT` · `AUTO_STOP_AFTER_MINUTES` · `EPU_OUTPUT_DIRS` · `EPU_HOST` · `EPU_PORT` · `CRYOEM_POLL_INTERVAL`

### 4.4 Drug Discovery / IND
`BENCHLING_API_KEY` 🔑 · `BENCHLING_TENANT` · `BIOMATE_INTERNAL_KEY` 🔑 · `BIOMATE_REQUIRE_AUTH` · `MODAL_REGULATORY_LLM_ENDPOINT` · `REGULATORY_LLM_ADAPTER` · `REGULATORY_LLM_ADAPTER_NAME` · `REGULATORY_LLM_FRONTIER_MODEL` · `REGULATORY_LLM_TIMEOUT_S` · `VLLM_BASE_URL` · `GOOGLE_API_KEY` 🔑 · `VOYAGE_API_KEY` 🔑 · `ZHIPU_API_KEY` 🔑 · `BIOGRID_ORCS_KEY` 🔑 · `BIOMATE_SIGN_AUDIT_S3_BUCKET` · `BIOMATE_SIGN_AUDIT_S3_PREFIX` · `BIOMATE_SIGN_AUDIT_RETAIN_DAYS`

### 4.5 合规 / 电子签名
`BIOMATE_AUDIT_STRICT` · `BIOMATE_ESIG_REQUIRED` · `BIOMATE_ESIG_KEY` 🔑 · `BIOMATE_REQUIRE_ENCRYPTED_ESIG`

### 4.6 邮件 / OAuth / 通知 / 支付
邮件: `EMAIL_HOST` · `EMAIL_PORT` · `EMAIL_USER` 🔑 · `EMAIL_PASS` 🔑 · `EMAIL_FROM` · `EMAIL_SECURE`
OAuth: `GOOGLE_CLIENT_ID` · `GOOGLE_CLIENT_SECRET` 🔑 · `GITHUB_CLIENT_ID` · `GITHUB_CLIENT_SECRET` 🔑
通知: `SLACK_BOT_URL` · `SLACK_SIGNING_SECRET` 🔑 · `WECHAT_BOT_URL` · `WECHAT_TOKEN` 🔑 · `GA4_PROD_API_SECRET` 🔑 · `GA4_DEV_API_SECRET` 🔑
支付(P2): `STRIPE_SECRET_KEY` 🔑 · `STRIPE_WEBHOOK_SECRET` 🔑 · `STRIPE_PRICE_*`(6 个 plan)· `BILLING_API_URL`

### 4.7 仪器集成
`INSTRUMENT_WATCH_DIRS` · `LCMS_WATCH_DIRS` · `LCMS_AUTO_CONVERT` · `LCMS_AGENT_URL` · `QPCR_WATCH_DIRS` · `PLATE_READER_WATCH_DIRS` · `FLOW_CYTOMETER_WATCH_DIRS`

### 4.8 模型 / 行为开关 (public)
`BIOMATE_INTENT_MODEL` · `BIOMATE_RESPONSE_MODEL` · `BIOMATE_TOOL_RANKING_MODEL` · `BIOMATE_INTENT_MODEL_PRO` · `BIOMATE_INTENT_MODEL_FLASH` · `BIOMATE_ENABLE_THINKING` · `BIOMATE_THINKING_BUDGET` · `BIOMATE_CHAT_VIA_CHAIN` · `GALAXY_AI_LLM_PROVIDER` · `BIOMATE_MEMORY_QUERY_ENRICH` · `BIOMATE_FAMILY_PRIORITIZE` · `BIOMATE_WORKFLOW_INTENT_INJECT` · `BIOMATE_WORKFLOW_INTENT_PRIORITIZE` · `ENABLE_UX_FEEDBACK` · `REQUIRE_INVITE_CODE` · `PILOT_ACCOUNT_EMAILS` · `NVIDIA_API_KEY` 🔑 · `BIOLM_API_KEY` 🔑

### 4.9 前端 Vite 客户端 (`import.meta.env`, 打包进客户端 — 严禁放密钥)
`VITE_API_URL` · `VITE_BACKEND_URL` · `VITE_ENABLE_BACKEND_SYNC` · `VITE_ENABLE_UX_FEEDBACK` · `VITE_ENABLE_UX_FEEDBACK_ADMIN`

---

## 5. 仅测试 / 开发 (🧪 dev / CI — 绝不进生产运行时)

| 变量 | 用途 |
|---|---|
| `BIOMATE_URL` | E2E 目标地址(几乎所有 e2e 文件) |
| `E2E_TEST_TOKEN` | 绕过限流的测试 token(生产留空禁用) |
| `E2E_FIXTURE_EMAIL` / `E2E_FIXTURE_PASSWORD` | 测试账号 |
| `BIOMATE_E2E_EMAIL` / `BIOMATE_E2E_PASSWORD` | 同上,真实数据上传测试 |
| `DEMO_EMAIL` / `DEMO_PASSWORD` / `DEMO_PROMPT` | 录屏 demo |
| `RUN_LIVE_EXECUTE_CONTRACT` / `REQUIRE_AWS_EXEC_200` | live 契约测试开关 |
| `CI` / `PLAYWRIGHT_CHANNEL` / `PW_OUTPUT_DIR` | Playwright 运行环境 |
| `BIOMATE_REQUIRE_AUTH` / `JWT_SECRET_KEY` / `PI_RUN_*` | IND 报告测试 |

---

## 6. ⚠️ 命名冲突 / 待规范 (Phase 0 决议项)

| 概念 | 现存名字 | 规范名(建议) | 受影响文件 |
|---|---|---|---|
| Lago 地址 | `LAGO_URL` vs `LAGO_API_URL` | **`LAGO_API_URL`** | FE `routes.ts`/`auth-service.ts`/`billing-smoke` 用 `LAGO_URL`;BE 全用 `LAGO_API_URL` |
| Redis | `REDIS_URL` vs `REDIS_HOST`+`REDIS_PORT` | **`REDIS_URL`** | FE `redis-session.ts` 用 HOST/PORT |
| AWS 区域 | `AWS_REGION` vs `AWS_DEFAULT_REGION` | **两者都设(SDK 兼容)** | 散布 FE/BE |
| 存储桶 | `S3_BUCKET_NAME` / `AWS_S3_BUCKET` / `AWS_S3_NEXTFLOW_BUCKET` / `NEXTFLOW_S3_BUCKET` | **需厘清用途**:通用 vs Nextflow 专用 | FE `routes.ts`/`s3-client.ts`,BE nextflow runners |
| Nextflow AWS 凭证 | `AWS_NF_ACCESS_KEY_ID` / `AWS_NF_SECRET_ACCESS_KEY` 独立于通用 AWS 凭证 | **确认是否需独立凭证** | FE `routes.ts`/`runs-outputs-service.ts` |
| 计费内部 key | `BILLING_INTERNAL_KEY` / `BILLING_API_KEY`(同值) / `BIOMATE_INTERNAL_KEY` | **统一为 `BILLING_INTERNAL_KEY`** | `billing_router.py` 读两个;drug-discovery 用第三个 |
| Galaxy 地址 | `GALAXY_URL` vs `GALAXY_API_URL` | **`GALAXY_URL`** | 一处测试文件用 `GALAXY_API_URL` |

---

## 7. ⚠️ 已知硬编码点 (Phase 2 清理目标,引用本表规范名)

| 文件:行 | 变量 | 硬编码值 |
|---|---|---|
| `backend/start_backend.sh:37-45` | `LAGO_API_KEY` `REDIS_URL` `LAGO_API_URL` `JAVA_BILLING_SERVICE_URL` | 真实生产值 |
| `frontend/server/routes.ts:5805,8148` | `LAGO_URL` | `http://35.86.137.71:3000` |
| `frontend/e2e/billing-smoke.e2e.ts:18-19` | `LAGO_URL` `LAGO_API_KEY` | IP + 真实 key |
| `backend/scripts/backfill_billing_customers.py:29` | `JAVA_BILLING_SERVICE_URL` | `http://35.86.137.71:8080` |
| `.env.example:74` | `LAGO_URL` | `http://35.86.137.71:3000` |

---

## 维护

新增 env 变量时,**必须**在此表登记(scope / set_in / consumer),并同步更新 `.env.example` 与 `.env.ec2.example`。CI 护栏(Phase 5)会校验代码中出现的变量名是否已在本表登记。
</content>
