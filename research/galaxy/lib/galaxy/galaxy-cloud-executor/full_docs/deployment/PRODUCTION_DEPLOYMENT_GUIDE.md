# Galaxy Cloud Executor 生产部署指南

## 概览

本指南说明如何将 Galaxy Cloud Executor 部署到生产环境，实现 Galaxy workflow 的自动云执行和资源自动分配。

---

## 一、系统架构

### 完整流程图

```
Galaxy WebUI
    ↓
用户提交 Workflow
    ↓
Galaxy Core (job_conf.xml)
    ↓
GalaxyCloudJobRunner (galaxy_job_runner.py)
    ↓
CloudExecutor (aws_executor.py)
    ↓
AWS Batch API
    ↓
[自动资源分配开始]
    ↓
1. Job → Job Queue (SUBMITTED)
    ↓
2. Job Queue → Compute Environment (PENDING)
    ↓
3. Compute Environment 检查当前容量
    ↓
4. 如果容量不足 → 触发 Auto Scaling Group
    ↓
5. Auto Scaling Group → 使用 Launch Template 启动 EC2
    ↓
6. EC2 实例启动 (2-3 分钟)
    ↓
7. ECS Agent 启动并注册 (1-2 分钟)
    ↓
8. 实例注册到 ECS 集群 (RUNNABLE → STARTING)
    ↓
9. 任务调度到实例 (STARTING → RUNNING)
    ↓
10. 容器启动，拉取 Docker 镜像
    ↓
11. 执行生物信息学工具
    ↓
12. 输出写入 S3
    ↓
13. CloudWatch Logs 捕获日志
    ↓
14. 任务完成 (SUCCEEDED)
    ↓
GalaxyCloudJobRunner 获取结果和日志
    ↓
Galaxy 显示结果和日志
    ↓
用户查看结果
    ↓
[10 分钟无新任务]
    ↓
Auto Scaling Group 自动缩容
    ↓
EC2 实例终止 (成本归零)
```

### 核心组件

#### 1. Galaxy 端
- **job_conf.xml**: 配置作业路由规则
- **GalaxyCloudJobRunner**: Galaxy 插件，负责作业提交和监控
- **cloud_config.yaml**: AWS 云配置（凭证、区域、队列等）

#### 2. AWS Batch 端
- **Job Queue**: 作业队列，接收 Galaxy 提交的任务
- **Compute Environment**: 计算环境，管理资源容量
- **Auto Scaling Group**: 自动扩缩容组，根据需求启动/终止 EC2
- **Launch Template**: 实例模板，定义实例配置（AMI、类型、IAM 等）

#### 3. AWS 基础设施
- **ECS Cluster**: 容器集群，管理容器实例
- **EC2 Instances**: 实际执行任务的虚拟机
- **S3 Bucket**: 存储输入/输出数据
- **CloudWatch Logs**: 存储任务日志
- **IAM Roles**: 权限管理

---

## 二、自动资源分配机制详解

### 核心原理：按需自动扩容

AWS Batch 的自动资源分配基于以下逻辑：

```python
# 伪代码示例
def auto_scaling_logic():
    # 1. 检查作业队列
    pending_jobs = count_jobs_in_queue(status='RUNNABLE')

    # 2. 计算所需资源
    required_vcpus = sum([job.vcpus for job in pending_jobs])

    # 3. 检查当前容量
    current_vcpus = get_current_ecs_capacity()

    # 4. 决定是否扩容
    if required_vcpus > current_vcpus:
        needed_vcpus = required_vcpus - current_vcpus

        # 5. 更新 Auto Scaling Group DesiredCapacity
        asg.set_desired_capacity(
            instances_needed_for(needed_vcpus)
        )

        # 6. Auto Scaling Group 启动新 EC2 实例
        launch_instances_from_template()

    # 7. 10 分钟无新作业 → 自动缩容
    if idle_time > 600:
        scale_down_to_min_capacity()
```

### 配置参数说明

#### minvCpus (最小容量)
```yaml
minvCpus: 0  # 推荐生产环境配置
```
- **含义**: 空闲时保持的最小 vCPU 数量
- **minvCpus=0**: 无作业时完全缩容，成本为零
- **优点**: 成本最优
- **缺点**: 首次作业需要等待实例启动（5-10 分钟）

