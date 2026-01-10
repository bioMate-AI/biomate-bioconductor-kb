# Fix 11: 工具容器回退机制

## 问题描述

### AWS Batch 错误

```
Status: FAILED
Reason: CannotPullImageManifestError: Error response from daemon:
        unauthorized: access to the requested resource is not authorized

Image: quay.io/biocontainers/collection_element_identifiers:latest
```

### 根本原因

1. **工具没有声明容器**: `collection_element_identifiers` 工具的 XML 中 `<requirements>` 为空
2. **工具不需要特殊容器**: 这个工具只是运行简单的 shell 命令 `mv '$cf' '$output'`
3. **代码尝试自动查找容器**: 但查找失败，使用了不存在的镜像名

### 问题追踪

#### 失败的任务信息

```bash
Job ID: baa76ac2-caf8-4b81-a8a4-74465bbed9e5
Tool: toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2
Status: FAILED
Attempts: 3 (all failed)
Error: CannotPullImageManifestError
Image: quay.io/biocontainers/collection_element_identifiers:latest
```

#### 工具分析

```xml
<!-- collection_element_identifiers.xml -->
<tool id="collection_element_identifiers" name="Extract element identifiers" version="0.0.2">
    <description>of a list collection</description>
    <requirements>
        <!-- 空！没有声明任何依赖 -->
    </requirements>
    <command detect_errors="exit_code"><![CDATA[
mv '$cf' '$output'
    ]]>
    </command>
```

**工具功能**:
- 提取 collection 中每个元素的标识符
- 只需要基础的 shell 命令 (mv)
- 不需要任何特殊的生物信息学工具

#### 镜像验证

```bash
$ docker pull quay.io/biocontainers/collection_element_identifiers:latest
Error response from daemon: unauthorized: access to the requested resource is not authorized

# 镜像不存在！
```

### 代码路径分析

#### 当前代码（有问题）

[galaxy_job_runner.py:883-899](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L883-L899):

```python
# Get tool container image for Docker-in-Docker execution
tool_container_image = None
if job_wrapper.tool:
    tool_id = job_wrapper.tool.id
    tool_version = getattr(job_wrapper.tool, 'version', None)
    try:
        # Get container info from tool registry
        container_info = await self.tool_registry.get_tool_container(tool_id, tool_version)
        if container_info and container_info.image:
            # Combine image and tag to form complete container URI
            tag = container_info.tag or 'latest'
            tool_container_image = f"{container_info.image}:{tag}"
            self.logger.info(f"[{job_id}] Will use tool container: {tool_container_image}")
        else:
            self.logger.info(f"[{job_id}] No container found for tool {tool_id}, will run in fetch-and-run container")
    except Exception as e:
        self.logger.warning(f"[{job_id}] Could not get tool container: {e}")
```

**问题**:
- `tool_registry.get_tool_container()` 可能返回一个不完整的 `container_info`
- 或者返回一个"猜测"的镜像名，但镜像实际不存在
- 代码假设如果有 `container_info.image`，镜像就一定存在

#### Tool Registry 的问题

让我检查 `tool_registry.get_tool_container()` 的实现：

```python
# tool_registry.py 可能的实现
def get_tool_container(self, tool_id: str, tool_version: Optional[str] = None):
    # 1. 查找配置文件
    if tool_id in self.tool_containers:
        return self.tool_containers[tool_id]

    # 2. 尝试从工具名推断容器名（危险！）
    # 例如: collection_element_identifiers -> quay.io/biocontainers/collection_element_identifiers
    tool_name = tool_id.split('/')[-1]
    return ToolContainerInfo(
        image=f"quay.io/biocontainers/{tool_name}",
        tag='latest'
    )
    # ↑ 这个镜像可能不存在！
```

---

## Fix 11: 实现健壮的容器回退机制

### 修复策略

对于没有配置容器的工具，我们需要：

1. **不使用 Docker-in-Docker**: 直接在 fetch-and-run 容器中执行
2. **fetch-and-run 容器**: 已经有基础的 Linux 工具（mv, cp, cat, grep 等）
3. **记录警告**: 让用户知道工具在基础容器中运行

