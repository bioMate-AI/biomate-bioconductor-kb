# BioMate Deployment Secrets 向下兼容指南

## 📋 概述

BioMate 现在支持**两种方式**管理环境变量，完全向下兼容：

### 方式 A：现有方式（不变）
- ✅ 手动在 EC2 创建 `/opt/biomate/.env`
- ✅ 继续使用当前的部署流程
- ✅ **无需任何改动**

### 方式 B：GitHub Secrets（新增）
- ✅ 在 GitHub 配置一次 Secrets
- ✅ 自动注入到部署环境
- ✅ **随时可启用，不影响现有流程**

---

## 🔄 向下兼容机制

`scripts/deploy.sh` 会自动检测：

1. **如果没有配置 GitHub Secrets** → 使用现有的 `/opt/biomate/.env`（方式 A）
2. **如果配置了 GitHub Secrets** → 合并到 `/opt/biomate/.env`（方式 B）

```bash
# deploy.sh 的逻辑
if [[ -n "$ANTHROPIC_API_KEY" ]] || [[ -n "$JWT_SECRET" ]]; then
  # 检测到 GitHub Secrets → 合并模式
  echo "Using GitHub Secrets + existing .env"
  merge_secrets_with_existing_env
else
  # 未检测到 GitHub Secrets → 兼容模式
  echo "Using existing /opt/biomate/.env (backward compatible)"
fi
```

**关键特性**：
- ✅ 不会删除现有的 `/opt/biomate/.env`
- ✅ 自动备份现有 `.env` 到 `.env.backup.YYYYMMDD_HHMMSS`
- ✅ 如果 GitHub Secrets 未配置，完全不影响现有流程
- ✅ 可以逐步迁移：先配置部分 Secrets，其余仍使用 `.env` 文件

---

## 🚀 使用方式 B：配置 GitHub Secrets

### 第一步：生成安全密钥

在本地终端运行：

```bash
# 生成所有需要的密钥
echo "JWT_SECRET=$(openssl rand -hex 32)"
echo "SESSION_SECRET=$(openssl rand -hex 32)"
echo "BILLING_INTERNAL_KEY=$(openssl rand -hex 32)"
echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "CSRF_SECRET=$(openssl rand -hex 32)"
```

### 第二步：添加 GitHub Secrets

访问：https://github.com/bioMate-AI/biomate/settings/secrets/actions

点击 **"New repository secret"**，逐个添加：

#### 必需 Secrets（缺失会导致启动失败）

| Secret Name | 示例值 | 说明 |
|-------------|--------|------|
| `ANTHROPIC_API_KEY` | `sk-ant-api03-...` | 从 Anthropic 控制台获取 |
| `JWT_SECRET` | `8dc05a7f0e03...` | 上面生成的 64 位十六进制 |
| `SESSION_SECRET` | `cdc776d1d858...` | 上面生成的 64 位十六进制 |
| `BILLING_INTERNAL_KEY` | `814c10d85030...` | 上面生成的 64 位十六进制 |
| `DATABASE_URL` | `postgresql://user:pass@host:5432/biomate` | RDS 连接字符串 |
| `AWS_ACCESS_KEY_ID` | `AKIA...` | IAM 用户凭证 |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtn...` | IAM 用户凭证 |
| `S3_BUCKET_NAME` | `biomate-production` | S3 存储桶名称 |
| `GALAXY_API_KEY` | `glx_...` | Galaxy admin 生成 |

#### 可选 Secrets（增强功能）

| Secret Name | 说明 |
|-------------|------|
| `GALAXY_URL` | Galaxy 后端地址（默认：`http://galaxy-backend:8080`） |
| `REDIS_URL` | Redis 连接字符串 |
| `LAGO_API_KEY` | 计费系统 API Key |
| `OPENAI_API_KEY` | OpenAI API Key（备选 AI） |
| `GEMINI_API_KEY` | Google Gemini API Key |
| `NVIDIA_API_KEY` | NVIDIA NGC API Key |
| `BIOLM_API_KEY` | BioLM API Key |
| `ENCRYPTION_KEY` | 额外数据加密密钥 |
| `CSRF_SECRET` | CSRF 保护密钥 |

### 第三步：验证配置

配置完成后，在 GitHub Secrets 页面应该看到至少这些：

```
✅ ANTHROPIC_API_KEY
✅ JWT_SECRET
✅ SESSION_SECRET
✅ BILLING_INTERNAL_KEY
✅ DATABASE_URL
✅ AWS_ACCESS_KEY_ID
✅ AWS_SECRET_ACCESS_KEY
✅ S3_BUCKET_NAME
✅ GALAXY_API_KEY
```

### 第四步：测试部署

推送一个 tag 触发部署：

```bash
git tag dev-v0.9.3-test-secrets
git push origin dev-v0.9.3-test-secrets
```

查看 Actions 日志，应该看到：

```
=== Step 2: Configure environment variables (backward compatible) ===
GitHub Secrets detected → Merging with existing .env...
Merged GitHub Secrets with existing .env
```

