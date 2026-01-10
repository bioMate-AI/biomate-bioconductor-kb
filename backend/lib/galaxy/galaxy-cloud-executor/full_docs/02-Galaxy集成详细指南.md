# Galaxy 集成详细指南

## 概述

本指南提供 Galaxy Cloud Executor 与 Galaxy 集成的详细步骤和说明。如果你需要快速集成，请参考 [01-快速开始指南.md](01-快速开始指南.md)。

---

## 前提条件

### 必须完成的工作

- ✅ AWS Batch 基础设施已创建 (Batch Queue, Compute Environment)
- ✅ S3 存储桶已创建并可访问
- ✅ BatchJobRole 已配置 S3 访问权限
- ✅ 2步 workflow 测试已通过

### 你的配置信息

```yaml
AWS Region: us-west-2
Account ID: 399683337364
Batch Queue: galaxy-cloud-queue
S3 Bucket: galaxy-cloud-data-1760241377
Job Role ARN: arn:aws:iam::399683337364:role/BatchJobRole
```

---

## 第一部分: 理解集成架构

### Galaxy 作业执行流程

```
用户在 Galaxy UI 提交作业
    ↓
Galaxy Job Manager (job_conf.yml)
    ↓
匹配工具 ID 到执行环境
    ↓
选择 Runner (local / galaxy_cloud / slurm 等)
    ↓
如果是 galaxy_cloud:
    ↓
GalaxyCloudJobRunner 初始化
    ↓
读取 aws_cloud_config.yaml
    ↓
准备作业 (输入数据 → S3)
    ↓
提交到 AWS Batch Job Queue
    ↓
监控作业状态
    ↓
获取结果 (S3 → Galaxy) 和日志 (CloudWatch → Galaxy)
    ↓
更新 Galaxy 数据库
    ↓
Galaxy UI 显示结果和日志
```

### 关键组件

1. **job_conf.yml** - Galaxy 作业配置
   - 定义可用的 runners
   - 定义执行环境 (destinations)
   - 映射工具到环境

2. **aws_cloud_config.yaml** - AWS 云配置
   - AWS 连接信息
   - Batch 队列和 S3 存储桶
   - IAM 角色 ARN

3. **GalaxyCloudJobRunner** - Python 模块
   - 实现 Galaxy JobRunner 接口
   - 处理作业提交、监控、日志获取

4. **PYTHONPATH** - Python 模块路径
   - 让 Galaxy 能导入 galaxy_cloud 模块

---

## 第二部分: 配置文件准备

### 步骤 1: 准备 aws_cloud_config.yaml

#### 1.1 复制模板

```bash
cd /Users/renyuankai/work/biometa/galaxy
cp lib/galaxy/galaxy-cloud-executor/config/aws_cloud_config.yaml config/
```

#### 1.2 编辑配置

打开 `config/aws_cloud_config.yaml`:

```yaml
# ============================================================
# Galaxy Cloud Executor - AWS 云配置
# ============================================================

cloud_providers:
  aws:
    # ========== 基础配置 (必须) ==========
    enabled: true
    region: "us-west-2"                              # ✅ 你的 region
    batch_queue: "galaxy-cloud-queue"                # ✅ 你的队列名称
    s3_bucket: "galaxy-cloud-data-1760241377"        # ✅ 你的 S3 存储桶

    # ========== IAM 角色 (必须!) ==========
    job_role_arn: "arn:aws:iam::399683337364:role/BatchJobRole"  # ✅ 你的 Job Role ARN
    # 重要: 这是容器访问 S3 的关键配置!

    # ========== Spot 实例 (可选) ==========
    use_spot: false  # 设置为 true 可节省 60-90% 成本
    spot_bid_percentage: 100

    # ========== 日志配置 ==========
    log_retention_days: 7  # CloudWatch Logs 保留天数

    # ========== 作业配置 ==========
    job_timeout_seconds: 172800  # 48小时超时
    max_retries: 2

    # ========== 数据传输配置 ==========
    s3_multipart_threshold_mb: 100
    s3_multipart_chunksize_mb: 50
```

#### 1.3 验证配置

