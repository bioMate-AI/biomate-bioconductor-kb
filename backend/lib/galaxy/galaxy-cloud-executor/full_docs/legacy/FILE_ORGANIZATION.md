# 文件组织说明

本文档记录了Galaxy Cloud Executor的文件组织结构调整。

---

## 📁 新的目录结构

```
galaxy-cloud-executor/
├── README.md                       # 主README（已更新）
├── galaxy_cloud/                   # ⭐ 核心代码（生产级通用云执行框架）
│   ├── core/                       # 执行引擎
│   ├── galaxy_workflow/            # Galaxy集成
│   └── providers/                  # 云提供商（AWS/GCP/Azure/K8s）
│
├── scripts/                        # 🔧 辅助脚本（新建）
│   ├── README.md                   # 脚本使用说明
│   ├── aws/                        # AWS工具
│   │   ├── check_logs.sh          # 查看AWS Batch作业日志
│   │   ├── refresh_credentials.sh # 刷新AWS凭证
│   │   ├── setup_credentials.sh   # AWS凭证设置助手
│   │   └── test_config.sh         # 测试AWS配置
│   └── workflow/                   # Workflow执行脚本
│       └── run_qiime2_cloud.sh    # QIIME2 workflow云执行
│
├── testing/                        # 🧪 Workflow测试工具
│   ├── run_any_workflow.py
│   ├── batch_test_workflows.sh
│   └── test_aws_connection.py
│
├── full_docs/                      # 📚 完整文档集
│   ├── README.md                   # 文档索引（已更新）
│   ├── 通用模块运行/               # ⭐ 通用模块使用指南（新增）
│   │   ├── 00-运行准备.md          # 运行前检查清单
│   │   ├── 00-问题修复总结.md      # 所有问题修复记录
│   │   ├── 01-快速开始.md          # 3步快速上手
│   │   ├── 02-详细使用指南.md      # 架构和原理详解
│   │   ├── 03-问题排查.md          # 问题解决方案
│   │   ├── 04-测试脚本说明.md      # 所有脚本文档
│   │   ├── 05-Galaxy平台调用栈详解.md  # 完整调用链路
│   │   ├── 06-Python环境配置说明.md    # Python环境配置
│   │   └── 07-脚本Python环境检测详解.md # 环境检测机制
│   ├── architecture/               # 架构设计文档
│   └── features/                   # 功能说明文档
│
├── test_data/                      # 测试数据
│   └── qiime2_demo/               # QIIME2测试数据（3个FASTQ文件）
│
├── config/                         # ⚙️ 配置模板
└── examples/                       # 示例代码
```

---

## 🔄 文件移动记录

### 脚本移动

| 原位置 | 新位置 | 说明 |
|--------|--------|------|
| `check_aws_logs.sh` | `scripts/aws/check_logs.sh` | 查看AWS Batch日志 |
| `refresh_aws_credentials.sh` | `scripts/aws/refresh_credentials.sh` | 刷新AWS凭证 |
| `setup_aws_credentials.sh` | `scripts/aws/setup_credentials.sh` | 凭证设置助手 |
| `test_aws_config.sh` | `scripts/aws/test_config.sh` | AWS配置测试 |
| `run_qiime2_cloud.sh` | `scripts/workflow/run_qiime2_cloud.sh` | QIIME2执行脚本 |

### 文档移动

| 原位置 | 新位置 | 说明 |
|--------|--------|------|
| `READY_TO_RUN.md` | `full_docs/通用模块运行/00-运行准备.md` | 运行准备文档 |

### 新创建的文档

| 路径 | 说明 |
|------|------|
| `scripts/README.md` | 脚本目录说明 |
| `full_docs/通用模块运行/00-问题修复总结.md` | 问题修复记录 |
| `full_docs/通用模块运行/01-快速开始.md` | 快速开始 |
| `full_docs/通用模块运行/02-详细使用指南.md` | 详细指南 |
| `full_docs/通用模块运行/03-问题排查.md` | 问题排查 |
| `full_docs/通用模块运行/04-测试脚本说明.md` | 脚本说明 |
| `full_docs/通用模块运行/05-Galaxy平台调用栈详解.md` | 调用栈 |
| `full_docs/通用模块运行/06-Python环境配置说明.md` | Python环境 |
| `full_docs/通用模块运行/07-脚本Python环境检测详解.md` | 环境检测 |

---

## 📝 更新的文档

### README.md（主README）

