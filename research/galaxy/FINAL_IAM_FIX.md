# ✅ 最终 IAM 角色修复 - 完整解决方案

## 问题总结

虽然修改了 `aws_cloud_config.yaml`，但容器仍然使用 `ecsInstanceRole` 而不是 `BatchJobRole`。

## 根本原因

有**两个**配置需要修改：

### 1. ❌ `aws_cloud_config.yaml` (不够！)

这个文件只在**没有 job destination** 时使用。但 Galaxy 提交任务时使用的是 `job_conf.yml` 中的 destination。

### 2. ❌ `galaxy_job_runner.py` 缺少参数传递

即使 `job_conf.yml` 有 IAM 角色参数，`galaxy_job_runner.py` 也没有传递它们给 cloud executor。

## 完整修复

### 修复 1: `galaxy_job_runner.py` 传递 IAM 角色

**文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**修改** `_build_provider_config` 方法（第 123-127 行）：

```python
# IAM Roles for AWS Batch jobs
if 'job_role_arn' in params:
    config['job_role_arn'] = params['job_role_arn']
if 'execution_role_arn' in params:
    config['execution_role_arn'] = params['execution_role_arn']
```

### 修复 2: `job_conf.yml` 添加 IAM 角色参数

**文件**: `config/job_conf.yml`

**在 `cloud_fetch_and_run` 环境中添加**（第 433-435 行）：

```yaml
cloud_fetch_and_run:
  runner: galaxy_cloud
  use_fetch_and_run: true
  provider: aws
  aws_region: us-west-2
  aws_batch_queue: galaxy-cloud-queue
  aws_s3_bucket: galaxy-cloud-data-1760241377
  fetch_and_run_image: "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest"
  # 新增这两行 👇
  job_role_arn: "arn:aws:iam::399683337364:role/BatchJobRole"
  execution_role_arn: "arn:aws:iam::399683337364:role/ecsTaskExecutionRole"
  cpus: 2
  memory: 4
  disk: 20
```

## 配置流程图

```
┌──────────────────────────────────────────────────────┐
│ config/job_conf.yml                                  │
│                                                      │
│ cloud_fetch_and_run:                                │
│   aws_region: us-west-2                             │
│   aws_batch_queue: galaxy-cloud-queue               │
│   aws_s3_bucket: galaxy-cloud-data-1760241377       │
│   job_role_arn: arn:aws:iam::.../BatchJobRole       │ ◄── 新增
│   execution_role_arn: arn:aws:iam::.../ecsTask...   │ ◄── 新增
└───────────────────────┬──────────────────────────────┘
                        │
                        │ Galaxy 读取 job destination
                        ↓
┌──────────────────────────────────────────────────────┐
│ galaxy_job_runner.py                                 │
│                                                      │
│ def _build_provider_config(job_destination):        │
│   params = job_destination.params                   │
│   config = {}                                        │
│   config['region'] = params['aws_region']           │
│   config['batch_queue'] = params['aws_batch_queue'] │
│   config['s3_bucket'] = params['aws_s3_bucket']     │
│   config['job_role_arn'] = params['job_role_arn']   │ ◄── 新增
│   config['execution_role_arn'] = ...                │ ◄── 新增
│   return config                                      │
└───────────────────────┬──────────────────────────────┘
                        │
                        │ 传递给 cloud executor
                        ↓
┌──────────────────────────────────────────────────────┐
│ AWSBatchExecutor (providers/aws/executor.py)        │
│                                                      │
│ def _build_job_definition(job_spec, job_def_name):  │
│   container_props = {...}                           │
│                                                      │
│   job_role = self.config.get('job_role_arn')        │
│   if job_role:                                       │
│     container_props['jobRoleArn'] = job_role        │ ◄── 使用配置
│                                                      │
│   execution_role = self.config.get('execution_...')│
│   if execution_role:                                 │
│     container_props['executionRoleArn'] = ...       │ ◄── 使用配置
└───────────────────────┬──────────────────────────────┘
                        │
                        │ 注册 job definition
                        ↓
┌──────────────────────────────────────────────────────┐
│ AWS Batch Job Definition                             │
│                                                      │
│ {                                                    │
│   "containerProperties": {                           │
│     "jobRoleArn": "arn:aws:iam::.../BatchJobRole",  │ ✅
│     "executionRoleArn": "arn:aws:iam::.../ecsTask..."│ ✅
│   }                                                  │
│ }                                                    │
└───────────────────────┬──────────────────────────────┘
                        │
                        │ 提交任务
                        ↓
┌──────────────────────────────────────────────────────┐
│ AWS Batch Job (Container)                           │
│                                                      │
│ Environment:                                         │
│   AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=/v2/...    │ ✅
│                                                      │
│ aws sts get-caller-identity:                        │
│ {                                                    │
│   "Arn": "arn:aws:sts::.../BatchJobRole/..."       │ ✅
│ }                                                    │
│                                                      │
│ aws s3 cp s3://bucket/file → 成功！ ✅               │
└──────────────────────────────────────────────────────┘
```

