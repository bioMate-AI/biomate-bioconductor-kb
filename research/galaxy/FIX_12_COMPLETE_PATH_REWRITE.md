# Fix 12: 完整的路径重写修复

## 当前问题

从最新的 AWS CloudWatch 日志看，有两个严重问题：

###  1. 输入文件没有被正确链接

```bash
DEBUG: Files in INPUT_DIR:
total 0  # ← 空的！
drwxr-xr-x 2 root root 6 Oct 22 07:15 .
drwxr-xr-x 1 root root 73 Oct 22 07:15 ..
```

但 S3 上有文件：
```bash
$ aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/403/inputs/
2025-10-22 15:12:34     330397 jobs/403/inputs/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat
```

### 2. 符号链接使用了错误的路径

生成的脚本（第 46 行）：
```bash
ln -s 'dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat' 'sample1_fastq_gz.gz'
```

**问题**: 使用相对路径，但文件在 `${INPUT_DIR}` 中！

应该是：
```bash
ln -s "${INPUT_DIR}/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat" 'sample1_fastq_gz.gz'
```

### 3. 工具命令中仍有本地路径

```bash
mkdir -p '/Users/renyuankai/work/biometa/galaxy/database/objects/d/b/c/dataset_dbcde253-803f-4f3a-a06b-e7ba5b732482_files' &&
fastqc --outdir '/Users/renyuankai/work/biometa/galaxy/database/objects/d/b/c/dataset_dbcde253-803f-4f3a-a06b-e7ba5b732482_files'  ...
cp '/Users/renyuankai/work/biometa/galaxy/database/objects/d/b/c/dataset_dbcde253-803f-4f3a-a06b-e7ba5b732482_files'/*/fastqc_data.txt output.txt
```

**Fix 10 没有工作！**

---

## 根本原因分析

### 问题 1: Fix 10 的逻辑错误

[galaxy_job_runner.py:377-378](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L377-L378):

```python
# Map absolute path to simple filename (already symlinked in working dir)
path_mapping[original_path] = filename
```

**错误**: 注释说"already symlinked in working dir"，但符号链接还没创建！

### 问题 2: Fix 7 在脚本中重写符号链接，但没有考虑 Fix 10 的修改

Fix 7 期望在脚本中找到原始的绝对路径：
```python
old_pattern = f"ln -s '{abs_path}'"  # abs_path = /Users/.../dataset_xxx.dat
```

但是 Fix 10 已经将命令行中的路径改为相对路径了：
```python
path_mapping[original_path] = filename  # filename = dataset_xxx.dat
```

结果：Fix 7 找不到需要重写的模式，所以没有任何修改！

### 问题 3: 输入文件下载的路径问题

`fetch_and_run.sh` 下载文件到 `/tmp/galaxy_job_403/inputs/`，但脚本中的符号链接是：
```bash
ln -s 'dataset_xxx.dat' 'target.gz'
```

这会在当前工作目录（`/tmp/work`）查找 `dataset_xxx.dat`，但文件在 `/tmp/galaxy_job_403/inputs/` 中！

---

## Fix 12: 完整重写路径逻辑

### 策略

1. **Fix 10 应该重写 OUTPUT 路径，但保留 INPUT 绝对路径**
2. **Fix 7 负责重写符号链接，使用 `${INPUT_DIR}`**
3. **确保顺序正确**: Fix 10（命令行）→ 脚本生成 → Fix 7（脚本）

### 修改 1: Fix 10 - 只重写输出路径

