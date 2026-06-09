# GitHub Environments 配置指南

## 概述

本文档说明如何为 bioMate-AI/biomate 配置 GitHub Environments，以实现基于 tag 的环境隔离和审批流程。

## 环境配置

### 前提条件

- GitHub 组织管理员权限或仓库管理员权限
- 访问 https://github.com/bioMate-AI/biomate/settings/environments

## 配置步骤

### 1. 创建 Development 环境

**访问**: https://github.com/bioMate-AI/biomate/settings/environments/new

**配置参数**:

```
Environment name: development
```

**Environment protection rules**:
- ☐ Required reviewers (不勾选 - 无需审批)
- ☐ Wait timer (不勾选)
- ✅ Deployment branches: Selected branches and tags
  - 添加 tag pattern: `dev-v*`

**Environment secrets** (配置以下 secrets):

无需额外 secrets，使用 repository 级别的 secrets：
- `AWS_ACCESS_KEY_ID` (如果不使用 OIDC)
- `AWS_SECRET_ACCESS_KEY` (如果不使用 OIDC)

**说明**: Development 环境用于日常开发测试，无需审批，推送 `dev-v*.*.*` tag 即可触发部署。

---

### 2. 创建 Staging 环境

**访问**: https://github.com/bioMate-AI/biomate/settings/environments/new

**配置参数**:

```
Environment name: staging
```

**Environment protection rules**:
- ✅ Required reviewers: 1 reviewer
  - 添加审批人员（建议：Tech Lead 或 Senior Developer）
- ☐ Wait timer (不勾选)
- ✅ Deployment branches: Selected branches and tags
  - 添加 tag pattern: `beta-v*`

**Environment secrets**:

可选：如果 staging 环境使用不同的 AWS 账户，配置以下 secrets：
- `AWS_ACCESS_KEY_ID_STAGING`
- `AWS_SECRET_ACCESS_KEY_STAGING`
- `ECR_REGISTRY_STAGING` (如果不同)

**说明**: Staging 环境用于预发布测试，需要 1 人审批，推送 `beta-v*.*.*` tag 后需等待审批通过才能构建。

---

### 3. 创建 Production 环境

**访问**: https://github.com/bioMate-AI/biomate/settings/environments/new

**配置参数**:

```
Environment name: production
```

**Environment protection rules**:
- ✅ Required reviewers: 2 reviewers
  - 添加审批人员（建议：CTO + Tech Lead，或 2 个 Senior Developers）
- ✅ Wait timer: 5 minutes
  - 即使审批通过，也会等待 5 分钟后才开始部署（用于紧急取消）
- ✅ Deployment branches: Selected branches and tags
  - 添加 tag pattern: `release-v*`

**Environment secrets**:

如果 production 环境使用不同的 AWS 账户，配置以下 secrets：
- `AWS_ACCESS_KEY_ID_PROD`
- `AWS_SECRET_ACCESS_KEY_PROD`
- `ECR_REGISTRY_PROD`
- `ECR_REPO_BACKEND_PROD`
- `ECR_REPO_FRONTEND_PROD`

**说明**: Production 环境用于正式发布，需要 2 人审批 + 5 分钟等待时间，提供最高级别的保护。

---

## 使用方法

### Development 部署

```bash
# 无需审批，直接触发构建
git tag dev-v0.9.0
git push origin dev-v0.9.0
```

### Staging 部署

```bash
# 需要 1 人审批
git tag beta-v1.0.0-rc1
git push origin beta-v1.0.0-rc1

# 推送后，访问 GitHub Actions 页面，审批人员会收到通知
# 审批通过后自动开始构建
```

### Production 部署

```bash
# 需要 2 人审批 + 5 分钟等待
git tag release-v1.0.0
git push origin release-v1.0.0

# 推送后，访问 GitHub Actions 页面
# 需要 2 个审批人员批准
# 审批通过后，自动等待 5 分钟（可用于紧急取消）
# 5 分钟后自动开始构建
```

---

## 审批流程

### 审批人员如何审批

