# 迁移到通用方案 - 完整指南

## 当前状态

你已经有了两个关键组件：
1. **UniversalPathRewriter** - 通用路径重写器 ✅
2. **fetch_and_run_universal.sh** - 通用执行脚本 ✅

现在需要集成到galaxy_job_runner中。

---

## 迁移步骤

### 第1步：导入UniversalPathRewriter

在 `galaxy_job_runner.py` 开头添加导入：

```python
from .universal_path_rewriter import UniversalPathRewriter
```

### 第2步：简化 `_submit_fetch_and_run_job` 方法

这是核心修改。当前方法有很多特殊处理，我们要用通用方案替换：

#### 当前代码结构（需要替换的部分）：

```python
async def _submit_fetch_and_run_job(self, job_wrapper, job_destination):
    # ... 前面的设置代码 ...

    # ❌ 删除：Tool-specific container logic
    if job_wrapper.tool:
        tool_type = getattr(job_wrapper.tool, 'tool_type', 'default')
        if tool_type in skip_container_types:
            ...  # 特殊处理
        else:
            # 从requirements提取包名
            if hasattr(job_wrapper.tool, 'requirements'):
                ...  # 更多特殊逻辑

    # ❌ 删除：Special upload logic for extra_filenames
    if hasattr(job_wrapper, 'extra_filenames') and job_wrapper.extra_filenames:
        ...  # 特殊处理

    # ❌ 删除：Custom _rewrite_command_line_paths
    command_line = self._rewrite_command_line_paths(command_line, job, job_id)

    # ❌ 删除：Custom job_script generation with special cases
    job_script = f"""#!/bin/bash
    set -e
    # NOTE: set -o pipefail is intentionally NOT used
    ...
    """
```

#### 新代码结构（使用通用方案）：

```python
async def _submit_fetch_and_run_job(self, job_wrapper, job_destination):
    """
    Submit job using universal fetch-and-run approach.

    This method now uses UniversalPathRewriter for ALL tools,
    eliminating the need for tool-specific logic.
    """
    job_id = str(job_wrapper.job_id)
    job = job_wrapper.get_job()

    # ... 前面的基本设置（保持不变）...

    # ✅ NEW: Create universal path rewriter
    path_rewriter = UniversalPathRewriter(job_wrapper, job_id)

    # ✅ NEW: Universal file upload (no special cases)
    await self._universal_upload_job_files(
        job_wrapper,
        job_id,
        s3_bucket,
        s3_client,
        path_rewriter
    )

    # ✅ NEW: Get command line and rewrite using universal logic
    command_line = job_wrapper.runner_command_line or job_wrapper.command_line
    if not command_line:
        job_wrapper.prepare()
        command_line = job_wrapper.runner_command_line or job_wrapper.command_line

    rewritten_command = path_rewriter.rewrite_command(command_line)

    # ✅ NEW: Generate universal job script
    job_script = self._generate_universal_job_script(
        rewritten_command,
        path_rewriter
    )

    # ... 后面的S3上传和job提交（略微简化）...
```

### 第3步：实现新的辅助方法

#### 3.1 通用文件上传

```python
async def _universal_upload_job_files(
    self,
    job_wrapper,
    job_id: str,
    s3_bucket: str,
    s3_client,
    path_rewriter: UniversalPathRewriter
):
    """
    Upload ALL job files using universal structure.

    No special handling needed - just organize by type.
    """
    from pathlib import Path

    self.logger.info(f"[{job_id}] Uploading job files (universal structure)")

    # 1. Upload input datasets
    for input_assoc in job_wrapper.get_job().input_datasets:
        if input_assoc.dataset and input_assoc.dataset.dataset:
            try:
                file_path = input_assoc.dataset.dataset.get_file_name()
                if Path(file_path).exists() and Path(file_path).stat().st_size > 0:
                    filename = Path(file_path).name
                    s3_key = f"jobs/{job_id}/inputs/{filename}"
                    s3_client.upload_file(file_path, s3_bucket, s3_key)
                    self.logger.debug(f"[{job_id}] Uploaded input: {filename}")
            except Exception as e:
                self.logger.warning(f"[{job_id}] Failed to upload input: {e}")

    # 2. Upload working directory files (if job was prepared)
    if hasattr(job_wrapper, 'extra_filenames') and job_wrapper.extra_filenames:
        for extra_file in job_wrapper.extra_filenames:
            try:
                if Path(extra_file).exists():
                    filename = Path(extra_file).name
                    s3_key = f"jobs/{job_id}/working/{filename}"
                    s3_client.upload_file(extra_file, s3_bucket, s3_key)
                    self.logger.debug(f"[{job_id}] Uploaded working file: {filename}")
            except Exception as e:
                self.logger.warning(f"[{job_id}] Failed to upload working file: {e}")

    # 3. Upload configs (if any)
    # Galaxy may generate config files in the working directory
    # These are automatically handled by extra_filenames

    self.logger.info(f"[{job_id}] File upload complete")
```

#### 3.2 通用job script生成

