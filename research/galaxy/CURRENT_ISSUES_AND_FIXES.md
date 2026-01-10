# 当前问题和修复状态

## 核心问题: Storage Provider 错误 ✅ 已修复

### 错误现象
```
ERROR Failed to prepare file transfers for job 133: 'GalaxyDataManager' object has no attribute 'storage'
WARNING Falling back to command without file transfers
```

### 根本原因
`FileTransferManager` 需要一个 storage provider，但 `GalaxyDataManager` 没有所需的 `storage` 属性。

### 修复方案 ✅
创建了 `SimpleS3Storage` 类，直接使用 boto3 进行 S3 文件传输。

**修改的文件:**
1. [file_transfer_manager.py](lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py)
   - 添加 `SimpleS3Storage` 类
   - `FileTransferManager.__init__` 的 `storage_provider` 参数变为可选

2. [galaxy_job_runner.py](lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py)
   - 创建 FileTransferManager 时不再传递 storage_provider

**测试结果:** ✅ 全部通过
```bash
$ python3 test_storage_fix.py
✅ All tests passed!
```

**状态:** ⏳ 需要重启 Galaxy 以应用修复

---

## 次要问题 1: Connection Pool 警告

### 错误现象
```
WARNING urllib3.connectionpool Connection pool is full, discarding connection: batch.us-west-2.amazonaws.com. Connection pool size: 10
```

### 原因分析
这是 boto3/urllib3 的连接池管理警告，表示:
- 有很多并发的 AWS Batch API 调用
- 连接池大小限制为 10
- 连接使用后被丢弃而不是复用

### 影响
这只是一个警告，不会导致功能失败。但可能影响性能。

### 可能的原因
1. **任务状态轮询太频繁** - 可能每秒都在检查任务状态
2. **没有正确复用 boto3 客户端** - 每次调用都创建新客户端
3. **任务完成得太快 (0秒)** - 导致大量状态检查在短时间内完成

### 解决方案 (优先级低)
当主要问题修复后，如果此警告仍然出现：

1. **增加连接池大小**:
   ```python
   from botocore.config import Config
   config = Config(max_pool_connections=50)
   boto3.client('batch', config=config)
   ```

2. **减少轮询频率**:
   ```python
   # 从每秒轮询改为每 5 秒轮询
   time.sleep(5)  # instead of time.sleep(1)
   ```

3. **复用 boto3 客户端** - 确保在类初始化时创建一次，而不是每次调用都创建

---

## 次要问题 2: ObjectNotFound 错误

### 错误现象
```
ERROR galaxy.jobs Unable to cleanup job 131
...
galaxy.exceptions.ObjectNotFound: No such object found.
```

### 原因分析
任务在 AWS Batch 上运行了 0 秒就结束，说明:
1. **没有文件传输** - 因为 storage provider 错误
2. **容器收到空命令或只有本地路径** - 无法执行
3. **没有生成输出文件** - 任务立即失败
4. Galaxy 尝试清理不存在的输出文件 → ObjectNotFound

### 连锁反应
```
没有 storage provider
  ↓
没有文件上传到 S3
  ↓
容器收到本地路径 (容器内不存在)
  ↓
任务无法执行，0秒结束
  ↓
没有输出文件
  ↓
Galaxy cleanup 找不到对象 → ObjectNotFound
```

### 预期修复
✅ **修复 storage provider 后，这个错误应该消失**

修复后的流程:
```
有 SimpleS3Storage
  ↓
文件上传到 S3
  ↓
容器收到 S3 URIs 和下载命令
  ↓
任务正常执行 (运行时间 > 0)
  ↓
生成输出文件并上传回 S3
  ↓
Galaxy 下载输出文件
  ↓
Cleanup 成功
```

---

## 次要问题 3: Metadata 错误

### 错误现象
```
WARNING galaxy.metadata setting metadata externally failed for HistoryDatasetAssociation 206:
Metadata results could not be read from '/Users/.../metadata/metadata_results_fastq_out'
```

