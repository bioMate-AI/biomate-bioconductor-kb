# Storage Provider 问题修复

## 问题发现

在启动日志中发现新的错误:

```
ERROR Failed to prepare file transfers for job 133: 'GalaxyDataManager' object has no attribute 'storage'
WARNING Falling back to command without file transfers
```

## 根本原因

`FileTransferManager` 期望 `storage_provider` 参数有以下方法:
- `upload_file(local_path, bucket, key)`
- `download_file(bucket, key, local_path)`
- `delete_prefix(bucket, prefix)`

但是 `GalaxyDataManager` 类:
1. **没有 `storage` 属性** (只有 `storage_clients` 字典)
2. 使用完全不同的异步接口 (`async def stage_dataset(...)`)
3. 是为完整的 workflow 数据管理设计的，不适合单个文件传输

## 解决方案

**创建 `SimpleS3Storage` 类**，直接使用 boto3 进行同步文件传输。

### 修改 1: 添加 SimpleS3Storage 类

**文件**: `lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py`

```python
import boto3

class SimpleS3Storage:
    """Simple synchronous S3 storage wrapper using boto3."""

    def __init__(self, logger=None):
        """Initialize S3 storage with boto3 client."""
        self.s3_client = boto3.client('s3')
        self.logger = logger or logging.getLogger(__name__)

    def upload_file(self, local_path: str, bucket: str, key: str):
        """Upload a file to S3."""
        self.s3_client.upload_file(local_path, bucket, key)

    def download_file(self, bucket: str, key: str, local_path: str):
        """Download a file from S3."""
        self.s3_client.download_file(bucket, key, local_path)

    def delete_prefix(self, bucket: str, prefix: str):
        """Delete all files under a prefix."""
        paginator = self.s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket, Prefix=prefix)

        for page in pages:
            if 'Contents' in page:
                objects = [{'Key': obj['Key']} for obj in page['Contents']]
                if objects:
                    self.s3_client.delete_objects(
                        Bucket=bucket,
                        Delete={'Objects': objects}
                    )
```

### 修改 2: FileTransferManager 自动创建 storage

**文件**: `lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py`

```python
def __init__(self, s3_bucket: str, job_id: str, storage_provider=None, logger=None):
    """
    Initialize the file transfer manager.

    Args:
        s3_bucket: S3 bucket name for staging files
        job_id: Unique job identifier for this execution
        storage_provider: Optional cloud storage provider instance.
                        If None, creates a SimpleS3Storage instance.
        logger: Logger instance
    """
    self.s3_bucket = s3_bucket
    self.job_id = job_id
    self.logger = logger or logging.getLogger(__name__)

    # Create storage provider if not provided
    if storage_provider is None:
        self.logger.debug("Creating SimpleS3Storage for file transfers")
        self.storage = SimpleS3Storage(logger=self.logger)
    else:
        self.storage = storage_provider
```

**关键变化**:
- `storage_provider` 参数变为可选 (`storage_provider=None`)
- 如果未提供，自动创建 `SimpleS3Storage` 实例
- 使用 boto3 直接访问 S3，不再依赖 GalaxyDataManager

### 修改 3: galaxy_job_runner 不再传递 storage_provider

**文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

```python
# Before (错误):
file_transfer_manager = FileTransferManager(
    s3_bucket=s3_bucket,
    job_id=job_wrapper.get_id_tag(),
    storage_provider=self.data_manager.storage,  # ❌ 不存在！
    logger=self.logger
)

# After (正确):
file_transfer_manager = FileTransferManager(
    s3_bucket=s3_bucket,
    job_id=job_wrapper.get_id_tag(),
    storage_provider=None,  # ✅ 让它自己创建 SimpleS3Storage
    logger=self.logger
)
```

## 修复验证

### ✅ 语法测试通过
```bash
$ PYTHONPATH=lib python3 -c "from galaxy_cloud.galaxy_workflow.file_transfer_manager import FileTransferManager, SimpleS3Storage; print('✅ FileTransferManager import successful')"
✅ FileTransferManager import successful
```