#### maxvCpus (最大容量)
```yaml
maxvCpus: 256  # 根据需求调整
```
- **含义**: 最多可以扩容到的 vCPU 数量
- **建议**: 根据团队规模和工作负载设置
  - 小团队（5-10 人）: 64-128
  - 中团队（10-50 人）: 128-256
  - 大团队（50+ 人）: 256-512

#### desiredvCpus (期望容量)
```yaml
desiredvCpus: 0  # 通常等于 minvCpus
```
- **含义**: 系统期望维持的 vCPU 数量
- **动态调整**: AWS Batch 会根据队列中的作业自动调整

### 扩容触发条件

AWS Batch 会在以下情况触发扩容：

1. **有作业进入 RUNNABLE 状态**
   - 作业已排队，等待资源
   - 当前容量无法满足需求

2. **计算所需实例数**
   ```
   所需实例数 = ceil((作业总 vCPU 需求 - 当前可用 vCPU) / 实例 vCPU)
   ```

3. **更新 Auto Scaling Group**
   - 设置 DesiredCapacity
   - 触发实例启动

### 缩容触发条件

1. **空闲时间超过阈值**（默认 10 分钟）
   - 没有 RUNNING 作业
   - 没有 RUNNABLE 作业

2. **逐步缩容**
   - 先终止最空闲的实例
   - 最终缩容到 minvCpus

---

## 三、已解决的问题总结

在部署过程中遇到并解决了以下关键问题：

### 问题 1: 实例类型与可用区不兼容 ✅ 已解决

**现象**: 作业卡在 RUNNABLE，ASG 启动失败

**原因**:
```
m4.large 实例类型在 us-west-2d 可用区不支持
```

**解决方案**:
- 使用 `optimal` 实例类型（让 AWS 自动选择）
- 或使用现代实例类型（m5, m6i 等）
- AWS Batch 自动重试机制会在其他可用区尝试

**当前配置**:
```yaml
instanceTypes: ["optimal"]  # 或 ["m5.large", "m5.xlarge"]
```

### 问题 2: Launch Template 缺少 IAM Instance Profile ✅ 已解决

**现象**: 实例启动后立即被终止

**原因**:
```
Launch Template 中未设置 IamInstanceProfile
→ ECS Agent 无法认证
→ 无法注册到 ECS 集群
→ 实例被终止
```

**解决方案**:
- 运行 `fix_launch_template.sh` 脚本
- 手动更新 Launch Template，添加 IAM Instance Profile
- 确保 Instance Profile 关联了正确的 Role

**验证**:
```bash
# 检查新启动的实例
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
# 应该显示 ARN，不是 null
```

### 问题 3: Instance Profile 未关联 Role ✅ 已解决

**现象**: Instance Profile 存在但 Roles 列表为空

**原因**:
```
IAM Instance Profile 创建了，但没有关联 IAM Role
```

**解决方案**:
```bash
aws iam add-role-to-instance-profile \
  --instance-profile-name ecsInstanceRole \
  --role-name ecsInstanceRole
```

### 问题 4: 日志未传递到 Galaxy ✅ 已解决

**现象**: Galaxy UI 中看不到工具输出日志

**原因**:
```python
# galaxy_job_runner.py:359 (旧代码)
job_wrapper.finish("", "")  # 空字符串
```

**解决方案**:
```python
# galaxy_job_runner.py:360 (已修复)
job_wrapper.finish(result.stdout or "", result.stderr or "")
```

**日志流程**:
```
工具执行 → 容器 stdout/stderr
    ↓
CloudWatch Logs (自动捕获)
    ↓
AWSBatchExecutor._get_job_logs() (检索)
    ↓
JobResult.stdout / JobResult.stderr (存储)
    ↓
GalaxyCloudJobRunner (传递)
    ↓
job_wrapper.finish() (提交)
    ↓
Galaxy UI (显示)
```

---

## 四、生产环境部署步骤

### 前提条件

1. ✅ AWS 账户，有足够的权限
2. ✅ Galaxy 实例已安装并运行
3. ✅ 基本的 AWS 知识（IAM, VPC, EC2 等）

