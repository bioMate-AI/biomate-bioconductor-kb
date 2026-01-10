# Nextflow Fetch-and-Run 实现深度解析

## 概述

Nextflow 如何在 AWS Batch 上运行任务？它使用了一个巧妙的**三明治架构**。

## 架构层次

```
┌───────────────────────────────────────────────────────────┐
│ 1. AWS Batch Job Definition                              │
│    - Job name: nf-12345-fastqc                           │
│    - Image: nextflow/nextflow:23.10.0                    │
│    - Command: ["nxf", "run", "workflow.nf"]             │
└───────────────────────────────────────────────────────────┘
                        ↓
┌───────────────────────────────────────────────────────────┐
│ 2. Nextflow Runtime (运行在 AWS Batch 容器内)             │
│    - 启动 Nextflow 进程                                   │
│    - 解析 DSL 脚本                                        │
│    - 执行任务调度                                         │
└───────────────────────────────────────────────────────────┘
                        ↓
┌───────────────────────────────────────────────────────────┐
│ 3. Task Execution (在 Nextflow 容器内)                   │
│                                                           │
│    stage() {                                             │
│      // 下载输入文件                                      │
│      aws s3 cp s3://bucket/input.fastq work/input.fastq │
│    }                                                     │
│                                                           │
│    run() {                                               │
│      // 运行用户工具                                      │
│      docker run -v work:/data biocontainers/fastqc \   │
│                 /data/input.fastq                        │
│    }                                                     │
│                                                           │
│    unstage() {                                           │
│      // 上传输出文件                                      │
│      aws s3 cp work/output.html s3://bucket/output.html │
│    }                                                     │
└───────────────────────────────────────────────────────────┘
```

## Nextflow 的关键源码

### 1. AWS Batch Executor

Nextflow 的 AWS Batch 执行器核心代码（简化版）：

```groovy
// nextflow/src/main/groovy/nextflow/cloud/aws/batch/AwsBatchExecutor.groovy

class AwsBatchExecutor extends Executor {

    @Override
    TaskHandler createTaskHandler(TaskRun task) {
        return new AwsBatchTaskHandler(task, this)
    }

    @Override
    protected void register() {
        // 注册为 'awsbatch' executor
        super.register()
    }
}

class AwsBatchTaskHandler extends TaskHandler {

    @Override
    void submit() {
        // 1. Stage 输入文件到 S3
        def stagingPath = "s3://${bucket}/work/${task.hash}"
        stageInputFiles(task.inputFiles, stagingPath)

        // 2. 生成任务脚本
        def script = generateTaskScript(task)
        uploadScript(script, "${stagingPath}/.command.sh")

        // 3. 构建 AWS Batch Job 请求
        def jobDefinition = createJobDefinition(task)
        def submitRequest = [
            jobName: "nf-${task.hash}",
            jobQueue: config.queue,
            jobDefinition: jobDefinition,
            containerOverrides: [
                command: [
                    'bash', '-c',
                    """
                    # Download script
                    aws s3 cp ${stagingPath}/.command.sh /tmp/.command.sh

                    # Download inputs
                    aws s3 sync ${stagingPath}/inputs/ /tmp/work/

                    # Execute script
                    bash /tmp/.command.sh

                    # Upload outputs
                    aws s3 sync /tmp/work/ ${stagingPath}/outputs/
                    """
                ],
                environment: [
                    [name: 'NXF_TASK_WORKDIR', value: stagingPath]
                ]
            ]
        ]

        // 4. 提交到 AWS Batch
        def response = batchClient.submitJob(submitRequest)
        this.jobId = response.jobId
    }

    private void stageInputFiles(inputs, stagingPath) {
        inputs.each { file ->
            def s3Key = "${stagingPath}/inputs/${file.name}"
            s3Client.putObject(bucket, s3Key, file)
        }
    }

    private String generateTaskScript(task) {
        """
        #!/bin/bash
        set -e
        set -o pipefail

        # Nextflow-generated script
        cd /tmp/work

        # Run the tool container
        docker run --rm \\
          -v /tmp/work:/work \\
          ${task.container} \\
          bash -c '${task.script}'
        """
    }
}
```

