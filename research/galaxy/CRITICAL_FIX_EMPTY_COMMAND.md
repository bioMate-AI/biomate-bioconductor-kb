# 🔥 关键修复：空容器命令问题

## 问题现象

所有 AWS Batch 任务都：
- ✅ 状态显示 SUCCEEDED
- ❌ 运行时间 = **0 秒**
- ❌ Exit Code = 0 (没有实际执行任何命令就退出了)

## 根本原因

AWS Batch 容器收到的命令是 **空数组 `[]`**！

### 问题追踪

1. **Galaxy 代码准备了正确的命令**:
   ```python
   # galaxy_job_runner.py line 387
   return ["/bin/sh", "-c", final_command], file_transfer_manager
   ```
   返回的 `command_args` = `["/bin/sh", "-c", "mkdir -p /galaxy/work/inputs && ..."]`

2. **JobSpec 正确创建**:
   ```python
   # galaxy_job_runner.py line 279-285
   container_spec = ContainerSpec(
       image=full_image,
       command=command,        # None (from biocontainer)
       args=command_args,      # ["/bin/sh", "-c", "..."]  ← 正确的命令在这里！
       env=...,
       working_dir=working_dir
   )
   ```

3. **AWS Batch Executor 只传递了 command，忽略了 args**:
   ```python
   # providers/aws/executor.py line 386-387 (修复前)
   if job_spec.container.command:
       container_overrides['command'] = job_spec.container.command
   # ← 没有处理 job_spec.container.args！
   ```

4. **结果**:
   - `job_spec.container.command` = None
   - `job_spec.container.args` = `["/bin/sh", "-c", "..."]`
   - AWS Batch 收到: `containerOverrides['command']` **未设置**
   - AWS Batch 默认: `command = []` (空命令)
   - 容器启动 → 没有命令 → 立即退出 → 0秒运行时间

## 修复方案

**文件**: `lib/galaxy_cloud/providers/aws/executor.py`

**位置**: Line 383-390

### 修复前:
```python
# Job parameters
if job_spec.container.command or job_spec.container.args:
    container_overrides = {}

    if job_spec.container.command:
        container_overrides['command'] = job_spec.container.command

    if job_spec.container.env:
        ...
```

### 修复后:
```python
# Job parameters
if job_spec.container.command or job_spec.container.args:
    container_overrides = {}

    if job_spec.container.command:
        container_overrides['command'] = job_spec.container.command
    elif job_spec.container.args:
        # If no command specified, use args as command
        container_overrides['command'] = job_spec.container.args  # ← 新增

    if job_spec.container.env:
        ...
```

**逻辑**:
- 如果 `job_spec.container.command` 有值 → 使用它
- 否则，如果 `job_spec.container.args` 有值 → 使用它作为命令
- 这样确保命令不会丢失

## 验证修复

### 重启 Galaxy

```bash
# 停止
pkill -f gunicorn; pkill -f celery

# 清理缓存（已完成）
find lib/galaxy_cloud -name "*.pyc" -delete
find lib/galaxy_cloud -type d -name "__pycache__" -exec rm -rf {} +

# 启动
bash start_with_debug_log.sh
```

### 运行测试 workflow

运行任何 workflow (如 Enhanced Cloud Test Workflow)

### 检查 AWS Batch

```bash
# 获取最新任务
LATEST_JOB=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 1 --query 'jobSummaryList[0].jobId' --output text)

# 查看命令
aws batch describe-jobs --jobs $LATEST_JOB --query 'jobs[0].container.{Command:command,ExitCode:exitCode,Duration:duration}'
```

**期望看到 (修复后)**:
```json
{
    "Command": [
        "/bin/sh",
        "-c",
        "mkdir -p /galaxy/work/inputs && mkdir -p /galaxy/work/outputs && aws s3 cp s3://... && ..."
    ],
    "ExitCode": 0,
    "Duration": 15000  // ← 不再是 0！应该是实际运行时间(毫秒)
}
```