### 步骤 1: 安装依赖

```bash
# 在 Galaxy 服务器上
cd /path/to/galaxy

# 安装 galaxy-cloud-executor 依赖
pip install boto3 pydantic tenacity pyyaml aiofiles httpx structlog
```

### 步骤 2: 配置 AWS 凭证

选择以下方法之一：

#### 方法 A: 环境变量（推荐用于开发）
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

#### 方法 B: AWS CLI 配置（推荐用于生产）
```bash
aws configure
# 输入: Access Key, Secret Key, Region, Output format
```

#### 方法 C: IAM Instance Role（最安全，推荐）
- 为 Galaxy 服务器的 EC2 实例附加 IAM Role
- Role 需要包含 AWS Batch 操作权限

**推荐的 IAM 策略**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "batch:SubmitJob",
        "batch:DescribeJobs",
        "batch:TerminateJob",
        "batch:DescribeJobQueues",
        "batch:DescribeComputeEnvironments"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/batch/job:*"
    }
  ]
}
```

### 步骤 3: 创建 AWS Batch 基础设施

使用修复后的创建脚本：

```bash
cd lib/galaxy/galaxy-cloud-executor

# 运行创建脚本
bash scripts/create_aws_batch.sh

# 记录输出的配置信息
# - Job Queue 名称
# - S3 Bucket 名称
# - 区域
```

**重要**: 创建完成后，立即运行修复脚本：

```bash
# 修复 Launch Template IAM Profile 问题
bash scripts/fix_launch_template.sh
```

### 步骤 4: 配置 Galaxy

#### 4.1 复制并配置云配置文件

```bash
cd /path/to/galaxy

# 复制模板
cp lib/galaxy/galaxy-cloud-executor/config/aws_cloud_config.yaml \
   config/aws_cloud_config.yaml

# 编辑配置
vi config/aws_cloud_config.yaml
```

**修改以下内容**:
```yaml
cloud_providers:
  aws:
    enabled: true
    region: "us-west-2"  # 你的区域
    batch_queue: "galaxy-cloud-queue"  # 步骤 3 创建的队列名称
    s3_bucket: "galaxy-cloud-data-XXXXXXXXXX"  # 步骤 3 创建的桶名称

    # 认证方式（三选一）
    # 方法 1: 使用环境变量（不需要配置）

    # 方法 2: 显式配置（不推荐，有安全风险）
    # access_key_id: "YOUR_ACCESS_KEY"
    # secret_access_key: "YOUR_SECRET_KEY"

    # 方法 3: 使用 AWS Profile
    # aws_profile: "default"
```

#### 4.2 配置 Galaxy job_conf.xml

```bash
cd /path/to/galaxy/config

# 如果没有 job_conf.xml，从模板复制
cp job_conf.xml.sample job_conf.xml

# 编辑 job_conf.xml
vi job_conf.xml
```

**添加以下配置**:

```xml
<?xml version="1.0"?>
<job_conf>
    <plugins>
        <!-- 现有的插件 -->
        <plugin id="local" type="runner" load="galaxy.jobs.runners.local:LocalJobRunner" workers="4"/>

        <!-- 添加云执行插件 -->
        <plugin id="galaxy_cloud" type="runner"
                load="galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner"
                workers="16">
            <param id="cloud_config_file">config/aws_cloud_config.yaml</param>
            <param id="default_provider">aws</param>
        </plugin>
    </plugins>

    <destinations default="local">
        <!-- 现有的目标 -->
        <destination id="local" runner="local"/>

        <!-- 云执行目标：默认配置 -->
        <destination id="cloud_default" runner="galaxy_cloud">
            <param id="provider">aws</param>
            <param id="queue_name">galaxy-cloud-queue</param>
        </destination>

        <!-- 云执行目标：小型任务 -->
        <destination id="cloud_small" runner="galaxy_cloud">
            <param id="provider">aws</param>
            <param id="queue_name">galaxy-cloud-queue</param>
            <param id="vcpus">1</param>
            <param id="memory_mb">2048</param>
        </destination>

        <!-- 云执行目标：大型任务 -->
        <destination id="cloud_large" runner="galaxy_cloud">
            <param id="provider">aws</param>
            <param id="queue_name">galaxy-cloud-queue</param>
            <param id="vcpus">8</param>
            <param id="memory_mb">16384</param>
        </destination>
    </destinations>

    <tools>
        <!-- 配置特定工具使用云执行 -->

        <!-- 示例：小型工具 -->
        <tool id="fastqc" destination="cloud_small"/>
        <tool id="samtools_flagstat" destination="cloud_small"/>

        <!-- 示例：中型工具 -->
        <tool id="bwa" destination="cloud_default"/>
        <tool id="bowtie2" destination="cloud_default"/>

        <!-- 示例：大型工具 -->
        <tool id="gatk_haplotypecaller" destination="cloud_large"/>
        <tool id="deepvariant" destination="cloud_large"/>

        <!-- 其他工具使用本地执行 -->
    </tools>