```bash
# 检查文件存在
ls -l config/aws_cloud_config.yaml

# 检查 YAML 语法
python3 -c "import yaml; yaml.safe_load(open('config/aws_cloud_config.yaml'))"

# 检查关键配置
grep -E "batch_queue|s3_bucket|job_role_arn" config/aws_cloud_config.yaml
```

---

### 步骤 2: 配置 job_conf.yml

#### 2.1 备份原配置

```bash
cd /Users/renyuankai/work/biometa/galaxy
cp config/job_conf.yml config/job_conf.yml.backup.$(date +%Y%m%d_%H%M%S)
```

#### 2.2 理解 job_conf.yml 结构

```yaml
# job_conf.yml 的基本结构
runners:          # 定义可用的 job runners
  local: ...
  galaxy_cloud: ...  # 我们要添加这个

execution:
  default: local   # 默认使用哪个 runner

  environments:    # 定义执行环境 (destinations)
    local: ...
    cloud_small: ...   # 我们要添加这些
    cloud_medium: ...
    cloud_large: ...

tools:            # 工具映射规则
  - id: ...       # 特定工具 ID
    environment: ...  # 使用哪个环境
  - class: ...    # 工具类别
    environment: ...

limits:           # 资源限制
  - type: ...
    value: ...
```

#### 2.3 添加 galaxy_cloud Runner

打开 `config/job_conf.yml`，在 `runners:` 部分添加:

```yaml
runners:
  # ... 保留现有的配置 ...

  # 添加云执行 runner
  galaxy_cloud:
    load: galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner
    workers: 16  # 并发作业处理线程数
    cloud_config_file: config/aws_cloud_config.yaml
    default_provider: aws
```

**配置说明**:
- `load`: Python 模块路径 (galaxy_cloud 模块必须在 PYTHONPATH 中)
- `workers`: 同时处理的作业数 (建议 8-32)
- `cloud_config_file`: AWS 配置文件路径 (相对于 Galaxy 根目录)
- `default_provider`: 默认云提供商 (当前只支持 aws)

#### 2.4 添加云执行环境

在 `execution.environments:` 部分添加:

```yaml
execution:
  default: local  # 保持默认为本地执行

  environments:
    # ... 保留现有的配置 ...

    # ========== 云执行环境 ==========

    # 云执行 - 小型任务
    cloud_small:
      runner: galaxy_cloud           # 使用 galaxy_cloud runner
      provider: aws                  # 云提供商
      queue_name: galaxy-cloud-queue # ✅ 你的队列名称
      vcpus: 1                       # CPU 核心数
      memory_mb: 2048                # 内存 (MB)
      disk_gb: 20                    # 磁盘空间 (GB)
      embed_metadata_in_job: false   # 在本地计算元数据

    # 云执行 - 中型任务
    cloud_medium:
      runner: galaxy_cloud
      provider: aws
      queue_name: galaxy-cloud-queue
      vcpus: 4
      memory_mb: 8192
      disk_gb: 100

    # 云执行 - 大型任务
    cloud_large:
      runner: galaxy_cloud
      provider: aws
      queue_name: galaxy-cloud-queue
      vcpus: 8
      memory_mb: 16384
      disk_gb: 200

    # 云执行 - 超大型任务
    cloud_xlarge:
      runner: galaxy_cloud
      provider: aws
      queue_name: galaxy-cloud-queue
      vcpus: 16
      memory_mb: 32768
      disk_gb: 500
```

**资源配置建议**:
- **cloud_small** (1 vCPU, 2GB): FastQC, SAMtools, Cutadapt
- **cloud_medium** (4 vCPU, 8GB): BWA, Bowtie2, HISAT2
- **cloud_large** (8 vCPU, 16GB): GATK, DeepVariant
- **cloud_xlarge** (16 vCPU, 32GB): SPAdes, Trinity (组装)

#### 2.5 添加工具映射

在 `tools:` 部分添加:

```yaml
tools:
  # ... 保留现有的配置 ...

  # ========== 云执行工具映射 ==========

  # 质量控制 - 小型
  - id: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0
    environment: cloud_small

  - id: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0
    environment: cloud_small

  # 序列处理 - 小型
  - id: toolshed.g2.bx.psu.edu/repos/lparsons/cutadapt/cutadapt/4.4+galaxy0
    environment: cloud_small

  # SAM/BAM 工具 - 小型
  - id: toolshed.g2.bx.psu.edu/repos/devteam/samtools_flagstat/samtools_flagstat/2.0.5
    environment: cloud_small

  - id: toolshed.g2.bx.psu.edu/repos/devteam/samtools_stats/samtools_stats/2.0.5
    environment: cloud_small

  # 比对工具 - 中型
  - id: toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2
    environment: cloud_medium

  - id: toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/bowtie2/2.5.0+galaxy0
    environment: cloud_medium

  # 变异检测 - 大型
  - id: toolshed.g2.bx.psu.edu/repos/iuc/gatk4_haplotypecaller/gatk4_haplotypecaller/4.4.0.0
    environment: cloud_large

  # 组装工具 - 超大型
  - id: toolshed.g2.bx.psu.edu/repos/nml/spades/spades/3.15.5+galaxy2
    environment: cloud_xlarge

  # 默认规则 - 系统工具保持本地
  - class: local
    environment: local

  - class: requires_galaxy
    environment: local

  # 上传工具保持本地
  - id: upload1
    environment: local

  - id: __DATA_FETCH__
    environment: local
```

**工具 ID 查找方法**:
```bash
# 在 Galaxy UI 中运行工具后，查看作业详情
# 或在数据库中查询
sqlite3 database/universe.sqlite "SELECT tool_id FROM job LIMIT 10;"
```

#### 2.6 (可选) 添加资源限制

在 `limits:` 部分添加:

```yaml
limits:
  # ... 保留现有的配置 ...

  # 用户并发限制
  - type: environment_user_concurrent_jobs
    id: cloud_small
    value: 20

  - type: environment_user_concurrent_jobs
    id: cloud_medium
    value: 10

  - type: environment_user_concurrent_jobs
    id: cloud_large
    value: 5

  # 全局并发限制
  - type: environment_total_concurrent_jobs
    id: cloud_small
    value: 100

  # 作业时间限制
  - type: walltime
    value: '48:00:00'
```

#### 2.7 验证配置

```bash
# 检查 YAML 语法
python3 -c "import yaml; yaml.safe_load(open('config/job_conf.yml'))"

# 检查是否包含 galaxy_cloud
grep -q "galaxy_cloud:" config/job_conf.yml && echo "✅ Cloud runner configured"

# 检查是否有云环境
grep -q "cloud_small:" config/job_conf.yml && echo "✅ Cloud environments configured"

# 统计配置的云工具数量
grep -c "environment: cloud" config/job_conf.yml
```

---

### 步骤 3: 设置 PYTHONPATH

#### 3.1 理解 PYTHONPATH 的作用

Galaxy 需要能导入 `galaxy_cloud` 模块:

```python
# Galaxy 内部会执行类似这样的代码
from galaxy_cloud.galaxy_workflow.galaxy_job_runner import GalaxyCloudJobRunner
```

如果 `galaxy_cloud` 不在 Python 路径中，会报错:
```
ModuleNotFoundError: No module named 'galaxy_cloud'
```

#### 3.2 方法 1: 修改 run.sh (推荐)

编辑 `/Users/renyuankai/work/biometa/galaxy/run.sh`:

```bash
#!/bin/bash

# ============================================================
# Galaxy Cloud Executor - Python 路径配置
# ============================================================

# 添加 galaxy-cloud-executor 模块到 Python 路径
export PYTHONPATH="$PYTHONPATH:lib/galaxy/galaxy-cloud-executor"

# 验证模块可导入 (可选，调试用)
# python3 -c "import galaxy_cloud; print('✅ galaxy_cloud module loaded')" || echo "❌ Failed to load galaxy_cloud"

# ... 原有的 run.sh 内容 ...
```

#### 3.2 方法 2: 创建 .venv/bin/activate 扩展 (如果使用虚拟环境)