---

## 🔍 工作原理

### 部署流程对比

#### 方式 A（现有）：
```
GitHub Actions
  ↓
EC2 (使用现有 /opt/biomate/.env)
  ↓
Docker Compose (env_file: /opt/biomate/.env)
  ↓
容器环境变量
```

#### 方式 B（新增）：
```
GitHub Actions (读取 Repository Secrets)
  ↓
scripts/deploy.sh (通过 SSM 合并到 /opt/biomate/.env)
  ↓
Docker Compose (env_file: /opt/biomate/.env)
  ↓
容器环境变量
```

### 合并逻辑

```bash
# 如果 /opt/biomate/.env 已存在
if [ -f /opt/biomate/.env ]; then
  # 备份现有文件
  cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

  # 合并：现有 .env + GitHub Secrets（Secrets 优先）
  cat .env.old /tmp/.env.secrets | sort -u > .env.merged
  mv .env.merged .env
else
  # 没有现有 .env，直接使用 GitHub Secrets
  mv /tmp/.env.secrets .env
fi
```

**关键点**：
- 现有的 `.env` 变量会被保留
- GitHub Secrets 中的变量会**覆盖**同名的 `.env` 变量
- 每次部署前会自动备份现有 `.env`

---

## 📦 迁移策略

### 推荐方式：渐进式迁移

1. **第一阶段**：只配置必需 Secrets
   ```
   ANTHROPIC_API_KEY
   JWT_SECRET
   SESSION_SECRET
   BILLING_INTERNAL_KEY
   ```

2. **第二阶段**：配置数据库和 AWS Secrets
   ```
   DATABASE_URL
   AWS_ACCESS_KEY_ID
   AWS_SECRET_ACCESS_KEY
   S3_BUCKET_NAME
   ```

3. **第三阶段**：配置可选增强 Secrets
   ```
   OPENAI_API_KEY
   GEMINI_API_KEY
   REDIS_URL
   LAGO_API_KEY
   ```

每个阶段都可以独立部署和测试，不影响现有流程。

---

## ⚠️ 注意事项

### 安全性
- ✅ GitHub Secrets 在 Actions 日志中会被自动屏蔽（显示为 `***`）
- ✅ `/opt/biomate/.env` 权限自动设置为 `600`（仅所有者可读写）
- ✅ 每次部署会自动备份现有 `.env`

### 兼容性
- ✅ 如果不配置 GitHub Secrets，完全不影响现有部署流程
- ✅ 可以混合使用：部分变量用 Secrets，部分用 `.env` 文件
- ✅ 随时可以回退：删除 GitHub Secrets，恢复到方式 A

### 回滚
如果需要回滚到某个备份：

```bash
# 在 EC2 上
cd /opt/biomate
ls -la .env.backup.*  # 查看所有备份

# 恢复某个备份
cp .env.backup.20260609_103000 .env

# 重启容器
docker compose -f docker-compose.deploy.yml restart
```

---

## 🎯 FAQ

### Q1: 我必须配置 GitHub Secrets 吗？
**A**: 不必须。如果不配置，现有流程完全不变。

### Q2: 如果我只配置了部分 Secrets 会怎样？
**A**: 配置的 Secrets 会覆盖 `.env` 中的同名变量，未配置的继续使用 `.env` 中的值。

### Q3: 如何知道当前使用的是哪种方式？
**A**: 查看 GitHub Actions 的部署日志，会明确显示：
- `"No GitHub Secrets detected → Using existing /opt/biomate/.env"`（方式 A）
- `"GitHub Secrets detected → Merging with existing .env"`（方式 B）

### Q4: GitHub Secrets 会覆盖现有的 .env 吗？
**A**: 会合并，不是完全覆盖：
- 现有 `.env` 中的变量会保留
- GitHub Secrets 中配置的变量会**覆盖**同名的 `.env` 变量
- 不在 Secrets 中的变量保持 `.env` 原值

### Q5: 如何测试 GitHub Secrets 是否生效？
**A**:
1. 配置一个 test Secret（如 `TEST_VAR=hello`）
2. 推送 tag 触发部署
3. 在 EC2 上检查：`cat /opt/biomate/.env | grep TEST_VAR`
4. 应该看到 `TEST_VAR=hello`

---

## 📝 总结

**当前状态**：
- ✅ 完全向下兼容
- ✅ 无需任何配置即可继续使用现有流程
- ✅ 随时可启用 GitHub Secrets（渐进式迁移）

**下一步**（可选）：
1. 按照"第一步"生成安全密钥
2. 按照"第二步"添加 GitHub Secrets
3. 按照"第四步"测试部署
4. 如有问题，自动回退到现有 `.env`

**优势**：
- 🔒 更安全：敏感信息不存储在 EC2 文件系统
- 🚀 更便捷：一次配置，所有环境自动同步
- 🔄 更灵活：支持多环境（dev/staging/prod）差异化配置
- 💰 更经济：减少手动运维成本
