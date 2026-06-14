# CI/CD 环境变量流水线 (工业化外置配置)

> 日期: 2026-06-13 · 配套: [ENV_REGISTRY.md](ENV_REGISTRY.md) · [20260613_ENV_FILES_CONFLICT_AUDIT.md](20260613_ENV_FILES_CONFLICT_AUDIT.md)
> 目标: AWS CI/CD 自动部署时能正确读取环境变量,变量名在仓库、值在 GitHub 外部配置。

---

## 1. 架构(值从哪来,到哪去)

```
GitHub 网页 Settings → Secrets and variables → Actions
  ├─ Secrets   (敏感: API key / JWT / AWS / billing)
  └─ Variables (非敏感: URL / region / bucket / flag)
        │  deploy.yml: toJSON(secrets) + toJSON(vars) 全量透传(无需手维护列表)
        ▼
  scripts/render_env_manifest.sh
        │  按 deploy/biomate.env.manifest(仓库内,只有变量名)渲染
        │  · 有值才写 · 必需缺失则 fail-fast · OIDC 部署凭证已 unset 防泄漏
        ▼
  /tmp/managed.env (runner 上,临时)
        │  scripts/deploy.sh 用 OIDC 部署角色凭证经 S3+SSM 传输
        ▼
  EC2 /opt/biomate/.env  ← 逐 key upsert(托管值覆盖;主机独有 key 保留)
        │  docker-compose.deploy.yml: env_file 注入
        ▼
  galaxy-backend-deploy + frontend-deploy 容器
```

**单一事实源 = `deploy/biomate.env.manifest`**。增删一个生产变量 = 改 manifest 一行 + 在 GitHub 网页设值。workflow 不用动。

---

## 2. 关键设计点(为什么这么做)

| 设计 | 原因 |
|---|---|
| `toJSON(secrets/vars)` 全量透传 | 避免 deploy.yml 里手维护 17 行 `X: ${{ secrets.X }}` 与现实漂移 |
| manifest 决定哪些落地 | 只有 manifest 列出的变量写入 .env;CI-only(E2E token)不污染生产 |
| 渲染前 unset OIDC 凭证 | 否则没配应用 AWS key 时,会把部署角色的临时凭证误写进应用 .env |
| 渲染 / 传输 拆两个凭证上下文 | `AWS_ACCESS_KEY_ID` 一名两义(应用值 vs 部署角色),同进程会互相覆盖 |
| 逐 key upsert(非 `sort -u`) | 修复旧 bug:同 key 新旧值并存 + 文件被打乱 |
| 主机独有 key 保留 | `EMAIL_PASS`/`GALAXY_MASTER_API_KEY`/`LAGO_WEBHOOK_SECRET` 只在 EC2,不进 CI |
| opt-in 闸门 + fail-fast | 没配任何 Secret → 退回旧行为不破坏;配了却漏必需项 → 部署失败 |

---

## 3. 首次配置:把值灌进 GitHub

值来自 `env-files/`(私有,已 gitignore)。用 `gh` 批量设置:

```bash
# Secrets(敏感)——逐个 set,值从 env-files/ 取(示例)
gh secret set ANTHROPIC_API_KEY     --body "$(grep '^ANTHROPIC_API_KEY='   env-files/frontend/.env | cut -d= -f2-)"
gh secret set JWT_SECRET            --body "<生成的强密钥 openssl rand -base64 32>"
gh secret set SESSION_SECRET        --body "..."
gh secret set BILLING_INTERNAL_KEY  --body "..."
gh secret set DATABASE_URL          --body "<生产 RDS 连接串>"
gh secret set GALAXY_API_KEY        --body "..."
gh secret set AWS_ACCESS_KEY_ID     --body "<应用 IAM 用户 key>"
gh secret set AWS_SECRET_ACCESS_KEY --body "..."
gh secret set LAGO_API_KEY          --body "<生产 Lago key>"
gh secret set REDIS_URL             --body "<生产 ElastiCache URL>"
# ... 其余 secret 同理(ENCRYPTION_KEY/CSRF_SECRET/GALAXY_JWT_SECRET/OPENAI/GEMINI)

# Variables(非敏感)
gh variable set GALAXY_URL              --body "https://..."
gh variable set AWS_REGION              --body "us-west-2"
gh variable set S3_BUCKET_NAME          --body "galaxy-cloud-data-1760241377"
gh variable set LAGO_API_URL            --body "http://35.86.137.71:3000"
gh variable set JAVA_BILLING_SERVICE_URL --body "http://35.86.137.71:8080"
gh variable set JAVA_BILLING_ENABLED    --body "true"
gh variable set NODE_ENV                --body "production"
# ... CORS_ORIGINS / FORCE_HTTPS / ENABLE_HSTS / NEXTFLOW_* / POSTGRES_* 按需
```

