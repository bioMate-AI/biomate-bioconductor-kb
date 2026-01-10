# ✅ IAM 角色配置问题已修复

## 问题根本原因

### 发现的问题

容器日志显示使用的是 **EC2 实例角色** 而不是 **任务角色**：

```json
{
  "Arn": "arn:aws:sts::399683337364:assumed-role/ecsInstanceRole/i-0d3359b4b5cb3bd05"
}
```

而我们需要的是：

```json
{
  "Arn": "arn:aws:sts::399683337364:assumed-role/BatchJobRole/..."
}
```

### 根本原因

**`config/aws_cloud_config.yaml` 第 77 行配置错误**：

```yaml
# ❌ 错误配置
job_role_arn: "arn:aws:batch:us-west-2:399683337364:job-queue/galaxy-cloud-queue"
```

这是一个 **AWS Batch Queue ARN**，不是 **IAM Role ARN**！

## 修复方案

### 1. 修正配置文件

**修改前**:
```yaml
job_role_arn: "arn:aws:batch:us-west-2:399683337364:job-queue/galaxy-cloud-queue"
# execution_role_arn: "arn:aws:iam::123456789012:role/GalaxyBatchExecutionRole"
```

**修改后**:
```yaml
job_role_arn: "arn:aws:iam::399683337364:role/BatchJobRole"
execution_role_arn: "arn:aws:iam::399683337364:role/ecsTaskExecutionRole"
```

### 2. 重启 Galaxy

```bash
# 停止 Galaxy
pkill -f "python.*run.py"

# 启动 Galaxy
cd /Users/renyuankai/work/biometa/galaxy
./run.sh
```

## ARN 格式说明

### IAM Role ARN (正确)
```
arn:aws:iam::{account-id}:role/{role-name}
          ^^^                     ^^^^
```

示例：
- `arn:aws:iam::399683337364:role/BatchJobRole`
- `arn:aws:iam::399683337364:role/ecsTaskExecutionRole`

### AWS Batch Queue ARN (错误用法)
```
arn:aws:batch:{region}:{account-id}:job-queue/{queue-name}
          ^^^^^                               ^^^^^^^^^^
```

示例：
- `arn:aws:batch:us-west-2:399683337364:job-queue/galaxy-cloud-queue`

## 两个角色的区别

### jobRoleArn (任务角色)

**作用**: 容器内应用程序使用的权限

**用途**:
- 访问 S3 bucket
- 调用其他 AWS 服务 API
- 容器内的 AWS CLI/SDK 使用这个角色

**示例权限**:
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:ListBucket"
  ],
  "Resource": "arn:aws:s3:::galaxy-cloud-data-1760241377/*"
}
```

### executionRoleArn (执行角色)

**作用**: AWS Batch/ECS 用于管理容器的权限

**用途**:
- 从 ECR 拉取 Docker 镜像
- 写入 CloudWatch 日志
- 挂载 EFS 文件系统（如果使用）

**示例权限**:
```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "*"
}
```

## 配置工作流程

```
┌─────────────────────────────────────────────────┐
│ aws_cloud_config.yaml                           │
│                                                 │
│  job_role_arn: arn:aws:iam::../BatchJobRole    │
│  execution_role_arn: arn:aws:iam::../ecsTask.. │
└─────────────────┬───────────────────────────────┘
                  │
                  │ Galaxy 读取配置
                  ↓
┌─────────────────────────────────────────────────┐
│ Galaxy Cloud Executor                           │
│                                                 │
│  创建 AWS Batch Job Definition:                │
│    containerProperties:                         │
│      jobRoleArn: ${job_role_arn}               │
│      executionRoleArn: ${execution_role_arn}   │
└─────────────────┬───────────────────────────────┘
                  │
                  │ 提交任务
                  ↓
┌─────────────────────────────────────────────────┐
│ AWS Batch Job                                   │
│                                                 │
│  容器启动时:                                    │
│    1. ECS 使用 executionRoleArn 拉取镜像       │
│    2. 注入 jobRoleArn 临时凭证到容器           │
│    3. 设置 AWS_CONTAINER_CREDENTIALS_RELATIVE_URI│
└─────────────────┬───────────────────────────────┘
                  │
                  │ 容器运行
                  ↓
┌─────────────────────────────────────────────────┐
│ Fetch-and-Run Container                        │
│                                                 │
│  aws sts get-caller-identity                   │
│  → 返回: BatchJobRole ✅                        │
│                                                 │
│  aws s3 cp s3://bucket/file                    │
│  → 使用 BatchJobRole 的 S3 权限 ✅             │
└─────────────────────────────────────────────────┘
```

## 验证修复

### 1. 重启 Galaxy 后

查看 Galaxy 日志：
```bash
tail -f galaxy.log | grep "job_role_arn"
```

应该看到正确的 IAM role ARN。

### 2. 提交新的 workflow

运行一个测试 workflow。

### 3. 检查 AWS Batch 容器日志

预期输出：
```
Checking AWS credentials...
✓ Using ECS task role credentials
  Credentials URI: /v2/credentials/xxx

AWS Identity:
{
  "Account": "399683337364",
  "Arn": "arn:aws:sts::399683337364:assumed-role/BatchJobRole/..."
                                                     ^^^^^^^^^^^
}

[1/4] Downloading job script from S3...
✓ Job script downloaded successfully
```

**关键**: `Arn` 应该包含 **BatchJobRole**，而不是 `ecsInstanceRole`。

## 如果还有问题

### 检查 Galaxy 是否使用了新配置

```bash
# 查看 Galaxy 进程
ps aux | grep galaxy

# 确认进程已重启（启动时间应该是最近）
```

### 检查 AWS Batch job definition

```bash
# 获取最新提交的任务
JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING --region us-west-2 --max-items 1 --query 'jobSummaryList[0].jobId' --output text)

# 检查任务使用的角色
aws batch describe-jobs --jobs $JOB_ID --region us-west-2 --query 'jobs[0].container.jobRoleArn'
```

应该返回：
```
"arn:aws:iam::399683337364:role/BatchJobRole"
```

### 清理旧的 job definitions

如果需要，可以清理旧的错误配置：

```bash
# 列出所有 job definitions
aws batch describe-job-definitions --status ACTIVE --region us-west-2 --query 'jobDefinitions[].jobDefinitionName' --output table

# 注销不需要的版本
aws batch deregister-job-definition --job-definition <name>:<revision> --region us-west-2
```

## 总结

✅ **问题**: 配置文件中 `job_role_arn` 使用了错误的 ARN 类型（Batch Queue 而不是 IAM Role）

✅ **修复**: 更正为正确的 IAM Role ARN

✅ **验证**: 重启 Galaxy，运行 workflow，检查容器日志显示 BatchJobRole

**现在应该可以正常工作了！** 🎉

---

## 快速命令参考

```bash
# 1. 重启 Galaxy
pkill -f "python.*run.py" && cd /Users/renyuankai/work/biometa/galaxy && ./run.sh

# 2. 运行 workflow (在 Galaxy UI)

# 3. 查看日志
tail -f galaxy.log | grep -E "submit|job_role"

# 4. 检查 AWS Batch
aws batch list-jobs --job-queue galaxy-cloud-queue --region us-west-2

# 5. 查看容器日志 (在 AWS Console CloudWatch Logs)
```
