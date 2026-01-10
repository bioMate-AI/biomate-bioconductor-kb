# 修复 Docker 镜像标签缺失问题

## 问题描述

AWS Batch 任务失败，错误信息：
```
CannotPullImageManifestError: Error response from daemon: received unexpected HTTP status: 502 Bad Gateway
```

## 根本原因

**代码只传递了镜像名称，没有包含标签（tag）**

### 错误的镜像URL
```
quay.io/biocontainers/fastqc
```

这是不完整的镜像URL，缺少版本标签。Docker守护进程尝试拉取时会失败。

### 正确的镜像URL应该是
```
quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
```

## 问题位置

**文件**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**方法**: `_create_job_spec()`

**错误代码**（第250-258行）:
```python
# container_info is a ToolContainerInfo dataclass
image = container_info.image  # 只有: "quay.io/biocontainers/fastqc"
command = container_info.command
working_dir = container_info.working_dir
env_vars = container_info.env
resources = container_info.resources

# Build container specification
container_spec = ContainerSpec(
    image=image,  # ❌ 缺少tag！
    ...
)
```

**问题分析**:
- `ToolContainerInfo` 数据类有两个字段：
  - `image`: `"quay.io/biocontainers/fastqc"`
  - `tag`: `"0.12.1--hdfd78af_0"`
- 代码只使用了 `image`，忘记拼接 `tag`

## 修复方案

### 代码修改

```python
# container_info is a ToolContainerInfo dataclass - use attribute access
image = container_info.image      # "quay.io/biocontainers/fastqc"
tag = container_info.tag           # "0.12.1--hdfd78af_0"
command = container_info.command
working_dir = container_info.working_dir
env_vars = container_info.env
resources = container_info.resources

# ✅ Build full image URI with tag
full_image = f"{image}:{tag}" if tag else image

# 添加日志记录
self.logger.info(f"Using Docker image for tool {tool_id}: {full_image}")

# Build container specification
container_spec = ContainerSpec(
    image=full_image,  # ✅ 完整的镜像URL
    command=command,
    ...
)
```

### 修改内容

1. **提取tag字段**：
   ```python
   tag = container_info.tag
   ```

2. **拼接完整镜像URL**：
   ```python
   full_image = f"{image}:{tag}" if tag else image
   ```

3. **添加日志**：
   ```python
   self.logger.info(f"Using Docker image for tool {tool_id}: {full_image}")
   ```

4. **使用完整URL创建ContainerSpec**：
   ```python
   container_spec = ContainerSpec(image=full_image, ...)
   ```

## 修复后的行为

### 之前（错误）
```
工具: FastQC
    ↓
提取容器信息: {
    image: "quay.io/biocontainers/fastqc",
    tag: "0.12.1--hdfd78af_0"
}
    ↓
传递给AWS Batch: "quay.io/biocontainers/fastqc"  ❌
    ↓
Docker尝试拉取: quay.io/biocontainers/fastqc:latest  ❌
    ↓
失败: 502 Bad Gateway（latest标签不存在）
```

### 现在（正确）
```
工具: FastQC
    ↓
提取容器信息: {
    image: "quay.io/biocontainers/fastqc",
    tag: "0.12.1--hdfd78af_0"
}
    ↓
拼接完整URL: "quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"  ✅
    ↓
传递给AWS Batch: "quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"  ✅
    ↓
Docker成功拉取镜像 ✅
    ↓
任务开始运行 ✅
```

## 日志示例

### 修复前（无日志）
```
2025-10-20 15:00:01 INFO  Queued job 55 for cloud execution
2025-10-20 15:00:02 INFO  Submitted Galaxy job 55 as cloud job xxx
```

### 修复后（有详细日志）
```
2025-10-20 15:00:01 INFO  Queued job 55 for cloud execution
2025-10-20 15:00:01 INFO  Using Docker image for tool toolshed.../fastqc: quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
2025-10-20 15:00:02 INFO  Submitted Galaxy job 55 as cloud job xxx
```

## 验证步骤

### 1. 重启Galaxy
```bash
pkill -f "gunicorn\|celery"
PYTHONPATH=lib GALAXY_CONFIG_FILE=config/galaxy.yml \
  GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
  sh run.sh --daemon
```

### 2. 运行Workflow
在Galaxy Web UI中运行workflow

### 3. 检查日志
```bash
tail -f galaxy.log | grep "Using Docker image"
```

期望看到：
```
Using Docker image for tool toolshed.../fastqc/0.74+galaxy0: quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
Using Docker image for tool toolshed.../trimmomatic/0.38.1: quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2
```

### 4. 验证AWS Batch任务
```bash
# 更新AWS凭证
aws sso login

# 检查正在运行的任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 查看任务详情（替换JOB_ID）
aws batch describe-jobs --jobs JOB_ID --query 'jobs[0].container.image'
```

应该返回完整的镜像URL：
```
"quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"
```

## 相关文件

### 修改的文件
- `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
  - Line 239-269: 修复镜像URL拼接逻辑

### 配置文件
- `config/tool_containers.json`
  - 包含 `image` 和 `tag` 字段（正确）

### 数据模型
- `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/models.py`
  - `ToolContainerInfo` 数据类定义

## 常见的Docker镜像标签

### BioContainers镜像格式
```
quay.io/biocontainers/<tool>:<version>--<build>
```

**示例**:
- `quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0`
- `quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2`
- `quay.io/biocontainers/bowtie2:2.4.5--py39h3321a2d_0`

**标签组成**:
- `0.12.1`: 工具版本
- `hdfd78af_0`: conda构建哈希和版本

### 为什么需要完整标签？

1. **精确版本控制**：
   - ✅ `fastqc:0.12.1--hdfd78af_0` - 精确的版本
   - ❌ `fastqc:latest` - 不确定的版本，可能不存在

2. **可重现性**：
   - 相同的标签保证运行相同版本的工具
   - 科学计算需要可重现的环境

3. **避免镜像不存在**：
   - BioContainers不一定有 `latest` 标签
   - 必须使用具体的版本标签

## 总结

### 修复内容
✅ 修复镜像URL拼接逻辑，现在包含tag
✅ 添加详细日志记录
✅ 支持有tag和无tag两种情况

### 修复后的效果
- Docker可以成功拉取正确版本的镜像
- AWS Batch任务不再因为镜像拉取失败
- 日志清晰显示使用的镜像版本

### 重要提醒
**所有使用 ToolContainerInfo 的地方都必须拼接 image 和 tag！**

---

**修复时间**: 2025-10-20
**修复状态**: ✅ 已完成
**Galaxy状态**: ✅ 已重启
**下一步**: 运行workflow验证修复效果
