# next-phase TEST 环境:成本与一键启停

2026-06-16。专用 test 实例运行的是 next-phase(下个版本),用于在不影响线上 dev 的前提下验证。

## 资源与成本

| 资源 | 规格 | 常开月费(约) | 停机后 |
|---|---|---|---|
| EC2 `i-0482a6fa98c6f301a` | t3.medium | ~$30 | 仅 EBS 存储 ~$2-3 |
| 公网 IPv4(非 EIP) | — | ~$3.6 | $0(停机释放) |
| RDS `biomate-test-galaxy` | db.t3.micro,单 AZ | ~$12 | 仅存储 ~$2-3 |
| Secrets Manager 等 | — | ~$1-2 | 不变 |
| **合计** | | **~$50/月** | **~$6-8/月** |

## 最优策略:停机(stop),不要删除(terminate)

- **删除**会省到 0,但下次要重建一整套(RDS 库 `galaxymodel`、前端 drizzle schema、`/opt/biomate/.env`、secret),是几小时的活。
- **停机**只停计算、保留所有存储(EBS + RDS),容器有 `restart: unless-stopped` 会在开机后自动回来。几分钟恢复,省 ~$40/月。

## 一键启停

```bash
# 用有 EC2/RDS 启停权限的身份(biomate-admin)
AWS_PROFILE=biomate-admin bash scripts/test_env.sh stop     # 闲时停,省钱
AWS_PROFILE=biomate-admin bash scripts/test_env.sh start    # 用时起(先 RDS 后 EC2)
AWS_PROFILE=biomate-admin bash scripts/test_env.sh status   # 看状态
```

`start` 流程:启动 RDS → 等 available → 启动 EC2 → 等 running → 打印新 IP + hosts 更新命令。容器开机自起,给 ~2 分钟。

## ⚠️ IP 会变

公网 IP 不是 Elastic IP,**每次 stop/start 都会变**。`start` 会打印新 IP 和现成的 hosts 更新命令:

```bash
sudo sed -i '' '/test.stage-public.biomate.ai/d' /etc/hosts
echo "<新IP> test.stage-public.biomate.ai" | sudo tee -a /etc/hosts
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

一劳永逸方案:把 Route53 那条 stale A 记录(`test.stage-public.biomate.ai → 52.37.216.49`,已失效)改成走域名;但 IP 会变,所以更好的是给实例分配 EIP 后再绑 DNS。需要的话单独做。

## 访问

`https://test.stage-public.biomate.ai`(caddy → frontend:3000;Let's Encrypt 证书有效,2026-09 到期)。

## 关联

CI/CD 外部环境变量(Secrets Manager)方案见记忆 `cicd-env-secrets-manager`;deploy.sh 全流程已实测;唯一未闭环项为 GHA billing。
