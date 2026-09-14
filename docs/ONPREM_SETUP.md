# BioMate 本地部署指南

> 适用版本：`docker-compose.onprem.yml`  
> 目标读者：James 前站工程师团队  
> 前置要求：Docker ≥ 24、Docker Compose v2、≥ 16 GB RAM（Ollama 离线模式需要 ≥ 32 GB）

---

## 目录

1. [快速启动](#1-快速启动)
2. [LLM 提供商配置](#2-llm-提供商配置)
3. [系统管理面板](#3-系统管理面板)
4. [存储配置](#4-存储配置)
5. [工作流数据库更新](#5-工作流数据库更新)
6. [Ollama 离线模式](#6-ollama-离线模式)
7. [反向代理（HTTPS）](#7-反向代理https)
8. [备份与恢复](#8-备份与恢复)
9. [日常维护命令](#9-日常维护命令)
10. [故障排查](#10-故障排查)

---

## 1. 快速启动

```bash
# 1. 克隆代码
git clone <your-repo-url> biomate && cd biomate

# 2. 生成 .env 文件
cp .env.onprem.example .env
# 编辑 .env，至少填写以下必填项（见下方说明）
nano .env

# 3. 启动
docker compose -f docker-compose.onprem.yml up -d

# 4. 查看启动日志
docker compose -f docker-compose.onprem.yml logs -f

# 5. 访问
# 浏览器打开 http://<服务器IP>:5000
```

### .env 必填项

```bash
# 数据库密码（自行设置，复杂度要够）
POSTGRES_PASSWORD=your_strong_password

# JWT / Session 密钥（随机生成，不要用简单字符串）
JWT_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)

# LLM 提供商 API Key（根据下面第2节选择一个）
ANTHROPIC_API_KEY=sk-ant-...
# 或
DEEPSEEK_API_KEY=sk-...
```

---

## 2. LLM 提供商配置

BioMate 支持多种 LLM 提供商，无需翻墙的推荐使用 DeepSeek / 智谱 GLM / Ollama。

| 提供商 | 环境变量 | 国内直连 | 说明 |
|--------|----------|----------|------|
| Anthropic Claude | `ANTHROPIC_API_KEY` | 需要 VPN | 默认，效果最好 |
| DeepSeek | `DEEPSEEK_API_KEY` | ✅ | 国内直连，性价比高 |
| 智谱 GLM | `ZHIPU_API_KEY` | ✅ | 国内直连 |
| OpenRouter | `OPENROUTER_API_KEY` | 部分需要 VPN | 支持多种模型中转 |
| Ollama | 无需 Key | ✅ 完全离线 | 需要本地 GPU/大内存 |

### 切换提供商

**方法一：通过管理面板（推荐）**

1. 用 admin 账号登录 → 侧边栏点击「系统管理」
2. 在「系统 LLM 配置」中选择提供商
3. 点击「保存配置」，复制输出的环境变量
4. 更新 `.env` 文件，然后重启后端：

```bash
docker restart biomate-galaxy
```

**方法二：直接编辑 .env**

```bash
# 切换到 DeepSeek
GALAXY_AI_LLM_PROVIDER=deepseek
GALAXY_AI_LLM_MODEL=deepseek-chat
DEEPSEEK_API_KEY=sk-your-deepseek-key

# 应用配置
docker restart biomate-galaxy
```

支持的 `GALAXY_AI_LLM_PROVIDER` 值：`anthropic` / `deepseek` / `zhipu` / `openrouter` / `ollama`

---

## 3. 系统管理面板

管理面板位于 `http://<服务器>:5000/admin`，需要 admin 账号登录。

**创建 admin 账号：**

```bash
# 方法：在 PostgreSQL 中将现有用户升级为 admin
docker exec -it biomate-postgres psql -U biomate -d biomate -c \
  "UPDATE users SET subscription_tier = 'admin' WHERE email = 'your@email.com';"
```

**管理面板功能：**

- **服务健康状态**：实时查看各服务是否正常，自动标红异常服务
- **LLM 配置**：选择提供商、填写模型名，保存后自动生成需要配置的环境变量

---

## 4. 存储配置

### 默认：本地磁盘

工作流运行产生的文件默认存储在 Docker volume 中。数据在容器重启后保留。

```bash
# 查看存储占用
docker system df -v
```

### 可选：AWS S3

如果客户有 AWS 账号，可配置 S3 存储更大文件：

```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=cn-northwest-1   # 国内用宁夏区域
S3_BUCKET_NAME=biomate-data
```

---

## 5. 工作流数据库更新

BioMate 的工作流目录存储在 `backend/database/galaxy_ai_tools.db`（279 MB SQLite 文件，2600+ 工作流）。

**更新方法：**

```bash
# 停止后端
docker stop biomate-galaxy

# 备份旧版本
docker cp biomate-galaxy:/app/database/galaxy_ai_tools.db ./backups/galaxy_ai_tools_$(date +%Y%m%d).db

# 从新版代码中复制最新数据库
# （当收到 BioMate 团队的新版本包时，解压后运行）
docker cp ./backend/database/galaxy_ai_tools.db biomate-galaxy:/app/database/galaxy_ai_tools.db

# 重启
docker start biomate-galaxy
```

**接收更新包：**

BioMate 团队会定期提供包含最新工作流库的更新包（`.tar.gz`）。解压后按上述步骤替换数据库文件即可，无需完整重新构建镜像。

---

## 6. Ollama 离线模式

适用于：**完全内网、不允许任何外部 API 调用** 的场景。

**要求：** ≥ 32 GB RAM，推荐 NVIDIA GPU（≥ 24 GB 显存用于 qwen3:32b）

**启用步骤：**

```bash
# 1. 在 docker-compose.onprem.yml 中取消 ollama 服务的注释（约第100行）

# 2. 在 .env 中设置
GALAXY_AI_LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://ollama:11434

# 3. 启动（包含 Ollama）
docker compose -f docker-compose.onprem.yml up -d

# 4. 拉取模型（首次需要下载，约 20 GB）
docker exec biomate-ollama ollama pull qwen3:32b

# 5. 重启后端使配置生效
docker restart biomate-galaxy
```

**无 GPU 时的替代模型（CPU 推理，较慢）：**

```bash
docker exec biomate-ollama ollama pull qwen3:8b   # 需要约 8 GB RAM
# 然后设置
GALAXY_AI_LLM_MODEL=qwen3:8b
```

---

## 7. 反向代理（HTTPS）

生产环境建议在 `biomate-frontend:5000` 前面加 Nginx 或 Caddy 做 SSL 终止。

**Caddy 示例（最简单）：**

```
biomate.your-company.com {
    reverse_proxy localhost:5000
}
```

**Nginx 示例：**

```nginx
server {
    listen 443 ssl;
    server_name biomate.your-company.com;
    ssl_certificate /etc/ssl/certs/your.crt;
    ssl_certificate_key /etc/ssl/private/your.key;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 600s;
    }
}
```

启用 HTTPS 后，在 `.env` 中设置：

```bash
FORCE_HTTPS=1
ENABLE_HSTS=1
```

---

## 8. 备份与恢复

### 备份

```bash
#!/bin/bash
# backup.sh — 建议每天定时执行
BACKUP_DIR=/opt/biomate/backups/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# PostgreSQL（用户数据、项目、历史）
docker exec biomate-postgres pg_dump -U biomate biomate | gzip > $BACKUP_DIR/postgres.sql.gz

# 工作流数据库
docker cp biomate-galaxy:/app/database/galaxy_ai_tools.db $BACKUP_DIR/

# 保留最近 30 天
find /opt/biomate/backups -maxdepth 1 -mtime +30 -type d -exec rm -rf {} +
echo "Backup done: $BACKUP_DIR"
```

### 恢复

```bash
# 恢复 PostgreSQL
gunzip -c /opt/biomate/backups/20260101/postgres.sql.gz | \
  docker exec -i biomate-postgres psql -U biomate -d biomate

# 恢复工作流数据库
docker stop biomate-galaxy
docker cp /opt/biomate/backups/20260101/galaxy_ai_tools.db \
  biomate-galaxy:/app/database/galaxy_ai_tools.db
docker start biomate-galaxy
```

---

## 9. 日常维护命令

```bash
# 查看所有服务状态
docker compose -f docker-compose.onprem.yml ps

# 查看日志（实时）
docker logs -f biomate-galaxy   # AI 后端
docker logs -f biomate-frontend # Node 前端
docker logs -f biomate-postgres # 数据库

# 重启单个服务（改完配置后）
docker restart biomate-galaxy
docker restart biomate-frontend

# 升级（拉取新镜像后）
docker compose -f docker-compose.onprem.yml pull
docker compose -f docker-compose.onprem.yml up -d

# 停止所有服务
docker compose -f docker-compose.onprem.yml down

# 彻底清除（包括数据库，慎用！）
docker compose -f docker-compose.onprem.yml down -v
```

---

## 10. 故障排查

### 服务启动慢（Galaxy 后端 120 秒才 healthy）

正常现象。Galaxy 启动时需要加载 AI 嵌入模型（约 500 MB）。等待即可。如果超过 3 分钟仍未 healthy：

```bash
docker logs biomate-galaxy 2>&1 | tail -50
```

### 工作流搜索不返回结果

```bash
# 检查工作流索引是否加载
curl http://localhost:8081/api/admin/index-health
# 或通过管理面板查看「工作流索引」状态
```

### LLM 调用失败（中国网络）

1. 先确认 API Key 是否正确：`docker exec biomate-galaxy printenv DEEPSEEK_API_KEY`
2. 如果使用 Anthropic，需要确认服务器能访问 `api.anthropic.com`（境外需要 VPN）
3. 国内推荐切换到 DeepSeek 或 智谱 GLM（见第2节）

### 数据库连接失败（Frontend 启动报错）

```bash
# 确认 PostgreSQL 已就绪
docker exec biomate-postgres pg_isready -U biomate -d biomate

# 确认 DATABASE_URL 格式正确
docker exec biomate-frontend printenv DATABASE_URL
```

### 磁盘空间不足

```bash
# 查看 Docker 占用
docker system df

# 清理无用镜像和容器（不影响运行中的服务）
docker system prune -f

# 查看工作流运行产生的文件
docker exec biomate-galaxy du -sh /app/logs /app/database
```

---

## 联系支持

- 技术问题：联系 BioMate 工程团队
- 更新包申请：请求最新 `galaxy_ai_tools.db` 和 Docker 镜像
