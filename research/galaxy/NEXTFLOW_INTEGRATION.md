# Galaxy + Nextflow + AWS Batch 集成指南

## 概述

此集成方案使用 **Nextflow** 作为 Galaxy 和 AWS Batch 之间的桥梁，完全解决了容器文件传输的复杂性。

### 优势

✅ **简单** - Nextflow 自动处理所有 S3 文件传输
✅ **成熟** - Nextflow 是业界标准的云工作流引擎
✅ **兼容** - 支持所有 BioContainers 镜像，无需修改
✅ **可扩展** - 支持多云（AWS, GCP, Azure）
✅ **高性能** - 自动优化数据传输和任务调度

## 架构

```
┌─────────────────────────────────────────────┐
│ Galaxy Web UI                               │
│  - 用户上传数据                              │
│  - 定义 Workflow                             │
│  - 监控任务状态                              │
└─────────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────────┐
│ Galaxy Cloud Job Runner                     │
│  - 检测到 use_nextflow=true                 │
│  - 提取输入/输出路径                          │
│  - 生成 Nextflow DSL 脚本                    │
└─────────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────────┐
│ Nextflow                                    │
│  - 上传输入到 S3                             │
│  - 提交任务到 AWS Batch                       │
│  - 自动重试失败任务                           │
│  - 下载输出回 Galaxy                          │
└─────────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────────┐
│ AWS Batch                                   │
│  - 容器执行（自动从 S3 拉取数据）              │
│  - 结果写回 S3                                │
└─────────────────────────────────────────────┘
```

## 安装步骤

### 1. 安装 Nextflow

```bash
# 方法 1: 使用 curl (推荐)
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/
chmod +x /usr/local/bin/nextflow

# 方法 2: 使用 conda
conda install -c bioconda nextflow

# 验证安装
nextflow -version
# 应该看到类似: nextflow version 23.10.0.5889
```

### 2. 配置 AWS 凭证

确保 Galaxy 运行用户有 AWS 访问权限：

```bash
# 配置 AWS CLI
aws configure
# 输入:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: us-west-2
# Default output format: json

# 验证配置
aws s3 ls s3://galaxy-cloud-data-1760241377/
aws batch describe-job-queues --job-queue galaxy-cloud-queue
```

### 3. 更新 Galaxy 配置

使用新的 job 配置文件：

```bash
cd /path/to/galaxy

# 备份原配置
cp config/job_conf.yml config/job_conf.yml.backup

# 使用 Nextflow 配置
cp config/job_conf_nextflow.yml config/job_conf.yml

# 或者编辑现有配置，添加 use_nextflow: true
vim config/job_conf.yml
```

配置示例：

```yaml
execution:
  default: nextflow_cloud
  environments:
    nextflow_cloud:
      runner: galaxy_cloud
      params:
        use_nextflow: true           # 启用 Nextflow
        provider: aws
        aws_region: us-west-2
        aws_batch_queue: galaxy-cloud-queue
        aws_s3_bucket: galaxy-cloud-data-1760241377
        cpus: 2
        memory: 4
```

### 4. 重启 Galaxy

```bash
# 停止 Galaxy
pkill -f "python.*run.py"

# 启动 Galaxy（使用 Nextflow 配置）
PYTHONPATH=lib \
GALAXY_CONFIG_FILE=config/galaxy.yml \
GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_nextflow.yml \
sh run.sh
```

## 使用方法

### 测试单个工具

1. **上传测试文件**
   - 在 Galaxy UI 上传一个 FASTQ 文件
   - 例如：`sample.fastq.gz`

2. **运行 FastQC 工具**
   - 在工具面板选择 "FastQC"
   - 选择上传的文件
   - 点击 "Execute"

3. **监控执行**

查看 Galaxy 日志：
```bash
tail -f database/galaxy.log | grep -i nextflow
```

应该看到：
```
Job 123 will use Nextflow execution
Nextflow executor initialized successfully
Uploading 1 input files to S3
Nextflow script written to /tmp/galaxy_nextflow_xxx/job_123.nf
Launching Nextflow execution
Nextflow completed successfully
Downloading 1 output files from S3
```

### 运行完整 Workflow

1. **导入 Workflow**
   - 使用 `test_enhanced_cloud_workflow.py` 中的 workflow
   - 或通过 Galaxy UI 导入 workflow JSON

