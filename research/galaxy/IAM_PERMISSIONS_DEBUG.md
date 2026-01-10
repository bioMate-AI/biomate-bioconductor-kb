# IAM 权限问题排查和解决

## 问题现象

AWS Batch 容器日志显示 403 错误：
```
[1/4] Downloading job script from S3...
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

## 你的问题

> 你帮我新建的镜像，要把AWS配置写死进去吗？

**答案：不需要！**

AWS 凭证是通过 **IAM 角色** 自动注入到容器中的，不需要硬编码任何配置。

## AWS 凭证工作原理

### 1. IAM 角色配置

AWS Batch job definition 配置了两个角色：

```json
{
  "jobRoleArn": "arn:aws:iam::399683337364:role/BatchJobRole",
  "executionRoleArn": "arn:aws:iam::399683337364:role/ecsTaskExecutionRole"
}
```

- **jobRoleArn**: 容器内的应用程序使用的角色（用于 S3 访问）
- **executionRoleArn**: ECS/Batch 用于拉取镜像、写日志的角色

### 2. 凭证自动注入

当容器启动时，AWS 会：

1. 在容器内设置环境变量 `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`
2. AWS CLI/SDK 自动从这个 URI 获取临时凭证
3. 凭证会自动轮换，永远不会过期

### 3. 在容器内使用

```bash
# 不需要 aws configure
# 不需要设置 AWS_ACCESS_KEY_ID 或 AWS_SECRET_ACCESS_KEY
# 直接使用 AWS CLI
aws s3 ls s3://my-bucket/
```

## 已完成的修复

### 1. ✅ IAM 权限验证

运行了诊断脚本，确认：
- ✅ BatchJobRole 有 S3 访问权限
- ✅ 信任策略允许 ecs-tasks.amazonaws.com 假定角色
- ✅ 本地可以正常访问 S3

### 2. ✅ 添加调试日志

更新了 `fetch_and_run.sh`，在下载前检查凭证：

```bash
# 检查凭证环境变量
if [ -n "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}" ]; then
    echo "✓ Using ECS task role credentials"
else
    echo "⚠ No ECS task role credentials found"
fi

# 验证身份
aws sts get-caller-identity
```

### 3. ✅ 重新构建镜像

新镜像已推送：
- Digest: `sha256:6a26f3ca13933aaa8d927b51880cadda6d65d1d62bc5190ec387155d2cee045c`
- 包含凭证调试功能

## 排查 403 错误的步骤

### 1. 重新运行 workflow

新镜像会输出更详细的调试信息：

```
Checking AWS credentials...
✓ Using ECS task role credentials
  Credentials URI: /v2/credentials/xxx-xxx-xxx

AWS Identity:
{
  "UserId": "AROA...",
  "Account": "399683337364",
  "Arn": "arn:aws:sts::399683337364:assumed-role/BatchJobRole/..."
}
```

### 2. 检查日志输出

**如果看到**:
```
✓ Using ECS task role credentials
AWS Identity: {...}
```
说明凭证正常，403 可能是：
- S3 bucket policy 问题
- 对象被加密且角色没有 KMS 权限
- 对象路径错误

**如果看到**:
```
⚠ No ECS task role credentials found
ERROR: Cannot get AWS identity
```
说明 IAM 角色没有正确配置，需要检查 job definition。

### 3. 验证 S3 路径

检查日志中的 S3 URL 是否正确：
```
Script URL: s3://galaxy-cloud-data-1760241377/jobs/208/job_script.sh
```

确认文件是否存在：
```bash
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/208/
```

## 可能的原因和解决方案

### 原因 1: IAM 角色传播延迟

**症状**: 刚创建/更新的 IAM 角色，立即运行失败

**解决方案**: 等待 1-2 分钟后重试

### 原因 2: S3 对象不存在

**症状**: Galaxy 上传失败，但 Batch job 仍然提交

**解决方案**:
```bash
# 检查 Galaxy 日志
tail -f galaxy.log | grep "S3"

# 检查 S3 bucket
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive
```

### 原因 3: S3 Bucket Policy

**症状**: IAM 角色有权限，但 bucket policy 拒绝访问

**解决方案**:
```bash
# 检查 bucket policy
aws s3api get-bucket-policy --bucket galaxy-cloud-data-1760241377

# 如果需要，更新 bucket policy 允许该角色访问
```

### 原因 4: KMS 加密

**症状**: S3 对象使用 KMS 加密，但角色没有 KMS 解密权限

**解决方案**:
```bash
# 检查是否使用了 KMS
aws s3api head-object --bucket galaxy-cloud-data-1760241377 --key jobs/208/job_script.sh

# 如果 ServerSideEncryption 是 aws:kms，需要添加 KMS 权限
```

## 测试命令

### 从容器内测试（如果有访问权限）

```bash
# 获取 Batch job ID
JOB_ID="5ee220c6-d466-4c8b-ba24-d4e631e597bc"

# 获取容器实例
aws batch describe-jobs --jobs $JOB_ID --region us-west-2

# SSH 到 ECS 实例（如果可以），然后
docker exec -it <container-id> bash
aws sts get-caller-identity
aws s3 ls s3://galaxy-cloud-data-1760241377/
```

### 从本地测试 S3 访问

```bash
# 假定 BatchJobRole
aws sts assume-role \
  --role-arn arn:aws:iam::399683337364:role/BatchJobRole \
  --role-session-name test-session

# 使用返回的临时凭证测试 S3
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/208/
```

## 下一步

1. **重新运行 Galaxy workflow**
2. **查看新的 AWS Batch 日志** - 现在会有详细的凭证调试信息
3. **根据日志输出** 确定真正的问题

如果新日志显示凭证正常但仍然 403，请提供：
- 完整的容器日志
- Galaxy 日志中的相关输出
- S3 路径的 `aws s3 ls` 输出

## 关键点

✅ **不需要在镜像中硬编码任何 AWS 配置**
✅ **IAM 角色会自动提供凭证**
✅ **凭证通过环境变量 `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` 获取**
✅ **新镜像包含调试日志，会显示凭证状态**

**现在重新运行 workflow 并查看新的日志输出！** 🔍