### ✅ Python 缓存已清理
```bash
$ find lib/galaxy_cloud -name "*.pyc" -delete
$ find lib/galaxy_cloud -type d -name "__pycache__" -exec rm -rf {} +
```

### ⏳ 需要重启 Galaxy
缓存已清理，需要重启 Galaxy 以加载新代码。

## 预期效果

修复后，运行 workflow 时应该看到:

**成功日志**:
```
DEBUG Creating SimpleS3Storage for file transfers
INFO Job XXX prepared with file transfers
INFO Found 1 input files and 2 output paths
DEBUG S3: Uploading /path/to/input.fastq.gz to s3://bucket/workflows/job-XXX/inputs/input_0_input.fastq.gz
INFO Uploaded 1 input files
INFO Expecting 2 output files
INFO Final command (first 150 chars): mkdir -p /galaxy/work/inputs && aws s3 cp s3://bucket/... && fastqc ...
```

**不再有错误**:
- ❌ ~~`'GalaxyDataManager' object has no attribute 'storage'`~~
- ❌ ~~`Falling back to command without file transfers`~~

**AWS Batch 容器接收的命令**:
```bash
# 完整的带文件传输的命令
mkdir -p /galaxy/work/inputs && \
mkdir -p /galaxy/work/outputs && \
aws s3 cp s3://bucket/workflows/job-XXX/inputs/input_0_sample1.fastq.gz /galaxy/work/inputs/sample1.fastq.gz && \
(fastqc /galaxy/work/inputs/sample1.fastq.gz -o /galaxy/work/outputs/) && \
aws s3 cp /galaxy/work/outputs/report.html s3://bucket/workflows/job-XXX/outputs/output_0_report.html
```

**不再是空命令或只包含本地路径！**

## 涉及文件

1. **lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py**
   - 添加 `SimpleS3Storage` 类 (line 32-69)
   - 修改 `__init__` 使 `storage_provider` 可选 (line 82-102)

2. **lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py**
   - 修改创建 FileTransferManager 时不传递 storage_provider (line 366-370)

## 下一步

1. **重启 Galaxy**:
   ```bash
   sh start_galaxy_with_ai.sh
   ```

2. **运行测试 workflow**

3. **监控日志**:
   ```bash
   tail -f database/gravity/log/gunicorn.log | grep -E "(SimpleS3Storage|File transfer|S3:|Uploaded|Downloaded)"
   ```

4. **检查 AWS Batch**:
   - 容器命令不再为空
   - 任务运行时间 > 0 秒
   - CloudWatch 日志显示实际执行了工具
   - S3 bucket 中有 `workflows/job-XXX/` 目录

## 技术细节

### 为什么不修改 GalaxyDataManager?

`GalaxyDataManager` 是为完整的 workflow 执行设计的:
- 异步接口 (`async def`)
- 需要 `WorkflowRunConfig` 对象
- 管理整个 workflow 的数据生命周期
- 支持多种云提供商

而 `FileTransferManager` 需要的是:
- 同步接口 (因为在 `prepare_job` 中直接调用)
- 简单的单文件上传/下载
- 只针对 S3

所以创建一个轻量级的 `SimpleS3Storage` 更合适。

### boto3 依赖

`SimpleS3Storage` 使用 boto3，这已经是 AWS 云执行的必需依赖。如果 boto3 未安装，会抛出明确的错误信息:

```python
if not HAS_BOTO3:
    raise ImportError("boto3 is required for S3 storage. Install with: pip install boto3")
```

### AWS 凭证

`SimpleS3Storage` 使用 `boto3.client('s3')`，会自动从以下位置查找凭证:
1. 环境变量 (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. AWS CLI 配置文件 (`~/.aws/credentials`)
3. IAM 角色 (如果在 EC2 上运行)

这与 AWS Batch executor 使用相同的凭证机制。