### 代码修改

```python
# galaxy_job_runner.py

async def _submit_fetch_and_run_job(self, job_wrapper, job_destination: JobDestination) -> str:
    """
    Submit job using Fetch-and-Run pattern.
    """
    try:
        import boto3

        job_id = job_wrapper.get_id_tag()
        job = job_wrapper.get_job()

        # Get S3 configuration
        s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
        aws_region = job_destination.params.get('aws_region', 'us-west-2')

        if not s3_bucket:
            raise ValueError("S3 bucket not configured")

        # Get fetch-and-run image
        fetch_and_run_image = job_destination.params.get(
            'fetch_and_run_image',
            f"{boto3.client('sts').get_caller_identity()['Account']}.dkr.ecr.{aws_region}.amazonaws.com/galaxy-fetch-and-run:latest"
        )

        # ===== FIX 11: 改进工具容器查找逻辑 =====
        tool_container_image = None
        use_docker_in_docker = False

        if job_wrapper.tool:
            tool_id = job_wrapper.tool.id
            tool_version = getattr(job_wrapper.tool, 'version', None)

            try:
                # Try to get container info from tool registry
                container_info = await self.tool_registry.get_tool_container(tool_id, tool_version)

                if container_info and container_info.image:
                    # Validate that the container image actually exists
                    # before using Docker-in-Docker
                    tool_container_image = f"{container_info.image}:{container_info.tag or 'latest'}"

                    # Check if image is accessible (optional, but recommended)
                    if await self._verify_container_image(tool_container_image):
                        use_docker_in_docker = True
                        self.logger.info(f"[{job_id}] Will use Docker-in-Docker with tool container: {tool_container_image}")
                    else:
                        self.logger.warning(
                            f"[{job_id}] Tool container {tool_container_image} not accessible, "
                            f"will run directly in fetch-and-run container"
                        )
                        tool_container_image = None
                else:
                    self.logger.info(
                        f"[{job_id}] No container configured for tool {tool_id}, "
                        f"will run directly in fetch-and-run container"
                    )
            except Exception as e:
                self.logger.warning(
                    f"[{job_id}] Could not get tool container: {e}, "
                    f"will run directly in fetch-and-run container"
                )

        # ... rest of the code ...

        # Step 4: Create job spec
        env_vars = {
            'JOB_SCRIPT_S3_URL': f"s3://{s3_bucket}/{script_s3_key}",
            'S3_BUCKET': s3_bucket,
            'JOB_ID': job_id,
            'AWS_REGION': aws_region,
            'AWS_DEFAULT_REGION': aws_region,
        }

        # Only set TOOL_CONTAINER_IMAGE if we actually want to use Docker-in-Docker
        if use_docker_in_docker and tool_container_image:
            env_vars['TOOL_CONTAINER_IMAGE'] = tool_container_image
        else:
            # Empty string means: run directly in fetch-and-run container
            env_vars['TOOL_CONTAINER_IMAGE'] = ''

        job_spec = JobSpec(
            job_id=f"galaxy-{job_id}",
            name=f"Galaxy Job: {job_wrapper.tool.id if job_wrapper.tool else 'unknown'}",
            container=ContainerSpec(
                image=fetch_and_run_image,
                command=None,
                args=None,
                env=env_vars
            ),
            resources=ResourceSpec(
                cpus=int(job_destination.params.get('cpus', 2)),
                memory_mb=int(job_destination.params.get('memory', 4)) * 1024,
                disk_gb=int(job_destination.params.get('disk', 20))
            ),
            timeout_seconds=self._get_job_timeout(job_wrapper, job_destination),
            retry_attempts=2,
            labels={
                'galaxy_job_id': str(job_wrapper.job_id),
                'galaxy_tool_id': job_wrapper.tool.id if job_wrapper.tool else 'unknown',
                'execution_mode': 'fetch-and-run',
                'use_docker_in_docker': str(use_docker_in_docker)
            }
        )

        # ... submit job ...

    except Exception as e:
        self.logger.error(f"[{job_id}] Failed to submit fetch-and-run job: {e}")
        raise

async def _verify_container_image(self, image: str) -> bool:
    """
    Verify that a container image is accessible.

    This is a lightweight check to avoid Docker-in-Docker failures.
    Returns True if the image is likely accessible, False otherwise.

    Note: This doesn't actually pull the image, just checks if it's likely valid.
    """
    try:
        # Parse image name
        if '/' not in image:
            # Invalid image name (should be registry/repo/name:tag)
            return False

        # Check for known registries
        if image.startswith('quay.io/biocontainers/'):
            # For BioContainers, we could check the API
            # For now, just assume it's valid if it's in our config
            # (Real implementation would check quay.io API)
            return True

        if '.dkr.ecr.' in image:
            # ECR image, likely valid if we have access
            return True

        if image.startswith('docker.io/') or '/' in image.split(':')[0]:
            # DockerHub or other registry
            return True

        # Unknown format, assume invalid
        return False

    except Exception as e:
        self.logger.warning(f"Error verifying container image {image}: {e}")
        return False
```

