# Nextflow 文件传输机制分析

## 核心问题

我们的问题：**容器内没有 Python/AWS CLI，无法执行 S3 传输脚本**

## Nextflow 的解决方案

### 1. 不在容器内处理 S3 传输！

**关键发现**：Nextflow **从不在用户容器内安装 AWS CLI**。

#### Nextflow 的执行流程

```
┌─────────────────────────────────────────────┐
│ Nextflow 进程（在 AWS Batch 的帮助容器中）    │
│  - 有完整的 Nextflow runtime                │
│  - 有 AWS CLI                               │
│  - 有 Java/Groovy                           │
└─────────────────────────────────────────────┘
                ↓
        1. 下载输入文件
           S3 → 本地 work 目录
                ↓
┌─────────────────────────────────────────────┐
│ 用户工具容器（干净的 BioContainer）           │
│  - 只运行工具命令                            │
│  - 文件通过 volume 挂载获得                  │
│  - 不需要任何 AWS 工具                       │
└─────────────────────────────────────────────┘
                ↓
        2. 上传输出文件
           本地 work 目录 → S3
                ↓
        由 Nextflow 进程处理
```

### 2. AWS Batch 的 Multi-Container Job

Nextflow 使用 AWS Batch 的 **Multi-Container Jobs**（或 sidecar 模式）：

```yaml
# AWS Batch Job 定义
{
  "jobDefinition": "nextflow-job",
  "containers": [
    {
      # Container 1: Nextflow runner（负责文件传输）
      "image": "nextflow/nextflow:latest",
      "command": [
        "bash", "-c",
        "aws s3 cp s3://bucket/input.fastq /shared/input.fastq &&
         docker run -v /shared:/data biocontainers/fastqc /data/input.fastq &&
         aws s3 cp /shared/output.html s3://bucket/output.html"
      ],
      "mountPoints": [
        {"sourceVolume": "shared", "containerPath": "/shared"}
      ]
    },
    # Container 2: 实际工具容器（由 Container 1 启动）
    # 或者使用 Docker-in-Docker
  ],
  "volumes": [
    {"name": "shared", "host": {"sourcePath": "/tmp/shared"}}
  ]
}
```

## 我们可以借鉴的思路

### 方案 1: Wrapper 容器（推荐）

**不要在 BioContainer 内处理 S3，而是用一个包装容器**。

#### 实现

创建一个 wrapper 镜像：

```dockerfile
# Dockerfile.galaxy-cloud-wrapper
FROM amazonlinux:2

# 安装必要工具
RUN yum install -y python3 python3-pip docker && \
    pip3 install boto3 awscli && \
    yum clean all

# 复制传输脚本
COPY s3_transfer.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/s3_transfer.sh
```

传输脚本：

```bash
#!/bin/bash
# s3_transfer.sh

set -e

# 参数
S3_INPUT_PREFIX=$1
S3_OUTPUT_PREFIX=$2
TOOL_IMAGE=$3
TOOL_COMMAND=$4

# 1. 创建共享目录
mkdir -p /tmp/work/inputs /tmp/work/outputs

# 2. 下载输入文件
echo "Downloading inputs from $S3_INPUT_PREFIX..."
aws s3 sync $S3_INPUT_PREFIX /tmp/work/inputs/

# 3. 运行工具容器（挂载共享目录）
echo "Running tool: $TOOL_IMAGE"
docker run --rm \
  -v /tmp/work/inputs:/inputs:ro \
  -v /tmp/work/outputs:/outputs:rw \
  $TOOL_IMAGE \
  bash -c "$TOOL_COMMAND"

# 4. 上传输出文件
echo "Uploading outputs to $S3_OUTPUT_PREFIX..."
aws s3 sync /tmp/work/outputs/ $S3_OUTPUT_PREFIX

echo "Done!"
```

#### Galaxy 集成

```python
# galaxy_job_runner.py
def _create_job_spec_with_wrapper(self, job_wrapper, job_destination):
    """使用 wrapper 容器包装工具执行"""

    # 1. 准备 S3 路径
    job_id = job_wrapper.get_id_tag()
    s3_input_prefix = f"s3://{self.s3_bucket}/jobs/{job_id}/inputs/"
    s3_output_prefix = f"s3://{self.s3_bucket}/jobs/{job_id}/outputs/"

    # 2. 上传输入文件到 S3（在 Galaxy 端）
    for input_path in input_paths:
        self._upload_to_s3(input_path, s3_input_prefix)

    # 3. 获取工具容器和命令
    tool_image = self._get_tool_container(job_wrapper)
    tool_command = self._get_tool_command(job_wrapper)

    # 4. 创建 wrapper job spec
    job_spec = JobSpec(
        container=ContainerSpec(
            # 使用 wrapper 镜像，不是工具镜像！
            image="your-registry/galaxy-cloud-wrapper:latest",

            # wrapper 的命令
            command=["/bin/bash", "-c"],
            args=[
                f"/usr/local/bin/s3_transfer.sh "
                f"{s3_input_prefix} "
                f"{s3_output_prefix} "
                f"{tool_image} "
                f"'{tool_command}'"
            ]
        ),
        # 需要 Docker-in-Docker 权限
        resources=ResourceSpec(privileged=True)
    )

    return job_spec
```

