# Galaxy Cloud Executor

Galaxy workflow 云执行解决方案，将 Galaxy 作业管理系统与 AWS Batch 无缝集成。

---

## 📚 完整文档

**推荐从这里开始**: [full_docs/START_HERE.md](full_docs/START_HERE.md)

### 🎯 架构理解（重要！）⭐

**如果你不理解 testing/ 和 galaxy_cloud/ 的区别，请先阅读这些**：

| 文档 | 用途 | 时长 |
|------|------|------|
| [full_docs/architecture/](full_docs/architecture/) | 架构文档索引 | - |
| [full_docs/architecture/QUICK_CLARIFICATION.md](full_docs/architecture/QUICK_CLARIFICATION.md) | ⭐ 快速澄清核心概念 | 1-2 分钟 |
| [full_docs/architecture/VISUAL_COMPARISON.txt](full_docs/architecture/VISUAL_COMPARISON.txt) | 可视化流程对比 | 3-5 分钟 |
| [full_docs/architecture/ARCHITECTURE_EXPLAINED.md](full_docs/architecture/ARCHITECTURE_EXPLAINED.md) | 详细架构说明 | 10-15 分钟 |
| [full_docs/architecture/FLOW_COMPARISON.md](full_docs/architecture/FLOW_COMPARISON.md) | 执行流程对比 | 15-20 分钟 |

### 🆕 功能特性

| 文档 | 用途 | 状态 |
|------|------|------|
| [full_docs/features/](full_docs/features/) | 功能文档索引 | - |
| [full_docs/features/CLOUD_DATA_REFERENCE_README.md](full_docs/features/CLOUD_DATA_REFERENCE_README.md) | 云数据引用功能总览 | ✅ 核心完成 |
| [full_docs/features/CLOUD_DATA_REFERENCE_USER_GUIDE.md](full_docs/features/CLOUD_DATA_REFERENCE_USER_GUIDE.md) | 云数据引用使用指南 | ✅ 核心完成 |

### 🚀 通用模块运行（推荐！）

| 文档 | 用途 | 时长 |
|------|------|------|
| [full_docs/通用模块运行/00-运行准备.md](full_docs/通用模块运行/00-运行准备.md) | ⭐ 运行前检查清单 | 2分钟 |
| [full_docs/通用模块运行/01-快速开始.md](full_docs/通用模块运行/01-快速开始.md) | 3步快速上手 | 5分钟 |
| [full_docs/通用模块运行/02-详细使用指南.md](full_docs/通用模块运行/02-详细使用指南.md) | 深入理解架构 | 15分钟 |
| [full_docs/通用模块运行/03-问题排查.md](full_docs/通用模块运行/03-问题排查.md) | 问题解决方案 | 按需 |

### 核心文档

| 文档 | 用途 |
|------|------|
| [full_docs/START_HERE.md](full_docs/START_HERE.md) | 快速导航 |
| [full_docs/01-快速开始指南.md](full_docs/01-快速开始指南.md) | 5步Galaxy集成 |
| [full_docs/05-Workflow云测试工具详解.md](full_docs/05-Workflow云测试工具详解.md) | Workflow测试工具 |
| [full_docs/07-常见问题排查.md](full_docs/07-常见问题排查.md) | 问题排查 |
| [full_docs/README.md](full_docs/README.md) | 完整文档索引 |

---

## ⚡ 快速开始

### 如果您已完成 AWS Batch 搭建

```bash
# 1. 运行集成检查
bash scripts/check_integration_ready.sh

# 2. 按照文档完成集成（10-15分钟）
cat full_docs/01-快速开始指南.md
```

### 如果您是第一次使用

```bash
# 1. 查看完整文档
cat full_docs/START_HERE.md

# 2. 按照指导完成 AWS 搭建和 Galaxy 集成
```

---

## 🎯 核心功能

### ✅ 已完成功能

- ✅ **AWS Batch 集成** - 完整的基础设施和测试
- ✅ **Workflow 执行** - DAG 分析、依赖管理、并行执行
- ✅ **数据管理** - S3 自动传输
- ✅ **状态同步** - 实时作业状态监控
- ✅ **错误处理** - CloudWatch 日志集成
- ✅ **测试验证** - 复杂 workflow 测试通过（14步，7层）
- ✅ **云数据引用** ⭐ NEW - 直接使用云上数据，跳过上传

### 🧪 Workflow 测试工具

```bash
# 测试单个 workflow
cd testing
python3 run_any_workflow.py <workflow.json>

# 批量测试
./batch_test_workflows.sh 5
```

详见：[full_docs/05-Workflow云测试工具详解.md](full_docs/05-Workflow云测试工具详解.md)

---

## 🏗️ 架构

### 真实生产流程（Galaxy 集成后）

