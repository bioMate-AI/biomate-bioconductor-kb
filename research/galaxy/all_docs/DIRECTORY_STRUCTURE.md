# Galaxy Cloud Executor 目录结构说明

## 📁 正确的目录结构

```
/Users/renyuankai/work/biometa/galaxy/
├── lib/
│   ├── galaxy/                              # Galaxy核心模块
│   │   ├── galaxy-cloud-executor/           ✅ 云执行模块的主目录
│   │   │   ├── galaxy_cloud/                # Python包（核心代码）
│   │   │   │   ├── __init__.py
│   │   │   │   ├── core/                    # 核心执行引擎
│   │   │   │   ├── providers/               # 云提供商适配器
│   │   │   │   ├── galaxy_workflow/         # Galaxy集成
│   │   │   │   └── ...
│   │   │   ├── config/                      # 配置文件
│   │   │   ├── examples/                    # 示例代码
│   │   │   ├── scripts/                     # 脚本工具
│   │   │   ├── full_docs/                   # 完整文档
│   │   │   ├── testing/                     # 测试代码
│   │   │   ├── test_data/                   # 测试数据
│   │   │   ├── README.md
│   │   │   ├── pyproject.toml
│   │   │   └── requirements.txt
│   │   └── ...                              # 其他Galaxy模块
│   ├── galaxy_cloud -> galaxy/galaxy-cloud-executor/galaxy_cloud  ✅ 软链接（供Galaxy导入）
│   └── galaxy-cloud-executor.backup         ⚠️  旧的备份（可删除）
├── config/
│   ├── galaxy.yml                           # Galaxy主配置
│   ├── job_conf_cloud.yml                   ✅ 云执行job配置
│   └── aws_cloud_config.yaml                # AWS配置
└── ...
```

## ✅ Galaxy使用的是哪个？

**Galaxy使用：`lib/galaxy/galaxy-cloud-executor/galaxy_cloud`**

通过软链接机制：
```python
# 在Galaxy代码中导入时：
import galaxy_cloud

# 实际加载的是：
# lib/galaxy_cloud (软链接) → lib/galaxy/galaxy-cloud-executor/galaxy_cloud
```

## 📝 工作流程

### 1. Galaxy启动时
```
1. Galaxy加载 lib/ 到Python路径
2. 读取 config/galaxy.yml，找到 job_config_file: config/job_conf_cloud.yml
3. 解析 job_conf_cloud.yml，发现 galaxy_cloud runner
4. 通过软链接导入：import galaxy_cloud
5. 加载 GalaxyCloudJobRunner
```

### 2. Workflow运行时
```
1. 用户在Galaxy UI运行workflow
2. Galaxy识别tool_id（如 toolshed.g2.bx.psu.edu/repos/iuc/...）
3. 匹配 job_conf_cloud.yml 中的规则
4. 路由到 cloud_small 环境
5. 调用 GalaxyCloudJobRunner.queue_job()
6. GalaxyCloudJobRunner提交作业到AWS Batch
7. 数据上传到S3，容器执行，结果返回
```

## 🗂️ 文件作用说明

### 核心代码
| 路径 | 作用 | Galaxy是否使用 |
|------|------|---------------|
| `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/` | Python包主目录 | ✅ 是 |
| `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/core/` | 云执行核心引擎 | ✅ 是 |
| `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/` | AWS/K8s适配器 | ✅ 是 |
| `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/` | Galaxy集成层 | ✅ 是（关键！） |
| `lib/galaxy_cloud` | 软链接 | ✅ 是（导入入口） |

### 配置文件
| 路径 | 作用 | Galaxy是否使用 |
|------|------|---------------|
| `config/job_conf_cloud.yml` | Job runner配置 | ✅ 是（必需） |
| `config/aws_cloud_config.yaml` | AWS连接配置 | ✅ 是 |
| `lib/galaxy/galaxy-cloud-executor/config/` | 示例配置 | ❌ 否（仅参考） |

