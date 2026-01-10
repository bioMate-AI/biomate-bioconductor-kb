# Galaxy Cloud Executor - Container Resolution Fix

## 问题总结

在AWS Batch运行Galaxy workflow时，遇到了两个关键的容器解析问题：

### 问题 1: Docker Tag格式不兼容

**错误日志**:
```
Tool Container: quay.io/biocontainers/text_processing:9.3+galaxy1
docker: invalid reference format
```

**根本原因**:
- Docker镜像tag不支持 `+` 符号
- Docker tag regex: `^[\w][\w.-]{0,127}$` (只允许 `[a-zA-Z0-9_.-]`)
- Galaxy工具版本使用 `9.3+galaxy1` (Semantic Versioning格式)
- BioContainers Docker镜像使用 `9.3--galaxy1` (用 `--` 替换 `+`)

**修复**: 在 `tool_registry.py` 中添加了 `_normalize_docker_tag()` 方法
```python
def _normalize_docker_tag(self, tag: str) -> str:
    """Replace '+' with '--' for Docker compatibility"""
    if not tag:
        return tag
    return tag.replace('+', '--')
```

### 问题 2: 工具ID与容器名称不匹配

**错误日志**:
```
Tool Container: quay.io/biocontainers/text_processing:9.3--galaxy1
Error response from daemon: unauthorized: access to the requested resource is not authorized
```

**根本原因**:
- Galaxy **工具ID** (text_processing) ≠ **Conda包名** (coreutils) ≠ **容器镜像名**
- BioContainers镜像是基于Conda包构建的，使用包名而非工具名
- 之前的实现直接使用tool.id来查找容器，导致查找错误的镜像

**实际映射**:
```xml
<!-- text_processing tool XML -->
<tool id="text_processing" ...>
    <requirements>
        <requirement type="package" version="9.3">coreutils</requirement>
    </requirements>
</tool>
```

| Galaxy Tool ID | Conda Package | Container Image |
|----------------|---------------|-----------------|
| text_processing | coreutils | quay.io/biocontainers/coreutils:9.3 |
| tp_replace_in_line | coreutils | quay.io/biocontainers/coreutils:9.3 |
| pick_value | pick_value | quay.io/biocontainers/pick_value:0.2.0 |

**修复**: 在 `galaxy_job_runner.py` 中修改容器查找逻辑

```python
# 从tool.requirements中提取实际的Conda包名
if hasattr(job_wrapper.tool, 'requirements') and job_wrapper.tool.requirements:
    packages = getattr(job_wrapper.tool.requirements, 'packages', [])
    if packages:
        primary_req = packages[0]  # 主要依赖包
        package_name = getattr(primary_req, 'name', None)
        package_version = getattr(primary_req, 'version', None)

# 使用包名而非工具ID查找容器
lookup_name = package_name if package_name else tool_id
container_info = await self.tool_registry.get_tool_container(lookup_name, lookup_version)
```

## 修复后的工作流程

### 1. 容器解析流程

```
Galaxy Workflow Job
    ↓
Job Wrapper (tool.id = "text_processing")
    ↓
Extract Requirements (tool.requirements.packages[0].name = "coreutils")
    ↓
Tool Registry Lookup ("coreutils", version="9.3")
    ↓
Normalize Tag ("9.3" → "9.3")  # No + sign in this case
    ↓
Resolve Container (quay.io/biocontainers/coreutils:9.3)
    ↓
AWS Batch Job Environment
    env:
      TOOL_CONTAINER_IMAGE: quay.io/biocontainers/coreutils:9.3
    ↓
Fetch-and-Run Container
    ↓
Docker Pull (✅ SUCCESS - image exists!)
    ↓
Tool Container Execution
```

### 2. Tag规范化示例

