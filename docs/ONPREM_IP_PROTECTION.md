# BioMate 知识产权保护指南

> 适用于：on-premises 部署包交付
> 目标：在客户本地环境运行 BioMate 的同时，保护 BioMate 的源代码、算法和数据库不被泄露

---

## 核心原则

**客户只应收到编译后的 Docker 镜像，而不是源代码。**

| 资产 | 风险 | 保护手段 |
|------|------|---------|
| Node.js 前端源码 | 打包时编译为 `.js` bundle，不含原始 TS/TSX | Vite 构建 + 混淆 |
| Python AI 后端 | `.py` 文件明文，风险最高 | Docker 分层 + 许可证锁 |
| 工作流数据库 (279 MB SQLite) | 包含 2600+ 专有工作流 | 访问控制 + 只读挂载 |
| 提示词 / AI 逻辑 | 嵌入在 Python 代码中 | 同后端保护 |

---

## 第一层：Docker 镜像分发（必须）

**绝对不要**把 git 仓库或源码压缩包交给客户。

### 正确的交付物

```
biomate-v2.5.0-delivery/
├── docker-compose.onprem.yml   # 启动编排文件
├── .env.onprem.example         # 环境变量模板
├── docs/ONPREM_SETUP.md        # 中文部署文档
└── README.md                   # 简短的交付说明（无源码）
```

### 镜像构建 & 推送（BioMate 内部）

```bash
# 构建镜像
docker build -t biomate-frontend:v2.5.0 ./frontend/
docker build -t biomate-galaxy:v2.5.0   ./backend/

# 推送到私有 ECR（客户无访问权限）
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/biomate-frontend:v2.5.0
docker push $ECR_REGISTRY/biomate-galaxy:v2.5.0

# 导出镜像文件（离线交付）
docker save biomate-frontend:v2.5.0 | gzip > biomate-frontend-v2.5.0.tar.gz
docker save biomate-galaxy:v2.5.0   | gzip > biomate-galaxy-v2.5.0.tar.gz
```

### 客户端加载镜像

```bash
# 客户执行（无需访问 ECR，无需 git）
docker load < biomate-frontend-v2.5.0.tar.gz
docker load < biomate-galaxy-v2.5.0.tar.gz
docker compose -f docker-compose.onprem.yml up -d
```

### Docker 镜像内源码层保护

Python 代码在 Docker 层中仍然可读。额外加固：

```dockerfile
# backend/Dockerfile — 在最终阶段删除不必要的文件
FROM python:3.11-slim AS final
COPY --from=builder /app /app
# 删除测试、脚本、文档（减少暴露面）
RUN find /app -name "*.md" -delete && \
    find /app -name "test_*.py" -delete && \
    find /app -name "*_test.py" -delete && \
    find /app -path "*/scripts/*.sh" -delete
```

---

## 第二层：许可证密钥系统（必须）

见 [系统管理面板文档](ONPREM_SETUP.md#3-系统管理面板)。

**关键点：**

- 许可证密钥与 `BIOMATE_LICENSE_SECRET` 配对使用
- `BIOMATE_LICENSE_SECRET` 由 BioMate 生成，**每个客户可以不同**（增加破解难度）
- 密钥包含过期时间，到期后系统显示许可证过期页面
- 密钥格式 `BMOP-XXXX-XXXX-YYMM-SSSS` 中 `SSSS` 是 HMAC 签名，无法伪造

**生成客户密钥（内部工具）：**

```bash
# 为客户 "上海某药厂" 生成有效到 2027-06 的密钥
python3 scripts/generate_license_key.py \
  --customer "SHPHARMA001" \
  --expiry "2027-06" \
  --secret "your-internal-signing-secret-here"
```

**续期流程：**
1. BioMate 团队生成新密钥（新的过期时间）
2. 通过加密邮件发送给客户
3. 客户更新 `.env` 中的 `BIOMATE_LICENSE_KEY` 并重启后端

---

## 第三层：工作流数据库保护（推荐）

`galaxy_ai_tools.db`（279 MB）是 BioMate 的核心竞争力之一。

### 方案 A：容器内只读挂载（简单，推荐）

```yaml
# docker-compose.onprem.yml
galaxy-backend:
  volumes:
    - biomate-backend-db:/app/database:ro   # 只读，客户无法修改
```

将 DB 文件预先打包进 Docker 镜像（不通过 volume 挂载），客户无法直接访问：

```dockerfile
# backend/Dockerfile
COPY database/galaxy_ai_tools.db /app/database/galaxy_ai_tools.db
# 不暴露为 volume
```

客户 `docker exec` 进容器可以看到文件，但需要专业工具才能解析 SQLite。

### 方案 B：SQLCipher 加密（最强，较复杂）

用加密版 SQLite（SQLCipher）存储工作流数据库：

```python
# 需要安装 sqlcipher3
from sqlcipher3 import dbapi2 as sqlite3

conn = sqlite3.connect('/app/database/galaxy_ai_tools.db')
conn.execute(f"PRAGMA key='{DB_ENCRYPTION_KEY}'")
# 读写操作同普通 SQLite
```

加密密钥 `DB_ENCRYPTION_KEY` 通过 `BIOMATE_LICENSE_SECRET` 派生：

```python
import hashlib
DB_ENCRYPTION_KEY = hashlib.sha256(
    (os.environ['BIOMATE_LICENSE_SECRET'] + 'db-key').encode()
).hexdigest()[:32]
```

这样即使客户拿到 `.db` 文件，没有 `BIOMATE_LICENSE_SECRET` 也无法读取内容。

---

## 第四层：更新机制控制（推荐）

不允许客户自行修改工作流数据库，更新只能通过 BioMate 提供的更新包：

1. BioMate 团队发布新版镜像（含更新的工作流 DB）
2. 客户执行 `bash scripts/onprem-update.sh --tag v2.6.0`
3. 脚本自动备份、拉取新镜像、重启服务

```bash
# 严禁客户直接修改（通过只读挂载 + 文件权限实现）
docker exec biomate-galaxy chmod 444 /app/database/galaxy_ai_tools.db
```

---

## 交付清单

在向客户交付 on-prem 包之前，确认以下内容：

- [ ] 镜像已从源码构建，**未包含** `.git` 目录或源码文件
- [ ] 已生成客户专属许可证密钥（含过期时间）
- [ ] 已生成客户专属 `BIOMATE_LICENSE_SECRET`
- [ ] `.env.onprem.example` 中 `BIOMATE_LICENSE_SECRET` 字段已填写
- [ ] 工作流数据库采用只读挂载或已加密
- [ ] 文档使用中文且不包含内部技术细节
- [ ] 已测试客户端加载镜像 → 启动 → 许可证验证全流程

---

## 防逆向工程建议

| 措施 | 复杂度 | 效果 |
|------|--------|------|
| Docker 镜像分发（不含源码） | 低 | 中等 |
| 许可证密钥 + HMAC 签名 | 低 | 中等（商业层面） |
| Python `.pyc` 预编译 | 低 | 低（.pyc 可反编译） |
| Cython 编译关键模块 | 中 | 高 |
| SQLCipher 加密 DB | 中 | 高（DB 层完全保护） |
| 代码混淆（商业工具） | 高 | 高 |

**短期（现阶段）推荐：** Docker 镜像分发 + 许可证密钥 + 工作流 DB 只读挂载。这三层已足够防止普通技术人员轻易复制系统。

**中期升级：** 对 `ai_assistant.py`、`nextflow_executor.py` 等核心文件用 Cython 编译，生成 `.so` 文件替代 `.py`。
