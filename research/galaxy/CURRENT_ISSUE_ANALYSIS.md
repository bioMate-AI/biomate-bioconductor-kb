# 当前问题分析 - Job 879提交卡住
## Date: 2025-10-30 13:50

## 现象描述

Job 879 (Create text file tool) 在文件上传完成后卡住，没有提交到AWS Batch。

## 日志时间线

```
13:41:03 - Job 879 dispatched
13:41:03 - "Submitted job 879 to cloud for execution" (这个消息有误导性)
13:41:16 - Preparing job (调用prepare())
13:41:17 - Path rewriter initialized
13:41:18 - Uploading job files
13:41:18 - File upload complete
13:41:18 - [卡住 - 没有后续日志]
```

## S3状态

✅ Job script已成功上传：
```bash
$ aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/879/
2025-10-30 13:41:20       1411 jobs/879/job_script.sh
```

## 预期行为 vs 实际行为

**预期：**
```
13:41:18 - File upload complete
13:41:18 - Getting tool container image...
13:41:19 - Creating job spec...
13:41:20 - Submitting to AWS Batch...
13:41:21 - [879] Submitted as cloud job <job-id> (universal fetch-and-run)
```

**实际：**
```
13:41:18 - File upload complete
[没有后续日志]
```

## 问题定位

代码执行卡在`_submit_fetch_and_run_job()`的某个地方，可能的位置：

1. **Line 1174:** `await self._get_tool_container_image(job_wrapper)` - 调用tool registry API可能超时
2. **Line 1209:** `await self._get_cloud_executor(cloud_provider, job_destination)` - 创建cloud executor可能卡住
3. **Line 1210:** `await cloud_executor.submit_job(job_spec)` - 提交AWS Batch可能超时

## 误导性日志

有一条日志很误导：
```
13:41:03 INFO Submitted job 879 to cloud for execution
```

这条日志在`queue_job()`中打印，**在实际提交AWS Batch之前**。
这条消息应该改为：
```
"Started cloud submission process for job 879"
```

## 根本原因分析

### 可能原因 #1: Tool Registry API超时 (最可能)

`_get_tool_container_image()`调用tool registry API:
```python
container_info = await self.tool_registry.get_tool_container(
    package_name,
    package_version
)
```

如果API响应慢或网络问题，可能导致超时。

### 可能原因 #2: AWS API调用无限期等待

boto3客户端默认没有timeout设置。如果AWS API响应慢，可能无限期等待。

### 可能原因 #3: Event Loop死锁

async/await调用链中可能存在死锁。

## 建议修复

### 修复 #1: 添加超时保护

```python
# In _submit_fetch_and_run_job()

# 添加超时保护
import asyncio

try:
    # Get tool container image with timeout
    self.logger.info(f"[{job_id}] Getting tool container image...")
    tool_container_image = await asyncio.wait_for(
        self._get_tool_container_image(job_wrapper),
        timeout=30.0  # 30 seconds timeout
    )
    self.logger.info(f"[{job_id}] Tool container: {tool_container_image or 'none'}")

    # Create job spec
    self.logger.info(f"[{job_id}] Creating job specification...")
    job_spec = JobSpec(...)

    # Get cloud executor with timeout
    self.logger.info(f"[{job_id}] Getting cloud executor...")
    cloud_executor = await asyncio.wait_for(
        self._get_cloud_executor(cloud_provider, job_destination),
        timeout=10.0
    )

    # Submit to AWS Batch with timeout
    self.logger.info(f"[{job_id}] Submitting to AWS Batch...")
    cloud_job_id = await asyncio.wait_for(
        cloud_executor.submit_job(job_spec),
        timeout=60.0  # 1 minute for AWS Batch submission
    )

    self.logger.info(f"[{job_id}] Submitted as cloud job {cloud_job_id}")

except asyncio.TimeoutError as e:
    self.logger.error(f"[{job_id}] Timeout during job submission: {e}")
    raise RuntimeError(f"Job submission timed out") from e
```

### 修复 #2: 添加详细日志

在每个异步调用前后添加日志，精确定位卡住的位置。

### 修复 #3: boto3超时配置

```python
import boto3
from botocore.config import Config

# Configure boto3 with timeouts
boto_config = Config(
    connect_timeout=10,
    read_timeout=30,
    retries={'max_attempts': 2}
)

s3_client = boto3.client('s3', region_name=aws_region, config=boto_config)
```

## 诊断步骤

1. ✅ 确认job script已上传到S3
2. ⏳ 添加更多日志确定卡住位置
3. ⏳ 添加超时保护
4. ⏳ 测试修复

## 临时解决方案

如果问题持续，可以考虑：
1. 跳过tool container image查找（使用None）
2. 使用同步boto3调用而不是异步
3. 简化AWS Batch提交流程

## 下一步行动

1. **立即:** 添加详细日志定位卡住位置
2. **短期:** 添加超时保护防止无限等待
3. **长期:** 优化异步调用链，改进错误处理

## 关键观察

这个问题**只影响新的workflow运行**。之前成功的jobs（866, 867等）都是在修复NoneType错误之前提交的。

修复NoneType错误后的第一个job（879）就卡住了，说明可能是：
1. 代码修改引入了新问题
2. 或者之前就存在但没有暴露的问题

需要对比修改前后的代码，确认是否引入了新的await调用或异步逻辑。
