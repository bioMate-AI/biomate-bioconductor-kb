# Galaxy Workflow 云执行测试工具

## 📋 概述

已创建的通用工具可以自动将任意 Galaxy workflow JSON 文件部署到 AWS Batch 云上执行。

## ✅ 已完成的修复

### 1. 支持两种 Workflow JSON 格式
- **格式1**: 直接包含 `steps` 字段
- **格式2**: 外层有 `workflow_json` 字段，`steps` 在内层

### 2. AWS Batch Job Name 规范化
- 自动清理特殊字符（空格、冒号、斜杠等）
- 处理 `None` 或空 label
- 智能步骤命名（优先级：label > name > tool_id > step_id）
- 符合 AWS 规则：只包含字母、数字、连字符、下划线

### 3. 空 Workflow 处理
- 自动跳过没有步骤的 workflow
- 不会报错，继续处理下一个

### 4. 自动依赖分析
- 拓扑排序，自动分层执行
- 并行执行同层步骤
- 自动处理步骤依赖关系

## 🚀 使用方法

### 方法0: 测试 AWS 连接（推荐先运行）⭐

在测试 workflow 之前，先验证 AWS 连接是否正常：

```bash
cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/testing

# 测试 AWS 连接
python3 test_aws_connection.py
```

**测试内容**：
- ✅ AWS 凭证有效性
- ✅ Batch 队列连接和状态
- ✅ S3 存储桶访问（读写权限）
- ✅ CloudWatch Logs 连接
- ✅ IAM 角色配置

**输出示例**：
```
================================================================================
  AWS 连接测试
================================================================================

配置:
  区域: us-west-2
  Batch 队列: galaxy-cloud-queue
  S3 存储桶: galaxy-cloud-data-1760241377

================================================================================
  测试 1: AWS 凭证
================================================================================

✅ PASS: AWS 凭证有效
       Account: 399683337364
       ARN: arn:aws:sts::399683337364:assumed-role/...

================================================================================
测试汇总
================================================================================
✅ AWS 凭证
✅ AWS Batch
✅ S3 存储
✅ CloudWatch Logs
✅ IAM 角色

通过率: 5/5 (100%)

🎉 所有测试通过！AWS 连接正常。
```

### 方法1: 测试单个 Workflow

```bash
cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/testing

# 设置环境变量（每次新终端都需要）
export AWS_DEFAULT_REGION="us-west-2"
export AWS_BATCH_QUEUE="galaxy-cloud-queue"
export AWS_S3_BUCKET="galaxy-cloud-data-1760241377"
export AWS_BATCH_JOB_ROLE_ARN="arn:aws:iam::399683337364:role/BatchJobRole"

# 运行任意 workflow
python3 run_any_workflow.py <workflow路径>
```

**示例**:
```bash
# 测试已验证成功的 workflow
python3 run_any_workflow.py ../../ai/data/workflows/workflow_00a4dbc9329c638b.json

# 测试其他 workflow
python3 run_any_workflow.py ../../ai/data/workflows/workflow_00381bbae3fd7e78.json
```

### 方法2: 批量测试多个 Workflows

```bash
cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/testing

# 测试 5 个 workflows（默认）
./batch_test_workflows.sh

# 测试 10 个 workflows
./batch_test_workflows.sh 10

# 测试所有 workflows
./batch_test_workflows.sh 100
```

**功能**:
- ✅ 自动遍历 `../../ai/data/workflows/` 下所有 workflow 文件
- ✅ 生成详细日志文件（每个 workflow 一个）
- ✅ 生成测试汇总报告（成功率、失败列表）
- ✅ 每个测试间隔 10 秒，避免过载

## 🔧 重要提示

### AWS 凭证刷新

AWS 凭证会定期过期，如果看到 `UnrecognizedClientException` 错误，需要重新登录：

```bash
aws sso login
```

登录成功后，再运行测试命令。

### 验证凭证状态

```bash
# 检查凭证是否有效
aws sts get-caller-identity

# 如果返回账户信息，说明凭证有效
# 如果报错，需要重新登录
```

## 📊 工具特性

### 自动分析 Workflow 结构
```
================================================================================
Workflow 云执行测试
================================================================================

Workflow 名称: Ref-guided WPS processing_whole data
步骤数: 10
执行层数: 7
最大并行度: 3

执行计划:
  Layer 0: 2 步骤 - ['0', '1']
  Layer 1: 3 步骤 - ['2', '3', '4']
  Layer 2: 1 步骤 - ['5']
  Layer 3: 1 步骤 - ['6']
  Layer 4: 1 步骤 - ['7']
  Layer 5: 1 步骤 - ['8']
  Layer 6: 1 步骤 - ['9']
```

