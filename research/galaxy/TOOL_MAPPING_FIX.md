# ✅ 工具环境映射问题 - 最终修复

## 真正的问题

虽然修改了代码和配置，但 **FastQC 工具被硬编码到了 `cloud_small` environment**，没有使用 `cloud_fetch_and_run`！

## 问题发现过程

### 1. AWS Batch 日志仍显示 ecsInstanceRole

```
"Arn": "arn:aws:sts::399683337364:assumed-role/ecsInstanceRole/..."
```

### 2. 检查 job definitions

所有的 job definitions 都没有 `jobRoleArn`：

```bash
aws batch describe-job-definitions --status ACTIVE
# jobRoleArn: None  ← 说明没有使用新配置
```

### 3. 检查 Galaxy 日志

**没有找到** "fetch-and-run" 相关日志！说明代码没有进入 fetch-and-run 分支。

### 4. 检查工具映射配置

```yaml
# config/job_conf.yml
tools:
- id: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0
  environment: cloud_small  ← 问题在这里！
```

**FastQC 工具特定配置覆盖了 default environment！**

## Galaxy 配置优先级

```
工具特定配置 > Default 执行环境

tools:
  - id: fastqc
    environment: cloud_small      ← 优先级最高

execution:
  default: cloud_fetch_and_run    ← 被覆盖了
```

## 完整的修复链

### 修复 1: 代码传递 IAM 角色 ✅

**文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

```python
def _build_provider_config(job_destination):
    # ...
    if 'job_role_arn' in params:
        config['job_role_arn'] = params['job_role_arn']
    if 'execution_role_arn' in params:
        config['execution_role_arn'] = params['execution_role_arn']
```

### 修复 2: job_conf.yml 配置 IAM 角色 ✅

```yaml
cloud_fetch_and_run:
  runner: galaxy_cloud
  use_fetch_and_run: true
  aws_region: us-west-2
  aws_batch_queue: galaxy-cloud-queue
  aws_s3_bucket: galaxy-cloud-data-1760241377
  fetch_and_run_image: "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest"
  job_role_arn: "arn:aws:iam::399683337364:role/BatchJobRole"          # ← 新增
  execution_role_arn: "arn:aws:iam::399683337364:role/ecsTaskExecutionRole"  # ← 新增
```

### 修复 3: 设置 default environment ✅

```yaml
execution:
  default: cloud_fetch_and_run  # ← 已设置
```

### 修复 4: 删除工具特定映射 ✅ **（关键！）**

**修改前**:
```yaml
tools:
- id: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0
  environment: cloud_small  # ❌ 覆盖了 default
```

**修改后**:
```yaml
tools:
# All tools use default environment (cloud_fetch_and_run)
- class: local
  environment: local  # 只有 local 类工具使用 local
# FastQC 等工具不再有特定配置，使用 default (cloud_fetch_and_run)
```

## 配置流程图（完整版）

