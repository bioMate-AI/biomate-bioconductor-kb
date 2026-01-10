# Galaxy云执行完整工作原理详解

## 🎯 你的核心问题

> "复杂的workflow在云上运行，是上传tool，还是利用docker？根据什么配置文件？"

让我从头到尾解释清楚。

---

## 📚 第一部分：Galaxy工具的本质

### Galaxy工具不是直接运行的程序

在Galaxy中，一个"工具"实际上包含：

```
Galaxy Tool = XML配置文件 + 容器镜像 + 实际程序
```

#### 例如：FastQC工具

```xml
<!-- FastQC工具的XML描述 -->
<tool id="fastqc" name="FastQC">
  <requirements>
    <container type="docker">quay.io/biocontainers/fastqc:0.12.1</container>
  </requirements>
  <command>
    fastqc $input_file -o $output_dir
  </command>
</tool>
```

**关键点：**
- 工具的**XML文件**描述如何运行
- 工具的**实际程序**在**Docker容器**里
- 容器镜像来自**BioContainers** (quay.io/biocontainers)

---

## 🏗️ 第二部分：本地运行 vs 云端运行

### 本地运行（传统方式）

```
用户提交workflow
    ↓
Galaxy读取工具XML
    ↓
Galaxy在本地拉取Docker镜像
    ↓
Galaxy在本地启动容器
    ↓
在容器内运行工具
    ↓
结果保存到本地文件系统
```

**问题：**
- ❌ 需要本地有足够的CPU/内存
- ❌ 需要本地安装Docker
- ❌ 大量计算会占用Galaxy服务器资源
- ❌ 无法弹性扩展

### 云端运行（我们的方案）

```
用户提交workflow
    ↓
Galaxy读取工具XML
    ↓
GalaxyCloudJobRunner拦截作业 ←【关键！】
    ↓
提取工具的Docker镜像地址
    ↓
上传输入数据到S3
    ↓
提交作业到AWS Batch
    ↓
AWS Batch在云端拉取Docker镜像
    ↓
AWS Batch在EC2实例上运行容器
    ↓
容器执行完毕，结果上传到S3
    ↓
Galaxy下载结果
```

**优势：**
- ✅ 不占用本地资源
- ✅ 自动弹性扩展
- ✅ 按需付费
- ✅ 可以同时运行成百上千个作业

---

## 🔑 第三部分：云执行的关键配置

### 配置文件1：job_conf_cloud.yml（最重要！）

这个文件告诉Galaxy：**哪些工具应该在云端运行**

```yaml
# /Users/renyuankai/work/biometa/galaxy/config/job_conf_cloud.yml

runners:
  galaxy_cloud:
    load: galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner
    # ↑ 这是我们的云执行器

execution:
  environments:
    cloud_small:
      runner: galaxy_cloud  # 使用云执行器
      params:
        provider: aws
        vcpus: 2
        memory_mb: 4096
        # ↑ 云端资源配置

tools:
  # === 关键：工具路由规则 ===
  - id: "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/.*"
    environment: cloud_small
    # ↑ FastQC工具路由到cloud_small环境

  - id: "toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/.*"
    environment: cloud_large
    # ↑ Bowtie2工具路由到cloud_large环境
```

**工作流程：**

```
用户运行FastQC工具
    ↓
Galaxy查看 job_conf_cloud.yml
    ↓
匹配到规则：fastqc → cloud_small
    ↓
调用 GalaxyCloudJobRunner
    ↓
在AWS上运行
```

### 配置文件2：aws_cloud_config.yaml

这个文件配置AWS资源：

```yaml
# config/aws_cloud_config.yaml
aws:
  region: us-west-2
  batch:
    job_queue: galaxy-cloud-queue      # AWS Batch队列
    job_definition_prefix: galaxy-job  # 作业定义前缀
  s3:
    bucket: galaxy-cloud-data-1760241377  # 数据存储桶
```

### 配置文件3：工具的XML（在Tool Shed中）

每个工具都有XML描述，包含Docker镜像：

```xml
<!-- FastQC的XML（在Tool Shed中） -->
<tool>
  <requirements>
    <container type="docker">
      quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
    </container>
  </requirements>
</tool>
```

---

## 🚀 第四部分：完整的云执行流程（详细版）

### 场景：运行FastQC工具

#### Step 1：用户在Galaxy UI中点击运行

```
用户选择FastQC工具
用户上传 input.fastq
用户点击 "Execute"
```

#### Step 2：Galaxy接收请求

```python
# Galaxy内部
job = Job(tool_id="toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74")
job.input_datasets = [input.fastq]
```

#### Step 3：Galaxy查找执行环境

```python
# Galaxy读取 job_conf_cloud.yml
for rule in tool_rules:
    if rule.matches("toolshed.g2.bx.psu.edu/repos/devteam/fastqc/.*"):
        environment = rule.environment  # "cloud_small"
        runner = get_runner(environment)  # GalaxyCloudJobRunner
        break
```

#### Step 4：GalaxyCloudJobRunner接管

