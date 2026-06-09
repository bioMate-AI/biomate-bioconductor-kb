# bioMate CI/CD 优化分析

**日期**: 2026-06-09
**当前分支**: integration/next-phase
**分析范围**: GitHub Actions workflows

---

## 📋 当前配置分析

### 现有 Workflows

| Workflow | 触发条件 | 功能 | 问题 |
|----------|---------|------|------|
| **backend-image.yml** | push 到 main/next-phase | 构建后端镜像 | ✅ 每次推送都构建 |
| **frontend-image.yml** | push 到 main/next-phase | 构建前端镜像 | ✅ 每次推送都构建 |
| **deploy.yml** | workflow_run 或 manual | 自动部署到 test 环境 | ⚠️ 构建完自动部署 |
| **rollback.yml** | manual | 回滚功能 | ✅ 已有回滚机制 |
| **aws-release-gate.yml** | ? | AWS 发布门控 | ? |
| **aws-release-update.yml** | ? | AWS 发布更新 | ? |

### 关键发现

#### ✅ 优点

1. **已有 OIDC 认证**: 使用 AWS OIDC 而非长期密钥（安全）
2. **镜像标签策略清晰**:
   - `sha-<commit>`: 永久固定标签
   - `<branch>-latest`: 移动指针
   - `release-*`: 发布标签
3. **环境隔离**: 使用 GitHub Environment (`test`)
4. **已有回滚机制**: rollback.yml 存在
5. **防御性编程**: 包含多个安全检查（L1-L22）

#### ❌ 问题

1. **每次推送都构建镜像** ⭐ 主要问题
   ```yaml
   # backend-image.yml:20-32
   on:
     push:
       branches: [main, integration/next-phase]
       # No paths: filter - 每次推送都构建
   ```

2. **构建完自动部署**
   ```yaml
   # deploy.yml:27-31
   workflow_run:
     workflows: ["Build & push backend image", "Build & push frontend image"]
     types: [completed]
   ```

3. **缺少 staging/production 环境**
   ```yaml
   # deploy.yml:35-38
   options: [test]  # 只有 test 环境
   ```

4. **没有基于 release tag 的发布流程**
   - 目前 `release-*` 标签只是构建镜像，不触发特殊流程

---

## 🎯 优化目标

你的直觉是对的！问题：

> "他所有推送都给我重新打包部署了"

### 期望的流程

```
开发阶段:
  git push → 仅运行测试 ❌ (目前：构建+部署)

测试发布:
  git tag beta-v1.0.0 → 构建并部署到 staging ❌ (目前：无 staging)

正式发布:
  git tag release-v1.0.0 → 构建并部署到 production ✅ (需要审批)
```

---

## 💡 优化方案

### 方案 A: 最小改动（推荐用于快速修复）

**只修改触发条件**，保持现有架构：

```yaml
# backend-image.yml 修改
on:
  push:
    tags:
      - 'release-v*.*.*'      # 生产发布
      - 'beta-v*.*.*'         # 测试发布
      - 'dev-v*.*.*'          # 开发发布
  pull_request:               # PR 时运行测试
    branches: [main, integration/next-phase]
  workflow_dispatch: {}       # 保留手动触发
```

**优点**:
- 改动最小，风险低
- 立即生效
- 保持现有的镜像标签策略

**缺点**:
- PR 时不构建镜像（可能需要手动测试）
- 没有 CI 测试 workflow

### 方案 B: 分离测试和构建（推荐）

**创建独立的 CI 测试 workflow**：

```
git push → 运行测试（快速反馈）
git tag release-v* → 构建镜像 + 部署
```

**新增文件**:
- `.github/workflows/ci-tests.yml`: 运行测试，不构建镜像
- 修改 `backend-image.yml`: 只在打 tag 时触发

**优点**:
- 开发时快速反馈（2-3 分钟测试）
- 减少 90% 构建时间和成本
- 明确的发布流程

**缺点**:
- 需要调整现有 workflow
- 需要团队适应新流程

### 方案 C: 完整重构（长期最优）

