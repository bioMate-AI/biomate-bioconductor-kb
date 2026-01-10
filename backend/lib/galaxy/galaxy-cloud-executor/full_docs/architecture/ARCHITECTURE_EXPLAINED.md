# Galaxy Cloud Executor 架构说明

## ⚠️ 重要：理解两种代码的区别

当前模块有**两个完全不同的部分**，用途完全不同：

---

## 第一部分：测试工具 (testing/) - 临时验证用 ✅ 已完成使命

```
testing/
├── run_any_workflow.py              ← 结构测试工具
├── run_workflow_with_real_data.py   ← 框架示例（未完成）
├── batch_test_workflows.sh          ← 批量测试脚本
└── test_aws_connection.py           ← AWS 连接测试
```

### 用途
在集成 Galaxy UI **之前**，验证 AWS Batch 基础设施能否正常工作

### 特点
- 🎯 **数据**：使用 mock 数据（自动生成的假数据）
- 🎯 **运行方式**：命令行手动执行
- 🎯 **目标**：验证 AWS Batch 配置正确

### 执行流程
```
你手动运行:
  python3 run_any_workflow.py workflow.json
    ↓
  测试工具解析 workflow JSON
    ↓
  自动生成 mock 输入数据（假数据）
    ↓
  直接调用 AWS Batch API 提交作业
    ↓
  验证作业结构、依赖关系是否正确 ✅
```

### 重要性
✅ **已完成使命**！
- 证明了 AWS Batch 基础设施可用
- 验证了复杂 workflow 的 DAG 结构
- Galaxy 集成后可以删除这些测试工具

---

## 第二部分：真正的云执行器 (galaxy_cloud/) - 生产代码 ⭐⭐⭐

```
galaxy_cloud/
├── galaxy_workflow/
│   ├── galaxy_job_runner.py    ← Galaxy UI 调用的入口点 ⭐⭐⭐
│   ├── dag_executor.py         ← Workflow DAG 执行引擎
│   ├── data_manager.py         ← S3 数据管理（上传/下载真实数据）
│   ├── step_executor.py        ← 单步任务执行
│   ├── tool_registry.py        ← 工具容器注册表
│   └── models.py               ← 数据模型
├── providers/aws/
│   ├── executor.py             ← AWS Batch 集成层
│   ├── batch_client.py         ← AWS Batch API 封装
│   └── s3_storage.py           ← S3 存储管理
├── core/
│   ├── executor.py             ← 云执行器抽象接口
│   ├── job.py                  ← 作业规范定义
│   └── storage.py              ← 存储抽象接口
└── config/
    └── cloud_config.py         ← 云配置管理
```

### 用途
**这是 Galaxy UI 真正使用的生产代码！**

### 特点
- 🎯 **数据**：使用 Galaxy 用户上传的**真实数据**
- 🎯 **运行方式**：Galaxy UI 自动调用（用户点击按钮即可）
- 🎯 **目标**：在生产环境中执行真实的生物信息学分析

### 执行流程（真实生产）
```
用户在 Galaxy UI 点击 "Run Workflow"
    ↓
Galaxy 调用: GalaxyCloudJobRunner.queue_job()
    ↓ (galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:171)
    ↓
GalaxyCloudJobRunner 创建 JobSpec
    ↓ (包含真实的工具、容器、资源配置)
    ↓
调用: DataManager.upload_input_data()
    ↓ (galaxy_cloud/galaxy_workflow/data_manager.py)
    ↓
DataManager 上传用户的真实数据到 S3
    ↓ (例如：用户的 FASTQ 文件、参考基因组等)
    ↓
调用: AWSBatchExecutor.submit_job()
    ↓ (galaxy_cloud/providers/aws/executor.py)
    ↓
AWS Batch 启动真实工具容器
    ↓ (例如：BWA, GATK, Bowtie2 等 BioContainers)
    ↓
容器从 S3 下载输入数据
    ↓
执行真实的生物信息学分析
    ↓
容器上传输出结果到 S3
    ↓
DataManager.download_output_data()
    ↓
结果下载回 Galaxy 数据库
    ↓
用户在 Galaxy UI 看到结果 🎉
```

### 重要性
⭐⭐⭐ **这才是云模块的核心**！
- 永久使用的生产代码
- Galaxy 集成后每次点击都会调用这些代码
- 处理真实用户数据和真实生物信息学工具

---

## 关键入口点：GalaxyCloudJobRunner