如果 Galaxy 使用 Python 虚拟环境:

```bash
# 编辑虚拟环境的 activate 脚本
vim .venv/bin/activate

# 在文件末尾添加
export PYTHONPATH="$PYTHONPATH:$VIRTUAL_ENV/../lib/galaxy/galaxy-cloud-executor"
```

#### 3.3 方法 3: systemd 服务配置 (如果使用 systemd)

如果 Galaxy 作为 systemd 服务运行，编辑服务文件:

```ini
[Service]
Environment="PYTHONPATH=/path/to/galaxy/lib/galaxy/galaxy-cloud-executor:$PYTHONPATH"
```

#### 3.4 验证 PYTHONPATH

```bash
# 测试模块导入
cd /Users/renyuankai/work/biometa/galaxy
export PYTHONPATH="$PYTHONPATH:lib/galaxy/galaxy-cloud-executor"
python3 -c "import galaxy_cloud; print('✅ Module import successful')"

# 测试特定类导入
python3 -c "from galaxy_cloud.galaxy_workflow.galaxy_job_runner import GalaxyCloudJobRunner; print('✅ GalaxyCloudJobRunner import successful')"
```

---

## 第三部分: 集成验证

### 步骤 4: 运行集成检查脚本

```bash
cd /Users/renyuankai/work/biometa/galaxy
bash lib/galaxy/galaxy-cloud-executor/scripts/check_integration_ready.sh
```

这个脚本会检查:

1. **AWS 基础设施** (5项)
   - ✅ AWS 凭证有效
   - ✅ Batch 队列存在且启用
   - ✅ S3 存储桶可访问
   - ✅ BatchJobRole 存在
   - ✅ BatchJobRole 有 S3 权限

2. **Galaxy 配置文件** (6项)
   - ✅ job_conf.yml 存在
   - ✅ job_conf.yml 包含 galaxy_cloud runner
   - ✅ job_conf.yml 包含云环境
   - ✅ job_conf.yml YAML 语法正确
   - ✅ aws_cloud_config.yaml 存在
   - ✅ aws_cloud_config.yaml 包含 job_role_arn

3. **Python 模块** (3项)
   - ✅ galaxy_cloud 模块可导入
   - ✅ boto3 已安装
   - ✅ PyYAML 已安装

**期望输出**:
```
====================================================================
  Galaxy Cloud Executor 集成就绪检查
====================================================================

✅ 通过: 14
❌ 失败: 0
⚠️  警告: 2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 集成就绪! 可以开始使用 Galaxy Cloud Executor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 第四部分: 启动 Galaxy

### 步骤 5: 重启 Galaxy

#### 5.1 停止 Galaxy

```bash
cd /Users/renyuankai/work/biometa/galaxy

# 方法 1: 使用 run.sh
sh run.sh --stop

# 方法 2: 如果上面不工作，手动终止
pkill -f "python.*galaxy"

# 验证已停止
ps aux | grep galaxy
```

#### 5.2 启动 Galaxy

```bash
# 前台运行 (可以看到启动日志)
sh run.sh

# 或后台运行
sh run.sh --daemon
```

#### 5.3 监控启动日志

```bash
# 实时查看所有日志
tail -f galaxy.log

# 只查看云执行相关日志
tail -f galaxy.log | grep -i cloud

# 查看错误
tail -f galaxy.log | grep -i error
```

#### 5.4 期望看到的日志

```
galaxy.jobs.manager INFO Loading job runner plugin: galaxy_cloud
galaxy.jobs.runners.galaxy_cloud INFO GalaxyCloudJobRunner initialized
galaxy.jobs.runners.galaxy_cloud INFO Loading cloud config: config/aws_cloud_config.yaml
galaxy.jobs.runners.galaxy_cloud INFO AWS provider configured: region=us-west-2, queue=galaxy-cloud-queue
galaxy.jobs.runners.galaxy_cloud INFO Cloud executor ready with 16 workers
```

#### 5.5 常见启动错误

**错误 1: ModuleNotFoundError**
```
ModuleNotFoundError: No module named 'galaxy_cloud'
```
**解决**: 检查 PYTHONPATH 是否在 run.sh 中设置

**错误 2: FileNotFoundError**
```
FileNotFoundError: config/aws_cloud_config.yaml
```
**解决**: 确认 aws_cloud_config.yaml 在 config/ 目录

**错误 3: YAML 语法错误**
```
yaml.scanner.ScannerError: ...
```
**解决**: 检查 job_conf.yml 或 aws_cloud_config.yaml 的YAML语法

---

## 第五部分: 测试云执行

### 步骤 6: 在 Galaxy UI 中测试

#### 6.1 访问 Galaxy UI

打开浏览器: `http://localhost:8080` (或你的 Galaxy URL)

