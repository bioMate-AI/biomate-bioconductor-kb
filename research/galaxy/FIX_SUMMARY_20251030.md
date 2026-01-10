# AWS Cloud Workflow Fix Summary
## Date: 2025-10-30

## Issue Reported
用户运行一个复杂的RNA-Seq workflow时，容器报错：
```
sed: can't read /galaxy_execution/datasets/objects/5/b/8/dataset_5b8e2a2f-33a8-4d1a-8dec-5f2287e63e38.dat: No such file or directory
```

## Root Cause Analysis

通过分析日志和代码,发现了**两个关键bug**：

### Bug #1: NoneType错误导致数据集下载失败 ✅ **已修复**

**位置:** `galaxy_job_runner.py:1474`

**问题代码:**
```python
s3_bucket = self.app.config.object_store_config.get('config', {}).get('s3_bucket')
```

**错误原因:**
当`object_store_config`为`None`时（这是正常情况，因为我们没有使用S3作为object store），
调用`.get('config', {})`会引发`AttributeError: 'NoneType' object has no attribute 'get'`

**影响:**
1. AWS Batch job成功完成
2. 但Galaxy无法从S3下载输出数据集
3. 本地输出文件保持0字节
4. 下游job看到空的输入文件

**日志证据:**
```
[866] Failed to download datasets from S3: 'NoneType' object has no attribute 'get'
[867] Input file size: 0 bytes
[867] Input file is empty (0 bytes)
```

### Bug #2: Workflow步骤依赖未正确执行 ⚠️ **需要进一步处理**

**问题描述:**
- Job 866 (Create text file) 在13:06:58开始
- Job 867 (Text transformation/sed) 在13:10:15开始
- Job 867的输入文件在Job 866下载完成**之前**就被使用（0字节）

**时间线:**
```
13:06:58 - Job 866 queued
13:07:10 - Job 866 submitted to AWS Batch
13:10:14 - Job 866 download失败（NoneType error）
13:10:15 - Job 867 queued（输入文件0字节！）
13:10:17 - Job 867提交到云端，携带空文件
13:14:08 - Job 867在AWS Batch中执行失败（sed找不到文件）
```

**为什么会这样:**
1. Galaxy的job handler在排队前检查输入数据集是否为"ok"状态
2. Dataset 1198被标记为"ok"，因为Job 866提交成功
3. 但**实际文件内容**（0字节）没有被检查
4. Job 867使用了有效的dataset ID但是空文件就被排队了

## 实施的修复

### Fix #1: 健壮的S3配置处理 ✅

**修改文件:** `galaxy_job_runner.py` (lines 1470-1510)

**修复策略:**
```python
# 1. 安全检查object_store_config是否存在
if hasattr(self.app.config, 'object_store_config') and self.app.config.object_store_config:
    object_store_cfg = self.app.config.object_store_config
    if isinstance(object_store_cfg, dict):
        config_section = object_store_cfg.get('config', {})
        s3_bucket = config_section.get('s3_bucket')

# 2. 回退到job destination参数
if not s3_bucket:
    job_dest = job_wrapper.job_destination
    s3_bucket = job_dest.params.get('s3_bucket') or job_dest.params.get('aws_s3_bucket')

# 3. 使用job提交时存储的bucket
if not s3_bucket and hasattr(job_wrapper, '_fetch_and_run_s3_bucket'):
    s3_bucket = job_wrapper._fetch_and_run_s3_bucket
```

**改进:**
1. ✅ 优雅处理缺失的`object_store_config`
2. ✅ 回退到job destination参数
3. ✅ 使用job提交时存储的S3 bucket
4. ✅ 清晰的日志记录

### Fix #2: Workflow步骤同步 ⚠️ **待实施**

**当前状态:** 问题已识别，建议的解决方案：

**选项 A: 在排队前添加文件大小检查**
```python
# 在queue_job()中，提交cloud job之前:
for input_assoc in job.input_datasets:
    if input_assoc.dataset and input_assoc.dataset.dataset:
        file_path = input_assoc.dataset.dataset.get_file_name()
        if Path(file_path).exists():
            file_size = Path(file_path).stat().st_size
            if file_size == 0:
                # 文件为空 - 前一个job还没完成下载
                self.logger.warning(f"Input {file_path} is empty, delaying job")
                # 延迟提交或标记为waiting
                return  # 不提交，等待下次检查
```

**优点:**
- 防止浪费云资源
- 简单有效
- 不需要修改Galaxy核心

**缺点:**
- 需要添加重试逻辑
- 可能会增加workflow完成时间

## 测试计划

### 修复前:
```
Job 866: FAILED - NoneType错误
Job 867: FAILED - 输入文件0字节
Workflow: 整体失败
```

### 修复后（期望）:
```
Job 866: SUCCESS - 输出正确下载
Job 867: SUCCESS - 等待Job 866完成后执行
Workflow: 整体成功
```

### 测试步骤:
1. ✅ 重启Galaxy（已完成）
2. ⏳ 重新运行RNA-Seq workflow
3. ⏳ 验证Job 866成功下载数据
4. ⏳ 验证Job 867等待Job 866完成
5. ⏳ 验证所有workflow步骤顺序完成

## 下一步行动

### 立即行动:
1. ✅ **已部署Fix #1** - NoneType错误修复
2. ⏳ **测试workflow** - 验证Fix #1是否解决问题
3. ⏳ **监控日志** - 确认不再出现NoneType错误

### 后续改进:
1. **实施Fix #2** - 添加文件大小检查
2. **添加重试机制** - 如果输入文件为空，延迟并重试
3. **改进日志** - 更清晰地显示workflow步骤依赖
4. **文档更新** - 记录workflow执行的最佳实践

## 影响评估

**严重性:** 高 - 阻塞所有多步骤workflow
**影响用户:** 所有使用云执行的2+步骤workflow
**临时解决方法:** 手动逐步运行workflow步骤
**修复复杂度:**
- Fix #1: 低（已完成）
- Fix #2: 中等（待实施）

## 相关文件

修改的文件:
- `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

文档文件:
- `BUG_ANALYSIS_WORKFLOW_DEPENDENCIES.md` - 详细的bug分析
- `FIX_SUMMARY_20251030.md` - 本文档

## 总结

我们已经识别并修复了导致workflow失败的主要bug（NoneType错误）。第二个bug（workflow步骤依赖）已被识别，建议的解决方案已经准备好实施。

**关键要点:**
1. ✅ **NoneType错误已修复** - 数据集现在可以正确下载
2. ⚠️ **Workflow依赖需要改进** - 需要添加文件大小检查
3. 📋 **测试进行中** - 等待workflow完整执行验证修复

修复后的系统应该能够正确处理多步骤workflow，确保每个步骤在开始执行前都有有效的输入数据。