```python
# galaxy_cloud/galaxy_workflow/galaxy_job_runner.py

class GalaxyCloudJobRunner:
    def queue_job(self, job_wrapper):
        # 1. 获取工具信息
        tool = job_wrapper.tool
        tool_id = tool.id

        # 2. 查找Docker镜像
        container = self._get_container_for_tool(tool_id)
        # 结果: "quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"

        # 3. 上传输入数据到S3
        s3_input_path = self._upload_to_s3(job.input_file)
        # 结果: "s3://galaxy-cloud-data-1760241377/jobs/job-123/input.fastq"

        # 4. 生成命令
        command = tool.command_template.format(
            input_file="/data/input.fastq",
            output_file="/data/output.html"
        )
        # 结果: "fastqc /data/input.fastq -o /data/"

        # 5. 提交到AWS Batch
        batch_job = self._submit_to_aws_batch(
            image=container,
            command=command,
            vcpus=2,
            memory=4096,
            s3_input=s3_input_path
        )
```

#### Step 5：AWS Batch执行

```bash
# AWS Batch在EC2实例上执行：

# 1. 拉取Docker镜像
docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0

# 2. 从S3下载输入
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/job-123/input.fastq /data/

# 3. 运行容器
docker run \
  -v /data:/data \
  quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
  fastqc /data/input.fastq -o /data/

# 4. 上传输出到S3
aws s3 cp /data/output.html s3://galaxy-cloud-data-1760241377/jobs/job-123/output.html
```

#### Step 6：结果返回Galaxy

```python
# GalaxyCloudJobRunner监控作业
def check_job_status(batch_job_id):
    status = aws_batch.describe_jobs(jobs=[batch_job_id])

    if status == "SUCCEEDED":
        # 下载结果
        s3_output = "s3://galaxy-cloud-data-1760241377/jobs/job-123/output.html"
        local_output = "/galaxy/database/files/output.html"
        self._download_from_s3(s3_output, local_output)

        # 标记作业完成
        job_wrapper.finish(output_path=local_output)
```

#### Step 7：用户看到结果

```
Galaxy UI显示：
  ✓ FastQC completed successfully
  📄 Output: output.html (可下载)
```

---

## 🎯 第五部分：百分百云端运行的方法

### 问题：如何确保100%在云端运行？

#### 方案1：配置所有toolshed工具云端运行

```yaml
# config/job_conf_cloud.yml

tools:
  # 匹配所有Tool Shed工具
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_small

  # 内置工具保持本地
  - id: ".*"
    environment: local
```

**结果：**
- ✅ 所有Tool Shed安装的工具 → 云端
- ⚠️  内置工具（upload, text manipulation等）→ 本地（这些工具很轻量，没必要云端）

#### 方案2：配置特定类型的工具

```yaml
tools:
  # 计算密集型
  - id: "toolshed.g2.bx.psu.edu/repos/devteam/bowtie.*"
    environment: cloud_large

  - id: "toolshed.g2.bx.psu.edu/repos/.*/.*alignment.*"
    environment: cloud_large

  # 中等计算
  - id: "toolshed.g2.bx.psu.edu/repos/.*/trimmomatic.*"
    environment: cloud_medium

  # 其他Tool Shed工具
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_small
```

#### 方案3：使用标签（Tags）路由

```yaml
execution:
  environments:
    cloud_ml:
      runner: galaxy_cloud
      tags: [machine_learning]

    cloud_genomics:
      runner: galaxy_cloud
      tags: [genomics, alignment]

tools:
  # 根据工具标签路由
  - id: "toolshed.g2.bx.psu.edu/repos/bgruening/sklearn.*"
    environment: cloud_ml
```

### 完全云端执行的配置示例

```yaml
# 这个配置确保几乎所有计算都在云端

runners:
  local:
    load: galaxy.jobs.runners.local:LocalJobRunner
    workers: 2  # 只保留2个本地worker

  galaxy_cloud:
    load: galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner
    workers: 100  # 云端可以有很多并发

execution:
  default: galaxy_cloud  # 默认使用云端！

  environments:
    local:
      runner: local

    cloud_tiny:
      runner: galaxy_cloud
      params: {vcpus: 1, memory_mb: 2048}

    cloud_small:
      runner: galaxy_cloud
      params: {vcpus: 2, memory_mb: 4096}

    cloud_medium:
      runner: galaxy_cloud
      params: {vcpus: 4, memory_mb: 8192}

    cloud_large:
      runner: galaxy_cloud
      params: {vcpus: 8, memory_mb: 16384}

    cloud_xlarge:
      runner: galaxy_cloud
      params: {vcpus: 16, memory_mb: 32768}

tools:
  # === 例外：这些必须本地 ===
  - id: "__UPLOAD__"
    environment: local  # 上传工具必须本地

  - id: "__SET_METADATA__"
    environment: local  # 元数据设置必须本地

  # === 云端执行规则（按计算需求分类）===

  # 超大型计算（序列比对、组装等）
  - id: "toolshed.g2.bx.psu.edu/repos/.*(bowtie|bwa|hisat|star).*"
    environment: cloud_xlarge

  # 大型计算（变异检测、统计分析）
  - id: "toolshed.g2.bx.psu.edu/repos/.*(gatk|bcftools|samtools).*"
    environment: cloud_large

  # 中型计算（质量处理、过滤）
  - id: "toolshed.g2.bx.psu.edu/repos/.*(trim|cutadapt|filter).*"
    environment: cloud_medium

  # 小型计算（质量评估、统计）
  - id: "toolshed.g2.bx.psu.edu/repos/.*(fastqc|multiqc|stats).*"
    environment: cloud_small

  # === 默认规则 ===

  # 所有其他Tool Shed工具 → 云端（小实例）
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_tiny

  # 最后的兜底：内置工具 → 本地
  - id: ".*"
    environment: local
```

