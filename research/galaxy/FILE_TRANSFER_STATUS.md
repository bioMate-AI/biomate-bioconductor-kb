# 文件传输状态诊断

## 当前观察到的行为

根据最新的错误日志（9:40），我们看到：

### ✅ 成功的部分

1. **FileTransferManager 正在运行**
   ```
   Downloading output files for job cb9870ee-9c1b-4cb0-a4f6-88f101c89f22
   Downloaded 2 output files
   S3 staging cleaned up successfully
   ```

2. **部分文件下载成功**
   ```
   Downloaded: s3://.../output_1_dataset_xxx_files → 本地
   Downloaded: s3://.../output_3_dataset_xxx_files → 本地
   ```

3. **任务状态为 'ok'** - 表示 AWS Batch 任务成功完成

### ❌ 问题

1. **部分文件404 Not Found**
   ```
   ERROR Failed to download s3://.../output_0_dataset_xxx.dat: 404 Not Found
   ERROR Failed to download s3://.../output_2_dataset_xxx.dat: 404 Not Found
   ```

2. **Metadata 错误**
   ```
   WARNING setting metadata externally failed for HistoryDatasetAssociation 212:
   Metadata results could not be read from '.../metadata_results_html_file'
   ```

3. **ObjectNotFound in cleanup**
   ```
   ERROR Unable to cleanup job 135
   galaxy.exceptions.ObjectNotFound: No such object found.
   ```

## 问题分析

### 根本原因

**容器没有上传 `.dat` 主输出文件到 S3**

FastQC 的输出处理：
1. FastQC 生成输出到 `_files` 目录 ✅
2. Galaxy wrapper 使用 `cp` 命令将特定文件复制出来：
   ```bash
   cp '..._files'/*/fastqc_data.txt output.txt
   cp '..._files'/*\.html output.html
   ```
3. 这些 `cp` 的目标文件（`output.txt`, `output.html`）**没有完整路径**
4. 它们被创建在当前工作目录，而不是预期的输出目录

### 问题链

```
Galaxy 生成的命令包含相对路径的 cp 目标
  ↓
FileTransferManager 无法正确重写这些路径
  ↓
容器执行 cp 时，文件创建在工作目录
  ↓
文件传输脚本期望在 /galaxy/work/outputs/ 找文件
  ↓
找不到文件 → 没有上传到 S3
  ↓
下载时 404 Not Found
  ↓
Metadata 生成失败
  ↓
Cleanup 失败 (对象不存在)
```

## 解决方案选项

### 选项 1: 修复路径重写逻辑 (推荐)

修改 FileTransferManager 的 `_wrap_command_with_transfers` 方法，确保：

1. **所有文件都在正确的目录**
   ```bash
   # 当前工作目录设置为 /galaxy/work
   cd /galaxy/work

   # 执行原始命令（会在当前目录生成 output.txt, output.html）
   fastqc ... && cp ... output.txt && cp ... output.html

   # 将所有生成的文件移动到 outputs 目录
   find . -maxdepth 1 -type f -exec mv {} /galaxy/work/outputs/ \;
   ```

2. **或者修改 cp 命令的目标路径**
   - 在 `_rewrite_command_paths` 中识别 `output.txt` 等相对路径
   - 添加输出目录前缀: `/galaxy/work/outputs/output.txt`

### 选项 2: 放宽输出文件检查

修改清理命令，使用 `|| true` 避免失败：
```bash
if [ -f /galaxy/work/outputs/file.txt ]; then
    aws s3 cp /galaxy/work/outputs/file.txt s3://...
elif [ -f /galaxy/work/file.txt ]; then
    aws s3 cp /galaxy/work/file.txt s3://...
else
    echo "Warning: Output file not found, searching..."
    # 在整个工作目录搜索并上传
    find /galaxy/work -name "*.txt" -o -name "*.html" | xargs -I {} aws s3 cp {} s3://...
fi
```

### 选项 3: 简化方案 - 上传整个输出目录