**更新内容**:
- 添加了"通用模块运行"章节（推荐入口）
- 更新了"主要工具"章节，分为：
  - 🚀 快速执行（scripts/workflow/）
  - 🔧 AWS辅助工具（scripts/aws/）
  - 🧪 Workflow测试工具（testing/）
- 更新了目录结构说明

### full_docs/README.md（文档索引）

**更新内容**:
- 添加了"通用模块运行指南"章节
- 包含9个新文档的链接和说明
- 调整了章节编号（原3-7 → 现4-8）

---

## 🎯 使用指南

### 快速开始

1. **运行前准备**
   ```bash
   # 阅读运行准备文档
   cat full_docs/通用模块运行/00-运行准备.md
   ```

2. **设置AWS凭证**
   ```bash
   # 使用凭证设置助手
   ./scripts/aws/setup_credentials.sh
   ```

3. **运行Workflow**
   ```bash
   # 执行QIIME2 workflow
   ./scripts/workflow/run_qiime2_cloud.sh
   ```

4. **查看日志**
   ```bash
   # 查看最新作业日志
   ./scripts/aws/check_logs.sh latest
   ```

### 文档导航

- **快速开始**: [full_docs/通用模块运行/01-快速开始.md](full_docs/通用模块运行/01-快速开始.md)
- **问题排查**: [full_docs/通用模块运行/03-问题排查.md](full_docs/通用模块运行/03-问题排查.md)
- **完整索引**: [full_docs/README.md](full_docs/README.md)

---

## ✅ 组织原则

### 1. **scripts/** - 可执行脚本

**目的**: 用户直接运行的辅助脚本

**子目录**:
- `aws/` - AWS相关工具（凭证、日志、测试）
- `workflow/` - Workflow执行脚本

**特点**:
- 可执行权限
- 用户友好（交互式、清晰输出）
- 独立运行

### 2. **testing/** - 测试和验证工具

**目的**: 验证AWS配置和workflow执行

**特点**:
- Python脚本为主
- 用于开发和调试
- Galaxy集成后可选

### 3. **full_docs/** - 完整文档集

**目的**: 所有文档的中心位置

**子目录**:
- `通用模块运行/` - 使用指南（新增）
- `architecture/` - 架构设计
- `features/` - 功能说明

**特点**:
- Markdown格式
- 系统化组织
- 相互引用

### 4. **galaxy_cloud/** - 核心代码

**目的**: 生产级云执行框架

**特点**:
- 通用性（任何workflow）
- 生产就绪
- 多云支持

---

## 🔍 查找文件

### 按功能查找

**AWS相关**:
- 凭证设置: `scripts/aws/setup_credentials.sh`
- 凭证刷新: `scripts/aws/refresh_credentials.sh`
- 配置测试: `scripts/aws/test_config.sh`
- 日志查看: `scripts/aws/check_logs.sh`

**Workflow执行**:
- QIIME2: `scripts/workflow/run_qiime2_cloud.sh`
- 通用执行: `examples/run_any_galaxy_workflow.py`

**文档**:
- 快速开始: `full_docs/通用模块运行/01-快速开始.md`
- 问题排查: `full_docs/通用模块运行/03-问题排查.md`
- 调用栈: `full_docs/通用模块运行/05-Galaxy平台调用栈详解.md`

**测试**:
- AWS连接: `testing/test_aws_connection.py`
- Workflow测试: `testing/run_any_workflow.py`

---

## 📅 更新历史

### 2025-10-17
- ✅ 创建 `scripts/` 目录结构
- ✅ 移动所有辅助脚本到 `scripts/`
- ✅ 创建 `full_docs/通用模块运行/` 目录
- ✅ 移动和创建通用模块文档
- ✅ 更新主README和文档索引
- ✅ 创建本组织说明文档

---

## 💡 维护建议

### 添加新脚本时

1. **确定类型**:
   - AWS工具 → `scripts/aws/`
   - Workflow执行 → `scripts/workflow/`
   - 测试验证 → `testing/`

2. **添加文档**:
   - 更新 `scripts/README.md`
   - 在主README的"主要工具"章节添加说明

### 添加新文档时

1. **确定分类**:
   - 使用指南 → `full_docs/通用模块运行/`
   - 架构设计 → `full_docs/architecture/`
   - 功能说明 → `full_docs/features/`

2. **更新索引**:
   - 更新 `full_docs/README.md`
   - 在主README相关章节添加链接

### 保持整洁

- 定期检查重复文件
- 及时删除过时文档
- 保持命名一致性
- 更新交叉引用

---

**版本**: 1.0
**最后更新**: 2025-10-17
**维护者**: Galaxy Cloud Executor Team