#### 6.2 上传测试数据

1. 点击左侧菜单 **"Upload Data"** 按钮
2. 选择一个小型 FASTQ 文件 (< 10MB)
3. 或使用 Galaxy 自带的测试数据
4. 点击 **"Start"** 上传

#### 6.3 运行 FastQC

1. 在左侧工具面板搜索 **"FastQC"**
2. 选择刚上传的 FASTQ 文件
3. 保持其他参数默认
4. 点击 **"Execute"**

#### 6.4 观察作业状态

在右侧历史面板，作业应该经历以下状态:

```
灰色 (new/queued)
  ↓ (几秒)
黄色 (running)  ← 表示在云端执行!
  ↓ (5-15分钟，包含冷启动)
绿色 (ok)  ← 成功完成!
```

**如果卡在灰色**:
- Galaxy 可能没有加载 galaxy_cloud runner
- 检查 galaxy.log 中的错误

**如果变成红色 (error)**:
- 点击作业查看错误信息
- 检查 galaxy.log 最后100行

#### 6.5 查看作业详情

点击作业的 **(i)** 信息按钮:

```
Job Information:
  Tool: FastQC
  Destination: cloud_small  ← 确认使用云环境
  Runner: galaxy_cloud      ← 确认使用云 runner

Job Metrics:
  Runtime: XX:XX:XX
  Memory: X.X GB

stdout:
  [FastQC 的输出日志]  ← 确认日志可见

stderr:
  [如果有错误]
```

---

## 第六部分: 验证 AWS 端

### 步骤 7: 检查 AWS Batch

#### 7.1 查看 AWS Batch 控制台

访问: https://console.aws.amazon.com/batch/

1. 点击左侧 **"Jobs"**
2. 选择队列: `galaxy-cloud-queue`
3. 应该能看到最近的作业

#### 7.2 查看作业详情

点击作业 ID，查看:

- **Status**: SUCCEEDED
- **Status history**:
  ```
  SUBMITTED → PENDING → RUNNABLE → STARTING → RUNNING → SUCCEEDED
  ```
- **Job definition**: Galaxy 创建的
- **vCPUs**: 1 (对应 cloud_small)
- **Memory**: 2048 MB

- **Log stream**: 点击 CloudWatch Logs 链接查看容器日志

#### 7.3 查看 CloudWatch Logs

1. 在作业详情页点击 **"View logs"**
2. 或访问: https://console.aws.amazon.com/cloudwatch/
3. 日志组: `/aws/batch/job`
4. 找到对应的日志流
5. 应该能看到 FastQC 的完整输出

#### 7.4 查看 S3 数据

```bash
# 查看作业数据
aws s3 ls s3://galaxy-cloud-data-1760241377/galaxy-jobs/ --recursive

# 应该看到类似这样的文件
# .../input/dataset_123.fastq
# .../output/dataset_123_result.html
```

---

## 故障排查

### 问题 1: Galaxy 启动失败

**症状**: `sh run.sh` 报错

**诊断**:
```bash
# 查看最后的错误
tail -50 galaxy.log

# 检查语法
python3 -c "import yaml; yaml.safe_load(open('config/job_conf.yml'))"
```

**常见原因**:
- YAML 语法错误
- 模块导入失败
- 配置文件路径错误

### 问题 2: 作业一直灰色

**症状**: 作业提交后一直停在灰色 (queued) 状态

