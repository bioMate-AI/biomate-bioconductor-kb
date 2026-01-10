# 重新启动并测试指南

## 当前状态

### 已完成的修复
1. ✅ 创建了 `SimpleS3Storage` 类
2. ✅ 修改了 `FileTransferManager` 使 storage_provider 可选
3. ✅ 修改了 `galaxy_job_runner.py` 不再依赖 GalaxyDataManager.storage
4. ✅ 添加了调试日志查看 job_destination.params

### 已知问题
1. ❌ 容器收到空命令 `[]`
2. ❌ 文件传输准备阶段没有执行
3. ❌ 输出文件 404 Not Found

### 根本原因猜测
`job_destination.params` 可能不包含 `aws_s3_bucket` 参数。

## 重启步骤

### 步骤 1: 清理并启动

```bash
# 停止当前 Galaxy（如果在运行）
pkill -f gunicorn
pkill -f celery

# 清理 Python 缓存
find lib/galaxy_cloud -name "*.pyc" -delete
find lib/galaxy_cloud -type d -name "__pycache__" -exec rm -rf {} +

# 启动 Galaxy（日志会输出到终端和文件）
bash start_with_debug_log.sh
```

### 步骤 2: 等待启动完成

看到这个消息后 Galaxy 就ready了：
```
Serving on http://127.0.0.1:8080
```

### 步骤 3: 运行测试 workflow

1. 打开浏览器访问 http://localhost:8080
2. 运行 "Enhanced Cloud Test Workflow" 或创建一个简单的 FastQC 任务

### 步骤 4: 监控日志

在日志中查找关键信息：

**期望看到（如果修复成功）**:
```
INFO Job XXX destination params: {'provider': 'aws', 'aws_region': 'us-west-2', ..., 'aws_s3_bucket': 'galaxy-cloud-data-1760241377'}
DEBUG Creating SimpleS3Storage for file transfers
INFO Job XXX prepared with file transfers
INFO Found N input files and M output paths
DEBUG S3: Uploading /path/to/file to s3://bucket/...
INFO Uploaded N input files
INFO Expecting M output files
```

**如果仍然失败（S3 bucket 未配置）**:
```
INFO Job XXX destination params: {'provider': 'aws', 'aws_region': 'us-west-2', ...}
WARNING No S3 bucket configured in job destination params: [...]
WARNING File transfers will not work for job XXX
INFO Job XXX using command without file transfers
```

## 如果 S3 bucket 仍然未配置

### 检查 job_conf_cloud.yml

确认配置文件中有 `aws_s3_bucket`:

```bash
cat config/job_conf_cloud.yml | grep -A 10 "cloud_small"
```

应该看到:
```yaml
cloud_small:
  runner: galaxy_cloud
  params:
    provider: aws
    aws_region: us-west-2
    aws_batch_queue: galaxy-cloud-queue
    aws_s3_bucket: galaxy-cloud-data-1760241377  # ← 必须有这一行
    vcpus: 2
    memory_mb: 4096
```

### 检查 Galaxy 是否使用了正确的配置文件

在启动日志中查找：
```
INFO     galaxy.jobs.runners Loading job configuration from config/job_conf_cloud.yml
```

或者：
```bash
# 检查 galaxy.yml 中的 job_config_file 设置
grep "job_config_file" config/galaxy.yml
```

应该指向 `job_conf_cloud.yml`：
```yaml
job_config_file: config/job_conf_cloud.yml
```

## 调试命令

### 1. 验证代码加载
```bash
python3 << 'EOF'
import sys
sys.path.insert(0, 'lib')
from galaxy_cloud.galaxy_workflow.file_transfer_manager import SimpleS3Storage, FileTransferManager

# 测试自动创建 SimpleS3Storage
ftm = FileTransferManager(s3_bucket="test-bucket", job_id="test-123")
print(f"Storage type: {type(ftm.storage).__name__}")
assert type(ftm.storage).__name__ == "SimpleS3Storage", "Should auto-create SimpleS3Storage"
print("✅ Code is correct")
EOF
```

### 2. 检查最新的 AWS Batch 任务
```bash
# 获取最新任务
LATEST_JOB=$(aws batch list-jobs --job-queue galaxy-cloud-queue --max-results 1 --query 'jobSummaryList[0].jobId' --output text)

# 查看任务命令
aws batch describe-jobs --jobs $LATEST_JOB --query 'jobs[0].{Command:container.command,Status:status,CreatedAt:createdAt}'
```

期望看到完整的命令（不是空的 `[]`）：
```json
{
    "Command": [
        "/bin/sh",
        "-c",
        "mkdir -p /galaxy/work/inputs && mkdir -p /galaxy/work/outputs && aws s3 cp s3://... && ..."
    ],
    "Status": "SUCCEEDED",
    "CreatedAt": ...
}
```

### 3. 检查 S3 文件
```bash
# 列出最新的 workflow 目录
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ | tail -5

# 查看特定 workflow 的内容
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/XXX/ --recursive
```

应该看到 `inputs/` 和 `outputs/` 目录及文件。

## 预期结果

### 成功场景
1. ✅ 日志显示 "destination params" 包含 `aws_s3_bucket`
2. ✅ 日志显示 "Creating SimpleS3Storage"
3. ✅ 日志显示 "prepared with file transfers"
4. ✅ 日志显示 "Uploaded N input files"
5. ✅ AWS Batch 容器命令不为空
6. ✅ 容器运行时间 > 0 秒
7. ✅ S3 中有 inputs 和 outputs 文件
8. ✅ 输出文件成功下载
9. ✅ Galaxy History 中任务显示绿色（成功）

### 失败场景处理

#### 场景 A: destination params 不包含 aws_s3_bucket

**症状**:
```
INFO Job XXX destination params: {'provider': 'aws', 'aws_region': 'us-west-2'}
WARNING No S3 bucket configured
```

**解决**:
1. 检查 `galaxy.yml` 中的 `job_config_file` 配置
2. 确认 `job_conf_cloud.yml` 中有 `aws_s3_bucket` 参数
3. 重启 Galaxy

#### 场景 B: SimpleS3Storage 未创建

**症状**:
```
ERROR Failed to prepare file transfers: ... SimpleS3Storage ...
```

**解决**:
1. 确认 boto3 已安装: `pip install boto3`
2. 清理 Python 缓存
3. 重启 Galaxy

#### 场景 C: 输出文件 404

**症状**:
```
INFO Uploaded N input files  (成功)
ERROR Failed to download s3://.../output_0_xxx.dat: 404 Not Found
```

**解决**: 这是输出文件路径重写问题，需要修改 FileTransferManager 的逻辑（下一步修复）

## 下一步

根据调试日志的结果，我们将：

1. **如果 params 包含 aws_s3_bucket** → 修复输出文件路径问题
2. **如果 params 不包含 aws_s3_bucket** → 修复配置文件加载问题
3. **如果 SimpleS3Storage 创建失败** → 修复 boto3 或导入问题

## 快速启动命令

```bash
# 一键执行所有步骤
pkill -f gunicorn; pkill -f celery; \
find lib/galaxy_cloud -name "*.pyc" -delete; \
bash start_with_debug_log.sh
```

然后在浏览器中运行 workflow，并观察终端输出。