</job_conf>
```

#### 4.3 重启 Galaxy

```bash
cd /path/to/galaxy

# 停止 Galaxy
sh run.sh --stop

# 启动 Galaxy
sh run.sh --daemon

# 检查日志
tail -f galaxy.log
```

**验证 Galaxy 启动成功**:
```bash
# 应该看到类似日志:
# galaxy.jobs DEBUG: Loading job runner plugin: galaxy_cloud
# galaxy.jobs.runners.galaxy_cloud INFO: Initialized GalaxyCloudJobRunner
```

### 步骤 5: 测试云执行

#### 5.1 命令行测试

```bash
cd lib/galaxy/galaxy-cloud-executor

export AWS_DEFAULT_REGION="us-west-2"
export AWS_BATCH_QUEUE="galaxy-cloud-queue"
export AWS_S3_BUCKET="your-bucket-name"

# 运行测试
python3 testing/test_workflow_simple.py
```

**预期结果**:
- ✅ 自动检测 minvCpus 配置
- ✅ 作业从 RUNNABLE → STARTING → RUNNING
- ✅ 首次需要 5-10 分钟（冷启动）
- ✅ 后续作业 < 1 分钟（实例已预热）
- ✅ 两步工作流成功完成

#### 5.2 Galaxy UI 测试

1. **登录 Galaxy**
   ```
   http://your-galaxy-server:8080
   ```

2. **上传测试数据**
   - 点击 "Upload Data"
   - 上传一个小的 FASTQ 文件（用于测试）

3. **运行工具**
   - 选择配置为云执行的工具（如 FastQC）
   - 输入测试数据
   - 点击 "Execute"

4. **监控执行**
   - 工具应该显示 "running" 状态
   - 首次可能需要等待 5-10 分钟（冷启动）
   - 后续执行应该很快

5. **检查结果**
   - 工具完成后，查看输出文件
   - 点击 "View Details" → 查看日志
   - 应该能看到工具的 stdout/stderr 输出

#### 5.3 监控 AWS 资源

```bash
# 检查 ECS 集群
aws ecs list-container-instances \
  --cluster <your-ecs-cluster> \
  --region us-west-2

# 检查运行中的作业
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status RUNNING \
  --region us-west-2

# 查看 CloudWatch 日志
aws logs tail /aws/batch/job --follow --region us-west-2
```

---

## 五、正常运行流程（用户视角）

### 场景：用户提交一个 Workflow

#### 第 1 步：用户操作
```
用户在 Galaxy UI 中:
1. 选择 Workflow
2. 配置输入数据
3. 点击 "Run Workflow"
```

#### 第 2 步：Galaxy 处理
```
Galaxy Core:
1. 解析 Workflow DAG
2. 根据 job_conf.xml 路由任务
3. 调用 GalaxyCloudJobRunner
```

#### 第 3 步：任务提交（自动）
```
GalaxyCloudJobRunner:
1. 读取 cloud_config.yaml
2. 构建 JobSpec (容器、命令、资源)
3. 上传输入数据到 S3
4. 调用 AWSBatchExecutor.submit_job()

AWSBatchExecutor:
1. 调用 AWS Batch API
2. 提交作业到 Job Queue
3. 返回 cloud_job_id