### 2. 任务脚本生成

Nextflow 生成的实际脚本示例：

```bash
#!/bin/bash
# Nextflow generated task script

# Exit on error
set -e
set -u
set -o pipefail

# Nextflow variables
NXF_TASK_WORKDIR="s3://bucket/work/abc123"
NXF_SCRATCH="/tmp/nf-scratch-abc123"

# Stage inputs
echo "Staging inputs..."
aws s3 sync ${NXF_TASK_WORKDIR}/inputs/ ${NXF_SCRATCH}/

# Change to work directory
cd ${NXF_SCRATCH}

# Run the task
echo "Running task..."
docker run --rm \
  -v ${NXF_SCRATCH}:/work \
  -w /work \
  quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
  fastqc /work/input.fastq -o /work/

# Stage outputs
echo "Staging outputs..."
aws s3 sync ${NXF_SCRATCH}/ ${NXF_TASK_WORKDIR}/outputs/ \
  --exclude '*' \
  --include '*.html' \
  --include '*.zip'

# Cleanup
rm -rf ${NXF_SCRATCH}
```

### 3. Docker-in-Docker 配置

Nextflow 需要在 AWS Batch 容器内运行 Docker，使用的是 **Docker-in-Docker (DinD)** 模式：

```dockerfile
# Nextflow 官方镜像
FROM amazoncorretto:17-al2023

# 安装 Docker 客户端
RUN yum install -y docker

# 安装 AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install

# 安装 Nextflow
RUN curl -s https://get.nextflow.io | bash && \
    mv nextflow /usr/local/bin/

# Nextflow 配置
ENV NXF_MODE=awsbatch
ENV NXF_EXECUTOR=awsbatch

ENTRYPOINT ["nextflow"]
```

AWS Batch Job Definition 需要特殊配置：

```json
{
  "jobDefinitionName": "nextflow-job",
  "type": "container",
  "containerProperties": {
    "image": "nextflow/nextflow:23.10.0",
    "vcpus": 2,
    "memory": 4096,

    // 关键：挂载 Docker socket
    "volumes": [
      {
        "name": "docker-sock",
        "host": {
          "sourcePath": "/var/run/docker.sock"
        }
      }
    ],
    "mountPoints": [
      {
        "sourceVolume": "docker-sock",
        "containerPath": "/var/run/docker.sock"
      }
    ],

    // 需要 privileged 模式运行 Docker
    "privileged": true
  }
}
```

## 我们的 Fetch-and-Run vs Nextflow

### 相同点

1. **都使用 wrapper 容器**处理文件传输
2. **都将用户容器与传输逻辑分离**
3. **都在 Galaxy/Nextflow 端上传输入，容器端下载**

### 不同点

| 特性 | Nextflow | 我们的 Fetch-and-Run |
|------|----------|---------------------|
| **工具容器运行方式** | Docker-in-Docker | 直接在 wrapper 容器内运行命令 |
| **脚本生成** | Groovy DSL → Bash | Python → Bash |
| **容器隔离** | 完全隔离（嵌套容器） | 共享容器环境 |
| **复杂度** | 高（需要 DinD） | 低（单层容器） |
| **灵活性** | 高（支持多个工具） | 中（一个任务一个容器） |

## 为什么我们不用 Docker-in-Docker？

Nextflow 使用 DinD 是因为：
- 需要**同时运行多个不同的工具容器**
- 需要**完全隔离**每个工具的环境
- 支持**容器嵌套**（容器内再运行容器）

但这带来了问题：
- ❌ 需要 `privileged` 模式（安全风险）
- ❌ 需要挂载 Docker socket（复杂配置）
- ❌ 容器启动开销大

### 我们的简化方案

我们不需要 DinD，因为：
- ✅ **每个任务只运行一个工具**
- ✅ **在 wrapper 容器内直接运行命令**
- ✅ **使用符号链接解决路径问题**

示例对比：

**Nextflow (DinD)**:
```bash
# 在 nextflow 容器内
docker run -v /work:/data biocontainers/fastqc /data/input.fastq
```

