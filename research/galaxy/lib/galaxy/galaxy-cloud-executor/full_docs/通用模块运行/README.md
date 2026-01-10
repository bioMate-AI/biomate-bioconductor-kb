# Galaxy Cloud 通用模块运行指南

## 📚 文档目录

本目录包含使用`galaxy_cloud`通用模块执行任何Galaxy workflow的完整文档。

### 1. [快速开始](01-快速开始.md) ⭐

**适合：** 想要快速上手的用户

**内容：**
- 3步快速开始
- 基本使用示例
- 常用命令
- 模块功能概览

**阅读时间：** 5-10分钟

---

### 2. [详细使用指南](02-详细使用指南.md) 📖

**适合：** 需要深入了解的用户

**内容：**
- galaxy_cloud模块架构
- 工作原理详解
- Python API使用
- 配置选项详解
- 扩展工具支持
- 与定制化脚本的对比

**阅读时间：** 20-30分钟

---

### 3. [问题排查](03-问题排查.md) 🔧

**适合：** 遇到问题的用户

**内容：**
- 常见问题解决
- Executor未注册
- 配置格式错误
- AWS凭证问题
- 完整错误日志分析

**阅读时间：** 10-15分钟

---

## 🚀 快速开始（3步）

如果你只有5分钟，这里是最简单的开始方式：

### 步骤 1: 设置环境变量

```bash
export GALAXY_AWS_ENABLED=true
export GALAXY_AWS_BATCH_QUEUE=galaxy-cloud-queue
export GALAXY_AWS_S3_BUCKET=galaxy-cloud-data-1760241377
export AWS_DEFAULT_REGION=us-west-2
```

### 步骤 2: 配置AWS凭证

```bash
aws configure
# 或者
export AWS_ACCESS_KEY_ID=你的key
export AWS_SECRET_ACCESS_KEY=你的secret
```

### 步骤 3: 运行workflow

```bash
cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor

# 使用快捷脚本
./run_qiime2_cloud.sh

# 或使用通用脚本
PYTHONPATH=/Users/renyuankai/work/biometa/galaxy/lib python3 examples/run_any_galaxy_workflow.py \
    /path/to/workflow.json \
    --input 0:/path/to/data \
    --provider aws \
    --monitor
```

就这么简单！🎉

---

## 🎯 核心概念

### galaxy_cloud 是什么？

`galaxy_cloud` 是一个**通用的**云执行模块，可以：
- ✅ 执行**任何** Galaxy workflow
- ✅ 支持多云平台（AWS, Azure, GCP, Kubernetes）
- ✅ 自动处理依赖和数据流
- ✅ 不需要为每个workflow编写定制代码

### 为什么使用 galaxy_cloud？

**传统做法 ❌**
```python
# 为每个workflow写定制脚本
if workflow_type == 'qiime2':
    run_qiime2_specific_code()
elif workflow_type == 'fastqc':
    run_fastqc_specific_code()
# 需要为每个workflow写大量代码...
```

**galaxy_cloud做法 ✅**
```python
# 一套代码执行所有workflow
execution = await integration.submit_workflow_from_file(
    workflow_file=any_workflow,  # 任何workflow！
    inputs=inputs,
    run_config=run_config
)
```

### 关键组件

```
galaxy_cloud/
├── core/                       # 核心抽象层
│   ├── executor.py            # CloudExecutor基类
│   ├── storage.py             # CloudStorage基类
│   └── job.py                 # Job模型
├── providers/                  # 云平台实现
│   ├── aws/                   # AWS Batch + S3
│   ├── azure/                 # Azure Batch + Blob
│   ├── gcp/                   # GCP Batch + GCS
│   └── k8s/                   # Kubernetes + PVC
└── galaxy_workflow/            # Galaxy workflow支持
    ├── integration.py         # 主入口 ⭐
    ├── dag_executor.py        # DAG执行引擎
    ├── converter.py           # Workflow转换
    ├── tool_registry.py       # 工具注册表
    └── data_manager.py        # 数据管理
```

---

## 📖 使用场景

### 场景 1: 执行QIIME2 Workflow

```bash
python3 examples/run_any_galaxy_workflow.py \
    qiime2_workflow.json \
    --input 0:/path/to/fastq_directory \
    --provider aws \
    --monitor
```

