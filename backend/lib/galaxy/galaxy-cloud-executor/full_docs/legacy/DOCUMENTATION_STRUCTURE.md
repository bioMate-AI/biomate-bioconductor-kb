# 文档结构说明

## 📂 整理后的文档结构

本文档说明 Galaxy Cloud Executor 的完整文档组织结构。

---

## 🎯 核心原则

1. **所有文档都在 full_docs/ 下**
2. **testing/ 只保留可执行脚本**
3. **按主题分类到子文件夹**
4. **清晰的索引和导航**

---

## 📁 完整目录结构

```
galaxy-cloud-executor/
│
├── README.md                                  ← 项目主入口
│
├── full_docs/                                 ← 📚 所有文档集中在这里
│   ├── README.md                              ← 完整文档索引
│   ├── START_HERE.md                          ← 快速导航
│   │
│   ├── architecture/                          ← 🏗️ 架构理解文档
│   │   ├── README.md                          ← 架构文档索引
│   │   ├── START_HERE_ARCHITECTURE.md         ← 架构文档导航
│   │   ├── QUICK_CLARIFICATION.md             ← ⭐ 快速澄清（1分钟）
│   │   ├── VISUAL_COMPARISON.txt              ← 可视化对比图
│   │   ├── ARCHITECTURE_EXPLAINED.md          ← 详细架构说明
│   │   ├── FLOW_COMPARISON.md                 ← 流程对比
│   │   └── GALAXY_CLOUD_CODE_WALKTHROUGH.md   ← 代码详解
│   │
│   ├── features/                              ← 🆕 功能特性文档
│   │   ├── README.md                          ← 功能文档索引
│   │   ├── CLOUD_DATA_REFERENCE_README.md     ← 云数据引用总览
│   │   ├── CLOUD_DATA_REFERENCE_USER_GUIDE.md ← 云数据引用使用指南
│   │   └── CLOUD_DATA_REFERENCE_DESIGN.md     ← 云数据引用设计文档
│   │
│   ├── 00-项目总览.md                         ← 项目总览
│   ├── 01-快速开始指南.md                     ← Galaxy 集成指南
│   ├── 02-Galaxy集成详细指南.md               ← 详细集成步骤
│   ├── 05-Workflow云测试工具详解.md           ← 测试工具文档
│   ├── 07-常见问题排查.md                     ← 问题排查
│   ├── 11-配置文件完整参考.md                 ← 配置参考
│   ├── 12-脚本工具使用指南.md                 ← 脚本使用
│   ├── SUMMARY-已完成工作总结.md              ← 工作总结
│   ├── INPUT_DATA_EXPLAINED.md                ← 输入数据说明
│   └── README_WORKFLOW_TESTING.md             ← Workflow 测试说明
│
├── testing/                                   ← 🧪 只保留可执行脚本
│   ├── run_any_workflow.py                    ← 测试任意 workflow
│   ├── batch_test_workflows.sh                ← 批量测试脚本
│   ├── test_aws_connection.py                 ← AWS 连接测试
│   ├── analyze_real_workflow.py               ← 分析 workflow 结构
│   ├── check_failed_job.py                    ← 诊断失败作业
│   └── run_workflow_with_real_data.py         ← 真实数据测试（框架）
│
├── galaxy_cloud/                              ← 🌟 生产代码
│   ├── core/
│   │   ├── cloud_data_reference.py            ← 云数据引用模型
│   │   └── cloud_data_validator.py            ← 云数据验证器
│   ├── galaxy_workflow/
│   │   ├── galaxy_job_runner.py               ← Galaxy 入口
│   │   ├── data_manager.py                    ← 数据管理
│   │   └── cloud_data_manager.py              ← 云数据管理
│   └── providers/aws/
│       └── executor.py                        ← AWS Batch 执行器
│
├── examples/                                  ← 📝 示例代码
│   ├── test_cloud_data_reference.py           ← 云数据引用示例
│   └── test_workflow_with_cloud_data.py       ← Workflow 云数据示例
│
├── scripts/                                   ← 🛠️ 诊断脚本
│   ├── check_integration_ready.sh
│   ├── diagnose_batch.sh
│   └── check_aws_credentials.sh
│
├── config/                                    ← ⚙️ 配置模板
└── docs/                                      ← 📄 设计文档（较老）
```

---

## 📖 文档分类

### 1. 架构理解文档 (full_docs/architecture/)

**目的**: 帮助理解 testing/ 和 galaxy_cloud/ 的区别

