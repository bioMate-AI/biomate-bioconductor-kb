# Galaxy 云执行故障排除指南

## 当前状态

根据最新日志分析（Job 88-100）：

### ✅ 正常工作的部分
1. GalaxyCloudJobRunner 正在被使用
2. 命令生成成功（prepare() 工作正常）
3. 容器镜像配置正确
4. S3 bucket 配置正确

### ❌ 当前问题

#### 问题 1: AWS 认证失败

**错误消息**:
```
UnrecognizedClientException: The security token included in the request is invalid.
```

**原因**: AWS 凭证过期或无效

**解决方案**:

```bash
# 1. 重新认证 AWS
aws sso login
# 或
aws configure

# 2. 验证凭证
aws sts get-caller-identity --region us-west-2

# 3. 测试 S3 访问
aws s3 ls s3://galaxy-cloud-data-1760241377/ --region us-west-2

# 4. 测试 AWS Batch 访问
aws batch describe-job-queues --job-queue galaxy-cloud-queue --region us-west-2
```

#### 问题 2: 文件传输未执行

**原因**: 因为 AWS 认证失败，代码在提交任务前就抛出异常，没有执行到文件传输逻辑

**验证**: 查看日志中是否有：
```
INFO Job X prepared with file transfers
INFO Uploaded N input files
```

如果没有这些消息，说明文件传输代码未被执行。

#### 问题 3: Fallback 到本地执行

当云执行失败时，Galaxy 可能会 fallback 到本地执行，这就是为什么 Job 100 看起来像在本地运行。

## 完整测试步骤

### 1. 重新认证 AWS

```bash
# 使用您的认证方法
aws sso login
# 或
aws configure

# 验证
aws sts get-caller-identity
```

### 2. 验证 AWS 资源访问

```bash
# 测试 S3
aws s3 ls s3://galaxy-cloud-data-1760241377/

# 测试 AWS Batch
aws batch describe-job-queues --job-queue galaxy-cloud-queue --region us-west-2

# 测试提交一个简单任务
aws batch submit-job \
  --job-name test-job \
  --job-queue galaxy-cloud-queue \
  --job-definition test:1
```

### 3. 重启 Galaxy

```bash
# 彻底停止
pkill -9 -f "python.*galaxy"
rm -f database/gravity/supervisor/supervisor.sock

# 启动
sh run.sh --daemon

# 等待启动完成
tail -f database/gravity/log/gunicorn.log | grep "Galaxy server instance.*is running"
```

### 4. 运行测试 Workflow

访问 http://localhost:8080 并运行 workflow

### 5. 实时监控日志

```bash
# 查看文件传输相关日志
tail -f database/gravity/log/gunicorn.log | grep -E "prepared with file transfers|Uploaded|Downloaded|FileTransferManager"

# 查看所有云执行相关日志
tail -f database/gravity/log/gunicorn.log | grep -E "GalaxyCloudJobRunner|Submitted Galaxy job|AWS"
```

### 6. 期望看到的日志

成功的执行应该包含：

```
INFO Job X runner_command_line: None
INFO Job X attempting to prepare job to generate command
INFO Job X command_line after prepare: ln -s '/Users/...
INFO Job X prepared with file transfers          # ← 新的！
INFO Uploaded 1 input files                      # ← 新的！
INFO Expecting 2 output files                    # ← 新的！
INFO Final command (first 150 chars): mkdir -p /galaxy/work/inputs && ...  # ← 新的！
INFO Submitted Galaxy job X as cloud job <uuid>
INFO Downloading output files for job <uuid>     # ← 新的！
INFO Downloaded 2 output files                   # ← 新的！
```

### 7. 检查 AWS Batch 任务

```bash
# 列出最近的任务
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --region us-west-2 \
  --job-status SUCCEEDED FAILED RUNNING \
  --max-items 5

# 查看特定任务
./check_aws_job.sh <job-id>
```

### 8. 验证容器命令

AWS Batch 任务的命令应该类似：

```json
{
  "command": [
    "/bin/sh",
    "-c",
    "mkdir -p /galaxy/work/inputs && mkdir -p /galaxy/work/outputs && aws s3 cp s3://bucket/workflows/job-123/inputs/input_0_sample.fastq /galaxy/work/inputs/sample.fastq && (ln -s /galaxy/work/inputs/sample.fastq sample.fastq && fastqc --outdir /galaxy/work/outputs/ sample.fastq) && if [ -f /galaxy/work/outputs/sample_fastqc.html ]; then aws s3 cp /galaxy/work/outputs/sample_fastqc.html s3://bucket/workflows/job-123/outputs/output_0_sample_fastqc.html; fi"
  ]
}
```

### 9. 检查 CloudWatch 日志