```
用户在 Galaxy UI 点击 "Run Workflow"
    ↓
Galaxy 内部调用 GalaxyCloudJobRunner.queue_job()
    ↓ (galaxy_cloud/galaxy_workflow/galaxy_job_runner.py)
    ↓
DataManager 上传真实数据到 S3
    ↓ (galaxy_cloud/galaxy_workflow/data_manager.py)
    ↓
AWSBatchExecutor 提交作业到 AWS Batch
    ↓ (galaxy_cloud/providers/aws/executor.py)
    ↓
AWS Batch 执行真实 BioContainer 工具
    ↓ (例如：BWA, GATK, Bowtie2)
    ↓
DataManager 下载结果回 Galaxy
    ↓
用户在 Galaxy UI 看到结果 ✅
```

### 核心组件

- **galaxy_cloud/** - ⭐ 生产代码（Galaxy 真正使用的执行器）
  - `galaxy_workflow/galaxy_job_runner.py` - Galaxy 调用入口
  - `galaxy_workflow/data_manager.py` - S3 数据管理
  - `providers/aws/executor.py` - AWS Batch 集成
- **testing/** - 测试工具（验证 AWS Batch 配置，Galaxy 集成后可删除）
- **scripts/** - 诊断和管理脚本
- **config/** - 配置模板
- **full_docs/** - 完整文档

---

## 📊 测试状态

### 已验证

- ✅ AWS 连接测试：5/5 通过
- ✅ 简单 workflow（2步）：通过
- ✅ 复杂 workflow（14步）：通过
- ✅ S3 数据传递：正常
- ✅ CloudWatch 日志：正常
- ✅ 动态资源分配：正常

### AWS 资源（已搭建）

| 资源 | 值 | 状态 |
|------|-----|------|
| Region | us-west-2 | ✅ |
| Batch Queue | galaxy-cloud-queue | ✅ ENABLED |
| S3 Bucket | galaxy-cloud-data-1760241377 | ✅ |
| Job Role | BatchJobRole | ✅ |

---

## 🛠️ 主要工具

### 🚀 快速执行（scripts/workflow/）

```bash
# 执行QIIME2 workflow（推荐入口）⭐
./scripts/workflow/run_qiime2_cloud.sh
```

### 🔧 AWS辅助工具（scripts/aws/）

```bash
# AWS凭证设置（交互式）⭐
./scripts/aws/setup_credentials.sh

# 测试AWS配置
./scripts/aws/test_config.sh

# 查看作业日志
./scripts/aws/check_logs.sh latest

# 刷新AWS凭证
./scripts/aws/refresh_credentials.sh
```

### 🧪 Workflow测试工具（testing/）

```bash
# 测试 AWS 连接（推荐先运行）⭐
python3 testing/test_aws_connection.py

# 测试任意 workflow
python3 testing/run_any_workflow.py <workflow.json>

# 批量测试
./testing/batch_test_workflows.sh <数量>

# 分析 workflow 结构
python3 testing/analyze_real_workflow.py <workflow.json>

# 诊断失败作业
python3 testing/check_failed_job.py <job-id>
```

---

## 📦 目录结构

```
galaxy-cloud-executor/
├── galaxy_cloud/              # ⭐ 核心代码（生产级通用云执行框架）
│   ├── core/                  # 执行引擎
│   ├── galaxy_workflow/       # Galaxy集成
│   └── providers/             # 云提供商（AWS/GCP/Azure/K8s）
├── scripts/                   # 🔧 辅助脚本
│   ├── aws/                   # AWS工具（凭证、日志、配置测试）
│   └── workflow/              # Workflow执行脚本
├── testing/                   # 🧪 Workflow测试工具
│   ├── run_any_workflow.py
│   ├── batch_test_workflows.sh
│   └── test_aws_connection.py
├── config/                    # ⚙️ 配置模板
├── full_docs/                 # 📚 完整文档集
│   ├── 通用模块运行/          # 通用模块使用指南
│   ├── architecture/          # 架构设计文档
│   └── features/              # 功能说明文档
├── test_data/                 # 测试数据
└── examples/                  # 示例代码
```

---

## 🔗 相关链接

- **完整文档**: [full_docs/README.md](full_docs/README.md)
- **快速开始**: [full_docs/01-快速开始指南.md](full_docs/01-快速开始指南.md)
- **Workflow测试**: [full_docs/05-Workflow云测试工具详解.md](full_docs/05-Workflow云测试工具详解.md)
- **问题排查**: [full_docs/07-常见问题排查.md](full_docs/07-常见问题排查.md)
- **配置参考**: [full_docs/11-配置文件完整参考.md](full_docs/11-配置文件完整参考.md)

---

## 📝 许可证

本项目是 Galaxy 项目的一部分。

---

**版本**: 1.0
**状态**: AWS Batch 完成，已通过复杂 workflow 测试
**更新**: 2025-10-15