| 文档 | 用途 | 阅读时长 |
|------|------|----------|
| [README.md](full_docs/architecture/README.md) | 架构文档索引 | 1 分钟 |
| [QUICK_CLARIFICATION.md](full_docs/architecture/QUICK_CLARIFICATION.md) | ⭐ 快速澄清核心概念 | 1-2 分钟 |
| [VISUAL_COMPARISON.txt](full_docs/architecture/VISUAL_COMPARISON.txt) | ASCII 可视化对比 | 3-5 分钟 |
| [ARCHITECTURE_EXPLAINED.md](full_docs/architecture/ARCHITECTURE_EXPLAINED.md) | 详细架构说明 | 10-15 分钟 |
| [FLOW_COMPARISON.md](full_docs/architecture/FLOW_COMPARISON.md) | 执行流程对比 | 15-20 分钟 |
| [GALAXY_CLOUD_CODE_WALKTHROUGH.md](full_docs/architecture/GALAXY_CLOUD_CODE_WALKTHROUGH.md) | 代码详解 | 30-45 分钟 |

**阅读顺序**: START_HERE → QUICK_CLARIFICATION → VISUAL_COMPARISON → ...

---

### 2. 功能特性文档 (full_docs/features/)

**目的**: 详细介绍各个功能特性

| 文档 | 用途 | 状态 |
|------|------|------|
| [README.md](full_docs/features/README.md) | 功能文档索引 | ✅ |
| [CLOUD_DATA_REFERENCE_README.md](full_docs/features/CLOUD_DATA_REFERENCE_README.md) | 云数据引用总览 | ✅ 核心完成 |
| [CLOUD_DATA_REFERENCE_USER_GUIDE.md](full_docs/features/CLOUD_DATA_REFERENCE_USER_GUIDE.md) | 使用指南 | ✅ 核心完成 |
| [CLOUD_DATA_REFERENCE_DESIGN.md](full_docs/features/CLOUD_DATA_REFERENCE_DESIGN.md) | 设计文档 | ✅ 核心完成 |

**云数据引用功能**:
- 跳过大文件上传，直接使用云上数据
- 节省时间和带宽
- 支持公共数据集和团队共享

---

### 3. 核心文档 (full_docs/ 根目录)

**目的**: 项目总览、集成指南、配置参考

| 文档 | 用途 | 页数 |
|------|------|------|
| [START_HERE.md](full_docs/START_HERE.md) | 快速导航 | 1 |
| [00-项目总览.md](full_docs/00-项目总览.md) | 完整架构和特性 | 15 |
| [01-快速开始指南.md](full_docs/01-快速开始指南.md) | 5步 Galaxy 集成 | 12 |
| [02-Galaxy集成详细指南.md](full_docs/02-Galaxy集成详细指南.md) | 详细配置步骤 | 18 |
| [05-Workflow云测试工具详解.md](full_docs/05-Workflow云测试工具详解.md) | 测试工具使用 | 25 |
| [07-常见问题排查.md](full_docs/07-常见问题排查.md) | 问题排查 | 15 |
| [11-配置文件完整参考.md](full_docs/11-配置文件完整参考.md) | 配置参考 | 10 |
| [12-脚本工具使用指南.md](full_docs/12-脚本工具使用指南.md) | 脚本使用 | 10 |
| [SUMMARY-已完成工作总结.md](full_docs/SUMMARY-已完成工作总结.md) | 工作总结 | 8 |

---

## 🎯 快速导航

### 新用户 - 第一次接触项目
1. 阅读 [README.md](README.md) - 项目主入口
2. 阅读 [full_docs/START_HERE.md](full_docs/START_HERE.md) - 快速导航
3. 阅读 [full_docs/architecture/QUICK_CLARIFICATION.md](full_docs/architecture/QUICK_CLARIFICATION.md) - 理解架构

### 不理解 testing/ 和 galaxy_cloud/ 的区别
1. 阅读 [full_docs/architecture/README.md](full_docs/architecture/README.md)
2. 阅读 [full_docs/architecture/QUICK_CLARIFICATION.md](full_docs/architecture/QUICK_CLARIFICATION.md)
3. 查看 [full_docs/architecture/VISUAL_COMPARISON.txt](full_docs/architecture/VISUAL_COMPARISON.txt)

### 准备 Galaxy 集成
1. 阅读 [full_docs/01-快速开始指南.md](full_docs/01-快速开始指南.md)
2. 运行 `bash scripts/check_integration_ready.sh`
3. 按步骤完成集成