| Galaxy Version | Docker Tag | Status |
|---------------|------------|--------|
| 9.3+galaxy1 | 9.3--galaxy1 | ✅ Normalized |
| 2.11.40.8+galaxy0 | 2.11.40.8--galaxy0 | ✅ Normalized |
| 1.0.0+build123 | 1.0.0--build123 | ✅ Normalized |
| 9.3 | 9.3 | ✅ No change needed |
| latest | latest | ✅ No change needed |

## 修改的文件

### 1. tool_registry.py
**位置**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/tool_registry.py`

**新增方法**:
- `_normalize_docker_tag()`: 将 `+` 转换为 `--`

**修改方法**:
- `_biocontainer_to_tool_container()`: 应用tag规范化
- `_resolve_by_pattern()`: 应用tag规范化

### 2. galaxy_job_runner.py
**位置**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**修改位置**: `queue_job()` 方法中的容器解析部分 (第896-931行)

**主要改动**:
- 从 `job_wrapper.tool.requirements.packages` 提取实际的Conda包名
- 优先使用包名而非工具ID进行容器查找
- 添加详细的日志记录包名和版本信息

## 测试验证

### 测试脚本
1. `test_docker_tag_fix.py` - 验证tag规范化
2. `test_package_resolution.py` - 验证包名解析

### 测试结果
```bash
$ PYTHONPATH=lib python3 test_docker_tag_fix.py
✅ All tests passed! The fix is working correctly.

$ PYTHONPATH=lib python3 test_package_resolution.py
✅ Package resolution working correctly:
   coreutils:9.3 → quay.io/biocontainers/coreutils:9.3
```

### 手动验证
```bash
$ docker pull quay.io/biocontainers/coreutils:9.3
9.3: Pulling from biocontainers/coreutils
✅ SUCCESS
```

## 重启Galaxy应用修复

```bash
# 停止Galaxy
pkill -f "gunicorn.*galaxy"

# 启动Galaxy
PYTHONPATH=lib sh run.sh --daemon

# 等待启动完成 (约1-2分钟)
curl http://localhost:8080/api/version
```

## 验证修复

### 查看日志
修复后的日志应该显示：

```
[528] Tool text_processing requires package: coreutils==9.3
[528] Will use tool container: quay.io/biocontainers/coreutils:9.3
```

### AWS Batch日志
AWS容器日志应该显示：

```
Tool Container: quay.io/biocontainers/coreutils:9.3
Pulling tool container image...
9.3: Pulling from biocontainers/coreutils
✅ Pull complete
```

## 后续优化建议

### 1. 创建静态映射配置
对于常用工具，可以创建静态映射文件避免运行时解析：

```yaml
# config/tool_containers.yaml
tools:
  text_processing:
    image: quay.io/biocontainers/coreutils
    tag: "9.3"
    registry: quay.io/biocontainers

  pick_value:
    image: quay.io/biocontainers/pick_value
    tag: "0.2.0"
    registry: quay.io/biocontainers
```

### 2. 缓存容器映射
在tool_registry中添加持久化缓存，避免重复查询BioContainers API。

### 3. 预拉取常用镜像
在fetch-and-run容器镜像中预先包含常用的工具容器，减少运行时拉取时间。

### 4. 容器镜像验证
在job提交前验证容器镜像是否存在，提前发现问题。

## 参考资料

1. [Docker Image Tag Specification](https://docs.docker.com/engine/reference/commandline/tag/)
2. [Docker Issue #16304 - Allow + in tag names](https://github.com/moby/moby/issues/16304)
3. [BioContainers Documentation](https://biocontainers-edu.readthedocs.io/)
4. [Galaxy Tool Requirements](https://docs.galaxyproject.org/en/master/dev/schema.html#tool-requirements)

## 更新日志

- **2025-10-28**: 初始修复
  - 添加Docker tag规范化 (`+` → `--`)
  - 实现从tool requirements提取包名
  - 更新容器查找逻辑使用包名
  - 添加测试脚本验证修复

---

**状态**: ✅ 修复完成，待重启Galaxy验证
**影响**: 所有使用云执行的Galaxy workflows
**优先级**: 🔴 高 - 阻塞所有云上工作流执行
