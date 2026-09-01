# feat/compute-platform-v2 合并总结（2026-09-01）

## 合并决策

分支 `feat/compute-platform-v2` → `integration/next-phase`，46 个提交，覆盖沙箱全栈隔离（Stages 1–4）和 UX 辅助改动。

**合并原因：**
- CI 已在 PR #200 中引入 sandbox self-tests 作为 hard gate（`test_sandbox.py` + `test_it_launcher.py`），防止未来 sandbox 回归
- 三个执行面（run_code / .nf head / IT）均已验证，ECR 镜像已烘焙
- 无破坏性变更：所有沙箱代码均 flag-gated，未设 env var = 原有行为不变

---

## 关联 PR

| PR | 内容 | 状态 |
|---|---|---|
| #200 | sandbox self-tests + CI hard gate + connector L3 tests | 已合并（2026-08-31） |
| compute-platform-v2 | sandbox 全栈（Stages 1–4） + UX 改动 | 本次合并 |

---

## Domain Regression Test 结果

在 test 实例（i-0482）对 RNA-seq / WGS / CryoEM 执行域跑回归测试：全部 HTTP 200 提交成功，但随后 422 失败。

**根因：IAM 权限，不是代码回归。**

test 实例 IAM role `BioMateEc2DeployRole` 对 S3 只有读权限（`s3:GetObject`/`s3:ListBucket` on `biomate-nextflow-work/dev-sync/*`），没有写权限，Nextflow executor 预检 S3 写入时失败。

**为什么不是代码回归：**
- Stage 3-4 改动仅影响 `LocalJobRunner`（sandbox launcher 路径）
- Batch 执行路径（`NextflowJobRunner` → Fargate → Nextflow）代码未改动
- test 实例 IAM 设计上不具备 Batch workflow S3 写权限，这一约束早于本次改动
- 4 域绿灯结果（ADMET/RNA-seq/WGS/CryoEM）来自 dev 实例（i-06696b），有完整 IAM 权限

**结论：** Batch 执行路径零回归风险，可安全合并。

---

## 合并内容分类

### Sandbox 核心（Stage 1–4）

| Stage | 内容 | 验证 |
|---|---|---|
| Phase 0 | ComputeBackend/Scheduler 抽象骨架，shadow mode | ✅ |
| Stage 1 | gVisor Tier 1-3，run_code 隔离，docker-socket-proxy，narrow launcher | ✅ test 实例 |
| Stage 2 | .nf head 经 launcher 执行，static validator | ✅ test 实例 |
| Stage 3 | backend 零 raw socket（DOCKER_HOST passthrough 修复），IT 走 proxy | ✅ test 实例 |
| Stage 4 | IT Option-A（/run_it/inspect_it），shell var volume 过滤，ECR 烘焙 | ✅ test 实例 |

全文参见：[docs/20260819_SANDBOX_MODE_COMPLETE.md](20260819_SANDBOX_MODE_COMPLETE.md)

### UX 辅助改动

- 面板骨架预开放（消息流式传输时，有附件则预开 panel）
- HTML 可视化 iframe 解除 CSP/X-Frame-Options 阻断
- IT session URL polling + 文本输出内联渲染（非 iframe）
- 修复 IT entry_point URL 字段名（`target` vs `entry_point_url`）
- 修复聊天中文消息 run_code 路由
- 修复 run_code 幻觉（stop fabrication）

---

## 待完成项（合并后）

1. **GHA CI 集成**：`docker-compose.sandbox.yml` 加入 deploy matrix，受 GHA 计费阻塞，需人工触发
2. **自定义 seccomp profile**：`SANDBOX_SECCOMP_PROFILE` 接口已就绪，profile 文件未制作（可选加固）
3. **M0.2 调度器 v2**：`COMPUTE_BACKEND_V2` shadow-mode → active routing，需 4 域 E2E 验证
4. **prod 部署**：sandbox overlay 尚未部署至生产，仅 test 实例验证过

---

## 安全边界（快速参考）

| 项目 | 状态 |
|---|---|
| run_code：gVisor + uid=1000 + 网络隔离 | ✅ |
| .nf head：gVisor + uid=1000 + 网络隔离 | ✅ |
| IT 容器：镜像白名单 + argv 验证（无 gVisor） | ⚠️ 有意取舍 |
| docker socket raw 访问 | ✅ 全部移除 |
| AWS/LLM 凭证泄漏 | ✅ filter_container_env() 过滤 |