### 测试 Workflow
1. 阅读 [full_docs/05-Workflow云测试工具详解.md](full_docs/05-Workflow云测试工具详解.md)
2. 运行 `cd testing && python3 test_aws_connection.py`
3. 运行 `python3 run_any_workflow.py <workflow.json>`

### 使用云数据引用功能
1. 阅读 [full_docs/features/CLOUD_DATA_REFERENCE_README.md](full_docs/features/CLOUD_DATA_REFERENCE_README.md)
2. 阅读 [full_docs/features/CLOUD_DATA_REFERENCE_USER_GUIDE.md](full_docs/features/CLOUD_DATA_REFERENCE_USER_GUIDE.md)
3. 运行 `cd examples && python3 test_cloud_data_reference.py`

### 遇到问题
1. 查看 [full_docs/07-常见问题排查.md](full_docs/07-常见问题排查.md)
2. 使用 [full_docs/12-脚本工具使用指南.md](full_docs/12-脚本工具使用指南.md) 中的诊断脚本
3. 运行 `bash scripts/diagnose_batch.sh`

---

## 📝 文档维护原则

### ✅ 应该做的

1. **所有文档放在 full_docs/**
   - 按主题分类（architecture/, features/）
   - 每个子文件夹有 README.md 索引

2. **testing/ 只保留脚本**
   - ✅ .py 文件
   - ✅ .sh 文件
   - ❌ .md 文件

3. **清晰的索引**
   - 根目录 README.md → full_docs/README.md → 子文件夹 README.md
   - 每个索引都有明确的导航

4. **文档命名规范**
   - 主题-说明.md（例如：CLOUD_DATA_REFERENCE_USER_GUIDE.md）
   - 编号-说明.md（例如：01-快速开始指南.md）

### ❌ 不应该做的

1. **不要在根目录放太多文档**
   - 只保留主 README.md
   - 其他都移到 full_docs/

2. **不要在 testing/ 放文档**
   - 测试相关的文档放 full_docs/05-Workflow云测试工具详解.md
   - INPUT_DATA_EXPLAINED.md 已移到 full_docs/

3. **不要创建孤立文档**
   - 每个文档都应该被索引引用
   - 有清晰的阅读路径

---

## 🔄 文档更新记录

### 2025-10-15 - 文档整理

**移动的文件**:
- ✅ `QUICK_CLARIFICATION.md` → `full_docs/architecture/`
- ✅ `ARCHITECTURE_EXPLAINED.md` → `full_docs/architecture/`
- ✅ `FLOW_COMPARISON.md` → `full_docs/architecture/`
- ✅ `GALAXY_CLOUD_CODE_WALKTHROUGH.md` → `full_docs/architecture/`
- ✅ `START_HERE_ARCHITECTURE.md` → `full_docs/architecture/`
- ✅ `VISUAL_COMPARISON.txt` → `full_docs/architecture/`
- ✅ `CLOUD_DATA_REFERENCE_README.md` → `full_docs/features/`
- ✅ `docs/CLOUD_DATA_REFERENCE_DESIGN.md` → `full_docs/features/`
- ✅ `docs/CLOUD_DATA_REFERENCE_USER_GUIDE.md` → `full_docs/features/`
- ✅ `testing/INPUT_DATA_EXPLAINED.md` → `full_docs/`
- ✅ `testing/README_WORKFLOW_TESTING.md` → `full_docs/`

**创建的索引**:
- ✅ `full_docs/architecture/README.md` - 架构文档索引
- ✅ `full_docs/features/README.md` - 功能文档索引

**更新的文档**:
- ✅ `README.md` - 更新文档链接
- ✅ `full_docs/README.md` - 添加新章节

---

## 📊 文档统计

| 类别 | 文档数量 | 位置 |
|------|---------|------|
| 架构理解 | 6 | full_docs/architecture/ |
| 功能特性 | 3 | full_docs/features/ |
| 核心文档 | 10 | full_docs/ |
| 测试脚本 | 6 | testing/ |
| 示例代码 | 2 | examples/ |
| 诊断脚本 | 3+ | scripts/ |
| **总计** | **30+** | - |

---

## 🔗 相关资源

- **主 README**: [README.md](README.md)
- **完整文档索引**: [full_docs/README.md](full_docs/README.md)
- **架构文档**: [full_docs/architecture/](full_docs/architecture/)
- **功能文档**: [full_docs/features/](full_docs/features/)

---

**维护者**: Galaxy Cloud Executor Team
**最后更新**: 2025-10-15
**版本**: 1.0
