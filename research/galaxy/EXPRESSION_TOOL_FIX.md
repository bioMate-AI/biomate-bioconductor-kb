# Galaxy Cloud Executor - Expression Tool Fix (修复 #5)

## 问题描述

Expression工具（如 `pick_value`）在云执行时失败：

```
Tool Container: none (direct execution)
Running in direct execution mode (no container isolation)
python: can't open file '_evaluate_expression_.py': [Errno 2] No such file or directory
ERROR: Script failed at line 40
Working directory: /host-tmp
```

## 根本原因

Expression工具是Galaxy的特殊工具类型，需要：

1. **Python执行脚本** (`_evaluate_expression_.py`)
   - Galaxy在job.prepare()时动态生成
   - 内容: `from galaxy_ext.expressions.handle_job import run; run()`
   - 存储在job的working directory

2. **Expression输入文件** (`expression_inputs.json`)
   - 包含表达式定义和输入参数
   - 也存储在working directory

3. **特殊的命令行格式**
   - `cd ../; python _evaluate_expression_.py`
   - 需要改变目录到父目录执行

但在云执行模式下：
- ❌ 这些文件没有被上传到S3
- ❌ `cd ../` 导致在错误的目录执行
- ❌ fetch-and-run没有下载working directory文件

## 修复方案

### 修复 1: 上传extra_filenames到S3

**文件**: `galaxy_job_runner.py:1032-1046`

在job.prepare()之后，上传所有extra_filenames：

```python
# Step 2.5: Upload extra files (e.g., expression scripts, tool-generated files)
if hasattr(job_wrapper, 'extra_filenames') and job_wrapper.extra_filenames:
    self.logger.info(f"[{job_id}] Uploading {len(job_wrapper.extra_filenames)} extra file(s)")
    for extra_file in job_wrapper.extra_filenames:
        try:
            if Path(extra_file).exists():
                filename = Path(extra_file).name
                s3_key = f"jobs/{job_id}/working/{filename}"
                self.logger.info(f"[{job_id}] Uploading extra file: {filename}")
                s3_client.upload_file(extra_file, s3_bucket, s3_key)
        except Exception as e:
            self.logger.warning(f"[{job_id}] Could not upload extra file: {e}")
```

### 修复 2: 下载working directory文件

**文件**: `fetch_and_run.sh:98-104`

在下载inputs之后，下载working files：

```bash
# Step 2.5: Download working directory files (e.g., expression scripts)
WORKING_S3_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/working/"
if aws s3 ls "${WORKING_S3_PREFIX}" --region "${AWS_REGION}" > /dev/null 2>&1; then
    echo "[2.5/4] Downloading working directory files..."
    aws s3 sync "${WORKING_S3_PREFIX}" "${WORK_DIR}/" --region "${AWS_REGION}" --quiet
    echo "[OK] Downloaded working files to ${WORK_DIR}/"
fi
```

### 修复 3: 重写expression命令行

**文件**: `galaxy_job_runner.py:373-383`

在`_rewrite_command_line_paths()`中添加特殊处理：

```python
# Special handling for expression tools (Fix #5)
# Expression tools use "cd ../; python _evaluate_expression_.py"
# We need to remove the "cd ../" part since files are in working directory
if '_evaluate_expression_.py' in command_line:
    self.logger.info(f"[{job_id}] Detected expression tool command, rewriting...")
    # Remove "cd ../;" or "cd ..;" or any variation
    rewritten = re.sub(r'cd\s+\.\./?\s*;?\s*', '', rewritten)
    rewritten = rewritten.strip()
    self.logger.info(f"[{job_id}] Rewritten expression command: {rewritten}")
    return rewritten
```

## 修复前后对比

### 原始命令行
```bash
cd ../; python _evaluate_expression_.py
```

### 问题
- `cd ../` 从 `/host-tmp/galaxy_job_538` 移动到 `/host-tmp`
- `_evaluate_expression_.py` 不在 `/host-tmp`，在 `/host-tmp/galaxy_job_538/`
- 文件找不到，执行失败

### 修复后命令行
```bash
python _evaluate_expression_.py
```