**而不是 (修复前)**:
```json
{
    "Command": [],  // ← 空命令！
    "ExitCode": 0,
    "Duration": 0
}
```

### 检查 CloudWatch 日志

```bash
# 获取日志流名称
LOG_STREAM=$(aws batch describe-jobs --jobs $LATEST_JOB --query 'jobs[0].container.logStreamName' --output text)

# 查看日志
aws logs tail /aws/batch/job --log-stream-names $LOG_STREAM --since 10m
```

**期望看到**:
```
+ mkdir -p /galaxy/work/inputs
+ mkdir -p /galaxy/work/outputs
+ aws s3 cp s3://galaxy-cloud-data-1760241377/workflows/XXX/inputs/input_0_dataset_xxx.dat /galaxy/work/inputs/...
download: s3://... to /galaxy/work/inputs/...
+ fastqc /galaxy/work/inputs/...
Analysis complete for /galaxy/work/inputs/...
+ aws s3 cp /galaxy/work/outputs/... s3://...
upload: /galaxy/work/outputs/... to s3://...
```

## 影响范围

### 修复前 - 完全不工作

- ❌ 所有任务运行 0 秒
- ❌ 容器收到空命令
- ❌ 没有文件处理
- ❌ 没有工具执行
- ❌ 输出文件不存在
- ⚠️ 但任务显示 SUCCESS (因为容器正常退出，exit code 0)

### 修复后 - 应该正常工作

- ✅ 任务实际执行工具
- ✅ 运行时间 > 0 秒
- ✅ 输入文件从 S3 下载
- ✅ 工具处理文件
- ✅ 输出文件上传到 S3
- ✅ 输出文件下载回 Galaxy
- ⚠️ 可能仍有部分输出文件 404 (路径映射问题，下一步修复)

## 其他观察

### 为什么之前的日志显示成功？

在之前的测试中，日志显示：
```
INFO Uploaded 1 input files
INFO Job prepared with file transfers
INFO Submitted job galaxy-142 to AWS Batch
```

这些都是 **Galaxy 端** 的日志，说明：
- ✅ Galaxy 正确准备了命令
- ✅ 文件上传到 S3 成功
- ✅ 任务提交成功

但是 **AWS Batch 端** 没有收到命令，所以：
- ❌ 容器没有执行任何操作
- ❌ 立即退出（0秒）

### Docker 容器的默认行为

当 Docker 容器启动时没有指定命令：
1. 使用 Dockerfile 中的 `CMD` (如果有)
2. 如果 `CMD` 是空的或不存在 → 容器立即退出
3. Exit code = 0 (因为没有错误，只是没有任务)

BioContainers 通常没有默认的 `CMD`，所以：
- 容器启动
- 没有命令执行
- 立即退出
- AWS Batch 记录为 SUCCESS, Duration = 0

## 修复总结

这是**最关键的修复**！没有这个修复，整个云执行功能完全不工作。

| 组件 | 修复前 | 修复后 |
|------|--------|--------|
| Galaxy 命令准备 | ✅ 正确 | ✅ 正确 |
| 文件上传 | ✅ 正确 | ✅ 正确 |
| AWS Batch 提交 | ✅ 成功 | ✅ 成功 |
| **容器命令** | ❌ **空** | ✅ **正确** |
| 容器执行 | ❌ 0秒退出 | ✅ 实际运行 |
| 输出文件 | ❌ 不存在 | ✅ 生成并上传 |

## 历史修复回顾

整个修复过程涉及多个问题：

1. ✅ **Storage Provider 错误** - SimpleS3Storage 类
2. ✅ **S3 Bucket 参数** - 兼容性修复
3. ✅ **重复监控** - monitoring_started 标志
4. ✅ **空容器命令** - **本次修复** (最关键！)
5. ⏳ **输出文件 404** - 待修复 (路径映射)

现在，经过本次修复，核心的云执行流程应该完全工作了！
