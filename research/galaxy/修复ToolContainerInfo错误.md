# 修复 ToolContainerInfo 对象不可订阅错误

## 问题描述

运行 `simple_cloud_workflow.ga` 时，云执行器无法提交任务到AWS Batch，报错：

```
ERROR galaxy_cloud.galaxy_workflow.galaxy_job_runner.GalaxyCloudJobRunner
Failed to queue job 16: 'ToolContainerInfo' object is not subscriptable
```

前台显示：`failed to submit job to cloud executor`

## 根本原因

在 `galaxy_job_runner.py` 的 `_create_job_spec()` 方法中，代码尝试使用字典式访问（`container_info['image']`）来获取容器信息，但是：

- `tool_registry.get_tool_container()` 返回的是 `ToolContainerInfo` **dataclass对象**，需要使用属性访问（`container_info.image`）
- `tool_registry.get_default_container()` 返回的是**字典**，需要使用字典访问（`container_info['image']`）

代码混淆了这两种不同的返回类型。

## 错误代码位置

**文件**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**行号**: 201-209

```python
# 错误的代码
container_info = future.result(timeout=30)

if not container_info:
    container_info = self.tool_registry.get_default_container()

# 这里假设 container_info 总是字典，但实际上可能是 ToolContainerInfo 对象
container_spec = ContainerSpec(
    image=container_info['image'],  # ❌ 错误：对象不能用 [] 访问
    command=container_info.get('command'),
    ...
)
```

## 修复方案

分别处理两种返回类型：

```python
# 修复后的代码
container_info = future.result(timeout=30)

if not container_info:
    # get_default_container() 返回字典
    default_container = self.tool_registry.get_default_container()
    image = default_container['image']
    command = default_container.get('command')
    working_dir = default_container.get('working_dir', '/galaxy-central')
    env_vars = default_container.get('env', {})
    resources = default_container.get('resources', {})
else:
    # container_info 是 ToolContainerInfo dataclass - 使用属性访问
    image = container_info.image
    command = container_info.command
    working_dir = container_info.working_dir
    env_vars = container_info.env
    resources = container_info.resources

# 使用统一的变量构建 ContainerSpec
container_spec = ContainerSpec(
    image=image,
    command=command,
    args=self._build_command_args(job_wrapper),
    env=self._build_environment(job_wrapper, job_destination, env_vars),
    working_dir=working_dir
)
```

## 修改的文件

1. **galaxy_job_runner.py** - 主要修复
   - `_create_job_spec()` 方法：分别处理对象和字典两种类型
   - `_build_environment()` 方法：参数从 `container_info: Dict` 改为 `env_vars: Dict`
   - `_determine_resources()` 方法：参数从 `container_info: Dict` 改为 `resources: Dict`

## ToolContainerInfo 数据类定义

位置：`lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/models.py:159-169`

```python
@dataclass
class ToolContainerInfo:
    """Information about a tool's container"""
    tool_id: str
    image: str
    tag: str = "latest"
    registry: str = "quay.io/biocontainers"
    command: Optional[List[str]] = None
    env: Dict[str, str] = field(default_factory=dict)
    working_dir: str = "/galaxy-central"
    resources: Dict[str, Any] = field(default_factory=dict)
```

## 测试验证

### 1. 重启 Galaxy

```bash
pkill -f "python.*run.py"
PYTHONPATH=lib GALAXY_CONFIG_FILE=config/galaxy.yml \
  GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
  sh run.sh --daemon
```

### 2. 验证服务启动

```bash
curl http://localhost:8080/api/version
# 应该返回: {"version_major":"25.1","version_minor":"dev0"}
```

### 3. 重新运行 Workflow

在 Galaxy Web UI 中：
1. 打开 `Workflow` → `Simple Cloud Test Workflow`
2. 点击 `Run`
3. 选择输入数据
4. 点击 `Run workflow`

### 4. 监控云执行

检查后台日志：
```bash
tail -f galaxy.log | grep "galaxy_cloud"
```

应该看到：
```
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Queued job 19 for cloud execution
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Submitted Galaxy job 19 as cloud job batch-job-xxx
```

检查 AWS Batch：
```bash
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING
```

## 相关文件

- **Bug修复**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
- **数据模型**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/models.py`
- **工具注册**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/tool_registry.py`
- **转换器**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/converter.py` (已正确处理两种类型)

## 注意事项

`converter.py` 文件已经正确处理了这两种类型：

```python
# converter.py:305-314 (正确的实现)
if isinstance(container_info, ToolContainerInfo):
    full_image = container_info.image  # 对象属性访问
    base_command = container_info.command
    working_dir = container_info.working_dir
else:
    full_image = container_info['image']  # 字典访问
    base_command = container_info.get('command')
    working_dir = container_info.get('working_dir', '/data')
```

这是正确的模式，`galaxy_job_runner.py` 也应该遵循这个模式。

## 下一步

修复完成后，workflow应该能够成功提交到AWS Batch：
1. ✅ 数据上传成功（使用本地执行）
2. ✅ Workflow导入成功（UUID格式正确）
3. ✅ Workflow运行开始（不再有"ToolContainerInfo不可订阅"错误）
4. ⏳ 等待AWS Batch执行任务
5. ⏳ 验证S3数据传输
6. ⏳ 验证CloudWatch日志
7. ⏳ 验证结果输出

---

**修复时间**: 2025-10-20
**影响范围**: Galaxy Cloud Executor - AWS Batch 集成
**修复状态**: ✅ 已完成并重启Galaxy