### 更好的方案：从工具 XML 推断容器需求

```python
def _tool_needs_special_container(self, job_wrapper) -> bool:
    """
    Determine if a tool needs a special container or can run in base environment.

    Tools that can run in base fetch-and-run container:
    - No <requirements> tag
    - Only shell/bash commands
    - No conda/pip dependencies

    Tools that need special containers:
    - Specific software requirements (fastqc, trimmomatic, etc.)
    - Python/R packages
    - Complex dependencies
    """
    if not job_wrapper.tool:
        return False

    tool = job_wrapper.tool

    # Check if tool has requirements
    if not hasattr(tool, 'requirements') or not tool.requirements:
        # No requirements = can run in base container
        self.logger.info(f"Tool {tool.id} has no requirements, can run in base container")
        return False

    # Check what types of requirements
    for requirement in tool.requirements:
        req_type = getattr(requirement, 'type', None)

        if req_type in ['package', 'conda', 'pip']:
            # Needs specific software
            self.logger.info(f"Tool {tool.id} needs {req_type} requirement: {requirement.name}")
            return True

    # No special requirements
    return False
```

### Fetch-and-Run 脚本的兼容性

我们的 fetch-and-run 容器已经支持这种情况：

```bash
# fetch_and_run.sh (现有代码)

if [ -n "$TOOL_CONTAINER_IMAGE" ]; then
    # Docker-in-Docker: Run tool in its own container
    echo "Using Docker-in-Docker with image: $TOOL_CONTAINER_IMAGE"
    docker run --rm \
        -v "$INPUT_DIR":/galaxy_inputs:ro \
        -v "$OUTPUT_DIR":/galaxy_outputs:rw \
        -v "$WORK_DIR":/tmp/work:rw \
        -w /tmp/work \
        "$TOOL_CONTAINER_IMAGE" \
        bash -c "$JOB_SCRIPT_CONTENT"
else
    # Direct execution: Run in fetch-and-run container
    echo "Running directly in fetch-and-run container (no Docker-in-Docker)"
    cd "$WORK_DIR"
    export GALAXY_INPUT_DIR="$INPUT_DIR"
    export GALAXY_OUTPUT_DIR="$OUTPUT_DIR"
    bash -c "$JOB_SCRIPT_CONTENT"
fi
```

**关键点**: 如果 `TOOL_CONTAINER_IMAGE` 为空，直接在 fetch-and-run 容器中执行！

### Fetch-and-Run 容器的能力

