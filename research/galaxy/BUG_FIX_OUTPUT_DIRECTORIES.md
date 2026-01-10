# Bug 修复: 输出文件目录不存在

## 问题描述

### 错误日志
```
bash: line 26: /galaxy_execution/datasets/objects/6/b/a/dataset_6ba122cf-95f2-4cbc-8d04-c24ab8463c9c.dat: No such file or directory
```

### 根本原因分析

#### 1. 初步判断
最初以为是**输入文件**不存在,但经过日志分析发现:

```
[594] Total input_datasets associations: 0
[594] Uploaded 0 input file(s)
```

Job 594 **没有任何输入数据集**!

#### 2. 深入分析
检查 job script 发现命令是:

```bash
yes -- 'GeneID__tc__...' | head -n $times >> '/galaxy_execution/datasets/objects/6/b/a/dataset_6ba122cf-95f2-4cbc-8d04-c24ab8463c9c.dat'
```

这是一个**输出重定向** (`>>`),不是读取输入文件!

#### 3. 根本问题
命令尝试写入 `/galaxy_execution/datasets/objects/6/b/a/dataset_xxx.dat`,但父目录 `/galaxy_execution/datasets/objects/6/b/a/` 不存在!

**现有脚本只创建了**:
- ✅ 输入文件的 symlinks
- ❌ 输出文件的目录

---

## 修复方案

### 修改文件
[lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py)

### 修改方法
`_generate_universal_job_script` (lines 778-816)

### 修改内容

#### Before:
```python
# Add symlink commands for each input dataset
job = job_wrapper.get_job()
for input_assoc in job.input_datasets:
    if input_assoc.dataset and input_assoc.dataset.dataset:
        try:
            from pathlib import Path
            original_path = input_assoc.dataset.dataset.get_file_name()
            filename = Path(original_path).name
            script += f'mkdir -p "$(dirname "{original_path}")"\n'
            script += f'ln -sf "${{GALAXY_INPUT_DIR}}/{filename}" "{original_path}"\n'
        except Exception as e:
            self.logger.warning(f"Could not create symlink command: {e}")

script += f"""
# Change to working directory
cd "$GALAXY_WORK_DIR"

# Execute the rewritten command
{command}
"""
```

#### After:
```python
# Add symlink commands for each input dataset
job = job_wrapper.get_job()
from pathlib import Path

for input_assoc in job.input_datasets:
    if input_assoc.dataset and input_assoc.dataset.dataset:
        try:
            original_path = input_assoc.dataset.dataset.get_file_name()
            filename = Path(original_path).name
            script += f'mkdir -p "$(dirname "{original_path}")"\n'
            script += f'ln -sf "${{GALAXY_INPUT_DIR}}/{filename}" "{original_path}"\n'
        except Exception as e:
            self.logger.warning(f"Could not create symlink command for input: {e}")

script += """
# Create directories for output datasets (so writes to absolute paths work)
"""

# ✅ NEW: Add directory creation for each output dataset
for output_assoc in job.output_datasets:
    if output_assoc.dataset and output_assoc.dataset.dataset:
        try:
            output_path = output_assoc.dataset.dataset.get_file_name()
            script += f'mkdir -p "$(dirname "{output_path}")"\n'
        except Exception as e:
            self.logger.warning(f"Could not create directory command for output: {e}")

script += f"""
# Change to working directory
cd "$GALAXY_WORK_DIR"

# Execute the rewritten command
{command}
"""
```

---

## 修复效果

### 生成的 Job Script

#### Before:
```bash
#!/bin/bash
# Create symlinks for input datasets (so original absolute paths work)
# (如果有输入文件,会在这里创建 symlinks)

# Change to working directory (standard execution location)
cd "$GALAXY_WORK_DIR"

# Execute the rewritten command
yes -- 'data' | head -n $times >> '/galaxy_execution/datasets/objects/6/b/a/dataset_xxx.dat'
# ❌ 失败: 目录 /galaxy_execution/datasets/objects/6/b/a/ 不存在
```

#### After:
```bash
#!/bin/bash
# Create symlinks for input datasets (so original absolute paths work)
# (如果有输入文件,会在这里创建 symlinks)

# Create directories for output datasets (so writes to absolute paths work)
mkdir -p "/galaxy_execution/datasets/objects/6/b/a"
mkdir -p "/galaxy_execution/datasets/objects/7/e/3"
# ... (为每个输出文件创建父目录)

# Change to working directory (standard execution location)
cd "$GALAXY_WORK_DIR"

# Execute the rewritten command
yes -- 'data' | head -n $times >> '/galaxy_execution/datasets/objects/6/b/a/dataset_xxx.dat'
# ✅ 成功: 目录已存在,可以写入文件
```

---

## 通用性保证

### ✅ 完全通用的解决方案

1. **适用于所有工具**:
   - 通过循环处理所有 `output_datasets`
   - 不依赖工具类型或名称
   - 自动为每个输出文件创建目录

