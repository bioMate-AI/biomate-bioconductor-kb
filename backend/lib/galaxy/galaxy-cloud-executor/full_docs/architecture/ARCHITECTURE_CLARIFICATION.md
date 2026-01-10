# Galaxy Cloud Executor Architecture Clarification

## Current Situation

尝试直接在云端执行 Galaxy workflow 时遇到的核心问题：

### 问题

1. **容器镜像问题**：`collection_element_identifiers` 等工具没有独立的 biocontainer
2. **命令构建失败**：容器启动时没有实际的执行命令（`/bin/sh -c` 没有参数）
3. **工具包装器缺失**：Galaxy 工具不是独立可执行程序，而是需要 Galaxy 环境的包装器

### 根本原因

**Galaxy 工具的执行模型**:
```
Galaxy Tool = Tool XML Wrapper + Actual Executable + Galaxy Runtime
```

Galaxy 工具不是简单的命令行程序，而是：
1. **Tool XML**：定义输入、输出、参数、命令行模板
2. **Tool Wrapper**：解析 XML，构建命令行，处理数据集
3. **Galaxy Runtime**：提供数据集/集合管理、文件路径映射、环境变量等

### 当前架构的两种执行模式

#### 模式 1：独立 Workflow 执行（testing/）⚠️ 不完整

```
用户 → run_any_workflow.py
     → GalaxyCloudIntegration.run_workflow()
     → WorkflowDAGExecutor.execute()
     → 直接提交到 AWS Batch
```

**问题**：
- ❌ 没有 Galaxy tool wrapper 处理
- ❌ 无法正确解析工具 XML
- ❌ 无法构建正确的命令行
- ❌ 无法处理 Galaxy 数据集/集合
- ❌ 需要为每个工具手动编写执行逻辑

**适用场景**：
- ✅ 测试 AWS Batch 连接
- ✅ 验证云基础设施
- ✅ 简单的自定义流程（不依赖 Galaxy 工具）

#### 模式 2：Galaxy 集成执行（galaxy_cloud/galaxy_workflow/galaxy_job_runner.py）✅ 正确方式

```
用户在 Galaxy UI 点击 Run
     ↓
Galaxy 内部处理
     ├─ 解析工具 XML
     ├─ 构建命令行
     ├─ 处理数据集
     └─ 调用 GalaxyCloudJobRunner.queue_job()
           ↓
           CloudExecutor.submit_job()
           ↓
           AWS Batch 执行
```

**优势**：
- ✅ Galaxy 处理所有工具包装器逻辑
- ✅ 正确的命令行构建
- ✅ 完整的数据集/集合支持
- ✅ 利用 Galaxy 现有的工具生态系统
- ✅ 用户使用 Galaxy UI，无需学习新工具

## 解决方案

### 短期：测试工具（testing/）

**目的**：验证 AWS Batch 配置和云基础设施

**当前状态**：
- ✅ AWS 连接正常
- ✅ S3 数据传输正常
- ✅ 作业提交成功
- ✅ 容器可以拉取（修复后）
- ⚠️ Galaxy 工具无法独立执行（预期的限制）

**测试工具应该只用于**：
1. 测试 AWS Batch 连接：`test_aws_connection.py`
2. 测试简单作业：不依赖 Galaxy 的独立容器
3. 诊断云资源问题

**不应该用于**：
- ❌ 执行真实的 Galaxy workflow
- ❌ 运行 Galaxy 工具

### 长期：Galaxy 集成（生产方式）

**架构**：使用 `GalaxyCloudJobRunner`

**实施步骤**：

1. **配置 Galaxy** (10-15 分钟)
   ```yaml
   # config/job_conf.yml
   runners:
     galaxy_cloud:
       load: galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner
       workers: 8
       params:
         cloud_config_file: config/aws_cloud_config.yaml
         default_provider: aws

   destinations:
     aws_default:
       runner: galaxy_cloud
       params:
         provider: aws
         cpus: 2
         memory_mb: 4096

   tools:
     - id: "toolshed.g2.bx.psu.edu/repos/.*"
       destination: aws_default
   ```

2. **重启 Galaxy**
   ```bash
   sh run.sh --daemon
   ```

3. **使用 Galaxy UI 运行 Workflow**
   - 用户在 UI 点击 "Run Workflow"
   - Galaxy 自动使用云执行器
   - 结果显示在 Galaxy UI

**优势**：
- ✅ 零代码运行任何 Galaxy 工具
- ✅ 完整的 Galaxy 功能支持
- ✅ 用户友好的 UI
- ✅ 与现有 Galaxy 生态系统集成

## 下一步行动

### 如果目标是测试云基础设施

继续使用 `testing/` 工具，但使用简单的非 Galaxy 容器测试：

```bash
# 测试 AWS Batch 连接
python3 testing/test_aws_connection.py

# 测试简单作业（不使用 Galaxy 工具）
# 创建一个测试作业，运行简单命令如 echo、ls 等
```

### 如果目标是运行真实 Galaxy Workflow

**立即切换到 Galaxy 集成模式**：

1. 阅读集成文档：`full_docs/01-快速开始指南.md`
2. 配置 Galaxy job_conf.yml
3. 重启 Galaxy
4. 在 Galaxy UI 运行 workflow

## 总结

| 方面 | 独立执行 (testing/) | Galaxy 集成 (galaxy_job_runner.py) |
|------|-------------------|-----------------------------------|
| **目的** | 测试云基础设施 | 生产 Galaxy workflow 执行 |
| **工具支持** | 仅简单容器 | 所有 Galaxy 工具 |
| **命令构建** | 手动编码 | Galaxy 自动处理 |
| **数据处理** | 手动编码 | Galaxy 自动处理 |
| **用户界面** | 命令行 | Galaxy UI |
| **生产就绪** | ❌ 否 | ✅ 是 |
| **开发工作量** | 每个工具需要编码 | 配置即可 |

**建议**：
- 如果只是测试 AWS Batch → 继续使用 testing/，但不要测试 Galaxy 工具
- 如果要运行生产 workflow → 切换到 Galaxy 集成模式

---

**创建时间**: 2025-10-17
**版本**: 1.0