1. 推送 tag 后，审批人员会收到 GitHub 通知邮件
2. 访问 https://github.com/bioMate-AI/biomate/actions
3. 点击正在等待审批的 workflow run
4. 点击 "Review deployments" 按钮
5. 选择要审批的环境，点击 "Approve and deploy" 或 "Reject"

### 查看审批状态

```bash
# 通过 GitHub Actions 页面查看
https://github.com/bioMate-AI/biomate/actions

# 或通过 gh CLI 查看
gh run list --limit 5
gh run view <run-id>
```

---

## 环境变量管理

### Repository-level Secrets (全局)

访问: https://github.com/bioMate-AI/biomate/settings/secrets/actions

推荐配置：
- `AWS_ACCOUNT_ID` - AWS 账户 ID
- `AWS_REGION` - AWS 区域 (us-west-2)

### Environment-specific Secrets

如果不同环境使用不同的 AWS 账户/资源：

**Development**:
- 无需额外 secrets，使用全局 secrets

**Staging**:
- `AWS_ACCOUNT_ID_STAGING`
- `ECR_REGISTRY_STAGING`

**Production**:
- `AWS_ACCOUNT_ID_PROD`
- `ECR_REGISTRY_PROD`
- `ECR_REPO_BACKEND_PROD`
- `ECR_REPO_FRONTEND_PROD`

---

## Workflow 自动识别逻辑

workflows 会根据 tag 前缀自动选择环境：

```yaml
environment:
  name: ${{ startsWith(github.ref, 'refs/tags/release-v') && 'production' || startsWith(github.ref, 'refs/tags/beta-v') && 'staging' || 'development' }}
```

**匹配规则**:
- `refs/tags/release-v*.*.*` → `production`
- `refs/tags/beta-v*.*.*` → `staging`
- `refs/tags/dev-v*.*.*` → `development`

---

## 测试配置

### 测试 Development 环境

```bash
cd /Users/renyuankai/work/biometa/biomate
git tag dev-v0.9.1-test
git push origin dev-v0.9.1-test

# 访问 https://github.com/bioMate-AI/biomate/actions
# 应该看到 workflow 直接运行，无需审批
```

### 测试 Staging 环境

```bash
git tag beta-v1.0.0-rc1-test
git push origin beta-v1.0.0-rc1-test

# 应该看到 workflow 等待 1 个审批人员批准
```

### 测试 Production 环境

```bash
git tag release-v1.0.0-test
git push origin release-v1.0.0-test

# 应该看到 workflow 等待 2 个审批人员批准
# 审批通过后等待 5 分钟再开始
```

---

## 故障排除

### 问题：Workflow 未触发

**检查**:
1. Tag 格式是否正确 (`dev-v*.*.*`, `beta-v*.*.*`, `release-v*.*.*`)
2. Workflow 文件中的 `on.push.tags` 是否匹配
3. GitHub Actions 是否启用

```bash
# 检查 workflow 配置
cat .github/workflows/backend-image.yml | grep -A 5 "on:"

# 检查 tag
git tag -l "*-v*"
```

### 问题：Environment 未找到

**原因**: GitHub Environments 尚未创建

**解决**: 按照本文档第 2 节创建相应环境

### 问题：审批人员未收到通知

**检查**:
1. GitHub 通知设置: https://github.com/settings/notifications
2. 审批人员是否被正确添加到 Environment protection rules
3. 审批人员是否有仓库访问权限

---

## 成本分析

### 优化前
- 每次 push 触发构建
- ~440 builds/月
- ~11,000 分钟/月
- **$180-220/月**

### 优化后
- 仅 tag 触发构建
- ~50 builds/月（假设每周 2-3 个 release）
- ~625 分钟/月
- **$6-12/月**

**节省**: ~90% ($126-154/月)

---

## 相关文档

- [CICD_OPTIMIZATION_ANALYSIS.md](./CICD_OPTIMIZATION_ANALYSIS.md) - CI/CD 优化分析
- [GitHub Environments 官方文档](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Deployment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#deployment-protection-rules)

---

## 联系人

如有问题，请联系：
- Tech Lead: [您的名字]
- DevOps Team: [团队邮箱]
- 或在 GitHub Issues 中提问: https://github.com/bioMate-AI/biomate/issues
