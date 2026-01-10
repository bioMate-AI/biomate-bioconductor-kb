# Galaxy 完全云端Workflow执行文档

这是Galaxy完全云端执行的核心文档集，专注于让**所有Galaxy workflow在云端运行**。

---

## 🎯 核心目标

**让Galaxy的所有workflow 100%在云端执行（AWS Batch）**

- ✅ 所有Tool Shed工具 → 云端执行
- ✅ 所有内置工具 → 云端执行
- ✅ 所有workflow步骤 → 云端执行
- ❌ 只有上传和元数据工具 → 本地执行（必须）

---

## 📖 文档导航

### 🔥 必读文档（按优先级）

#### 1️⃣ [云执行原理 - HOW_CLOUD_EXECUTION_WORKS.md](./HOW_CLOUD_EXECUTION_WORKS.md)
**阅读时间**: 10分钟
**内容**:
- Galaxy workflow如何在云端执行？
- 是上传tool还是Docker？
- 配置文件如何控制？
- 如何实现100%云端执行？

**最重要的问题**：
- ❓ Galaxy工具是什么？（XML + Docker容器）
- ❓ 云端执行的完整流程是什么？
- ❓ `job_conf_cloud.yml`如何路由工具？

---

#### 2️⃣ [完全云端配置总结 - CLOUD_CONFIG_SUMMARY.md](./CLOUD_CONFIG_SUMMARY.md)
**阅读时间**: 5分钟
**内容**:
- ✅ 现在已配置为完全云端执行！
- 之前配置 vs 现在配置对比
- 资源分配策略
- 如何验证云端配置

**关键配置**：
```yaml
execution:
  default: cloud_small  # ✅ 默认云端！

tools:
  - id: "__UPLOAD__"
    environment: local  # 例外
  - id: "__SET_METADATA__"
    environment: local  # 例外
  - id: ".*"
    environment: cloud_small  # ✅ 所有其他工具云端！
```

---

#### 3️⃣ [真实Workflow测试指南 - REAL_WORKFLOW_TEST_GUIDE.md](./REAL_WORKFLOW_TEST_GUIDE.md)
**阅读时间**: 10分钟
**内容**:
- 真实的6步生物信息学workflow
- 批量安装所有工具
- 准备真实测试数据
- 运行完整云端测试
- 验证AWS Batch执行

**Workflow步骤**:
```
Input FASTQ → FastQC → Trimmomatic → FastQC → Bowtie2 → BAM Stats
```

---

### 📚 进阶文档

#### [Galaxy云端设置 - GALAXY_CLOUD_SETUP.md](./GALAXY_CLOUD_SETUP.md)
- Galaxy与AWS Batch集成配置
- 环境变量设置
- 启动脚本

#### [快速开始 - QUICK_START.txt](./QUICK_START.txt)
- 测试云执行的最快路径
- 一键命令参考

#### [测试步骤 - QUICK_TEST_STEPS.md](./QUICK_TEST_STEPS.md)
- 简单测试workflow的步骤
- 快速验证配置

#### [如何测试云执行 - HOW_TO_TEST_CLOUD_EXECUTION.md](./HOW_TO_TEST_CLOUD_EXECUTION.md)
- 测试方法详解
- 检查AWS Batch作业

---

### 🏗️ 云执行架构

#### [目录结构 - DIRECTORY_STRUCTURE.md](./DIRECTORY_STRUCTURE.md)
- Galaxy云模块代码位置
- `lib/galaxy/galaxy-cloud-executor/` - 核心代码
- `lib/galaxy_cloud` - 软链接

#### [云模块README - galaxy-cloud-executor/README.md](../lib/galaxy/galaxy-cloud-executor/README.md)
- Galaxy Cloud Executor完整文档
- 架构设计
- testing/ vs galaxy_cloud/ 对比

---

### 📋 参考文档

#### [测试文件路径 - TEST_FILES_PATH.txt](./TEST_FILES_PATH.txt)
- Workflow文件位置
- 测试数据位置

#### [云设置指南 - cloud_setup_guide.md](./cloud_setup_guide.md)
- AWS凭证配置
- AWS资源设置

#### [测试总结 - testing_summary.md](./testing_summary.md)
- 历史测试记录

---

## 🚀 快速开始（3步）

### 第1步：理解云执行原理
```bash
cat all_docs/HOW_CLOUD_EXECUTION_WORKS.md
```

**核心概念**：
- Galaxy工具 = XML描述 + Docker容器镜像
- 云端执行 = AWS Batch运行Docker容器
- job_conf_cloud.yml控制工具路由

### 第2步：确认完全云端配置
```bash
cat all_docs/CLOUD_CONFIG_SUMMARY.md
```

**验证配置**：
```bash
# 检查默认执行环境
grep "default:" config/job_conf_cloud.yml

# 应该看到：
# default: cloud_small  ✅
```