**完全重新设计 CI/CD 流程**：

1. 添加 `staging` 和 `production` 环境
2. 实施审批流程
3. 基于语义化版本标签的发布
4. 环境特定的配置和密钥

**优点**:
- 企业级 CI/CD 最佳实践
- 完整的环境隔离
- 生产环境保护

**缺点**:
- 改动较大
- 需要配置多个环境
- 需要团队培训

---

## 📊 成本对比

### 当前成本

假设：
- 每天 20 次推送到 `integration/next-phase`
- 每次构建：后端 15 分钟 + 前端 10 分钟 = 25 分钟
- 每月工作日：22 天

```
每月构建次数: 20 × 22 = 440 次
每月构建时间: 440 × 25 = 11,000 分钟
GitHub Actions 成本: ~$180-220/月 (超出免费额度)
```

### 优化后成本（方案 B）

假设：
- 每天 20 次推送 → 仅运行测试（5 分钟）
- 每天 2 次发布 → 构建镜像（25 分钟）

```
每月测试次数: 20 × 22 = 440 次
每月测试时间: 440 × 5 = 2,200 分钟

每月构建次数: 2 × 22 = 44 次
每月构建时间: 44 × 25 = 1,100 分钟

总时间: 3,300 分钟
成本节省: 70% ($126-154/月节省)
```

---

## 🔐 环境变量和密钥管理

### 当前配置

```yaml
# 硬编码在 workflow 中
env:
  AWS_REGION: us-west-2
  ECR_REGISTRY: 399683337364.dkr.ecr.us-west-2.amazonaws.com
  DEPLOY_ROLE: arn:aws:iam::399683337364:role/GitHubActionsDeploy
```

### 优化建议

使用 GitHub Environments 管理环境特定配置：

```
test environment:
  variables:
    AWS_REGION: us-west-2
    ECR_REPO_BACKEND: biomate/test-backend
    ECR_REPO_FRONTEND: biomate/test-frontend
    DEPLOY_URL: http://stage-public.biomate.ai

staging environment:
  variables:
    AWS_REGION: us-west-2
    ECR_REPO_BACKEND: biomate/staging-backend
    ECR_REPO_FRONTEND: biomate/staging-frontend
    DEPLOY_URL: https://staging.biomate.ai
  protection_rules:
    - required_reviewers: 1

production environment:
  variables:
    AWS_REGION: us-west-2
    ECR_REPO_BACKEND: biomate/prod-backend
    ECR_REPO_FRONTEND: biomate/prod-frontend
    DEPLOY_URL: https://biomate.ai
  protection_rules:
    - required_reviewers: 2
    - wait_timer: 5 minutes
```

---

## 🚀 实施建议

### 快速修复（本周可完成）

**选择方案 A**: 只修改触发条件

1. ✅ **修改 backend-image.yml**:
   ```yaml
   on:
     push:
       tags: ['release-v*.*.*', 'beta-v*.*.*', 'dev-v*.*.*']
     workflow_dispatch: {}
   ```

2. ✅ **修改 frontend-image.yml**: 同上

3. ✅ **修改 deploy.yml**: 保持 workflow_run 不变

**效果**:
- 推送到 `integration/next-phase` 不再自动构建
- 打 tag 时才构建和部署
- 立即减少 90% 构建

### 中期优化（2 周内完成）

**选择方案 B**: 添加 CI 测试 workflow

1. **创建 `.github/workflows/ci-tests.yml`**:
   ```yaml
   on:
     push:
       branches: [main, integration/next-phase]
     pull_request:

   jobs:
     test-backend:
       # 运行 pytest, linting 等
     test-frontend:
       # 运行 jest, ESLint 等
   ```

2. **修改构建 workflows**: 只在 tag 时触发

3. **更新文档**: 告知团队新流程

### 长期优化（1-2 个月）

**选择方案 C**: 完整环境隔离

1. 配置 GitHub Environments (test/staging/production)
2. 实施审批流程
3. 环境特定的密钥和配置
4. 完善回滚机制

