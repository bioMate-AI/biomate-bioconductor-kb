# BioMate 外部环境变量配置方案

> 日期: 2026-06-12
> 目标: 把环境变量改造成"仓库内只引用变量名、变量值在外部平台配置"的形式
> (等价于 GitLab CI/CD Variables 的网页配置模式),并彻底清除仓库内的硬编码密钥。

---

## 0. 目标与原则

1. **仓库内零密钥值** —— 代码、脚本、模板、文档里只出现变量**名**和占位符,绝不出现真实的 key / IP / 连接串。
2. **值全部外置** —— 真实值只存在于三个外部位置(见 §1),仓库通过名字引用。
3. **快速失败** —— 必需变量缺失时**硬报错**,禁止 `process.env.X || '硬编码兜底值'` 这种静默回退(回退值本身就是泄漏)。
4. **单一事实源** —— 一个变量在全项目只有一个规范名,一份权威清单。
5. **防回归** —— pre-commit + CI 自动扫描,阻止密钥再次被提交。
6. **先轮换再清理** —— 已泄漏的密钥进了 git 历史,删 HEAD 没用,必须先轮换作废。

### GitLab 模式 → GitHub 对应关系

| 你说的 GitLab 网页配置 | 本项目对应物 |
|---|---|
| CI/CD Variables(masked / protected) | **GitHub Actions Secrets**(`${{ secrets.X }}`) |
| CI/CD Variables(普通,不脱敏) | **GitHub Actions Variables**(`${{ vars.X }}`) |
| Protected / 按环境隔离 | **GitHub Environments**(test / staging / production)+ 环境级 Secrets |
| 运行时主机上的值 | **EC2 主机文件** `/opt/biomate/shared/.env.ec2`(后续可升级到 AWS SSM/Secrets Manager) |

---