**诊断**:
```bash
# 检查 Galaxy 是否加载了 galaxy_cloud runner
grep "Loading job runner plugin: galaxy_cloud" galaxy.log

# 检查是否有错误
grep -i "error.*galaxy_cloud" galaxy.log

# 检查作业队列
sqlite3 database/universe.sqlite "SELECT state, runner_name FROM job ORDER BY id DESC LIMIT 5;"
```

**常见原因**:
- galaxy_cloud runner 没有加载
- job_conf.yml 配置错误
- PYTHONPATH 未设置

### 问题 3: 作业立即失败 (红色)

**症状**: 作业变红，显示错误

**诊断**:
1. 在 Galaxy UI 点击作业查看错误信息
2. 查看 galaxy.log:
   ```bash
   tail -100 galaxy.log | grep -A 10 "ERROR"
   ```

**常见错误**:

**错误信息: InvalidClientTokenId**
```
botocore.exceptions.ClientError: An error occurred (InvalidClientTokenId)
```
**解决**: AWS 凭证无效，运行 `aws configure`

**错误信息: 403 Forbidden**
```
An error occurred (403) when calling the HeadObject operation: Forbidden
```
**解决**: job_role_arn 未配置或 BatchJobRole 缺少 S3 权限

**错误信息: ResourceNotFoundException**
```
An error occurred (ResourceNotFoundException) ... queue 'galaxy-cloud-queue' not found
```
**解决**: 队列名称错误或队列不存在

### 问题 4: 作业完成但没有结果

**症状**: 作业显示绿色但输出数据集为空

**诊断**:
```bash
# 检查 S3 数据
aws s3 ls s3://galaxy-cloud-data-1760241377/galaxy-jobs/ --recursive

# 查看 CloudWatch 日志
# 在 AWS Batch 控制台查看作业的日志流
```

**常见原因**:
- 工具执行失败但没有报错
- S3 数据下载失败
- 文件路径问题

### 问题 5: 日志为空

**症状**: Galaxy UI 中作业的 stdout/stderr 为空

**诊断**:
```bash
# 检查 galaxy_job_runner.py 是否已修复
grep -A 2 "job_wrapper.finish" lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py

# 应该看到:
# job_wrapper.finish(result.stdout or "", result.stderr or "")
# 而不是:
# job_wrapper.finish("", "")
```

**解决**: 确认代码已修复 (应该已经修复)

---

## 高级配置

### 配置更多工具

批量配置同一类型的工具:

```yaml
tools:
  # 使用通配符匹配所有版本
  - id: toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/*
    environment: cloud_small

  # 匹配所有 GATK4 工具
  - id: toolshed.g2.bx.psu.edu/repos/iuc/gatk4_*
    environment: cloud_large
```

### 动态资源分配

根据输入文件大小自动选择环境:

```yaml
tools:
  - id: toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.17.2
    environment: cloud_medium
    # 可以在工具的 XML 中配置 dynamic destination
```

### 启用 Spot 实例

修改 `config/aws_cloud_config.yaml`:

```yaml
cloud_providers:
  aws:
    use_spot: true
    spot_bid_percentage: 100
```

节省 60-90% 成本，但作业可能被中断。

---

## 下一步

### 生产环境优化

- 创建优化的 AMI (预装 Docker 和缓存容器)
- 配置 CloudWatch 告警
- 设置成本预算
- 配置自动清理 S3 临时数据

### 监控和管理

- 使用 AWS Cost Explorer 追踪成本
- 配置 CloudWatch Dashboard
- 定期审查作业失败率

### 扩展功能

- 配置多个 Batch 队列 (不同优先级)
- 启用 GPU 工具支持
- 配置多区域部署

---

## 相关文档

- [01-快速开始指南.md](01-快速开始指南.md) - 快速集成步骤
- [11-配置文件完整参考.md](11-配置文件完整参考.md) - 配置参考
- [07-常见问题排查.md](07-常见问题排查.md) - 问题排查
- [SUMMARY-已完成工作总结.md](SUMMARY-已完成工作总结.md) - 工作总结

---

**集成完成后，你就可以在 Galaxy UI 中享受自动云执行了! 🚀**