### 场景 2: 执行任何其他Workflow

```bash
python3 examples/run_any_galaxy_workflow.py \
    any_workflow.json \
    --input 0:/data/input1 \
    --input 1:/data/ref \
    --provider aws \
    --staging workflows/my-analysis \
    --monitor
```

### 场景 3: Python API集成

```python
from galaxy_cloud.galaxy_workflow import GalaxyCloudIntegration

integration = GalaxyCloudIntegration(config)
execution = await integration.submit_workflow_from_file(
    workflow_file=Path("workflow.json"),
    inputs=inputs,
    run_config=run_config
)
```

---

## 🔧 工具和脚本

### 执行脚本

- **`run_qiime2_cloud.sh`** - QIIME2 workflow快捷启动脚本
- **`examples/run_any_galaxy_workflow.py`** - 通用workflow执行器 ⭐

### 测试工具

- **`test_aws_config.sh`** - AWS配置测试工具

### 示例

- **`examples/galaxy_workflow_example.py`** - 详细Python API示例
- **`examples/basic_usage.py`** - 基础使用示例

---

## 🆚 优势对比

| 特性 | galaxy_cloud模块 ✅ | 定制化脚本 ❌ |
|-----|-------------------|-----------|
| **通用性** | 任何workflow | 每个workflow需定制 |
| **维护成本** | 低 - 统一代码库 | 高 - 分散脚本 |
| **客户使用** | 可直接使用 | 无法给客户 |
| **工具支持** | 工具注册表 | 手动编写 |
| **云平台** | 多云支持 | 通常单一平台 |
| **数据管理** | 自动化 | 手动处理 |
| **错误处理** | 统一机制 | 各自实现 |
| **扩展性** | 易扩展 | 难扩展 |

---

## ⚙️ 配置

### 环境变量（推荐）

```bash
# AWS
export GALAXY_AWS_ENABLED=true
export GALAXY_AWS_BATCH_QUEUE=your-queue
export GALAXY_AWS_S3_BUCKET=your-bucket
export AWS_DEFAULT_REGION=us-west-2

# Azure
export GALAXY_AZURE_ENABLED=true
export GALAXY_AZURE_BATCH_ACCOUNT=your-account

# GCP
export GALAXY_GCP_ENABLED=true
export GOOGLE_CLOUD_PROJECT=your-project

# Kubernetes
export GALAXY_K8S_ENABLED=true
export GALAXY_K8S_NAMESPACE=galaxy-workflows
```

### 配置文件（可选）

创建 `config.yaml`:
```yaml
aws:
  enabled: true
  region: us-west-2
  batch_queue: galaxy-cloud-queue
  s3_bucket: galaxy-cloud-data-bucket

default_provider: aws
```

---

## 🆘 常见问题

### Q: Executor 'aws-batch' not found

**A:** 已修复！确保使用最新版本，providers会自动注册。

### Q: AWS凭证无效

**A:** 运行 `sh test_aws_config.sh` 检查配置，然后运行 `aws configure` 配置凭证。

### Q: 如何添加新工具支持？

**A:** 在 `ToolRegistry` 中注册工具和容器映射即可。详见《详细使用指南》。

### Q: 支持哪些云平台？

**A:** AWS Batch, Azure Batch, GCP Batch, Kubernetes。

### Q: 可以执行任何workflow吗？

**A:** 是的！只要是标准的Galaxy workflow格式(.ga或.json)。

---

## 📝 总结

**galaxy_cloud是一个完整的、生产级的通用模块，可以执行任何Galaxy workflow！**

**关键优势：**
- ✅ 完全通用 - 不需要定制代码
- ✅ 多云支持 - AWS/Azure/GCP/K8s
- ✅ 自动化 - DAG分析、数据管理、监控
- ✅ 易扩展 - 工具注册表、插件机制
- ✅ 生产级 - 错误处理、重试、日志

**开始使用：**
1. 阅读《快速开始》
2. 配置AWS凭证
3. 运行 `./run_qiime2_cloud.sh`

就是这么简单！🚀

---

## 📞 获取帮助

- 查看详细文档
- 运行 `test_aws_config.sh` 诊断问题
- 查看《问题排查》文档

---

**最后更新:** 2025-10-17
**版本:** 1.0
