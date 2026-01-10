# 容器镜像标签修复

## 问题诊断

### AWS 错误日志
```
Error response from daemon: manifest for quay.io/biocontainers/trimmomatic:latest not found
```

### 根本原因
代码在传递容器镜像时**没有包含正确的版本标签**，导致 Docker 默认使用 `:latest` 标签，但 BioContainers 镜像通常没有 `latest` 标签，只有特定版本标签（如 `:0.38.1--hdfd78af_0`）。

## 问题分析

### 数据结构设计
`ToolContainerInfo` 类设计为分离存储镜像路径和标签：
```python
@dataclass
class ToolContainerInfo:
    image: str          # 应该只包含路径，如 "quay.io/biocontainers/trimmomatic"
    tag: str            # 标签，如 "0.38.1--hdfd78af_0"
```

### Bug 位置

#### Bug 1: `_resolve_by_pattern` 方法
**文件**: `tool_registry.py:243-277`

**问题**:
```python
# 错误：模式包含 :latest 标签
pattern = r'quay.io/biocontainers/\1:latest'
image = template.replace(r'\1', tool_name)  # 结果: "quay.io/biocontainers/trimmomatic:latest"

return ToolContainerInfo(
    image=image,        # 包含标签！
    tag='latest'        # 标签重复！
)
```

**后果**: `image` 字段包含了完整 URI（含标签），导致后续使用时只用 `image` 字段会得到错误的标签。

#### Bug 2: BioContainers 解析
**文件**: `tool_registry.py:185-204`

**问题**:
```python
# 错误：image 包含完整 URI
image = f"quay.io/biocontainers/{actual_image_name}:{version_name}"

return BioContainerInfo(
    image=image,        # 包含标签！
    version=version_name  # 标签重复！
)
```

#### Bug 3: 使用容器信息时
**文件**: `galaxy_job_runner.py:609`

**问题**:
```python
# 错误：只使用 image 字段，没有添加 tag
tool_container_image = container_info.image  # 结果: "quay.io/biocontainers/trimmomatic" (缺少标签)
```

**后果**: 传递给 fetch-and-run 的容器镜像没有标签，Docker 默认使用 `:latest`。

## 解决方案