## 为什么需要两个修复

### 问题 1: 配置没有传递

即使在 `job_conf.yml` 中配置了 IAM 角色，`galaxy_job_runner.py` 的 `_build_provider_config` 方法也没有提取这些参数。

**代码修复前**:
```python
def _build_provider_config(job_destination):
    config = {}
    if 'aws_region' in params:
        config['region'] = params['aws_region']
    # ... 其他参数
    # ❌ 没有提取 job_role_arn 和 execution_role_arn
    return config
```

**代码修复后**:
```python
def _build_provider_config(job_destination):
    config = {}
    if 'aws_region' in params:
        config['region'] = params['aws_region']
    # ... 其他参数
    # ✅ 新增 IAM 角色参数提取
    if 'job_role_arn' in params:
        config['job_role_arn'] = params['job_role_arn']
    if 'execution_role_arn' in params:
        config['execution_role_arn'] = params['execution_role_arn']
    return config
```

### 问题 2: Job Destination 没有 IAM 角色参数

即使代码提取了参数，`job_conf.yml` 中的 destination 也没有定义这些参数。

**配置修复前**:
```yaml
cloud_fetch_and_run:
  runner: galaxy_cloud
  aws_region: us-west-2
  aws_batch_queue: galaxy-cloud-queue
  aws_s3_bucket: galaxy-cloud-data-1760241377
  # ❌ 没有 IAM 角色参数
```

**配置修复后**:
```yaml
cloud_fetch_and_run:
  runner: galaxy_cloud
  aws_region: us-west-2
  aws_batch_queue: galaxy-cloud-queue
  aws_s3_bucket: galaxy-cloud-data-1760241377
  # ✅ 添加 IAM 角色参数
  job_role_arn: "arn:aws:iam::399683337364:role/BatchJobRole"
  execution_role_arn: "arn:aws:iam::399683337364:role/ecsTaskExecutionRole"
```

## 重启 Galaxy

```bash
# 1. 停止 Galaxy
pkill -9 -f "galaxy|gunicorn|celery"

# 2. 启动 Galaxy
cd /Users/renyuankai/work/biometa/galaxy
./run.sh

# 3. 等待启动完成（约 30 秒）
# 查看日志确认启动
tail -f galaxy.log
```

## 验证修复

### 1. 提交新的 Workflow

在 Galaxy UI 中运行一个 workflow。

### 2. 检查 Galaxy 日志

```bash
tail -f galaxy.log | grep "Built provider config"
```

**预期输出**:
```
Built provider config from job destination: {
  'region': 'us-west-2',
  'batch_queue': 'galaxy-cloud-queue',
  's3_bucket': 'galaxy-cloud-data-1760241377',
  'job_role_arn': 'arn:aws:iam::399683337364:role/BatchJobRole',          ← 新增
  'execution_role_arn': 'arn:aws:iam::399683337364:role/ecsTaskExecutionRole' ← 新增
}
```

### 3. 检查 AWS Batch 容器日志

**预期输出**:
```
Checking AWS credentials...
✓ Using ECS task role credentials
  Credentials URI: /v2/credentials/xxx

AWS Identity:
{
  "Account": "399683337364",
  "Arn": "arn:aws:sts::399683337364:assumed-role/BatchJobRole/..."
         ↑↑↑ 现在是 BatchJobRole，不是 ecsInstanceRole ✅
}

[1/4] Downloading job script from S3...
✓ Job script downloaded successfully  ← 不再是 403 ✅
```

### 4. 检查创建的 Job Definition

```bash
# 获取最新的任务
JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING --region us-west-2 --max-items 1 --query 'jobSummaryList[0].jobId' --output text)

# 检查任务的 job role
aws batch describe-jobs --jobs $JOB_ID --region us-west-2 --query 'jobs[0].container.jobRoleArn' --output text
```

**预期输出**:
```
arn:aws:iam::399683337364:role/BatchJobRole  ✅
```

## 修改的文件

1. ✅ `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
   - 添加 IAM 角色参数传递

2. ✅ `config/job_conf.yml`
   - 在 `cloud_fetch_and_run` 环境添加 IAM 角色参数

## 为什么之前的修复不起作用

### 修复 aws_cloud_config.yaml

这个文件只在调用 `_load_cloud_config()` 时使用，但实际上 Galaxy 使用的是 `_build_provider_config(job_destination)`。

### 只修改 job_conf.yml

即使添加了参数，`_build_provider_config` 方法也不会提取它们，因为代码中没有这部分逻辑。

## 总结

✅ **需要两个修复才能完整解决问题**:
1. 代码修复：让 `galaxy_job_runner.py` 传递 IAM 角色参数
2. 配置修复：在 `job_conf.yml` 中添加 IAM 角色参数

✅ **重启 Galaxy 后生效**

✅ **验证成功标志**: 容器日志显示 `BatchJobRole` 而不是 `ecsInstanceRole`

**现在重启 Galaxy 并测试！** 🎉