### 实时进度跟踪
```
================================================================================
Layer 0: 2 个步骤
================================================================================
  ✓ 提交作业: Input_dataset -> 7df2b3c3...
  ✓ 提交作业: Input_dataset -> d17ea3f8...

等待 2 个作业完成...
  ✓ Input_dataset 完成 (115.5s)
  ✓ Input_dataset 完成 (115.5s)

所有作业完成，总耗时: 115.5秒 (1.9分钟)
```

### 成功汇总
```
================================================================================
✅ Workflow 执行成功!
================================================================================
总步骤数: 14
总层数: 7
总耗时: 892.3秒 (14.9分钟)

S3 输出路径: s3://galaxy-cloud-data-1760241377/workflow-test-20251015-164727/
测试ID: 20251015-164727
```

## 📁 文件结构

```
testing/
├── run_any_workflow.py          # 单个 workflow 测试工具
├── batch_test_workflows.sh      # 批量测试脚本
├── README_WORKFLOW_TESTING.md   # 本文档
└── test_results_<timestamp>/    # 测试结果目录（自动生成）
    ├── workflow_xxx.log         # 每个 workflow 的详细日志
    └── ...
```

## 🎯 已验证的功能

1. ✅ **14步复杂 workflow** 测试成功（workflow_00a4dbc9329c638b.json）
   - 7 层执行
   - 最大并行度 5
   - 总耗时约 15 分钟

2. ✅ **Job name 规范化** 修复完成
   - 处理 `None` label
   - 清理特殊字符
   - 智能命名策略

3. ✅ **双层 JSON 格式** 支持
   - 自动识别 `workflow_json` 字段
   - 兼容两种 workflow 格式

4. ✅ **空 workflow 跳过** 逻辑
   - 不会因空 workflow 而中断
   - 继续处理后续文件

## 🔍 下一步测试建议

1. **刷新 AWS 凭证**:
   ```bash
   aws sso login
   ```

2. **运行批量测试**:
   ```bash
   cd /Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/testing
   ./batch_test_workflows.sh 5
   ```

3. **查看测试结果**:
   - 检查控制台输出的成功率
   - 查看 `test_results_*/` 目录中的详细日志

## 🐛 常见问题

### Q: 报错 "Job name should match valid pattern"
**A**: 已修复！现在会自动清理 job name 中的特殊字符。

### Q: 报错 "The security token included in the request is invalid"
**A**: AWS 凭证过期，运行 `aws sso login` 重新登录。

### Q: Workflow 显示 "步骤数: 0"
**A**: 可能是 JSON 格式问题，工具会自动跳过并继续。

### Q: 如何查看失败的作业详细信息？
**A**: 使用 `check_failed_job.py` 工具：
```bash
python3 check_failed_job.py <job-id>
```

## 📝 技术细节

### Job Name 清理规则
```python
# 清理前: "Processing Reference " (有空格)
# 清理后: "Processing_Reference"

# 清理前: None
# 清理后: "step"

# 清理前: "toolshed.g2.bx.psu.edu/repos/iuc/minimap2"
# 清理后: "minimap2"
```

### 步骤命名优先级
1. `step_data['label']` - 用户定义的标签
2. `step_data['name']` - 步骤名称
3. `step_data['tool_id'].split('/')[-1]` - 工具名称（最后一段）
4. `f'step_{step_id}'` - 兜底方案

### AWS Batch 集成
- **容器镜像**: `amazonlinux:2`
- **自动安装 AWS CLI**: 每个作业启动时自动安装
- **资源配置**: 1 vCPU, 512MB 内存（可调整）
- **日志**: CloudWatch Logs `/aws/batch/job`

## 🎉 成功案例

### 测试 1: workflow_00a4dbc9329c638b.json
- ✅ 14 步骤，7 层
- ✅ 最大并行度 5
- ✅ 总耗时 14.9 分钟
- ✅ 所有作业成功

### 测试 2: workflow_00381bbae3fd7e78.json（修复后待测试）
- 10 步骤，7 层
- 最大并行度 3
- 预计耗时 10-15 分钟

---

**更新时间**: 2025-10-15
**状态**: 工具已就绪，等待 AWS 凭证刷新后进行批量测试