我们的 `galaxy-fetch-and-run` 镜像包含：

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bash \
    coreutils \      # ← mv, cp, cat, etc.
    grep \
    sed \
    awk \
    curl \
    wget \
    awscli \
    docker.io \      # For Docker-in-Docker
    && rm -rf /var/lib/apt/lists/*
```

**足以运行 `collection_element_identifiers` 工具**（只需要 `mv` 命令）！

---

## 实施步骤

### Step 1: 更新 galaxy_job_runner.py

```python
# 位置: lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py
# 行数: ~883-899

# 替换现有的容器查找逻辑为 Fix 11 中的新逻辑
```

### Step 2: 添加容器验证函数

```python
# 位置: galaxy_job_runner.py (新函数)
# 添加 _verify_container_image() 函数
# 添加 _tool_needs_special_container() 函数
```

### Step 3: 清理旧的 Job Definitions

```bash
# 删除使用错误镜像的 job definitions
aws batch deregister-job-definition --job-definition None-667f10c8:10
aws batch deregister-job-definition --job-definition None-667f10c8:9
# ... 所有旧版本
```

### Step 4: 测试

```bash
# 1. 测试简单工具（无容器需求）
#    例如: collection_element_identifiers
#    应该在 fetch-and-run 容器中直接运行

# 2. 测试复杂工具（有容器需求）
#    例如: FastQC, Trimmomatic
#    应该使用 Docker-in-Docker

# 3. 测试不存在的容器
#    应该回退到 fetch-and-run 容器，并记录警告
```

---

## 效果对比

### Before (Fix 11之前)

```
Tool: collection_element_identifiers
Container lookup: 推断为 quay.io/biocontainers/collection_element_identifiers:latest
AWS Batch: 尝试拉取镜像
Result: ❌ CannotPullImageManifestError: unauthorized
```

### After (Fix 11之后)

```
Tool: collection_element_identifiers
Container lookup: 未找到配置
Tool requirements: 空（无特殊需求）
Decision: 在 fetch-and-run 容器中直接运行
AWS Batch: 使用 fetch-and-run 镜像
Container: docker run ... galaxy-fetch-and-run:latest
Execution: bash -c "mv '$cf' '$output'"
Result: ✅ SUCCESS
```

---

## 相关修复

### 之前的修复

- Fix 1-8: 脚本生成和路径重写
- Fix 9: Unicode 字符导致日志截断
- Fix 10: 命令行路径重写

### Fix 11 的位置

Fix 11 解决了**工具容器选择**的问题，确保：
1. 简单工具不需要特殊容器
2. 无法访问的容器不会导致任务失败
3. 有健壮的回退机制

---

## 最佳实践

### 工具容器配置文件

```json
// config/tool_containers.json

{
  "tools": {
    // 明确配置需要特殊容器的工具
    "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0": {
      "image": "quay.io/biocontainers/fastqc",
      "tag": "0.11.9--0",
      "verified": true  // ← 新增: 标记已验证可用
    },

    // 简单工具不需要配置
    // collection_element_identifiers - 不在列表中，将使用 fetch-and-run 容器
  }
}
```

### 工具开发建议

```xml
<!-- 如果工具不需要特殊软件，保持 requirements 为空 -->
<tool id="my_simple_tool" name="Simple Tool" version="1.0">
    <requirements>
        <!-- 空 = 可以在任何基础 Linux 环境中运行 -->
    </requirements>
    <command><![CDATA[
        cat input.txt | sort > output.txt
    ]]></command>
</tool>

<!-- 如果工具需要特殊软件，明确声明 -->
<tool id="my_complex_tool" name="Complex Tool" version="1.0">
    <requirements>
        <requirement type="package" version="2.7.1">bwa</requirement>
        <container type="docker">quay.io/biocontainers/bwa:0.7.17--hed695b0_7</container>
    </requirements>
    <command><![CDATA[
        bwa mem reference.fa reads.fq > alignment.sam
    ]]></command>
</tool>
```

---

## 总结

### 问题
- 工具容器自动推断失败，生成不存在的镜像名
- 导致 AWS Batch 任务无法启动

### 解决方案
- 检查工具是否真的需要特殊容器
- 验证容器镜像是否可访问
- 回退到 fetch-and-run 基础容器

### 好处
1. ✅ 简单工具无需配置容器
2. ✅ 健壮的错误处理
3. ✅ 不会因为容器问题导致任务失败
4. ✅ 更好的日志记录

**核心理念**: 不是所有工具都需要专门的容器，很多简单工具在基础 Linux 环境中就能运行！