---

## 🔍 第六部分：如何验证是否在云端运行

### 方法1：查看Galaxy作业详情

```
Galaxy UI → History → 点击作业 → ℹ️ View Details

查看：
  Job Destination: cloud_small  ← 应该是 cloud_*
  Runner: galaxy_cloud          ← 应该是 galaxy_cloud

如果看到：
  Job Destination: local        ← 在本地运行
  Runner: local                 ← 使用本地runner
```

### 方法2：查看Galaxy日志

```bash
tail -f galaxy_startup.log | grep -i "submit.*batch\|cloud.*job"

# 应该看到类似：
# GalaxyCloudJobRunner: Submitting job to AWS Batch
# AWS Batch job submitted: job-abc123
# S3 upload: /galaxy/files/dataset_1.dat → s3://bucket/jobs/job-123/
```

### 方法3：查看AWS Batch

```bash
# 列出运行中的作业
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 输出应该显示作业ID
{
  "jobSummaryList": [
    {
      "jobId": "abc-123-xyz",
      "jobName": "galaxy-job-fastqc-456"
    }
  ]
}
```

### 方法4：查看S3

```bash
aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive | grep jobs

# 应该看到：
# jobs/job-123/input.fastq
# jobs/job-123/output.html
```

---

## 📊 第七部分：Docker镜像从哪里来？

### BioContainers仓库

所有生物信息学工具的Docker镜像都在：

```
https://quay.io/organization/biocontainers
```

**工作流程：**

1. **Tool Shed工具包含镜像地址**
   ```xml
   <requirements>
     <container type="docker">
       quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
     </container>
   </requirements>
   ```

2. **GalaxyCloudJobRunner提取镜像地址**
   ```python
   container = tool.requirements.containers[0]
   image = container.identifier
   # "quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"
   ```

3. **AWS Batch拉取镜像**
   ```bash
   docker pull quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
   ```

4. **运行容器**
   ```bash
   docker run quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
     fastqc /data/input.fastq
   ```

### 如果工具没有容器？

**情况A：** 老旧工具，没有容器定义

```python
# GalaxyCloudJobRunner会回退到本地执行
if not tool.has_container:
    logger.warning(f"Tool {tool.id} has no container, falling back to local")
    return LOCAL_RUNNER
```

**情况B：** 自定义工具

你需要自己构建Docker镜像：

```dockerfile
# Dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y my-tool
CMD ["my-tool"]
```

然后推送到Docker Hub或ECR，并在工具XML中指定：

```xml
<requirements>
  <container type="docker">
    your-dockerhub-user/my-tool:1.0
  </container>
</requirements>
```

---

## ✅ 总结：完全云端执行的完整方案

### 配置清单

1. **job_conf_cloud.yml** - 工具路由规则
2. **aws_cloud_config.yaml** - AWS资源配置
3. **AWS Batch** - 计算队列和环境
4. **S3 Bucket** - 数据存储
5. **Tool Shed工具** - 必须有Docker容器定义

### 确保100%云端的方法

```yaml
# config/job_conf_cloud.yml

execution:
  default: galaxy_cloud  # 默认云端

tools:
  # 例外：必须本地的
  - id: "__UPLOAD__|__SET_METADATA__"
    environment: local

  # 其他全部云端
  - id: ".*"
    environment: cloud_small
```

### 验证方法

```bash
# 1. 查看作业详情
Galaxy UI → Job Details → Destination: cloud_*

# 2. 查看AWS Batch
aws batch list-jobs --job-queue galaxy-cloud-queue

# 3. 查看S3
aws s3 ls s3://your-bucket/jobs/

# 4. 查看日志
tail -f galaxy_startup.log | grep -i "batch\|cloud"
```

---

## 🎯 最佳实践

1. **分级配置**：轻量工具用小实例，重型工具用大实例
2. **保留本地**：上传、元数据等必须本地
3. **监控成本**：大实例很贵，按需使用
4. **测试验证**：先用小workflow测试，再上生产
5. **日志监控**：定期查看AWS和Galaxy日志

---

**现在清楚了吗？有任何疑问随时问！** 🚀