作业状态: SUBMITTED
```

#### 第 4 步：资源分配（自动，首次 5-10 分钟）
```
AWS Batch:
1. 作业进入 PENDING 状态
2. 计算所需资源 (vCPUs)
3. 检查 Compute Environment 当前容量

如果容量不足:
4. 更新 Auto Scaling Group DesiredCapacity
5. ASG 从 Launch Template 启动 EC2 实例

作业状态: PENDING → RUNNABLE
```

#### 第 5 步：实例启动（自动，2-3 分钟）
```
EC2 实例:
1. 使用 AMI 启动 (amzn2-ami-ecs-hvm...)
2. 应用 User Data 脚本
3. 配置 ECS_CLUSTER 环境变量
4. 启动 ECS Agent
5. ECS Agent 使用 IAM Instance Profile 认证
6. 注册到 ECS 集群

作业状态: RUNNABLE (等待实例就绪)
```

#### 第 6 步：任务调度（自动，10-30 秒）
```
ECS Scheduler:
1. 检测到新的可用实例
2. 将作业调度到实例
3. 通知实例拉取容器

作业状态: RUNNABLE → STARTING
```

#### 第 7 步：容器启动（自动，30-60 秒）
```
Docker on EC2:
1. 拉取容器镜像 (如 biocontainers/fastqc)
2. 创建容器
3. 挂载 S3 数据（通过 fuse 或预下载）
4. 启动容器

作业状态: STARTING → RUNNING
```

#### 第 8 步：工具执行（时间取决于工具和数据）
```
Container:
1. 执行生物信息学工具 (如 fastqc input.fastq)
2. stdout/stderr → CloudWatch Logs
3. 输出文件写入本地 /tmp
4. 完成后上传输出到 S3

作业状态: RUNNING
```

#### 第 9 步：任务完成（自动）
```
Container exit:
1. 容器退出码 0 (成功)
2. AWS Batch 标记作业为 SUCCEEDED
3. CloudWatch 保留完整日志

作业状态: RUNNING → SUCCEEDED
```

#### 第 10 步：结果返回（自动，几秒）
```
GalaxyCloudJobRunner (轮询):
1. 检测到作业 SUCCEEDED
2. 调用 executor.get_job_result()
3. 获取 CloudWatch 日志
4. 下载 S3 输出文件
5. 调用 job_wrapper.finish(stdout, stderr)

Galaxy Core:
1. 更新作业状态为 "完成"
2. 保存输出文件到 Galaxy 数据库
3. 保存日志
```

#### 第 11 步：用户查看结果
```
Galaxy UI:
1. 作业显示绿色 "完成" 状态
2. 用户点击输出数据集 → 查看内容
3. 用户点击 "View Details" → 查看日志
4. 日志显示完整的 stdout/stderr
```

#### 第 12 步：自动缩容（10 分钟后，自动）
```
如果没有新作业:
1. 10 分钟后，Auto Scaling Group 开始缩容
2. 终止空闲的 EC2 实例
3. 最终缩容到 minvCpus (通常是 0)
4. 成本归零

下次有作业时，重复第 4-8 步
```

### 时间线总结

**首次作业（冷启动）**:
```
时间轴:
T+0s    : 用户提交作业
T+1s    : 作业进入 AWS Batch (SUBMITTED)
T+5s    : 作业排队 (PENDING)
T+10s   : 触发扩容 (RUNNABLE)
T+30s   : EC2 实例请求
T+2m    : 实例启动完成
T+3m    : ECS Agent 注册
T+4m    : 任务调度 (STARTING)
T+5m    : 容器启动，拉取镜像
T+6m    : 工具开始执行 (RUNNING)
T+10m   : 工具完成 (取决于数据大小)
T+10m5s : 结果返回 Galaxy
T+10m10s: 用户看到结果

总时间: ~10 分钟 (其中 6 分钟冷启动，4 分钟实际执行)
```

**后续作业（实例已预热）**:
```
时间轴:
T+0s    : 用户提交作业
T+1s    : 作业进入 AWS Batch (SUBMITTED)
T+5s    : 作业排队 (PENDING → RUNNABLE)
T+10s   : 任务调度 (STARTING, 实例已存在)
T+30s   : 容器启动 (镜像已缓存)
T+1m    : 工具开始执行 (RUNNING)
T+5m    : 工具完成
T+5m5s  : 结果返回 Galaxy
T+5m10s : 用户看到结果