### 第3步：运行真实workflow测试
```bash
cat all_docs/REAL_WORKFLOW_TEST_GUIDE.md
```

**测试流程**：
1. 安装workflow需要的工具（FastQC, Trimmomatic, Bowtie2等）
2. 导入真实workflow文件
3. 上传测试数据
4. 运行workflow
5. 验证所有步骤在AWS Batch执行

---

## ✅ 当前配置状态

### 完全云端执行 ✅

| 工具类型 | 执行位置 | 状态 |
|---------|---------|------|
| Tool Shed工具 | AWS Batch | ✅ 云端 |
| 内置工具 | AWS Batch | ✅ 云端 |
| FastQC | AWS Batch (cloud_small) | ✅ 云端 |
| Trimmomatic | AWS Batch (cloud_medium) | ✅ 云端 |
| Bowtie2 | AWS Batch (cloud_large) | ✅ 云端 |
| 上传工具 | 本地 | ⚠️ 必须本地 |
| 元数据工具 | 本地 | ⚠️ 必须本地 |
| **所有其他工具** | AWS Batch (cloud_small) | ✅ 云端 |

### AWS资源配置

| 环境 | vCPUs | 内存 | 磁盘 | 用途 |
|------|-------|------|------|------|
| cloud_small | 2 | 4GB | 20GB | 默认环境、轻量工具 |
| cloud_medium | 4 | 8GB | 50GB | 中等计算工具 |
| cloud_large | 8 | 16GB | 100GB | 计算密集工具 |

### 配置文件位置

```
/Users/renyuankai/work/biometa/galaxy/config/job_conf_cloud.yml
```

---

## 🔍 验证云端执行

### 方法1：查看Galaxy作业详情
```
1. 在Galaxy UI运行workflow
2. 点击历史记录中的作业
3. 查看 "Job Destination"
4. 应该显示: cloud_small / cloud_medium / cloud_large
```

### 方法2：查看AWS Batch作业
```bash
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING
```

### 方法3：查看S3数据传输
```bash
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive
```

### 方法4：查看Galaxy日志
```bash
tail -f galaxy_startup.log | grep -i "submit.*batch\|destination.*cloud"
```

---

## 💡 关键理解

### Galaxy云执行的核心
```
Galaxy UI
   ↓ (用户运行workflow)
Galaxy Job Manager
   ↓ (读取job_conf_cloud.yml)
GalaxyCloudJobRunner
   ↓ (上传数据到S3)
AWS Batch
   ↓ (启动Docker容器)
BioContainer工具执行
   ↓ (输出到S3)
Galaxy下载结果
   ↓
显示给用户 ✅
```

### 为什么是Docker而不是上传工具？

**❌ 错误理解**：上传工具程序到云端执行
**✅ 正确理解**：云端拉取Docker镜像执行

每个Galaxy工具都指定了Docker镜像：
```xml
<tool id="fastqc">
  <requirements>
    <container type="docker">
      quay.io/biocontainers/fastqc:0.11.9
    </container>
  </requirements>
</tool>
```

AWS Batch执行时：
1. 拉取Docker镜像（如果本地没有）
2. 从S3下载输入数据
3. 运行容器执行工具
4. 上传输出到S3

### 100%云端的唯一例外

只有2个工具**必须**在本地：
- `__UPLOAD__` - 需要直接访问Galaxy文件系统
- `__SET_METADATA__` - 需要直接操作Galaxy数据库

这两个工具执行非常快（<1秒），本地执行更合理。

---

## 📞 下一步

### 如果你想立即测试云执行

```bash
# 阅读测试指南
cat all_docs/REAL_WORKFLOW_TEST_GUIDE.md

# 运行批量工具安装
python3 install_workflow_tools.py

# 导入workflow
# 上传测试数据
# 运行workflow
# 验证云端执行
```

### 如果你想深入理解

```bash
# 理解云执行原理
cat all_docs/HOW_CLOUD_EXECUTION_WORKS.md

# 查看完整配置
cat config/job_conf_cloud.yml

# 查看云模块代码
cat lib/galaxy/galaxy-cloud-executor/README.md
```

---

## 🎉 总结

**你的Galaxy现在是100%云端执行配置！**

- ✅ 默认执行环境：`cloud_small`（云端）
- ✅ Tool Shed工具：100%云端
- ✅ 内置工具：99%云端（除上传和元数据）
- ✅ Workflow执行：完全在AWS Batch
- ✅ 资源自动分配：根据工具类型
- ✅ Docker镜像：自动从BioContainers拉取

**配置文件**: [config/job_conf_cloud.yml](../config/job_conf_cloud.yml)
**云模块代码**: [lib/galaxy/galaxy-cloud-executor/](../lib/galaxy/galaxy-cloud-executor/)
**AWS资源**: Batch Queue + S3 + CloudWatch

---

**文档更新时间**: 2025-10-18
**Galaxy版本**: dev
**云模块版本**: 1.0