```bash
# 上传整个工作目录到 S3
aws s3 sync /galaxy/work/ s3://bucket/workflows/job-XXX/ --exclude "inputs/*"
```

然后下载时：
```bash
# 下载整个job目录
aws s3 sync s3://bucket/workflows/job-XXX/ /local/job-dir/

# 从中找到并复制需要的文件到最终位置
find /local/job-dir -name "output.txt" -exec cp {} /final/path/dataset.dat \;
```

## 立即行动

### 步骤 1: 验证当前代码是否正在使用

检查最新的job是否使用了 SimpleS3Storage：

```bash
# 查找最新日志
find database/gravity/log -type f -mmin -60 | xargs grep -l "SimpleS3Storage"

# 或者直接查看进程启动的日志
journalctl -u galaxy -n 200  # 如果使用systemd
# 或者
cat database/gravity/log/gunicorn.log | grep "SimpleS3Storage"
```

### 步骤 2: 运行新的测试任务

1. 在 Galaxy Web UI 中运行一个简单的 FastQC 任务
2. 监控日志看是否出现：
   ```
   DEBUG Creating SimpleS3Storage for file transfers
   INFO Job XXX prepared with file transfers
   ```

### 步骤 3: 检查 AWS Batch 命令

```bash
# 获取最新的 job ID
JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 1 --query 'jobSummaryList[0].jobId' --output text)

# 查看命令
aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].container.command'
```

**期望看到**:
```json
[
  "/bin/sh",
  "-c",
  "mkdir -p /galaxy/work/inputs && mkdir -p /galaxy/work/outputs && aws s3 cp s3://... /galaxy/work/inputs/... && (fastqc ...) && aws s3 cp /galaxy/work/outputs/... s3://..."
]
```

### 步骤 4: 检查 S3 内容

```bash
# 列出最新的 workflow 目录
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive | tail -20

# 查看特定job的文件
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/JOB-XXX/ --recursive
```

## 当前状态总结

| 组件 | 状态 | 备注 |
|------|------|------|
| SimpleS3Storage 类 | ✅ 已创建 | 代码已修改，测试通过 |
| FileTransferManager 修复 | ✅ 已修改 | 可以自动创建 SimpleS3Storage |
| Python 缓存 | ✅ 已清理 | 但无法确认新代码是否加载 |
| Galaxy 重启 | ✅ 已重启 | 9:29-9:30 AM 启动 |
| 文件上传 | ❓ 未知 | 需要检查日志 |
| 文件下载 | ⚠️ 部分工作 | `_files` 目录成功，`.dat` 文件404 |
| 路径重写 | ❌ 需要修复 | 相对路径输出文件未被正确处理 |

## 下一步优先级

1. **高优先级**: 确认 SimpleS3Storage 正在被使用
   - 查找 "Creating SimpleS3Storage" 日志
   - 如果没有，可能是缓存或者代码未正确加载

2. **高优先级**: 修复输出文件路径问题
   - 修改 `_wrap_command_with_transfers` 添加文件收集逻辑
   - 或者使用 `aws s3 sync` 上传整个工作目录

3. **中优先级**: 改进错误处理
   - 下载失败时不要导致整个 job 失败
   - 提供更好的诊断信息

## 诊断命令

```bash
# 1. 检查 Galaxy 是否使用新代码
python3 -c "
import sys
sys.path.insert(0, 'lib')
from galaxy_cloud.galaxy_workflow.file_transfer_manager import SimpleS3Storage
import inspect
print(f'SimpleS3Storage location: {inspect.getfile(SimpleS3Storage)}')
print(f'Has boto3: {hasattr(SimpleS3Storage, \"s3_client\")}')
"

# 2. 检查最近的任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 5

# 3. 查看任务命令
aws batch describe-jobs --jobs <JOB_ID> --query 'jobs[0].{Command:container.command, Status:status}'

# 4. 查看 CloudWatch 日志（如果有）
aws logs tail /aws/batch/job --follow
```