总时间: ~5 分钟 (几乎全是实际执行时间)
```

---

## 六、运维和监控

### 日常监控

#### 1. 检查 Job Queue 健康状态
```bash
aws batch describe-job-queues \
  --job-queues galaxy-cloud-queue \
  --region us-west-2 \
  --query 'jobQueues[0].[state,status]'
```

**期望输出**: `["ENABLED", "VALID"]`

#### 2. 检查 Compute Environment
```bash
aws batch describe-compute-environments \
  --region us-west-2 \
  --query 'computeEnvironments[0].[computeEnvironmentName,state,status,computeResources.desiredvCpus]'
```

**期望输出**: `["galaxy-cloud-compute", "ENABLED", "VALID", 0]`

#### 3. 检查运行中的作业
```bash
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --region us-west-2 \
  --job-status RUNNING
```

#### 4. 检查失败的作业
```bash
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --region us-west-2 \
  --job-status FAILED \
  --max-items 10
```

#### 5. 查看 CloudWatch 日志
```bash
# 实时查看日志
aws logs tail /aws/batch/job --follow --region us-west-2

# 查看特定作业的日志
aws logs tail /aws/batch/job \
  --log-stream-name <log-stream-name> \
  --region us-west-2
```

#### 6. 监控成本
```bash
# 使用 AWS Cost Explorer
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE \
  --filter file://batch-filter.json
```

### CloudWatch 告警

建议设置以下告警：

#### 告警 1: 作业失败率高
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name galaxy-batch-high-failure-rate \
  --alarm-description "Alert when job failure rate > 10%" \
  --metric-name FailedJobsCount \
  --namespace AWS/Batch \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

#### 告警 2: 作业等待时间长
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name galaxy-batch-long-wait-time \
  --alarm-description "Alert when jobs stuck in RUNNABLE > 15 min" \
  --metric-name RunnableJobsCount \
  --namespace AWS/Batch \
  --statistic Average \
  --period 900 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold
```

#### 告警 3: 成本超过预算
```bash
# 在 AWS Budgets 中设置成本预算
# 当实际成本超过预算 80% 时发送通知
```

### 常见运维任务

#### 任务 1: 更新实例类型
```bash
CE_NAME="galaxy-cloud-compute"

aws batch update-compute-environment \
  --compute-environment "$CE_NAME" \
  --compute-resources type=EC2,instanceTypes=optimal \
  --region us-west-2
```

#### 任务 2: 调整最大容量
```bash
aws batch update-compute-environment \
  --compute-environment "$CE_NAME" \
  --compute-resources maxvCpus=512 \
  --region us-west-2
```

#### 任务 3: 清理失败的作业
```bash
# 列出失败的作业
FAILED_JOBS=$(aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status FAILED \
  --region us-west-2 \
  --query 'jobSummaryList[].jobId' \
  --output text)

# 终止（清理记录）
for JOB_ID in $FAILED_JOBS; do
  aws batch terminate-job \
    --job-id "$JOB_ID" \
    --reason "Manual cleanup" \
    --region us-west-2
done
```

#### 任务 4: 强制重启 Compute Environment
```bash
# 禁用
aws batch update-compute-environment \
  --compute-environment "$CE_NAME" \
  --state DISABLED \
  --region us-west-2

sleep 30

# 启用
aws batch update-compute-environment \
  --compute-environment "$CE_NAME" \
  --state ENABLED \
  --region us-west-2
```

---

## 七、故障排查

### 常见问题

#### 问题 1: 作业一直卡在 RUNNABLE

**诊断**:
```bash
bash scripts/diagnose_batch.sh
```

**可能原因**:
1. Launch Template IAM Profile 未设置 → 运行 `fix_launch_template.sh`
2. 实例类型与可用区不兼容 → 更新为 `optimal`
3. 子网 IP 耗尽 → 添加更多子网
4. 达到 EC2 限额 → 申请提额