**我们 (Direct)**:
```bash
# 在 fetch-and-run 容器内直接运行
ln -sf /tmp/inputs/input.fastq /galaxy/database/files/dataset_123.dat
fastqc /galaxy/database/files/dataset_123.dat -o /tmp/outputs/
```

等等！**我们不能直接运行 fastqc**，因为 fetch-and-run 容器里没有 fastqc！

## 关键问题：我们的方案缺少什么？

### 问题

Fetch-and-Run 容器只有 AWS CLI 和 bash，**没有生物信息学工具**！

### 解决方案 1: 安装工具到 Fetch-and-Run 镜像（不推荐）

```dockerfile
FROM amazonlinux:2
RUN yum install -y python3 aws-cli docker
RUN pip3 install boto3

# 安装所有可能用到的工具？不现实！
# RUN apt-get install -y fastqc samtools bwa ...
```

❌ 这样做会导致镜像巨大（几十 GB）

### 解决方案 2: 使用 Docker-in-Docker（Nextflow 的方案）

```bash
# 在 fetch-and-run 容器内
docker run -v /tmp/work:/work \
  quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
  fastqc /work/input.fastq -o /work/
```

✅ 这就是 Nextflow 的做法！

### 解决方案 3: 使用 Conda（推荐！）

```bash
# 在 fetch-and-run 容器内
conda create -n tool-env -c bioconda fastqc
conda activate tool-env
fastqc /work/input.fastq -o /work/
```

✅ 动态安装工具，镜像保持小巧

### 解决方案 4: 使用多阶段构建（我们当前的方案）

我意识到我们的 fetch-and-run 脚本有个问题 - 它假设工具已经安装！

让我修正：**我们应该在脚本中使用 Docker-in-Docker 或 Conda 来运行工具**。

## 修正后的 Fetch-and-Run 方案

### 选项 A: 添加 Docker-in-Docker 支持

修改 `fetch_and_run.sh`:

```bash
#!/bin/bash
# ... (前面的下载代码)

# 获取工具容器镜像（从环境变量）
TOOL_IMAGE=${TOOL_CONTAINER_IMAGE:-ubuntu:20.04}

echo "Running tool in container: ${TOOL_IMAGE}"

# 使用 Docker-in-Docker 运行工具
docker run --rm \
  -v ${INPUT_DIR}:/inputs:ro \
  -v ${OUTPUT_DIR}:/outputs:rw \
  -v ${WORK_DIR}:/work:rw \
  ${TOOL_IMAGE} \
  bash "${SCRIPT_FILE}"

# ... (后面的上传代码)
```

修改 Galaxy 提交代码，传递工具镜像：

```python
# 在 _submit_fetch_and_run_job 中
env={
    'JOB_SCRIPT_S3_URL': f"s3://{s3_bucket}/{script_s3_key}",
    'TOOL_CONTAINER_IMAGE': container_image,  # ← 添加这行
    'S3_BUCKET': s3_bucket,
    'JOB_ID': job_id,
}
```

### 选项 B: 添加 Conda 支持

修改 `fetch_and_run.sh`:

```bash
#!/bin/bash
# ... (前面的下载代码)

# 获取工具名称
TOOL_NAME=${TOOL_NAME:-fastqc}

echo "Installing tool via Conda: ${TOOL_NAME}"

# 安装工具
conda create -y -n tool-env -c bioconda -c conda-forge ${TOOL_NAME}
conda activate tool-env

# 运行脚本
bash "${SCRIPT_FILE}"

# ... (后面的上传代码)
```

## 最终推荐

我建议采用 **Docker-in-Docker** 方案，原因：

1. ✅ **完全兼容 BioContainers** - 不需要重新打包
2. ✅ **工具隔离** - 每个工具在自己的容器中
3. ✅ **与 Nextflow 一致** - 使用成熟的模式
4. ❌ 需要 `privileged` 模式 - 这是唯一的缺点

## 下一步

需要我修改 fetch-and-run 脚本，添加 Docker-in-Docker 支持吗？这样它就和 Nextflow 的机制完全一样了！