> 完整变量清单见 `deploy/biomate.env.manifest`(`required` 标记的必须配,否则部署 fail-fast)。
> secret vs variable 的归类见 [ENV_REGISTRY.md](ENV_REGISTRY.md) §1/§2。

---

## 4. 日常:新增一个变量

1. 在 `deploy/biomate.env.manifest` 加一行(`NAME` 或 `NAME required`)。
2. `gh secret set NAME` 或 `gh variable set NAME` 设值。
3. 下次部署自动写入 `/opt/biomate/.env` 并注入容器。无需改 workflow。

> `.env.ec2.example` 由 manifest 派生(供人工填主机 .env 参考)。改 manifest 后重新生成:
> `awk '/^# ──/{print "";print;next} /^[[:space:]]*#/{next} /^[[:space:]]*$/{next} {printf "%s=\n",$1}' deploy/biomate.env.manifest`

---

## 5. 改动的文件

| 文件 | 改动 |
|---|---|
| `deploy/biomate.env.manifest` | 🆕 单一事实源:生产变量名清单 |
| `scripts/render_env_manifest.sh` | 🆕 渲染 + 必需校验 + 向后兼容 |
| `scripts/deploy.sh` | Step 2 改为消费预渲染文件 + 逐 key upsert(修 `sort -u` bug) |
| `.github/workflows/deploy.yml` | deploy 步骤改 `toJSON` 透传 + OIDC 凭证 save/unset/restore |
| `.env.ec2.example` | 由 manifest 派生,对齐 |
| `.gitignore` | 加 `env-files/`(防真实密钥误提交) |

---

## 6. 本地已验证(未部署)

- `bash -n` 语法检查:deploy.sh / render_env_manifest.sh 通过
- 渲染脚本三场景:完整必需→渲染14项 ✅ / 漏必需→fail-fast exit1 ✅ / 空→向后兼容 exit0 ✅
- 空值变量(如未配 OPENAI)正确跳过,不写空行
- 逐 key upsert:主机独有 key 保留、托管 key 替换无重复 ✅
- deploy.yml YAML 合法

> ⚠️ 尚未在真实 EC2 上跑过完整部署。首次实跑前:① 按 §3 配好 GitHub Secrets/Variables(至少全部 `required`)② 在 GitHub Actions 手动 `workflow_dispatch` 触发一次 test 环境部署观察。

---

## 7. 已知遗留(后续单独处理,不在本次范围)

- 代码内硬编码(`start_backend.sh` / `routes.ts` 的 Lago 兜底)仍在 → 见 [20260612_EXTERNAL_ENV_CONFIG_PLAN.md](20260612_EXTERNAL_ENV_CONFIG_PLAN.md) Phase 2/3。
- 已泄漏密钥轮换(按你的决定)稍后做。
- `frontend/.env` vs `backend/.env` 的值漂移(Lago/JWT/AWS)合并 → 见 [20260613_ENV_FILES_CONFLICT_AUDIT.md](20260613_ENV_FILES_CONFLICT_AUDIT.md)。
</content>