### 结果
- ✅ 在正确的工作目录执行
- ✅ `_evaluate_expression_.py` 已从S3下载到工作目录
- ✅ `expression_inputs.json` 也在工作目录
- ✅ Python脚本可以找到并执行

## 工作流程

### 1. Job准备阶段 (Galaxy本地)
```
job_wrapper.prepare()
  ↓
ExpressionTool.exec_before_job()
  ↓
expressions.write_evalute_script(working_directory)
  ↓
生成 _evaluate_expression_.py
  ↓
添加到 job_wrapper.extra_filenames
```

### 2. 上传阶段 (galaxy_job_runner)
```
遍历 job_wrapper.extra_filenames
  ↓
对每个文件:
  - s3_key = f"jobs/{job_id}/working/{filename}"
  - s3_client.upload_file(local_path, bucket, s3_key)
  ↓
上传到 s3://bucket/jobs/538/working/_evaluate_expression_.py
上传到 s3://bucket/jobs/538/working/expression_inputs.json
```

### 3. 执行阶段 (fetch-and-run容器)
```
下载 job_script.sh
  ↓
下载 inputs/ (如果有)
  ↓
下载 working/ 文件
  - _evaluate_expression_.py
  - expression_inputs.json
  ↓
执行: python _evaluate_expression_.py
  ↓
Python加载 expression_inputs.json
  ↓
执行expression逻辑
  ↓
生成输出文件
  ↓
上传 outputs/ 到S3
```

## 修改的文件

### 1. galaxy_job_runner.py
- **1032-1046行**: 上传extra_filenames
- **373-383行**: 重写expression命令行

### 2. fetch_and_run.sh
- **98-104行**: 下载working directory文件

### 3. 需要重新构建的镜像
- `galaxy-fetch-and-run` Docker镜像

## 重新构建fetch-and-run镜像

```bash
cd /Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run

# 构建新镜像
./build_and_push.sh

# 或手动构建
docker build -t <AWS_ACCOUNT>.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest .
docker push <AWS_ACCOUNT>.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest
```

## 测试验证

### 预期日志 - fetch-and-run容器
```
[2/4] Downloading input files from S3...
[WARN] No input files found (expression tools usually don't need inputs)

[2.5/4] Downloading working directory files...
[OK] Downloaded working files to /host-tmp/galaxy_job_538/

[3/4] Executing job script...
Running in direct execution mode (no container isolation)
Starting Galaxy tool execution...
Executing tool command...
python _evaluate_expression_.py
✅ Expression evaluation successful
```

### 预期日志 - Galaxy
```
[Job 538] Uploading 2 extra file(s)
[Job 538] Uploading extra file: _evaluate_expression_.py
[Job 538] Uploading extra file: expression_inputs.json
[Job 538] Detected expression tool command, rewriting...
[Job 538] Rewritten expression command: python _evaluate_expression_.py
```

## 相关文件位置

### Expression工具相关代码
- `/lib/galaxy/tools/expressions/script.py` - 脚本生成
- `/lib/galaxy/tools/__init__.py:3203` - ExpressionTool类
- `/lib/galaxy_ext/expressions/` - Expression执行引擎

### 修复文件
- `galaxy_job_runner.py` - 云执行runner
- `fetch_and_run.sh` - AWS Batch执行脚本

## 其他受益的工具类型

这个修复不仅支持expression工具，也支持其他需要working directory文件的工具：
- Expression tools (pick_value, etc.)
- Upload tools (某些情况)
- Interactive tools (配置文件)
- 任何使用job_wrapper.extra_filenames的工具

## 已知限制

### Working Directory大小
- 默认情况下，working files会完整下载到容器
- 对于大型working files，可能影响性能
- 建议: 优化expression工具避免生成大文件

### Python环境要求
- Expression工具需要 `galaxy_ext` Python包
- fetch-and-run镜像必须包含Galaxy的Python环境
- 当前实现: fetch-and-run基于Galaxy镜像，包含所需依赖

---

**更新时间**: 2025-10-28 22:00 (UTC+8)
**状态**: ✅ 代码修复完成，待重新构建镜像和测试
**影响**: Expression工具和所有使用extra_filenames的工具
**优先级**: 🔴 高 - 阻塞expression工具执行