```
┌─────────────────────────────────────────────────────┐
│ Galaxy 提交 FastQC 任务                             │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 1. 查找工具配置
                     ↓
┌─────────────────────────────────────────────────────┐
│ config/job_conf.yml - tools 部分                    │
│                                                     │
│ ❌ 之前:                                            │
│   - id: fastqc                                     │
│     environment: cloud_small  ← 使用这个           │
│                                                     │
│ ✅ 现在:                                            │
│   # 没有 fastqc 特定配置                           │
│   # 使用 default environment                        │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 2. 使用 default environment
                     ↓
┌─────────────────────────────────────────────────────┐
│ config/job_conf.yml - execution 部分                │
│                                                     │
│ execution:                                          │
│   default: cloud_fetch_and_run  ← 现在会用这个     │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 3. 加载 environment 配置
                     ↓
┌─────────────────────────────────────────────────────┐
│ config/job_conf.yml - environments 部分             │
│                                                     │
│ cloud_fetch_and_run:                                │
│   runner: galaxy_cloud                              │
│   use_fetch_and_run: true                           │
│   job_role_arn: arn:aws:iam::.../BatchJobRole      │
│   execution_role_arn: arn:aws:iam::.../ecsTask...  │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 4. Galaxy 调用 job runner
                     ↓
┌─────────────────────────────────────────────────────┐
│ galaxy_job_runner.py - queue_job()                  │
│                                                     │
│ use_fetch_and_run = params.get('use_fetch_and_run')│
│ if use_fetch_and_run:  # ✅ True                   │
│   _submit_fetch_and_run_job()                      │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 5. 构建 provider config
                     ↓
┌─────────────────────────────────────────────────────┐
│ galaxy_job_runner.py - _build_provider_config()     │
│                                                     │
│ config = {                                          │
│   'region': params['aws_region'],                  │
│   'batch_queue': params['aws_batch_queue'],        │
│   's3_bucket': params['aws_s3_bucket'],            │
│   'job_role_arn': params['job_role_arn'],    ✅    │
│   'execution_role_arn': params['execution_...'] ✅ │
│ }                                                   │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 6. 创建 cloud executor
                     ↓
┌─────────────────────────────────────────────────────┐
│ AWSBatchExecutor - _build_job_definition()          │
│                                                     │
│ container_props = {                                 │
│   'jobRoleArn': config.get('job_role_arn'),   ✅   │
│   'executionRoleArn': config.get('execution_...') ✅│
│ }                                                   │
└────────────────────┬────────────────────────────────┘
                     │
                     │ 7. 提交 AWS Batch job
                     ↓
┌─────────────────────────────────────────────────────┐
│ AWS Batch Job                                       │
│                                                     │
│ AWS Identity:                                       │
│ {                                                   │
│   "Arn": "arn:aws:sts::.../BatchJobRole/..."  ✅   │
│ }                                                   │
│                                                     │
│ aws s3 cp s3://bucket/file  ← 成功！ ✅            │
└─────────────────────────────────────────────────────┘
```

## 为什么之前的修复不起作用

### ❌ 只修改了 cloud_fetch_and_run environment

虽然配置了 IAM 角色，但 FastQC 工具根本不使用这个 environment。

### ❌ 只设置了 default environment

工具特定配置的优先级更高，覆盖了 default。

### ✅ 需要删除工具特定配置

让工具回退到使用 default environment。

## 验证修复

### 1. 重新运行 workflow

在 Galaxy UI 中运行 FastQC workflow。

### 2. 检查 Galaxy 日志

```bash
tail -f galaxy.log | grep -E "fetch-and-run|Built provider config"
```

**预期输出**:
```
Job 227 will use Fetch-and-Run execution
Built provider config from job destination: {
  'region': 'us-west-2',
  'batch_queue': 'galaxy-cloud-queue',
  's3_bucket': 'galaxy-cloud-data-1760241377',
  'job_role_arn': 'arn:aws:iam::399683337364:role/BatchJobRole',  ← 出现了！
  'execution_role_arn': 'arn:aws:iam::399683337364:role/ecsTaskExecutionRole'
}
```

### 3. 检查 AWS Batch 容器日志

**预期输出**:
```
AWS Identity:
{
  "Arn": "arn:aws:sts::399683337364:assumed-role/BatchJobRole/..."  ← BatchJobRole！
}

[1/4] Downloading job script from S3...
✓ Job script downloaded successfully  ← 成功！
```

### 4. 检查 job definition

```bash
# 最新的 job definition 应该有 jobRoleArn
JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING --region us-west-2 --max-items 1 --query 'jobSummaryList[0].jobId' --output text)
aws batch describe-jobs --jobs $JOB_ID --region us-west-2 --query 'jobs[0].container.jobRoleArn'
```

**预期输出**:
```
"arn:aws:iam::399683337364:role/BatchJobRole"  ← 有值了！
```

## 修改的文件总结

1. ✅ `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
   - 添加 IAM 角色参数传递

2. ✅ `config/job_conf.yml` - environments 部分
   - 在 `cloud_fetch_and_run` 中添加 IAM 角色

3. ✅ `config/job_conf.yml` - execution 部分
   - 设置 default 为 `cloud_fetch_and_run`

4. ✅ `config/job_conf.yml` - tools 部分
   - **删除 FastQC 的特定 environment 配置**

## 不需要重启 Galaxy

`job_conf.yml` 的更改会**自动重新加载**，不需要重启 Galaxy！

## 立即测试

**直接在 Galaxy UI 重新运行 workflow**，应该立即看到效果！

---

## 关键要点

✅ **工具特定配置 > Default 配置**

✅ **删除不需要的工具特定配置，让工具使用 default**

✅ **job_conf.yml 会自动重新加载**

**现在立即测试 - 不需要重启！** 🚀