### 文档和测试
| 路径 | 作用 | Galaxy是否使用 |
|------|------|---------------|
| `lib/galaxy/galaxy-cloud-executor/full_docs/` | 完整文档 | ❌ 否 |
| `lib/galaxy/galaxy-cloud-executor/scripts/` | 工具脚本 | ❌ 否（但有用） |
| `lib/galaxy/galaxy-cloud-executor/examples/` | 示例代码 | ❌ 否 |
| `lib/galaxy/galaxy-cloud-executor/testing/` | 测试代码 | ❌ 否 |

### 旧文件（可删除）
| 路径 | 状态 |
|------|------|
| `lib/galaxy-cloud-executor.backup/` | ⚠️ 旧版本备份（确认无误后可删除） |

## 🔍 验证当前结构

### 检查软链接是否正确
```bash
cd /Users/renyuankai/work/biometa/galaxy/lib
ls -la galaxy_cloud
# 应该显示: galaxy_cloud -> galaxy/galaxy-cloud-executor/galaxy_cloud
```

### 验证Python导入
```bash
cd /Users/renyuankai/work/biometa/galaxy/lib
python3 -c "import galaxy_cloud; print(galaxy_cloud.__file__)"
# 应该显示: .../lib/galaxy/galaxy-cloud-executor/galaxy_cloud/__init__.py
```

### 验证Galaxy加载
```bash
cd /Users/renyuankai/work/biometa/galaxy
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud"
# 应该看到: Galaxy Cloud Job Runner initialized successfully
```

## 🔧 如何修改代码

### 修改云执行逻辑
```bash
# 编辑核心代码
nano lib/galaxy/galaxy-cloud-executor/galaxy_cloud/core/executor.py

# Galaxy会通过软链接使用最新代码（无需重新链接）
# 但需要重启Galaxy
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

### 修改Galaxy集成
```bash
# 编辑job runner
nano lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py

# 重启Galaxy生效
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

### 修改配置
```bash
# 编辑job配置
nano config/job_conf_cloud.yml

# 编辑AWS配置
nano config/aws_cloud_config.yaml

# 重启Galaxy生效
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

## 🧹 清理建议

### 安全删除旧备份
```bash
# 首先验证Galaxy运行正常
curl http://localhost:8080/api/version

# 验证云runner加载成功
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud.*init"

# 确认无误后删除备份
cd /Users/renyuankai/work/biometa/galaxy/lib
rm -rf galaxy-cloud-executor.backup

echo "✅ 清理完成"
```

### 清理其他临时文件
```bash
cd /Users/renyuankai/work/biometa/galaxy

# 清理日志备份（如果不需要）
rm -f galaxy_startup.log.* galaxy_final_start.log manual_start.log

# 清理测试脚本产生的临时文件
rm -f job_detail.json

echo "✅ 临时文件已清理"
```

## 📊 目录大小参考

```bash
du -sh lib/galaxy/galaxy-cloud-executor/
# 应该约: 5-10 MB（取决于.venv等）

du -sh lib/galaxy/galaxy-cloud-executor/galaxy_cloud/
# 应该约: 500KB - 1MB（核心代码）
```

## 🆘 故障排除

### 问题1：Galaxy找不到galaxy_cloud模块
```bash
# 检查软链接
ls -la lib/galaxy_cloud

# 应该指向: galaxy/galaxy-cloud-executor/galaxy_cloud
# 如果不对，重新创建：
cd lib
rm galaxy_cloud
ln -s galaxy/galaxy-cloud-executor/galaxy_cloud galaxy_cloud
```

### 问题2：修改代码不生效
```bash
# 确认修改的是正确的文件
ls -la lib/galaxy/galaxy-cloud-executor/galaxy_cloud/

# 重启Galaxy
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

### 问题3：不确定某个文件在哪个目录
```bash
# 搜索文件
find lib -name "文件名.py" -type f

# 检查是否是软链接
ls -la lib/路径/文件名.py
```

---

## 📚 相关文档

- [项目README](lib/galaxy/galaxy-cloud-executor/README.md)
- [完整文档](lib/galaxy/galaxy-cloud-executor/full_docs/)
- [配置参考](config/job_conf_cloud.yml)

---

**最后更新：** 2025-10-17
**Galaxy版本：** 25.1.dev0
**云执行模块位置：** lib/galaxy/galaxy-cloud-executor/
