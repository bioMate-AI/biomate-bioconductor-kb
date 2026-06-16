# 会话总结:CI/CD 外部环境变量方案 + next-phase 部署到 TEST 全流程验证

日期:2026-06-16
分支:`integration/next-phase`
相关合并:`457ec9759`(Step 2 加载器)、`f18fcdb8b`(deploy.sh 流程修复)、`9e3e99e24`(一键启停)

---

## 0. 目标(用户原始诉求)

> "很多变量只维护在本地,本地能用,CICD 自动部署就失败 —— 因为这些变量为了安全不可能走 GitHub 推送。要一个 GitLab 配置变量式的外部配置,让 AWS CICD 自动部署时能正常读取。"

落地选型:**AWS Secrets Manager**(= GitLab CI Variables 的等价物)。

---

## 1. 外部环境变量方案(已完成 + 实测)

**机制:** 运行时变量的**值**存在 AWS Secrets Manager `<env>/biomate/galaxy-env`;仓库只放变量**名**(`deploy/biomate.env.manifest`,69 个 / 14 个标 `required`)。部署机用自己的 **EC2 实例角色**(`BioMateEc2DeployRole`,有 `secretsmanager:GetSecretValue`,作用域 `dev/*`+`test/*`)拉取,**值不经过 GitHub**。

| 脚本 | 作用 |
|---|---|
| `scripts/load_env_from_secrets.sh` | 在主机上跑,把 secret 逐键 upsert 进 `/opt/biomate/.env`(保留主机独有键),失败 fail-fast |
| `scripts/put_env_to_secret.sh` | 写入侧(需 `PutSecretValue`),从 .env 构建 JSON 写 secret(整体替换,排除 VITE_*/PORT 等) |
| `scripts/deploy.sh` Step 2 | **本会话接入**:经 SSM base64 投递 loader,用实例角色拉取并 upsert;secret 缺失则大声告警回退主机 .env |

**`deploy.sh` 全流程已端到端实测**(`AWS_PROFILE=biomate-admin bash scripts/deploy.sh test sha-9dee60cb2c6a`,7 步全绿):备份 → **从 Secrets Manager 灌 21 变量** → 投递 compose → ECR 登录 → 拉镜像 → down/up 重建 → 健康检查。这正是 GHA 构建完镜像后会执行的同一套逻辑。

**deploy.sh 流程修复(`f18fcdb8b`):**
- `ssm_run` 改为 base64 编码命令 —— 多行/引号/`$()` 此前会撞 AWS CLI `commands=[...]` shorthand 解析。
- Step 3 改为经 SSM 投递**本地** `deploy/docker-compose.deploy.yml` —— 原来从 `main` curl,但该文件在 `integration/next-phase` 不在 main,导致每次 404 中止。

---

## 2. next-phase 部署到专用 TEST 机(已完成)

实例 `i-0482a6fa98c6f301a`(tag `Env=test`),跑手动构建镜像 `sha-9dee60cb2c6a`(GHA 被 billing 封,手动构建绕开)。踩坑与修复:

| 问题 | 根因 | 修复 |
|---|---|---|
| galaxy crash(NoVersionTableError) | override 把 galaxy 指向了 Node app 的库 | **Plan B**:建空库 `galaxymodel`,`GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION` 指过去 |
| 前端 crash(`relation execution_runs does not exist`) | test 前端库缺 drizzle 基础表(execution_runs + ltm/project 共 17 张);drizzle push 是交互式,管道喂不进 | **`drizzle-kit export`** 导出全量 DDL → 幂等应用(已存在跳过)→ 13→30 张表 → 19 个迁移全过 |
| docker 误报 unhealthy | app 强制 HTTP→HTTPS,healthcheck 明文探测被 301 | healthcheck 加 `X-Forwarded-Proto: https`(实例 compose + 仓库 `deploy/docker-compose.deploy.yml` 均已修) |
| 页面白屏(JS/CSS 500) | 生产 CORS 默认白名单只有 `https://biomate.ai`;Vite 的 crossorigin 资源带 Origin 被拒 | secret 加 `CORS_ORIGINS=https://test.stage-public.biomate.ai`([security-config.ts:54](../frontend/server/security-config.ts#L54)) |
| Redis ENOTFOUND | test 机解析不到 AWS 计费 ElastiCache | 起本地 `biomate-redis` 容器,secret 的 `REDIS_URL` 指向它 |
| AI unavailable | secret 缺 `ANTHROPIC_API_KEY` | 从 dev secret 复用(账号级 key) |

**最终验证(经 caddy 真实入口 + 用户浏览器):** 页面正常渲染、`/api/health` `status:ok` / `galaxy connected` / `ai:ok`、Redis `Connected`、三容器全 healthy。

**test secret 现状:** 21 个变量,14/14 必需项齐全。

---

## 3. 访问方式

`https://test.stage-public.biomate.ai`(caddy → frontend:3000;Let's Encrypt 证书有效,2026-09 到期)。

DNS 那条 A 记录指向已失效旧 IP(`52.37.216.49`),用户选择**本机 hosts 覆盖**(`<IP> test.stage-public.biomate.ai`)访问,不动共享 DNS。

---

## 4. 成本与一键启停(已完成,`9e3e99e24`)

常开 ~$50/月(EC2 t3.medium + RDS db.t3.micro + 公网 IPv4)。**最优 = 停机不删除**:停机 ~$6-8/月,保留所有数据/配置,几分钟恢复。

```bash
AWS_PROFILE=biomate-admin bash scripts/test_env.sh {start|stop|status}
```
详见 [20260616_TEST_ENV_LIFECYCLE.md](20260616_TEST_ENV_LIFECYCLE.md)。**当前已 stop**(本会话结束时用户要求停掉省费用)。

⚠️ 公网 IP 非 EIP,每次 stop/start 会变;`start` 会打印新 IP + hosts 更新命令。

---

## 5. 已知未闭环 / 下一步

1. **GHA billing-blocked(唯一阻塞自动触发的项)** —— push tag 不产出镜像(`sha-81d8ed9` 实测无产出)。费用恢复后:推个 tag 验证 `push → 构建 → 自动调 deploy.sh` 最后一环。这是 ECR 镜像构建 + GHA→deploy.sh 触发两个环节,deploy.sh 本体已验证。
2. **staging/prod 未配** —— 实例角色对 `staging/*`、`prod/*` secret 无权限,secret 也不存在;各自需配自己的 `<env>/biomate/galaxy-env`(含各自域名的 `CORS_ORIGINS`)。
3. **TEST 的 DNS/EIP** —— 想免 hosts:给实例分配 EIP(固定 IP)再把 Route53 `test.stage-public` A 记录指过去。
4. **写 secret 需 biomate-admin** —— 默认 galaxy-dev profile 读不了/写不了 Secrets Manager;管理 secret 用 `aws sso login --profile biomate-admin`。

---

## 关键资源速查

- test 实例:`i-0482a6fa98c6f301a`(us-west-2,Env=test)
- RDS:`biomate-test-galaxy`(db.t3.micro;galaxy 用 `galaxymodel` 库,Node app 用 `galaxy` 库)
- 镜像:`399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/dev-{backend,frontend}:sha-9dee60cb2c6a`
- secret:`test/biomate/galaxy-env`(21 变量)、`dev/biomate/galaxy-env`(64 变量)
- 域名:`test.stage-public.biomate.ai`
