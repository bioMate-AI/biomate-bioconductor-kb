# 功能特性文档

本文件夹包含 Galaxy Cloud Executor 的功能特性文档。

---

## 📚 功能列表

### 1. 云数据引用功能 ⭐ 新功能

**状态**: ✅ 核心功能已完成，等待 Galaxy UI 集成

允许用户直接使用存储在云端（AWS S3）的数据，无需上传即可在 Galaxy 中运行 workflow。

#### 文档

- **[CLOUD_DATA_REFERENCE_README.md](CLOUD_DATA_REFERENCE_README.md)** - 功能总览和快速开始
- **[CLOUD_DATA_REFERENCE_USER_GUIDE.md](CLOUD_DATA_REFERENCE_USER_GUIDE.md)** - 详细使用指南
- **[CLOUD_DATA_REFERENCE_DESIGN.md](CLOUD_DATA_REFERENCE_DESIGN.md)** - 设计文档和技术细节

#### 核心价值

- ⚡ **性能提升**：跳过大文件上传，立即开始分析
- 💰 **成本节约**：避免重复存储和传输
- 🔄 **数据共享**：团队成员共享云数据
- 🌍 **公共数据集**：轻松使用公共基因组数据

#### 快速示例

```python
from galaxy_cloud.core.cloud_data_reference import create_s3_reference
from galaxy_cloud.galaxy_workflow.cloud_data_manager import CloudDataManager

# 创建云引用（公共数据）
ref_genome = create_s3_reference(
    "s3://public-genomes/hg38/genome.fa",
    region="us-west-2",
    is_public=True
)

# 在 workflow 中使用（混合输入）
cloud_manager = CloudDataManager(region="us-west-2")
prepared_inputs = await cloud_manager.prepare_input_data(
    inputs=[ref_genome, local_dataset],  # 云引用 + 本地上传
    run_config=run_config,
    data_manager=data_manager
)

# 结果:
# prepared_inputs[0]: 云引用，skip_upload=True ✅
# prepared_inputs[1]: 本地文件，已上传到 S3
```

#### 性能对比

| 方式 | 上传时间 | 节省时间 |
|------|---------|---------|
| 传统方式（上传 3 GB 参考基因组） | 10 分钟 | - |
| 云引用方式（验证云路径） | 5 秒 | ~10 分钟 ✅ |

---

## 📖 文档详情

### [CLOUD_DATA_REFERENCE_README.md](CLOUD_DATA_REFERENCE_README.md)

**用途**: 功能总览和快速开始
**时长**: 5-10 分钟
**内容**:
- 功能简介和核心价值
- 快速开始示例
- 性能对比
- 使用场景
- 文件结构
- 核心组件介绍
- 权限配置概览
- 功能状态

**适合**: 想快速了解云数据引用功能的人

---

### [CLOUD_DATA_REFERENCE_USER_GUIDE.md](CLOUD_DATA_REFERENCE_USER_GUIDE.md) ⭐

**用途**: 详细使用指南
**时长**: 30-45 分钟
**内容**:
- 快速开始（代码示例）
- 使用场景（公共数据、团队共享、大规模分析）
- 权限配置（IAM Role、Bucket Policy）
- API 参考
- 常见问题
- 最佳实践
- 性能对比
- 完整示例代码

**适合**: 准备实际使用云数据引用功能的人

---

### [CLOUD_DATA_REFERENCE_DESIGN.md](CLOUD_DATA_REFERENCE_DESIGN.md)

**用途**: 设计文档和技术细节
**时长**: 60+ 分钟
**内容**:
- 背景和问题陈述
- 用例场景详解
- 功能设计（数据类型、UI 设计、数据格式）
- 权限管理详解
- 数据验证流程
- DataManager 集成
- Workflow 集成
- 实现步骤（三个阶段）
- 配置示例
- 安全考虑
- 性能优化
- 用户体验分析
- 错误处理
- 测试用例

**适合**: 开发者、架构师，想深入理解技术实现的人

---

## 🚀 快速开始

### 1. 阅读总览
→ [CLOUD_DATA_REFERENCE_README.md](CLOUD_DATA_REFERENCE_README.md)

### 2. 学习使用
→ [CLOUD_DATA_REFERENCE_USER_GUIDE.md](CLOUD_DATA_REFERENCE_USER_GUIDE.md)

### 3. 运行示例
```bash
cd ../../examples
python3 test_cloud_data_reference.py
python3 test_workflow_with_cloud_data.py
```

### 4. 理解实现（可选）
→ [CLOUD_DATA_REFERENCE_DESIGN.md](CLOUD_DATA_REFERENCE_DESIGN.md)

---

## 📊 功能状态

| 功能 | 状态 | 说明 |
|------|------|------|
| 数据模型 | ✅ 完成 | CloudDataReference, ValidationResult |
| S3 验证 | ✅ 完成 | 支持公共和私有数据 |
| 批量验证 | ✅ 完成 | 支持并行验证 |
| 目录引用 | ✅ 完成 | 支持目录批量操作 |
| 混合输入 | ✅ 完成 | 云引用 + 本地上传 |
| IAM Role | ✅ 完成 | 私有数据访问 |
| 测试示例 | ✅ 完成 | 完整示例代码 |
| 文档 | ✅ 完成 | 设计、使用、API 文档 |
| GCS 支持 | 📋 计划 | Google Cloud Storage |
| Azure 支持 | 📋 计划 | Azure Blob Storage |
| Galaxy UI | 🔄 进行中 | 集成到 Galaxy 界面 |

---

## 💡 使用场景

### 场景 1：公共数据集
使用 1000 Genomes、NCBI 等公共数据，节省上传时间

### 场景 2：团队共享
10 人共享 1 TB 数据，只需上传 1 次，节省 450 小时

### 场景 3：大规模分析
100 个样本（5 TB），跳过数天的上传时间

---

## 🔗 相关文档

- **[../README.md](../README.md)** - 完整文档索引
- **[../01-快速开始指南.md](../01-快速开始指南.md)** - Galaxy 集成指南
- **[../architecture/](../architecture/)** - 架构理解文档
- **[../../examples/](../../examples/)** - 示例代码

---

## 📞 反馈

如有问题或建议，请：
- 查看详细文档
- 运行示例代码
- 提交 Issue

---

**版本**: 1.0
**更新时间**: 2025-10-15
**状态**: 核心功能已完成，等待 Galaxy UI 集成