### 原因
任务运行 0 秒失败，没有生成 metadata 文件。

### 预期修复
✅ **修复 storage provider 后，任务能正常运行并生成 metadata**

---

## 行动计划

### 1. ✅ 完成: 修复 Storage Provider
- 创建 SimpleS3Storage 类
- 修改 FileTransferManager
- 修改 galaxy_job_runner.py
- 测试通过

### 2. ⏳ 待执行: 重启 Galaxy
```bash
# 停止当前 Galaxy (如果在运行)
pkill -f gunicorn

# 清理 Python 缓存 (已完成)
find lib/galaxy_cloud -name "*.pyc" -delete
find lib/galaxy_cloud -type d -name "__pycache__" -exec rm -rf {} +

# 重启 Galaxy
sh start_galaxy_with_ai.sh
```

### 3. ⏳ 待测试: 运行 Workflow
在 Galaxy Web UI 中运行测试 workflow

### 4. ⏳ 待验证: 检查日志
```bash
tail -f database/gravity/log/gunicorn.log | grep -E "(SimpleS3Storage|File transfer|S3:|Uploaded|Downloaded|Job [0-9]+)"
```

**期望看到:**
- ✅ "Creating SimpleS3Storage for file transfers"
- ✅ "Job XXX prepared with file transfers"
- ✅ "S3: Uploading /path/to/file to s3://bucket/..."
- ✅ "Uploaded 1 input files"
- ✅ "Expecting N output files"
- ❌ 不再有 "storage' attribute" 错误
- ❌ 不再有 "Falling back to command without file transfers"

### 5. ⏳ 待验证: 检查 AWS Batch
在 AWS 控制台查看:
- ✅ 容器收到非空命令
- ✅ 任务运行时间 > 0 秒 (不是0秒)
- ✅ CloudWatch Logs 显示实际执行了工具
- ✅ S3 bucket 中有 `workflows/job-XXX/` 目录

### 6. ⏳ 待验证: 检查 Galaxy History
在 Galaxy Web UI 中:
- ✅ 任务状态变为绿色 (成功)
- ✅ 输出数据集可以查看
- ❌ 不再有 ObjectNotFound 错误
- ❌ 不再有 metadata 错误

---

## 如果修复后仍有问题

### 检查 boto3
```bash
pip install boto3
python3 -c "import boto3; print(f'boto3 version: {boto3.__version__}')"
```

### 检查 AWS 凭证
```bash
aws sts get-caller-identity
```

### 手动测试 S3 上传
```bash
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://galaxy-cloud-data-1760241377/test/test.txt
aws s3 ls s3://galaxy-cloud-data-1760241377/test/
```

### 查看详细日志
```bash
# 查看完整的 job 创建过程
tail -200 database/gravity/log/gunicorn.log | grep "Job 130" -A 5 -B 5

# 查看 AWS Batch 提交
tail -200 database/gravity/log/gunicorn.log | grep "Submitted job" -A 2 -B 2
```

---

## 文档和测试文件

- [STORAGE_PROVIDER_FIX.md](STORAGE_PROVIDER_FIX.md) - 详细修复说明
- [S3_FIX_STATUS.md](S3_FIX_STATUS.md) - S3 参数修复状态
- [test_storage_fix.py](test_storage_fix.py) - Storage 修复测试 ✅
- [test_s3_bucket_fix.py](test_s3_bucket_fix.py) - S3 bucket 参数测试 ✅

---

## 总结

**主要问题:** `GalaxyDataManager.storage` 不存在
**修复状态:** ✅ 已修复，测试通过
**下一步:** 重启 Galaxy 并运行测试 workflow

**次要问题会在主要问题修复后自动解决:**
- ObjectNotFound → 任务能正常生成输出文件
- Metadata 错误 → 任务能正常运行并生成 metadata
- Connection pool 警告 → 如果仍然出现，优先级低，不影响功能