#### 问题 2: 实例启动后立即终止

**诊断**:
```bash
bash scripts/check_instance_logs.sh <instance-id>
```

**可能原因**:
1. IAM Instance Profile 未设置
2. ECS Agent 无法启动
3. 网络配置问题

#### 问题 3: 日志在 Galaxy 中看不到

**检查**:
1. 确认 `galaxy_job_runner.py:360` 已修复
2. 检查 CloudWatch Logs 是否有日志
3. 检查 IAM 权限（logs:GetLogEvents）

#### 问题 4: 成本意外增加

**检查**:
1. 是否有实例未正确缩容
2. 检查 `desiredvCpus` 是否异常
3. 查看 AWS Cost Explorer

### 紧急操作

#### 紧急情况 1: 成本失控

**立即停止所有作业**:
```bash
# 1. 禁用 Job Queue
aws batch update-job-queue \
  --job-queue galaxy-cloud-queue \
  --state DISABLED \
  --region us-west-2

# 2. 终止所有运行中的作业
RUNNING_JOBS=$(aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status RUNNING \
  --region us-west-2 \
  --query 'jobSummaryList[].jobId' \
  --output text)

for JOB_ID in $RUNNING_JOBS; do
  aws batch terminate-job \
    --job-id "$JOB_ID" \
    --reason "Emergency stop" \
    --region us-west-2
done

# 3. 强制缩容到 0
aws batch update-compute-environment \
  --compute-environment galaxy-cloud-compute \
  --compute-resources minvCpus=0,desiredvCpus=0 \
  --region us-west-2
```

#### 紧急情况 2: Galaxy 无法连接 AWS

**回退到本地执行**:
```xml
<!-- 临时修改 job_conf.xml -->
<destinations default="local">
  <!-- 注释掉云执行 -->
  <!-- <destination id="cloud_default" runner="galaxy_cloud"/> -->
</destinations>

<tools>
  <!-- 移除所有工具的云执行配置 -->
  <!-- <tool id="fastqc" destination="cloud_small"/> -->
</tools>
```

---

## 八、性能优化

### 优化 1: 使用优化的 AMI

创建包含预装容器镜像的自定义 AMI，减少冷启动时间 60-70%。

**步骤**:
1. 启动一个 ECS-optimized AMI 实例
2. 预拉取常用容器镜像
```bash
docker pull biocontainers/fastqc:latest
docker pull biocontainers/bwa:latest
docker pull biocontainers/samtools:latest
```
3. 创建 AMI
4. 更新 Launch Template 使用新 AMI

### 优化 2: 分层 Job Queue

为不同规模的工具创建不同的队列。

```yaml
# 快速队列 (Fargate)
fastqc, flagstat → Fargate (1-2 分钟启动)

# 标准队列 (EC2 minvCpus=2)
bwa, bowtie → EC2 hot (30 秒启动)

# 批量队列 (EC2 minvCpus=0)
variant calling → EC2 cold (5-10 分钟启动，但成本最优)
```

### 优化 3: 使用 Spot 实例

```bash
aws batch update-compute-environment \
  --compute-environment galaxy-cloud-compute \
  --compute-resources type=SPOT,allocationStrategy=SPOT_CAPACITY_OPTIMIZED \
  --region us-west-2
```

**成本节省**: 60-90%

**注意**: Spot 实例可能被中断，适合可重试的任务

---

## 九、安全最佳实践

### 1. IAM 权限最小化

不要使用 `*` 权限，明确指定资源 ARN。

### 2. 加密 S3 数据

```bash
aws s3api put-bucket-encryption \
  --bucket galaxy-cloud-data-xxx \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 3. 使用 VPC Endpoints

避免数据通过公网传输。

```bash
# 创建 S3 VPC Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-west-2.s3 \
  --route-table-ids rtb-xxxxx