```bash
# 获取日志流名称
LOG_STREAM=$(aws batch describe-jobs --jobs <job-id> --region us-west-2 \
  --query 'jobs[0].container.logStreamName' --output text)

# 查看日志
aws logs get-log-events \
  --log-group-name /aws/batch/job \
  --log-stream-name "$LOG_STREAM" \
  --region us-west-2
```

期望看到：
```
download: s3://bucket/workflows/.../inputs/input_0_sample.fastq to ./inputs/sample.fastq
Started analysis of sample.fastq
Analysis complete for sample.fastq
upload: ./outputs/sample_fastqc.html to s3://bucket/workflows/.../outputs/output_0_sample_fastqc.html
```

## 常见错误及解决方案

### 错误 1: "No S3 bucket configured"

**原因**: `job_conf_cloud.yml` 中缺少 `s3_bucket` 参数

**解决**:
```yaml
destinations:
  cloud_small:
    params:
      s3_bucket: galaxy-cloud-data-1760241377  # 添加这一行
```

### 错误 2: "AccessDenied" when uploading to S3

**原因**: AWS 凭证没有 S3 权限

**解决**: 确保 AWS 用户/角色有以下权限：
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": "arn:aws:s3:::galaxy-cloud-data-1760241377/*"
}
```

### 错误 3: Container "aws: command not found"

**原因**: BioContainers 镜像中没有 aws CLI

**解决**: 使用包含 aws CLI 的镜像，或修改镜像：
```dockerfile
FROM quay.io/biocontainers/fastqc:0.11.9--0
RUN pip install awscli
```

### 错误 4: "Unable to locate credentials"

**原因**: 容器中没有 AWS 凭证

**解决**: 在 AWS Batch 任务定义中配置 IAM 角色：
```yaml
# config/job_conf_cloud.yml
destinations:
  cloud_small:
    params:
      job_role_arn: arn:aws:iam::123456789012:role/GalaxyBatchJobRole
```

### 错误 5: 文件下载失败 "No such key"

**原因**: 容器中没有上传输出文件，或文件路径不匹配

**检查**:
1. CloudWatch 日志中查看 `aws s3 cp` 命令的输出
2. 列出 S3 bucket 内容：
   ```bash
   aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive
   ```

## 调试技巧

### 1. 增加日志级别

在 `galaxy_job_runner.py` 中临时添加更详细的日志：

```python
self.logger.setLevel(logging.DEBUG)
```

### 2. 测试单个文件上传

```bash
# 测试从本地上传到 S3
aws s3 cp test.txt s3://galaxy-cloud-data-1760241377/test/test.txt

# 测试从 S3 下载
aws s3 cp s3://galaxy-cloud-data-1760241377/test/test.txt ./downloaded.txt
```

### 3. 手动测试容器命令

```bash
# 在本地 Docker 中测试命令
docker run -it --rm \
  -e AWS_ACCESS_KEY_ID=xxx \
  -e AWS_SECRET_ACCESS_KEY=xxx \
  quay.io/biocontainers/fastqc:0.11.9--0 \
  /bin/sh -c "aws s3 ls s3://galaxy-cloud-data-1760241377/"
```

### 4. 简化测试

创建一个简单的测试工具，不需要输入文件：

```bash
# 测试命令
echo "Hello Cloud" > /galaxy/work/outputs/test.txt && \
aws s3 cp /galaxy/work/outputs/test.txt s3://bucket/test.txt
```

## 成功标准

完整的成功执行应该包括：

1. ✅ AWS 认证成功
2. ✅ 输入文件上传到 S3
3. ✅ 任务提交到 AWS Batch
4. ✅ 容器从 S3 下载输入文件
5. ✅ 工具执行成功
6. ✅ 输出文件上传到 S3
7. ✅ 输出文件下载回本地 Galaxy
8. ✅ Galaxy UI 显示正确结果

## 快速检查清单

- [ ] AWS 认证有效：`aws sts get-caller-identity`
- [ ] S3 bucket 可访问：`aws s3 ls s3://galaxy-cloud-data-1760241377/`
- [ ] AWS Batch queue 存在：`aws batch describe-job-queues --job-queue galaxy-cloud-queue`
- [ ] `config/job_conf_cloud.yml` 包含 `s3_bucket` 参数
- [ ] Galaxy 正在运行：`curl http://localhost:8080/api/version`
- [ ] Cloud job runner 正在使用：查看日志中的 "GalaxyCloudJobRunner"
- [ ] 文件传输正在执行：查看日志中的 "prepared with file transfers"

## 需要帮助？

如果问题仍然存在，提供以下信息：

1. AWS 认证状态：`aws sts get-caller-identity`输出
2. Galaxy 日志：最后 200 行 `database/gravity/log/gunicorn.log`
3. AWS Batch 任务 ID 和状态
4. CloudWatch 日志（如果任务已运行）
5. `config/job_conf_cloud.yml` 相关部分

当前最关键的是：**先解决 AWS 认证问题**，然后就能看到文件传输功能工作了！
