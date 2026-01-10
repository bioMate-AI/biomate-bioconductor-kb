# 文件传输修复验证指南

## 问题总结

发现了两个关键问题：

### 问题1: S3 bucket参数名不匹配 ✅ 已修复

**问题**：
- `job_conf_cloud.yml` 使用 `aws_s3_bucket`
- `galaxy_job_runner.py` 查找 `s3_bucket`
- 结果：找不到S3配置，文件传输被跳过

**修复**：
```python
# 修复前：
s3_bucket = job_destination.params.get('s3_bucket')  # ❌ 找不到

# 修复后：
s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')  # ✅ 兼容两种格式
```

**验证日志**：
```
# 修复前：
WARNING No S3 bucket configured, file transfers will not work
INFO Job 119 using command without file transfers

# 修复后应该看到：
INFO Job XXX prepared with file transfers
INFO Uploaded N input files
INFO Expecting M output files
```

### 问题2: AWS任务运行0秒

**症状**：
- AWS Batch显示任务SUCCEEDED
- 运行时间: 0秒 (startedAt = stoppedAt)
- Container command: [] (空)

**原因**：
- 没有文件传输 → 没有生成完整命令
- 容器启动但没有命令可执行 → 立即退出

## 验证步骤

### 1. 确认Galaxy已重启（应用修复）

```bash
# 检查Galaxy是否在运行
curl -s http://localhost:8080/api/version

# 检查日志最后一行时间（应该是最近）
tail -1 database/gravity/log/gunicorn.log
```

### 2. 运行新的测试任务

**在Galaxy UI中：**
1. 访问 http://localhost:8080
2. 上传一个新的FASTQ文件（或使用现有的）
3. 运行FastQC工具
4. 监控执行

**监控日志：**
```bash
tail -f database/gravity/log/gunicorn.log | grep -E "(Job [0-9]+|prepared with file transfers|Uploaded|S3 bucket)"
```

### 3. 预期看到的日志

**成功的日志应该包含：**
```
INFO Built provider config from job destination: {..., 's3_bucket': 'galaxy-cloud-data-1760241377'}
INFO Job XXX runner_command_line: ...
INFO Job XXX prepared with file transfers
INFO Uploaded 1 input files
INFO Expecting 2 output files
INFO Final command (first 150 chars): mkdir -p /galaxy/work/inputs && aws s3 cp...
INFO Submitted Galaxy job XXX as cloud job <uuid>
```

**失败的日志（需要修复）：**
```
WARNING No S3 bucket configured in job destination params: ...
WARNING File transfers will not work
INFO Job XXX using command without file transfers
```

### 4. 检查AWS Batch任务

```bash
# 获取最新任务ID（从日志中）
# 例如：Submitted Galaxy job 120 as cloud job abc-123-def

# 检查任务详情
aws batch describe-jobs --jobs abc-123-def --region us-west-2 \
  --query 'jobs[0].[jobName,status,container.command,container.exitCode,startedAt,stoppedAt]' \
  --output json | python3 -m json.tool
```

**成功标志：**
```json
[
  "galaxy-job-120",
  "SUCCEEDED",
  [
    "/bin/sh",
    "-c",
    "mkdir -p /galaxy/work/inputs && aws s3 cp..."  // ✅ 有完整命令
  ],
  0,
  1761007500000,
  1761007530000  // ✅ startedAt 和 stoppedAt 相差30秒+
]
```

**失败标志：**
```json
[
  "galaxy-job-120",
  "SUCCEEDED",
  [],  // ❌ 命令为空
  0,
  1761007500000,
  1761007500100  // ❌ 相差<1秒，没有实际执行
]
```

## 快速测试脚本

```bash
#!/bin/bash
echo "=== 验证文件传输修复 ==="
echo ""

# 1. 检查Galaxy
if curl -s http://localhost:8080/api/version > /dev/null; then
    echo "✓ Galaxy正在运行"
else
    echo "✗ Galaxy未运行，请先启动"
    exit 1
fi

# 2. 监控新任务
echo "现在在Galaxy UI中运行一个新任务（例如FastQC）"
echo "监控日志中的关键信息..."
echo ""

tail -f database/gravity/log/gunicorn.log | grep --line-buffered -E "(Job [0-9]+.*(prepared with file transfers|using command|S3 bucket|Uploaded|Submitted))"
```

## 下一步

如果修复后仍然看到 "using command without file transfers"：

1. **检查配置文件**：
   ```bash
   grep "aws_s3_bucket" config/job_conf_cloud.yml
   # 应该看到：aws_s3_bucket: galaxy-cloud-data-1760241377
   ```

2. **检查代码**：
   ```bash
   grep -A 2 "s3_bucket = job_destination" lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py
   # 应该包含：or job_destination.params.get('aws_s3_bucket')
   ```

3. **完全重启Galaxy**：
   ```bash
   pkill -9 -f galaxy
   rm -rf database/gravity/supervisor
   sh run.sh --daemon
   ```

4. **检查参数传递**：
   ```bash
   # 在日志中查找
   grep "Built provider config" database/gravity/log/gunicorn.log | tail -1
   # 应该包含：'s3_bucket': 'galaxy-cloud-data-1760241377'
   ```

## 预期最终结果

**✅ 成功验证清单：**
- [ ] Galaxy日志显示 "prepared with file transfers"
- [ ] Galaxy日志显示 "Uploaded N input files"
- [ ] AWS Batch command不为空
- [ ] AWS任务运行时间 > 0秒
- [ ] S3中有上传的文件
- [ ] Galaxy History显示绿色结果