```

### 4. 启用 CloudTrail

记录所有 API 调用，用于审计。

---

## 十、成本估算

### 典型场景成本

**场景 A: 小团队（5-10 人，每天 10-20 个 workflow）**
- 配置: minvCpus=0, maxvCpus=64, Spot 实例
- 平均运行时间: 每天 4 小时
- 实例类型: m5.large (2 vCPU)
- **月成本**: $20-40

**场景 B: 中团队（10-50 人，每天 50-100 个 workflow）**
- 配置: minvCpus=2, maxvCpus=256, Spot 实例
- 平均运行时间: 每天 8 小时
- 实例类型: m5.xlarge (4 vCPU)
- **月成本**: $100-200

**场景 C: 大团队（50+ 人，持续运行）**
- 配置: minvCpus=16, maxvCpus=512, 混合 Spot/On-Demand
- 平均运行时间: 24/7
- 实例类型: m5.2xlarge (8 vCPU)
- **月成本**: $500-1500

**其他成本**:
- S3 存储: $0.023/GB/月
- CloudWatch Logs: $0.50/GB (ingestion)
- 数据传输: 前 100GB 免费

---

## 十一、总结

### 核心优势

✅ **自动资源管理**: 无需手动启动/停止实例
✅ **成本优化**: 按需计费，空闲时零成本
✅ **弹性扩展**: 自动适应负载高峰
✅ **完全集成**: Galaxy 用户无感知，体验一致
✅ **日志完整**: CloudWatch 日志自动捕获和传递

### 适用场景

✅ 批量生物信息学分析
✅ 间歇性工作负载
✅ 多用户共享集群
✅ 需要大规模计算资源
✅ 成本敏感的项目

### 不适用场景

❌ 实时交互式分析（延迟敏感）
❌ 小规模持续运行（本地更便宜）
❌ 需要 GPU 加速（需要额外配置）

### 关键配置总结

```yaml
# 最佳生产配置
compute_environment:
  minvCpus: 0              # 空闲时零成本
  maxvCpus: 256            # 根据需求调整
  instanceTypes: optimal   # AWS 自动选择
  type: SPOT               # 成本节省 60-90%
  allocationStrategy: SPOT_CAPACITY_OPTIMIZED

launch_template:
  iamInstanceProfile: ecsInstanceRole  # 必须设置
  ami: ECS-optimized-AMI               # 使用最新版本
  instanceType: m5.large               # 或 optimal
```

---

## 附录

### A. 完整配置文件示例

见项目中的示例文件：
- `config/aws_cloud_config.yaml`
- `config/job_conf.xml.sample`
- `config/job_conf.yml.sample`

### B. 脚本索引

| 脚本 | 用途 |
|------|------|
| `scripts/create_aws_batch.sh` | 创建 AWS Batch 基础设施 |
| `scripts/fix_launch_template.sh` | 修复 Launch Template IAM 问题 |
| `scripts/diagnose_batch.sh` | 完整诊断 Batch 配置 |
| `scripts/check_asg_failure.sh` | 诊断 ASG 启动失败 |
| `scripts/check_ecs_instance.sh` | 检查 ECS 实例注册 |
| `scripts/check_instance_logs.sh` | 查看实例详细日志 |
| `scripts/recreate_compute_environment.sh` | 重建计算环境 |
| `scripts/fix_auto_scaling.sh` | 修复自动扩容问题 |

### C. 文档索引

| 文档 | 内容 |
|------|------|
| `AWS_SETUP_GUIDE.md` | AWS 完整设置指南 |
| `JOB_CONFIG_GUIDE.md` | Galaxy 作业配置详解 |
| `DYNAMIC_SCALING_OPTIMIZATION.md` | 动态扩容优化 |
| `TROUBLESHOOT_RUNNABLE_STUCK.md` | 作业卡住故障排查 |
| `LOG_FLOW_EXPLANATION.md` | 日志流程详解 |
| `ISSUE_RESOLVED_AZ_PROBLEM.md` | 可用区兼容性问题 |
| `PRODUCTION_DEPLOYMENT_GUIDE.md` | 本文档 |

### D. 支持资源

- **AWS Batch 文档**: https://docs.aws.amazon.com/batch/
- **ECS 文档**: https://docs.aws.amazon.com/ecs/
- **Galaxy 文档**: https://docs.galaxyproject.org/
- **问题反馈**: 项目 GitHub Issues

---

**版本**: 1.0
**最后更新**: 2025-10-12
**作者**: Claude Code
**状态**: 生产就绪 ✅