## 1. 配置分层(三个外部存储)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. GitHub 仓库设置 (Settings → Secrets and variables)        │
│    ├─ Secrets   : 所有敏感值(API key、JWT、AWS、DB、billing) │
│    └─ Variables : 非敏感值(URL、region、bucket 名、feature)  │
│    └─ Environments: test/staging/prod 各自一套(值不同)       │
│         → CI/CD(.github/workflows/*)消费                     │
└───────────────────────┬─────────────────────────────────────┘
                        │ deploy.sh 注入
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. EC2 主机 /opt/biomate/shared/.env.ec2  (chmod 600)        │
│    运行时真实值,带外设置(不进仓库)                          │
│    [推荐升级] AWS SSM Parameter Store / Secrets Manager       │
│         → 容器运行时消费                                       │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 3. 本地开发 .env (已被 .gitignore)                           │
│    开发者从 .env.example 复制后自填                            │
└─────────────────────────────────────────────────────────────┘
```

仓库内只保留:`.env.example`(占位符)、变量 schema、代码里的 `process.env.X` / `os.environ["X"]` 引用。

---

## 2. 当前问题清单(改造对象)

### 2.1 🔴 代码/脚本里的真实密钥(必须先轮换再删)

| 文件 | 行 | 问题 |
|---|---|---|
| `backend/start_backend.sh` | 37–45 | `export` 真实 `LAGO_API_KEY` / `REDIS_URL` / `LAGO_API_URL` / `JAVA_BILLING_SERVICE_URL` |
| `frontend/server/routes.ts` | 5805, 8148 | `process.env.LAGO_URL \|\| 'http://35.86.137.71:3000'` |
| `frontend/e2e/billing-smoke.e2e.ts` | 18–19 | 硬编码 IP + `LAGO_API_KEY` 兜底值 |
| `backend/scripts/backfill_billing_customers.py` | 29 | `JAVA_BILLING_SERVICE_URL` 默认 IP |
| `.env.example` | 74 | `LAGO_URL=http://35.86.137.71:3000`(模板里塞了真 IP) |
| `docs/**`(数十处) | — | `LAGO_API_KEY`、`BILLING_INTERNAL_KEY`、Redis 端点明文 |
| `CLAUDE.md` | billing 段 | 同上 |

### 2.2 🟠 deploy.sh 合并 bug

`scripts/deploy.sh:237` `cat .env.old /tmp/.env.secrets | sort -u > .env.merged`:
- 同 key 新旧值不同 → 两行都保留(重复 key,行为未定义)
- `sort -u` 把 .env 打乱成字母序
- 注释声称 "secrets take precedence",实际不成立

### 2.3 🟡 变量命名不一致

| 概念 | 出现过的名字 | 规范名(建议) |
|---|---|---|
| Lago 地址 | `LAGO_URL` / `LAGO_API_URL` | **`LAGO_API_URL`** |
| Redis | `REDIS_URL` / `REDIS_HOST`+`PORT`+`PASSWORD` | **`REDIS_URL`** |
| 数据库 | `DATABASE_URL` / `DB_HOST`+`DB_PORT`+… | **`DATABASE_URL`** |
| Java billing | `JAVA_BILLING_SERVICE_URL` | 保持 |

三处密钥清单(`deploy.yml` env 块 / `deploy.sh` / `.env.ec2.example`)互不一致,需对齐成同一份。

---

## 3. 实施阶段

### Phase 0 — 建立权威变量清单(地基)

产出 `docs/ENV_REGISTRY.md`(或 `config/env.schema.json`),逐变量登记:

| 字段 | 含义 |
|---|---|
| name | 规范变量名 |
| scope | secret / public |
| required | 是否必需 |
| consumer | frontend / backend / both |
| set_in | GH Secret / GH Variable / EC2 host / dev-only |
| default | 非密钥的默认值(若有) |

这份清单是后续所有改动的单一事实源。

### Phase 1 — 密钥轮换(安全优先,先做)

已泄漏(进了 git 历史,永久作废):
- `LAGO_API_KEY = 01b71711-…`
- `BILLING_INTERNAL_KEY = w498JF1dufdEd9O8…`
- Redis ElastiCache 端点、`35.86.137.71` 系列 IP(IP 改不了但应视为已知)

动作:
1. 在 Lago 生成新 API key;重新生成 `BILLING_INTERNAL_KEY`(`openssl rand -base64 32`)。
2. 新值只写入 GitHub Secrets + EC2 主机文件。
3. 更新 Lago / Java billing / backend 三端使其用新值,验证 `/api/billing/usage` 正常。

> 注:billing 改动后需按 CLAUDE.md 跑 `sync_to_dev.sh` 并在 dev 验证。

### Phase 2 — 删除代码/脚本里的硬编码

- `start_backend.sh`:删除所有 `export <secret>=<真值>`,改为 `source /opt/biomate/shared/.env.ec2`(本地开发则 source 本地 `.env`);缺必需变量直接 `exit 1`。
- `routes.ts` ×2:删 `|| 'http://35.86.137.71:3000'`,改为读 `LAGO_API_URL`,未设置则启动期报错(见 Phase 3 的 config loader)。
- `billing-smoke.e2e.ts`:删硬编码 key/IP,纯读 env;未设置时 `test.skip`(已是文档约定行为)。
- `backfill_billing_customers.py`:删 IP 默认值,缺失则报错退出。
- `.env.example` 第 74 行:`LAGO_API_URL=`(留空占位)。
- 文档脱敏:把 `docs/**` 和 `CLAUDE.md` 里的真值替换为 `<set-in-github-secrets>` 占位 + 指向本方案。

### Phase 3 — 集中式 fail-fast 配置加载器(核心)

让"仓库只引用名字"成为强制约束 —— 因为根本不存在兜底值可回退。

- **前端** `frontend/server/config.ts`:启动时一次性读取并用 zod 校验所有 env,必需缺失即 throw。其余代码只 `import { config }`,不再散落 `process.env.X || …`。
- **后端** `backend/lib/galaxy/ai/config.py`(或现有 settings):`os.environ["X"]` 必需项缺失即 raise;可选项给显式默认。

收益:任何"忘记在外部配置变量"的情况都会在启动期暴露,而不是悄悄用一个写死的生产值。

### Phase 4 — 修 deploy.sh 合并 + 对齐变量集

- 用逐 key upsert 替换 `sort -u`:
  ```bash
  # 对每个 secret key:先从旧 .env 删除该 key 的行,再追加新行
  while IFS='=' read -r k _; do grep -v "^${k}=" .env > .env.tmp && mv .env.tmp .env; done < secrets
  cat secrets >> .env
  ```
- 把 `deploy.yml` env 块、`deploy.sh` 注入列表、`.env.ec2.example` 收敛为同一份变量清单(由 Phase 0 的 registry 生成)。

### Phase 5 — 防回归护栏

- **pre-commit**:`gitleaks`(单二进制,不依赖 brew)或 `detect-secrets`(`pip install`)扫描暂存区。
- **CI**(`ci-tests.yml` 加 job):
  - `gitleaks detect` 全仓扫描
  - 自定义 grep 拦截:`|| ['\"]http`、`35\.86\.137\.71`、`sk-ant-api03-` 真值模式出现在 `frontend/`、`backend/` 源码即 fail。
- 注:本机 brew 已损坏(不认 macOS 26),装工具走 pip / 直接下二进制。

### Phase 6 —(推荐)升级到 AWS SSM / Secrets Manager

把运行时密钥从扁平 `.env.ec2` 文件升级为 **SSM Parameter Store (SecureString)** 或 **Secrets Manager**:
- EC2 instance role 按 IAM 最小权限读取
- 容器启动 entrypoint 拉取并模板化为 env
- 好处:加密、审计、可轮换、按环境/服务隔离 —— 这才是完整意义上的"外部配置"
- 扁平 `.env.ec2` 作为过渡形态保留

---

## 4. 推荐的 GitHub 配置矩阵(Phase 0 产出示例)

> 真实值在 GitHub 网页 Settings → Secrets and variables → Actions 配置,按 test/staging/production 三个 Environment 分别设置。

### Secrets(敏感)

`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `NVIDIA_API_KEY`, `BIOLM_API_KEY`,
`JWT_SECRET`, `SESSION_SECRET`, `ENCRYPTION_KEY`, `CSRF_SECRET`,
`BILLING_INTERNAL_KEY`, `LAGO_API_KEY`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`DATABASE_URL`, `GALAXY_API_KEY`, `REDIS_URL`

### Variables(非敏感,可用 `${{ vars.X }}`)

`AWS_REGION`, `S3_BUCKET_NAME`, `GALAXY_URL`, `LAGO_API_URL`, `JAVA_BILLING_SERVICE_URL`,
`JAVA_BILLING_ENABLED`, `VCPU_HOUR_QUOTA`, `CORS_ORIGINS`, `NODE_ENV`

---

## 5. 执行顺序建议

1. **Phase 1(轮换)** — 安全第一,先做,独立可验证。
2. **Phase 0(registry)** — 建清单,为后续提供事实源。
3. **Phase 3(config loader)** — 上 fail-fast 框架。
4. **Phase 2(删硬编码)** — 在有 loader 兜底报错后再删,安全。
5. **Phase 4(deploy.sh)** — 修合并 + 对齐。
6. **Phase 5(护栏)** — 锁死,防回归。
7. **Phase 6(SSM)** — 行有余力时升级。

> ⚠️ 注意:git 历史里的旧密钥即使全部删除也仍可被检出。Phase 1 轮换是唯一真正止血的手段;如需彻底清史可后续用 `git filter-repo`,但那会改写历史、影响所有协作者,需单独评估。

---

## 6. 待你拍板的决策点

1. **轮换范围** —— 现在就轮换 `LAGO_API_KEY` + `BILLING_INTERNAL_KEY`,还是先只做代码外置、轮换另行安排?
2. **是否上 SSM/Secrets Manager(Phase 6)** —— 还是先停在"GitHub Secrets + EC2 .env 文件"这一层?
3. **git 历史清洗** —— 是否需要 `git filter-repo` 彻底抹除历史中的密钥(影响所有 clone)?
4. **落地节奏** —— 一次性全做,还是按 Phase 分 PR 推进?
</content>