```python
def _rewrite_command_line_paths(self, command_line: str, job, job_id: str) -> str:
    """
    Rewrite Galaxy command line paths for cloud execution.

    Strategy:
    - Input paths: KEEP original absolute paths (will be symlinked by script)
    - Output paths: Rewrite to /tmp/outputs/
    """
    import re
    from pathlib import Path

    rewritten = command_line

    # Build path mapping - ONLY FOR OUTPUTS
    path_mapping = {}

    # DON'T map input paths - they will be handled by symlinks
    # for input_assoc in job.input_datasets:
    #     ...

    # ONLY map output paths
    for output_assoc in job.output_datasets:
        if output_assoc.dataset and output_assoc.dataset.dataset:
            try:
                original_path = output_assoc.dataset.dataset.get_file_name()
                filename = Path(original_path).name
                # Map absolute path to /tmp/outputs/
                path_mapping[original_path] = f"/tmp/outputs/{filename}"
                # Also map _files directories
                path_mapping[f"{original_path}_files"] = f"/tmp/outputs/{filename}_files"
            except Exception as e:
                self.logger.warning(f"[{job_id}] Could not map output path: {e}")

    # Replace all OUTPUT paths in command line
    replacements = 0
    for old_path, new_path in sorted(path_mapping.items(), key=lambda x: len(x[0]), reverse=True):
        # Replace in single quotes
        if f"'{old_path}'" in rewritten:
            rewritten = rewritten.replace(f"'{old_path}'", f"'{new_path}'")
            replacements += 1
            self.logger.debug(f"[{job_id}] Rewrote output path: '{old_path}' → '{new_path}'")
        # Replace in double quotes
        if f'"{old_path}"' in rewritten:
            rewritten = rewritten.replace(f'"{old_path}"', f'"{new_path}"')
            replacements += 1
            self.logger.debug(f"[{job_id}] Rewrote output path: \"{old_path}\" → \"{new_path}\"")
        # Replace without quotes
        if f" {old_path} " in rewritten:
            rewritten = rewritten.replace(f" {old_path} ", f" {new_path} ")
            replacements += 1

    if replacements > 0:
        self.logger.info(f"[{job_id}] Rewrote {replacements} OUTPUT path(s) in command line")
        self.logger.debug(f"[{job_id}] Rewritten command preview: {rewritten[:300]}...")
    else:
        self.logger.info(f"[{job_id}] No output paths found to rewrite in command line")

    return rewritten
```

### 修改 2: Fix 7 - 改进符号链接重写

```python
# In _rewrite_script_for_cloud()
# Line ~575-624

# ========================================
# Fix 7: Rewrite symlink commands in tool command line
# ========================================
# Problem: Galaxy tool commands create symlinks like:
#   ln -s '/local/absolute/path/dataset_xxx.dat' fastq_in.fastqsanger.gz
# These absolute paths don't exist in containers.
# Solution: Replace absolute paths with ${INPUT_DIR}/filename

try:
    job = job_wrapper.get_job()
    dataset_mapping = {}

    # Build mapping of absolute paths to filenames
    for input_assoc in job.input_datasets:
        dataset = input_assoc.dataset
        if dataset and dataset.dataset:
            try:
                from pathlib import Path
                original_path = dataset.dataset.get_file_name()
                filename = Path(original_path).name
                dataset_mapping[original_path] = filename
                self.logger.debug(f"[{job_id}] Input mapping: {original_path} → {filename}")
            except Exception as e:
                self.logger.warning(f"[{job_id}] Could not map dataset path: {e}")

    # Replace ln -s commands
    if dataset_mapping:
        self.logger.info(f"[{job_id}] Rewriting {len(dataset_mapping)} symlink path(s)")

        for abs_path, filename in dataset_mapping.items():
            # Pattern 1: ln -s '/abs/path' (single quotes)
            old_pattern_single = f"ln -s '{abs_path}'"
            new_pattern_single = f"ln -s \"${{INPUT_DIR}}/{filename}\""

            # Pattern 2: ln -s "/abs/path" (double quotes)
            old_pattern_double = f'ln -s "{abs_path}"'
            new_pattern_double = f"ln -s \"${{INPUT_DIR}}/{filename}\""

            # Pattern 3: ln -s /abs/path (no quotes)
            old_pattern_none = f"ln -s {abs_path}"
            new_pattern_none = f"ln -s \"${{INPUT_DIR}}/{filename}\""

            replaced = False
            if old_pattern_single in rewritten:
                rewritten = rewritten.replace(old_pattern_single, new_pattern_single)
                replaced = True
                self.logger.debug(f"[{job_id}] Rewrote symlink (single quotes): {abs_path}")
            elif old_pattern_double in rewritten:
                rewritten = rewritten.replace(old_pattern_double, new_pattern_double)
                replaced = True
                self.logger.debug(f"[{job_id}] Rewrote symlink (double quotes): {abs_path}")
            elif old_pattern_none in rewritten:
                rewritten = rewritten.replace(old_pattern_none, new_pattern_none)
                replaced = True
                self.logger.debug(f"[{job_id}] Rewrote symlink (no quotes): {abs_path}")

            if not replaced:
                self.logger.warning(
                    f"[{job_id}] Could not find symlink pattern for {abs_path} in script. "
                    f"Searching for any ln -s occurrence..."
                )
                # Debug: show what ln -s commands exist in the script
                import re
                ln_commands = re.findall(r'ln\s+-s\s+[\'"]?([^\s\'"]+)', rewritten)
                self.logger.debug(f"[{job_id}] Found ln -s commands: {ln_commands}")

except Exception as e:
    self.logger.warning(f"[{job_id}] Could not rewrite symlink paths: {e}")
    import traceback
    self.logger.debug(f"[{job_id}] Symlink rewrite error traceback: {traceback.format_exc()}")
```