```python
def _generate_universal_job_script(
    self,
    command: str,
    path_rewriter: UniversalPathRewriter
) -> str:
    """
    Generate job script using universal approach.

    No tool-specific logic - just a clean execution wrapper.
    """
    env_vars = path_rewriter.get_environment_variables()

    script = f"""#!/bin/bash
# Universal Galaxy Cloud Execution Script
# Auto-generated - works for ANY Galaxy tool

set -e  # Exit on error
# NOTE: pipefail NOT used - breaks legitimate pipes (yes | head, etc.)

# Environment (set by fetch-and-run)
# These are already exported, but shown here for reference:
{chr(10).join(f'# {k}=${k}' for k in env_vars.keys())}

# Change to working directory (standard execution location)
cd "$GALAXY_WORK_DIR"

echo "Executing tool command..."
echo "Working directory: $(pwd)"

# Execute the rewritten command
{command}

echo "Tool execution complete"
"""

    return script
```

### 第4步：更新container image selection

目前我们有复杂的tool container选择逻辑。简化为：

```python
def _get_tool_container_image(self, job_wrapper) -> Optional[str]:
    """
    Get tool-specific container image (if needed).

    Returns None for tools that run in fetch-and-run container.
    """
    if not job_wrapper.tool:
        return None

    # Check if tool explicitly requests a container
    if hasattr(job_wrapper.tool, 'requirements') and job_wrapper.tool.requirements:
        packages = getattr(job_wrapper.tool.requirements, 'packages', [])
        if packages:
            # Get from tool registry
            primary_req = packages[0]
            package_name = getattr(primary_req, 'name', None)
            package_version = getattr(primary_req, 'version', None)

            if package_name:
                # Look up container
                container_info = await self.tool_registry.get_tool_container(
                    package_name,
                    package_version
                )
                if container_info and container_info.image:
                    tag = container_info.tag or 'latest'
                    return f"{container_info.image}:{tag}"

    # Default: no tool-specific container
    return None
```

### 第5步：更新fetch-and-run镜像

替换原来的 `fetch_and_run.sh`：

```bash
cd /Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run

# 备份原文件
mv fetch_and_run.sh fetch_and_run.sh.old

# 使用新的通用版本
mv fetch_and_run_universal.sh fetch_and_run.sh

# 重新构建镜像
./build_and_push.sh
```

---

## 对比：改动范围

### 删除的代码（不再需要）：

1. ❌ Tool type检查 (`if tool_type in skip_container_types`)
2. ❌ Expression工具特殊处理
3. ❌ Extra files特殊上传逻辑
4. ❌ 自定义的 `_rewrite_command_line_paths`
5. ❌ 复杂的job script生成with多个if-else
6. ❌ Special handling for `cd ../`
7. ❌ Docker tag normalization in multiple places

### 新增的代码（更简单）：

1. ✅ `UniversalPathRewriter` (已完成)
2. ✅ `_universal_upload_job_files` (简单循环)
3. ✅ `_generate_universal_job_script` (单一模板)
4. ✅ `fetch_and_run_universal.sh` (已完成)

### 代码量对比：

- **当前**: ~1571行 (galaxy_job_runner.py)
- **预期**: ~800行 (简化50%)

---

## 测试计划

### 1. 单元测试

测试UniversalPathRewriter：

```bash
PYTHONPATH=lib python3 lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/universal_path_rewriter.py
```

✅ 已通过

### 2. 集成测试

使用真实workflow测试：

- [ ] Text processing workflow (测试basic tools)
- [ ] Expression tools workflow (测试pick_value等)
- [ ] Multi-step workflow (测试数据传递)
- [ ] Complex bioinformatics workflow (测试real-world case)

### 3. 回归测试

确保所有之前能工作的workflow仍然工作：

- [ ] Workflow A (简单测试)
- [ ] Workflow B (expression工具)
- [ ] Workflow C (多步骤)

---

## 迁移时间估算

| 任务 | 预计时间 | 状态 |
|------|----------|------|
| UniversalPathRewriter实现 | 2小时 | ✅ 完成 |
| fetch_and_run_universal.sh | 1小时 | ✅ 完成 |
| 修改galaxy_job_runner | 3小时 | ⏳ 进行中 |
| 重新构建镜像 | 0.5小时 | 待开始 |
| 测试和调试 | 2-4小时 | 待开始 |
| **总计** | **8.5-10.5小时** | **60%完成** |

---

## 下一步行动

### 立即行动（今天完成）：

1. **修改galaxy_job_runner.py**
   - 导入UniversalPathRewriter
   - 替换 `_submit_fetch_and_run_job` 中的特殊逻辑
   - 实现 `_universal_upload_job_files`
   - 实现 `_generate_universal_job_script`

2. **替换fetch_and_run.sh**
   - 使用通用版本
   - 重新构建Docker镜像

3. **测试**
   - 运行简单workflow验证基本功能
   - 逐步测试更复杂的workflow

### 预期结果：

- ✅ 任何Galaxy workflow都能在云上运行
- ✅ 不需要为新工具添加特殊处理
- ✅ 代码简洁，易维护
- ✅ 真正的"通用"方案

---

## 需要我帮你？

我可以：

1. **直接修改galaxy_job_runner.py** - 应用上述所有改动
2. **创建测试脚本** - 验证通用方案
3. **逐步指导** - 你来做，我指导每一步

你选哪个？