2. **启动 Workflow**
   - 上传输入数据
   - 配置 workflow 参数
   - 点击 "Run Workflow"

3. **查看进度**
   - Galaxy UI 显示任务状态
   - 检查 AWS Batch 控制台
   - 查看 S3 bucket 中的数据

## 调试

### 查看 Nextflow 脚本

生成的 Nextflow 脚本保存在：
```bash
ls /tmp/galaxy_nextflow_*/
# 例如: job_123.nf, job_123.config, job_123.log
```

查看脚本内容：
```bash
cat /tmp/galaxy_nextflow_*/job_123.nf
```

### 查看 Nextflow 日志

```bash
# 实时查看日志
tail -f /tmp/galaxy_nextflow_*/job_123.log

# 查看 Nextflow 报告
ls /tmp/galaxy_nextflow_*/report.html
ls /tmp/galaxy_nextflow_*/timeline.html
```

### 手动运行 Nextflow 脚本

```bash
cd /tmp/galaxy_nextflow_xxx/

# 运行脚本
nextflow run job_123.nf -c job_123.config

# 查看工作目录
ls -la s3://galaxy-cloud-data-1760241377/galaxy-workflows/
```

### 常见问题

#### 1. Nextflow 未找到

```bash
# 检查 PATH
which nextflow

# 如果不在 PATH 中，在 job_conf.yml 中指定完整路径
params:
  nextflow_bin: /usr/local/bin/nextflow
```

#### 2. AWS 权限错误

```bash
# 检查 AWS 凭证
aws sts get-caller-identity

# 确保有以下权限:
# - s3:GetObject, s3:PutObject, s3:ListBucket
# - batch:SubmitJob, batch:DescribeJobs
# - logs:GetLogEvents
```

#### 3. 容器下载失败

```bash
# 检查容器是否存在
docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0

# 在 AWS Batch 计算环境中配置 Docker Hub 镜像
```

#### 4. 文件未上传到 S3

```bash
# 检查 S3 bucket 权限
aws s3 ls s3://galaxy-cloud-data-1760241377/galaxy-workflows/

# 检查 Galaxy 日志中的上传信息
grep -i "upload" database/galaxy.log
```

## 性能调优

### 1. 并发任务数

编辑 `job_conf.yml`:

```yaml
execution:
  environments:
    nextflow_cloud:
      params:
        # 最大并发任务数
        max_concurrent_jobs: 100
```

### 2. 资源分配

为不同工具配置不同资源：

```yaml
tools:
  - id: fastqc
    params:
      cpus: 2
      memory: 4

  - id: bwa_mem
    params:
      cpus: 16
      memory: 32
```

### 3. Spot 实例

在 Nextflow 配置中启用 Spot 实例：

```groovy
aws {
    batch {
        cliPath = '/home/ec2-user/miniconda/bin/aws'
        jobRole = 'arn:aws:iam::ACCOUNT:role/BatchJobRole'

        // 使用 Spot 实例（便宜 70%）
        computeEnvironment = 'galaxy-batch-spot'
    }
}
```

## 成本估算

### 典型 Workflow 成本

假设运行一个包含 10 个任务的 workflow：

- **计算成本**: $0.05/小时 × 2 小时 × 10 任务 = $1.00
- **S3 存储**: 100 GB × $0.023/GB = $2.30/月
- **S3 传输**: 50 GB × $0.09/GB = $4.50（可通过 S3 Gateway 免费）

**总成本**: ~$1.00/workflow（计算）+ $2.30/月（存储）

### 优化建议

1. 使用 Spot 实例 → 节省 70% 计算成本
2. 及时清理 S3 work 目录 → 节省存储成本
3. 使用 S3 Infrequent Access → 归档数据节省 45%

## 下一步

- [ ] 测试完整的 workflow 执行
- [ ] 配置 Spot 实例降低成本
- [ ] 添加更多工具到配置中
- [ ] 设置 S3 生命周期策略自动清理
- [ ] 集成 Nextflow Tower 进行监控

## 相关资源

- [Nextflow 官方文档](https://www.nextflow.io/docs/latest/index.html)
- [Nextflow AWS Batch 指南](https://www.nextflow.io/docs/latest/awscloud.html)
- [nf-core Pipelines](https://nf-co.re/) - 现成的生物信息学 workflows
- [Galaxy Cloud Runner 文档](./README.md)