**位置**: `galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:31`

这是 Galaxy 调用云执行器的**唯一入口**：

```python
class GalaxyCloudJobRunner(AsynchronousJobRunner):
    """
    Galaxy job runner that executes jobs using the cloud executor framework.

    这个 runner 会在 Galaxy 的 job_conf.xml 中配置，
    让特定的工具路由到云平台执行。
    """

    def queue_job(self, job_wrapper):
        """
        Galaxy 调用这个方法来提交作业到云端

        这里会：
        1. 解析 Galaxy 作业配置
        2. 获取工具的容器镜像
        3. 上传用户的真实输入数据到 S3
        4. 创建 AWS Batch 作业定义
        5. 提交作业到 AWS Batch
        """
```

---

## 对比总结

| 项目 | 测试工具 (testing/) | 真正的云执行器 (galaxy_cloud/) |
|------|--------------------|-----------------------------|
| **用途** | 验证 AWS Batch 配置 | 生产环境执行真实分析 |
| **数据来源** | 自动生成 mock 数据 | Galaxy 用户上传的真实数据 |
| **调用方式** | 手动命令行 | Galaxy UI 自动调用 |
| **工具执行** | 简单的 echo 命令 | 真实的 BioContainers (BWA, GATK 等) |
| **输入文件** | 不需要（自动生成） | 真实文件（FASTQ, BAM, VCF 等） |
| **输出结果** | 测试日志 | 真实的分析结果 |
| **生命周期** | ✅ 已完成使命，可删除 | ⭐ 永久使用 |
| **重要性** | 临时验证工具 | **核心生产代码** |

---

## 为什么 run_workflow_with_real_data.py 不是重点？

`run_workflow_with_real_data.py` 只是一个**演示框架**，用来说明"如果要用命令行运行真实数据，需要做什么"。

但是在真实场景中：
- ❌ **不会**通过命令行手动运行
- ✅ **会**通过 Galaxy UI 自动调用 `GalaxyCloudJobRunner`
- ✅ `GalaxyCloudJobRunner` 自动处理所有数据上传、工具调用、结果下载

---

## Galaxy 集成后的用户体验

### 用户视角（他们看不到任何命令行）

1. **上传数据**：用户在 Galaxy UI 上传 FASTQ 文件
2. **选择 Workflow**：选择一个预设的分析流程（例如：变异检测）
3. **点击运行**：点击 "Run Workflow" 按钮
4. **等待结果**：在 Galaxy UI 监控进度
5. **查看结果**：分析完成后，在 Galaxy UI 下载结果

### 幕后发生的事情（全自动）

```
点击 "Run Workflow"
    ↓
Galaxy 内部调用 GalaxyCloudJobRunner ← galaxy_cloud/ 代码开始工作
    ↓
自动上传用户数据到 S3
    ↓
自动提交作业到 AWS Batch
    ↓
AWS Batch 启动真实工具容器
    ↓
容器执行真实分析
    ↓
自动下载结果回 Galaxy
    ↓
用户在 UI 看到结果 ✅
```

**用户完全不需要知道 AWS Batch、S3、容器等概念！**

---

## 现在的状态

### ✅ 已完成
1. **AWS Batch 基础设施**：100% 完成并验证
2. **测试工具**：验证了结构和依赖关系
3. **galaxy_cloud/ 核心代码**：已经完成，等待集成

### 🔄 下一步：Galaxy UI 集成
只需要 10-15 分钟配置：

1. **配置 job_conf.xml**：告诉 Galaxy 使用 `GalaxyCloudJobRunner`
2. **配置 galaxy.yml**：添加云执行器配置
3. **重启 Galaxy**：让配置生效
4. **测试**：在 UI 运行一个简单 workflow

完成这一步后，`galaxy_cloud/` 代码就开始真正工作了！

---

## 总结

**测试工具** (`testing/`) 已经完成使命 ✅
**真正的云执行器** (`galaxy_cloud/`) 等待 Galaxy 集成 ⭐⭐⭐

成功的标志不是 `run_workflow_with_real_data.py` 能运行，
而是用户在 **Galaxy UI** 点击按钮后，`galaxy_cloud/` 代码自动执行真实分析！

---

## 参考文档

- **集成指南**: `full_docs/01-快速开始指南.md`
- **配置参考**: `full_docs/11-配置文件完整参考.md`
- **架构总览**: `full_docs/00-项目总览.md`