### 修改 3: 添加脚本前的符号链接创建检查

在生成脚本时，添加检查确保符号链接不会引用不存在的相对路径：

```python
# In _submit_fetch_and_run_job(), after command_line rewriting

# Step 2.5: Verify symlink commands won't use relative paths
import re
ln_commands = re.findall(r"ln\s+-s\s+'?\"?([^'\" ]+)", command_line)
for ln_source in ln_commands:
    if not ln_source.startswith('/') and not ln_source.startswith('$'):
        self.logger.warning(
            f"[{job_id}] Found relative path in ln -s: {ln_source}. "
            f"This will likely fail. Command line may need additional rewriting."
        )
```

---

## 完整修复后的执行流程

### 输入文件处理

1. Galaxy 上传文件到 S3:
   ```
   s3://bucket/jobs/403/inputs/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat
   ```

2. fetch_and_run.sh 下载到容器:
   ```
   /tmp/galaxy_job_403/inputs/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat
   ```

3. 环境变量设置:
   ```
   INPUT_DIR=/tmp/galaxy_job_403/inputs
   ```

4. 脚本中的符号链接（Fix 7 重写后）:
   ```bash
   ln -s "${INPUT_DIR}/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat" 'sample1_fastq_gz.gz'
   # 展开后: ln -s /tmp/galaxy_job_403/inputs/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat sample1_fastq_gz.gz
   # ✅ 文件存在!
   ```

5. 工具命令可以使用符号链接:
   ```bash
   fastqc sample1_fastq_gz.gz
   # 实际读取: /tmp/galaxy_job_403/inputs/dataset_cff36b65-27d6-4e54-b676-56e5e72e54d1.dat
   ```

### 输出文件处理

1. 命令行（Fix 10 重写后）:
   ```bash
   mkdir -p '/tmp/outputs/dataset_xxx_files' &&
   fastqc --outdir '/tmp/outputs/dataset_xxx_files' ...
   ```

2. 工具生成输出:
   ```
   /tmp/outputs/dataset_xxx_files/fastqc_data.txt
   /tmp/outputs/dataset_xxx_files/fastqc_report.html
   ```

3. 脚本收集输出:
   ```bash
   cp -r /tmp/outputs/* "${OUTPUT_DIR}/"
   # ✅ 文件复制到 /tmp/galaxy_job_403/outputs/
   ```

4. fetch_and_run.sh 上传到 S3:
   ```
   s3://bucket/jobs/403/outputs/dataset_xxx_files/
   ```

---

## 实施步骤

### Step 1: 修改 Fix 10

文件: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

位置: Line 348-415

**关键修改**:
- 移除输入路径映射
- 只保留输出路径映射
- 改进日志输出

### Step 2: 修改 Fix 7

文件: Same file

位置: Line 575-624

**关键修改**:
- 检测更多符号链接模式（单引号、双引号、无引号）
- 添加调试日志，显示找到的 ln -s 命令
- 在找不到模式时输出警告

### Step 3: 重新启动 Galaxy

```bash
# 停止 Galaxy
pkill -f "python.*run.py"

# 启动 Galaxy
cd /Users/renyuankai/work/biometa/galaxy
PYTHONPATH=lib sh run.sh --daemon
```

### Step 4: 测试

```bash
# 运行一个简单的 workflow
# 检查日志确认:
# 1. Fix 10 只重写了输出路径
# 2. Fix 7 重写了符号链接
# 3. 输入文件正确链接
# 4. 输出文件正确生成和上传
```