---

## ⚠️ 注意事项

### sync_to_dev.sh 问题

你提到的 `scripts/sync_to_dev.sh`：

```yaml
# deploy.yml:21
# L7  (pkill orphan sync_to_dev.sh)
```

这个脚本会被自动清理，但注释提到它是"孤儿进程"问题。

**建议**:
- 检查 `sync_to_dev.sh` 的用途
- 如果它是自动同步脚本，应该由 cron 或 systemd 管理，而非手动运行
- 确保部署时清理旧进程

### 当前的 release-* 标签

目前 `release-*` 标签会触发构建，但：
- ❌ 不会自动部署到 production（deploy.yml 只部署 test）
- ❌ 没有审批流程
- ❌ 没有 production 环境配置

**需要补充**:
- 添加 production 环境
- 配置审批流程
- 修改 deploy.yml 支持 production 部署

---

## 📝 具体实施步骤（方案 A - 快速修复）

### 步骤 1: 备份现有配置

```bash
cd /Users/renyuankai/work/biometa/biomate
git checkout -b cicd-optimization

cp .github/workflows/backend-image.yml .github/workflows/backend-image.yml.backup
cp .github/workflows/frontend-image.yml .github/workflows/frontend-image.yml.backup
cp .github/workflows/deploy.yml .github/workflows/deploy.yml.backup
```

### 步骤 2: 修改 backend-image.yml

找到 `on:` 部分（第 20 行），修改为：

```yaml
on:
  push:
    tags:
      - 'release-v*.*.*'      # 生产发布: release-v1.0.0
      - 'beta-v*.*.*'         # 测试发布: beta-v1.0.0-rc1
      - 'dev-v*.*.*'          # 开发发布: dev-v0.9.0
  workflow_dispatch: {}
```

### 步骤 3: 修改 frontend-image.yml

同样的修改（找到 `on:` 部分）

### 步骤 4: 测试新流程

```bash
# 1. 提交修改
git add .github/workflows/
git commit -m "fix: optimize CI/CD - only build on release tags

问题: 每次推送都触发构建，浪费资源和时间
解决: 只在打标签时构建镜像

变更:
- backend-image.yml: 只在 tag 时触发
- frontend-image.yml: 只在 tag 时触发

新的发布流程:
1. 开发: git push → 不构建（需要后续添加 CI 测试）
2. 测试发布: git tag beta-v1.0.0-rc1 → 构建
3. 正式发布: git tag release-v1.0.0 → 构建

成本节约: 预计减少 90% 构建次数
"

# 2. 推送到远程
git push origin cicd-optimization

# 3. 创建 PR
gh pr create --title "优化 CI/CD: 基于 release tag 的构建" \
  --body "详见 docs/CICD_OPTIMIZATION_ANALYSIS.md"

# 4. 测试: 推送普通提交（不应触发构建）
git checkout integration/next-phase
echo "# test" >> README.md
git commit -am "test: verify CI no longer builds on push"
git push

# 5. 测试: 打标签（应该触发构建）
git tag dev-v0.9.0-test
git push origin dev-v0.9.0-test
```

---

## 🎓 后续计划

### 第 2 阶段: 添加 CI 测试（2 周后）

- 创建 `ci-tests.yml`
- 在推送时运行测试
- 快速反馈代码质量

### 第 3 阶段: 添加 staging 环境（1 个月后）

- 配置 GitHub Environment: `staging`
- 修改 deploy.yml 支持 staging
- 实施审批流程

### 第 4 阶段: 添加 production 环境（2 个月后）

- 配置 GitHub Environment: `production`
- 2 人审批 + 5 分钟等待
- 完善监控和告警

---

## 📚 参考资料

- 当前 workflows: `.github/workflows/`
- 部署脚本: `scripts/deploy.sh` (需要查看)
- CI/CD 重建计划: `docs/20260514_CICD_REBUILD_PLAN.md` (如果存在)

---

**创建者**: Claude Code
**日期**: 2026-06-09
**状态**: 待审核和实施