### 修复 1: `_resolve_by_pattern` 方法
**文件**: [`tool_registry.py:243-277`](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/tool_registry.py#L243-L277)

**修改前**:
```python
patterns = [
    (r'toolshed\.g2\.bx\.psu\.edu/repos/[^/]+/([^/]+)/.*', r'quay.io/biocontainers/\1:latest'),
]

image = template.replace(r'\1', tool_name)  # 包含 :latest
```

**修改后**:
```python
patterns = [
    # 移除 :latest 标签
    (r'toolshed\.g2\.bx\.psu\.edu/repos/[^/]+/([^/]+)/.*', r'quay.io/biocontainers/\1'),
]

# image 只包含路径，不含标签
image = template.replace(r'\1', tool_name)

return ToolContainerInfo(
    image=image,                        # 路径: "quay.io/biocontainers/trimmomatic"
    tag=tool_version or 'latest',       # 标签: "0.38.1" 或 "latest"
)
```

### 修复 2: BioContainers 解析
**文件**: [`tool_registry.py:189-204`](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/tool_registry.py#L189-L204)

**修改前**:
```python
image = f"quay.io/biocontainers/{actual_image_name}:{version_name}"

return BioContainerInfo(
    image=image,  # 包含标签
    version=version_name
)
```

**修改后**:
```python
# 分离路径和标签
image_path = f"quay.io/biocontainers/{actual_image_name}"
full_image_uri = f"{image_path}:{version_name}"

self.logger.info(f"Resolved BioContainer image: {full_image_uri}")

return BioContainerInfo(
    image=image_path,     # 只存储路径
    version=version_name  # 标签分离存储
)
```

### 修复 3: 使用容器信息
**文件**: [`galaxy_job_runner.py:609-612`](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L609-L612)

**修改前**:
```python
if container_info and container_info.image:
    tool_container_image = container_info.image  # 缺少标签
```

**修改后**:
```python
if container_info and container_info.image:
    # 组合镜像路径和标签
    tag = container_info.tag or 'latest'
    tool_container_image = f"{container_info.image}:{tag}"
    # 结果: "quay.io/biocontainers/trimmomatic:0.38.1"
```

## 修复验证

### 预期结果
修复后，日志应该显示：

**Galaxy 日志**:
```
[361] Will use tool container: quay.io/biocontainers/trimmomatic:0.38.1
```

**AWS CloudWatch 日志**:
```
Pulling tool container image...
✓ Successfully pulled quay.io/biocontainers/trimmomatic:0.38.1
Running tool container...
```

**不应该再看到**:
```
✗ Error: manifest for quay.io/biocontainers/trimmomatic:latest not found
```

### 测试步骤

1. **重启 Galaxy**（已完成）
   ```bash
   pkill -f "python.*run.py"
   sh start_galaxy_with_ai.sh
   ```

2. **提交测试任务**
   - 通过 Galaxy Web UI 提交一个 Trimmomatic 或 FastQC 任务

3. **检查 Galaxy 日志**
   ```bash
   tail -f logs/galaxy_startup_*.log | grep "Will use tool container"
   ```
   应该看到完整的镜像 URI（包含版本标签）

4. **检查 AWS Batch 任务**
   ```bash
   # 获取最新任务的日志流
   aws batch describe-jobs --jobs <JOB_ID> --region us-west-2 \
       --query 'jobs[0].attempts[0].container.logStreamName'
   ```

5. **检查 CloudWatch 日志**
   应该看到成功拉取镜像，不再出现 `:latest not found` 错误

## 相关问题

### 为什么三层容器发现都失败了？

从日志可以看到所有工具都使用了 "Fallback"：
```
✓ Fallback: Using parent class container for toolshed.g2.bx.psu.edu/repos/pjbriggs/trimmomatic/trimmomatic/0.38.1
```

**Layer 1 (Tool XML)**: 工具可能没有在 XML 中声明容器
**Layer 2 (BioContainers API)**: API 查询可能失败或超时
**Layer 3 (Auto-build)**: 尚未实现

所以最终使用了父类的 `_resolve_by_pattern` 方法（基于正则匹配），这就是为什么这个 bug 如此关键。

### 长期改进建议

1. **改进 Layer 1**: 确保工具 XML 包含容器声明
2. **改进 Layer 2**: 增加 BioContainers API 的重试逻辑和缓存
3. **实现 Layer 3**: 完成 conda 自动构建功能
4. **添加单元测试**: 测试 `ToolContainerInfo` 的 `image` 和 `tag` 分离

## 修复文件清单

- [x] [`tool_registry.py`](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/tool_registry.py)
  - `_resolve_by_pattern`: 移除模式中的 `:latest`
  - `_query_biocontainers_api`: 分离 `image` 和 `tag`

- [x] [`galaxy_job_runner.py`](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py)
  - 第 609-612 行: 组合 `image` 和 `tag`

- [x] Galaxy 已重启，等待用户测试

## 时间线

- **22:03** - 新任务提交（Job 361）
- **22:06** - AWS 报错: `manifest for trimmomatic:latest not found`
- **22:XX** - 分析代码，发现三个相关 bug
- **22:XX** - 修复三个 bug
- **22:XX** - 重启 Galaxy
- **待测试** - 提交新任务验证修复

## 预期完整流程

修复后的完整工作流程：

1. Galaxy 接收任务 → 调用 `get_tool_container()`
2. Tool Registry 解析容器信息:
   - `image = "quay.io/biocontainers/trimmomatic"`
   - `tag = "0.38.1"`
3. Job Runner 组合完整 URI:
   - `tool_container_image = "quay.io/biocontainers/trimmomatic:0.38.1"`
4. 传递给 fetch-and-run 容器
5. Fetch-and-run 执行:
   ```bash
   docker pull quay.io/biocontainers/trimmomatic:0.38.1  # ✓ 成功
   docker run quay.io/biocontainers/trimmomatic:0.38.1 <command>
   ```
6. 工具执行成功，输出上传到 S3
7. Galaxy 任务状态 → "ok"