### 方案 2: AWS Batch 的 Fetch-and-Run 模式（更简单）

AWS 官方推荐的模式，使用一个通用的 runner 镜像。

#### Fetch-and-Run 镜像

```dockerfile
# Dockerfile.fetch-and-run
FROM amazonlinux:2

# 安装 AWS CLI 和 Docker
RUN yum install -y aws-cli docker python3

# 复制 fetch-and-run 脚本
COPY fetch_and_run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/fetch_and_run.sh

ENTRYPOINT ["/usr/local/bin/fetch_and_run.sh"]
```

#### Fetch-and-Run 脚本

```bash
#!/bin/bash
# fetch_and_run.sh

# 从环境变量读取配置
SCRIPT_S3_URL=${BATCH_FILE_S3_URL}
TOOL_IMAGE=${TOOL_CONTAINER_IMAGE}

# 1. 从 S3 下载执行脚本
aws s3 cp $SCRIPT_S3_URL /tmp/job_script.sh
chmod +x /tmp/job_script.sh

# 2. 如果指定了容器，在容器内运行；否则直接运行
if [ -n "$TOOL_IMAGE" ]; then
    # 在容器内运行
    docker run --rm -v /tmp:/tmp $TOOL_IMAGE /tmp/job_script.sh
else
    # 直接运行
    /tmp/job_script.sh
fi
```

#### Galaxy 集成

```python
def _create_fetch_and_run_job(self, job_wrapper, job_destination):
    """使用 Fetch-and-Run 模式"""

    job_id = job_wrapper.get_id_tag()

    # 1. 生成执行脚本
    script_content = f"""#!/bin/bash
set -e

# 下载输入
aws s3 sync s3://{self.s3_bucket}/jobs/{job_id}/inputs/ /tmp/inputs/

# 运行工具
{job_wrapper.command_line}

# 上传输出
aws s3 sync /tmp/outputs/ s3://{self.s3_bucket}/jobs/{job_id}/outputs/
"""

    # 2. 上传脚本到 S3
    script_s3_url = f"s3://{self.s3_bucket}/scripts/{job_id}.sh"
    self._upload_string_to_s3(script_content, script_s3_url)

    # 3. 创建 job spec
    job_spec = JobSpec(
        container=ContainerSpec(
            image="your-registry/fetch-and-run:latest",
            environment={
                "BATCH_FILE_S3_URL": script_s3_url,
                "TOOL_CONTAINER_IMAGE": tool_image
            }
        )
    )

    return job_spec
```

### 方案 3: EFS 挂载（最优雅）

这是我之前提到的长期方案，**完全不需要容器内传输**。

```python
def _create_job_spec_with_efs(self, job_wrapper, job_destination):
    """使用 EFS 共享文件系统"""

    # Galaxy 数据已经在 EFS 上
    # /mnt/efs/galaxy/datasets/dataset_123.fastq

    job_spec = JobSpec(
        container=ContainerSpec(
            image=tool_image,
            command=["/bin/bash", "-c"],
            args=[
                # 直接使用 EFS 路径，无需传输！
                f"fastqc /mnt/efs/galaxy/datasets/dataset_123.fastq "
                f"-o /mnt/efs/galaxy/outputs/"
            ]
        ),
        # 挂载 EFS
        volumes=[
            {
                "name": "efs-storage",
                "efsVolumeConfiguration": {
                    "fileSystemId": "fs-12345678",
                    "rootDirectory": "/galaxy"
                }
            }
        ],
        mount_points=[
            {
                "sourceVolume": "efs-storage",
                "containerPath": "/mnt/efs/galaxy"
            }
        ]
    )

    return job_spec
```

## 三种方案对比

| 方案 | 复杂度 | 成本 | 性能 | 容器兼容性 |
|------|-------|------|------|-----------|
| Wrapper 容器 | 中 | 低 | 中（需要 S3 传输） | ✅ 完美 |
| Fetch-and-Run | 低 | 低 | 中（需要 S3 传输） | ✅ 完美 |
| EFS 挂载 | 低 | 高 | 🚀 最快（无传输） | ✅ 完美 |

## 推荐实现顺序

### 第一步：Fetch-and-Run（最简单）

1. 构建 `fetch-and-run` 镜像（10 分钟）
2. 修改 `galaxy_job_runner.py` 生成执行脚本（30 分钟）
3. 测试单个任务（10 分钟）

**预计时间**：1 小时

### 第二步：Wrapper 容器（更灵活）

如果 Fetch-and-Run 不够用，实现 Wrapper 模式。

**预计时间**：2 小时

### 第三步：EFS 挂载（长期方案）

如果数据量大且频繁执行，配置 EFS。

**预计时间**：1 天（包括 AWS 配置）

## 下一步？

你想先实现哪个方案？我推荐从 **Fetch-and-Run** 开始，因为：

1. ✅ 最简单 - 只需一个 Dockerfile 和少量代码修改
2. ✅ 不需要 Docker-in-Docker（避免权限问题）
3. ✅ 完全兼容所有 BioContainers
4. ✅ 代码改动最小

需要我帮你实现 Fetch-and-Run 方案吗？