---

## 调试技巧

### 1. 检查生成的脚本

```bash
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/JOB_ID/job_script.sh -

# 查找:
# - ln -s 命令是否使用 ${INPUT_DIR}
# - mkdir -p 命令是否使用 /tmp/outputs
# - fastqc 等工具命令的路径
```

### 2. 检查 Galaxy 日志

```bash
grep "Rewrote.*path" logs/galaxy_startup_*.log
grep "symlink" logs/galaxy_startup_*.log
```

### 3. 检查 CloudWatch 日志

```bash
aws logs filter-log-events \
    --log-group-name /aws/batch/job \
    --filter-pattern "DEBUG" \
    --start-time $(date -u -d '10 minutes ago' +%s)000
```

---

## 预期效果

### Before (当前)

```
❌ ln -s 'dataset_xxx.dat' 'target.gz'
   → 文件不存在（相对路径）

❌ mkdir -p '/Users/.../dataset_xxx_files'
   → 路径不存在（本地绝对路径）

❌ fastqc --outdir '/Users/.../dataset_xxx_files'
   → 无法创建输出目录
```

### After (Fix 12)

```
✅ ln -s "${INPUT_DIR}/dataset_xxx.dat" 'target.gz'
   → 文件: /tmp/galaxy_job_403/inputs/dataset_xxx.dat

✅ mkdir -p '/tmp/outputs/dataset_xxx_files'
   → 目录创建成功

✅ fastqc --outdir '/tmp/outputs/dataset_xxx_files'
   → 输出正确生成
```

---

## 长期改进建议

### 1. 统一路径管理

创建一个专门的路径管理类:

```python
class ContainerPathManager:
    """Manage path translations between Galaxy and containers"""

    def __init__(self, job, input_dir, output_dir):
        self.job = job
        self.input_dir = input_dir    # /tmp/galaxy_job_XXX/inputs
        self.output_dir = output_dir  # /tmp/galaxy_job_XXX/outputs

    def get_input_container_path(self, galaxy_path: str) -> str:
        """Convert Galaxy input path to container path"""
        filename = Path(galaxy_path).name
        return f"{self.input_dir}/{filename}"

    def get_output_container_path(self, galaxy_path: str) -> str:
        """Convert Galaxy output path to container path"""
        filename = Path(galaxy_path).name
        return f"/tmp/outputs/{filename}"

    def rewrite_command_line(self, command: str) -> str:
        """Rewrite ALL paths in command line"""
        # ... implementation
```

### 2. 验证路径重写

在脚本生成后添加验证：

```python
def _validate_script_paths(self, script: str, job_id: str):
    """Validate that no local paths remain in script"""
    import re

    # Check for local absolute paths
    local_paths = re.findall(r'/Users/[^ \n]+', script)
    if local_paths:
        self.logger.error(
            f"[{job_id}] CRITICAL: Found {len(local_paths)} unrewritten local paths in script!"
        )
        for path in local_paths[:5]:  # Show first 5
            self.logger.error(f"[{job_id}]   - {path}")
        raise ValueError(f"Script contains unrewritten local paths")

    # Check for relative ln -s without variables
    bad_symlinks = re.findall(r"ln\s+-s\s+'?([a-z_]+\.dat)", script)
    if bad_symlinks:
        self.logger.warning(
            f"[{job_id}] Found {len(bad_symlinks)} potentially incorrect symlinks"
        )
```

---

## 总结

Fix 12 解决了 Fix 10 和 Fix 7 之间的冲突：

1. **Fix 10**: 只重写输出路径，保留输入绝对路径
2. **Fix 7**: 重写脚本中的符号链接，使用 `${INPUT_DIR}`
3. **顺序**: Fix 10（命令行）→ 脚本生成 → Fix 7（脚本内容）

**核心理念**:
- 输入文件通过符号链接访问（`${INPUT_DIR}/filename`）
- 输出文件直接写入 `/tmp/outputs/`
- 不在命令行中使用相对路径

这样可以确保：
- ✅ 输入文件能被正确找到
- ✅ 输出文件在预期位置生成
- ✅ 没有本地路径残留
- ✅ 脚本在任何容器中都能运行