2. **处理各种输出场景**:
   - 单个输出文件
   - 多个输出文件
   - 深层目录结构
   - 无输出文件的情况 (循环不执行任何操作)

3. **健壮性**:
   - 使用 `mkdir -p` (创建父目录,已存在不报错)
   - `$(dirname ...)` 动态提取父目录路径
   - Try-except 错误处理

### ❌ 没有特殊逻辑

- 没有硬编码的路径
- 没有针对特定工具的判断
- 没有 if-else 分支逻辑

---

## 与之前修复的关系

### 修复序列

1. **修复 1**: 添加输入文件上传诊断日志
   - 目的: 诊断为什么没有输入文件
   - 结果: 发现 `input_datasets` 为空

2. **修复 2**: 获取完整 BioContainers Docker 标签
   - 目的: 解决镜像不存在问题
   - 结果: 从 API 获取完整标签 (含构建信息)

3. **修复 3** (本次): 创建输出文件目录
   - 目的: 解决输出文件写入失败
   - 结果: 为所有输出文件预先创建目录

### 三个修复的关系

```
问题报告: 文件路径不存在
    ↓
修复 1: 添加诊断日志
    ↓
发现: 不是输入文件问题,是输出文件问题
    ↓
修复 3: 创建输出目录
    ↓
✅ 解决: 输出文件可以正常写入
```

---

## 测试验证

### 1. 重启 Galaxy

```bash
pkill -f "python.*galaxy"
GALAXY_CONFIG_FILE=config/galaxy.yml \
GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
sh run.sh
```

### 2. 重新运行 Workflow

使用相同的 RNA-Seq workflow。

### 3. 验证生成的 Job Script

```bash
# 等待新 job 提交
# 假设新 job ID 是 600

# 检查生成的 job script
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/600/job_script.sh - | grep -A5 "output datasets"
```

**期望看到**:
```bash
# Create directories for output datasets (so writes to absolute paths work)
mkdir -p "/galaxy_execution/datasets/objects/6/b/a"
mkdir -p "/galaxy_execution/datasets/objects/7/e/3"
...
```

### 4. 验证容器执行

```bash
# 查看 AWS Batch 任务日志
aws logs tail /aws/batch/job --follow
```

**期望结果**:
- ✅ 不再出现 "No such file or directory" 错误
- ✅ 输出文件成功创建
- ✅ 工具执行完成

---

## 潜在问题排查

### 如果仍然失败

#### 问题 1: 输出路径仍然不存在

**可能原因**:
- `output_datasets` 为空或未正确关联
- 路径提取失败

**调查**:
```bash
# 检查日志
grep "output_assoc" logs/galaxy_startup_*.log
grep "output_path" logs/galaxy_startup_*.log
```

#### 问题 2: 权限问题

**可能原因**:
- 容器内无权限创建目录
- `/galaxy_execution/datasets/objects/` 不存在

**解决**:
检查 `fetch_and_run_universal.sh` 是否创建了 `$OBJECTS_DIR`:

```bash
# 在 fetch_and_run_universal.sh 中
OBJECTS_DIR="$DATASETS_ROOT/objects"
mkdir -p "$OBJECTS_DIR"
```

#### 问题 3: 路径冲突

**可能原因**:
- 输入和输出使用相同路径
- 输出路径与工作目录冲突

**解决**:
添加日志记录创建的每个目录,便于调试。

---

## 后续优化

### 可能的改进

1. **批量创建目录**:
   ```bash
   # 收集所有需要的目录
   mkdir -p /galaxy_execution/datasets/objects/{6/b/a,7/e/3,8/c/d}
   ```

2. **预创建标准目录**:
   在 `fetch_and_run_universal.sh` 中预先创建常用的目录结构:
   ```bash
   mkdir -p "$OBJECTS_DIR"/{0..9}/{0..9}/{0..9}
   ```

3. **添加调试日志**:
   在 job script 中添加:
   ```bash
   echo "Created output directories:"
   find /galaxy_execution/datasets/objects -type d | head -20
   ```

---

## 总结

### 问题本质

这不是输入文件的问题,而是**输出文件的父目录不存在**的问题。

### 解决思路

**通用方法**:
1. 从 `job.output_datasets` 获取所有输出文件路径
2. 为每个输出文件路径创建父目录 (`mkdir -p $(dirname path)`)
3. 在执行命令之前完成目录创建

### 适用范围

✅ 所有需要写入绝对路径输出文件的工具
✅ 任何 Galaxy workflow
✅ 不需要了解工具具体行为

### 关键设计原则

**Environment Consistency > Command Rewriting**

我们不重写命令中的路径,而是:
1. 保持命令中的原始绝对路径
2. 创建必要的目录结构
3. 让工具按预期写入原始路径

这就是"通用"的本质!

---

**修复日期**: 2025-10-29
**修复者**: Claude Code
**状态**: ✅ 已修复,准备测试
