# S3 Bucket 参数修复状态

## 问题根因

**配置文件使用 `aws_s3_bucket`，但代码检查 `s3_bucket`**

### 配置文件 (`config/job_conf_cloud.yml`):
```yaml
cloud_small:
  params:
    aws_s3_bucket: galaxy-cloud-data-1760241377  # ← 配置文件用这个名字
```

### 代码中的两个不同位置:

1. **`_build_provider_config()` (line 115-116)** - ✅ 正确处理:
   ```python
   if 'aws_s3_bucket' in params:
       config['s3_bucket'] = params['aws_s3_bucket']  # 转换成 s3_bucket
   ```

2. **`_build_command_args()` (line 331)** - ❌ 修复前失败 → ✅ 已修复:
   ```python
   # 修复前（失败）:
   s3_bucket = job_destination.params.get('s3_bucket')  # 找不到！

   # 修复后（成功）:
   s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
   ```

## 修复验证

### ✅ 代码修复已应用
- 文件: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py` line 331
- 修改时间: 2025-10-21 08:44
- Python缓存已更新: cpython-310.pyc 在 08:46 重新编译

### ✅ 修复逻辑测试通过
```bash
$ python3 test_s3_bucket_fix.py
✅ 测试通过！修复后的代码能正确读取 aws_s3_bucket 参数
```

### ⏳ 等待实际运行验证
Galaxy 已在 9:04 AM 重启，但还没有新的 workflow 运行来验证修复效果。

## 预期行为 (修复后)

### 之前的错误日志 (08:41, 修复前):
```
WARNING No S3 bucket configured, file transfers will not work
INFO Job 110 using command without file transfers: ln -s '/Users/...
```

### 修复后应该看到 (待验证):
```
INFO Job XXX prepared with file transfers
INFO Uploaded 1 input files to s3://galaxy-cloud-data-1760241377/workflows/job-XXX/inputs/
INFO Expecting 2 output files
INFO Submitted Galaxy job XXX as cloud job <uuid>
```

### AWS Batch 容器应该收到:
```bash
# 完整的命令，包含 S3 操作
aws s3 cp s3://bucket/path/input.fastq.gz ./input.fastq.gz && \
fastqc input.fastq.gz -o output/ && \
aws s3 cp output/report.html s3://bucket/path/output/report.html
```

而不是空命令 `[]` 或只包含本地路径的命令。

## 下一步测试

1. **运行测试 workflow**:
   - 在 Galaxy Web UI 中运行已导入的 "Enhanced Cloud Test Workflow"
   - 或运行 "Simple Cloud Test Workflow"

2. **检查日志**:
   ```bash
   tail -f database/gravity/log/gunicorn.log | grep -E "(Job [0-9]+|S3 bucket|File transfer|Uploaded|Downloaded)"
   ```

3. **期望看到**:
   - ✅ "Built provider config... 's3_bucket': 'galaxy-cloud-data-1760241377'"
   - ✅ "Job XXX prepared with file transfers"
   - ✅ "Uploaded N input files"
   - ✅ "Downloaded M output files"
   - ❌ 不应该再看到 "No S3 bucket configured"

4. **检查 AWS Batch**:
   - 任务运行时间 > 0 秒 (不是0秒)
   - 容器日志显示实际执行了工具命令
   - S3 bucket 中有 `workflows/job-XXX/` 目录

## 当前状态总结

| 项目 | 状态 | 备注 |
|------|------|------|
| 代码修复 | ✅ 完成 | line 331 已修改 |
| 单元测试 | ✅ 通过 | test_s3_bucket_fix.py |
| Python缓存 | ✅ 已更新 | 08:46 重新编译 |
| Galaxy重启 | ✅ 完成 | 9:04 AM 启动 |
| 实际运行验证 | ⏳ 待测试 | 需要运行新的workflow |

## 修复代码详情

**文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**位置**: Line 322-335

```python
def _build_command_args(self, job_wrapper, job_destination: JobDestination) -> Tuple[List[str], Optional[FileTransferManager]]:
    """
    Build command arguments for the job with file transfer support.

    Returns:
        Tuple of (command_args, file_transfer_manager)
    """
    # Get S3 bucket from job destination params
    # Try both 's3_bucket' and 'aws_s3_bucket' for compatibility
    s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
    if not s3_bucket:
        self.logger.warning(f"No S3 bucket configured in job destination params: {job_destination.params.keys()}")
        self.logger.warning(f"File transfers will not work for job {job_wrapper.get_id_tag()}")
    # ... rest of method
```

**关键修改**:
```python
# Before:
s3_bucket = job_destination.params.get('s3_bucket')

# After:
s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
```

这个修改确保无论配置文件使用 `s3_bucket` 还是 `aws_s3_bucket`，代码都能正确识别。
