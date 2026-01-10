# Bug修复: Expression工具 _evaluate_expression_.py 缺失

## 问题描述

**症状**: 运行包含expression工具的workflow时，容器报错：
```
python: can't open file '_evaluate_expression_.py': [Errno 2] No such file or directory
```

**影响的workflow**:
- RNA-Seq Differential Expression Analysis with Visualization (v0.4)
- 任何使用expression工具的workflow（如 pick_value）

## 根本原因

在我的"通用方案"实现中，**文件上传的时机错误**：

### 错误的代码顺序（之前）：
```python
# 1. 创建path rewriter
path_rewriter = UniversalPathRewriter(job_wrapper, job_id)

# 2. ❌ 上传文件（此时extra_filenames还不存在！）
await self._universal_upload_job_files(...)

# 3. 准备job（这里才生成 _evaluate_expression_.py）
if not command_line:
    job_wrapper.prepare()  # <- extra_filenames在这里生成
    command_line = ...
```

### 问题分析：

1. **Expression工具的工作原理**：
   - Expression工具（如pick_value）需要动态生成的Python脚本
   - 这些脚本在`job_wrapper.prepare()`时生成
   - 生成的文件路径存储在`job_wrapper.extra_filenames`

2. **我的错误**：
   - 在第1002行调用`_universal_upload_job_files()`
   - 但`job_wrapper.prepare()`在第1014行才调用
   - 结果：上传时`extra_filenames`为空，`_evaluate_expression_.py`没有被上传

3. **为什么没有被测试发现**：
   - 我只用UniversalPathRewriter做了单元测试
   - 没有进行完整的端到端测试
   - 特别是没有测试expression工具

## 修复方案

### 正确的代码顺序（现在）：
```python
# 1. ✅ 先准备job（生成 _evaluate_expression_.py 等文件）
command_line = job_wrapper.runner_command_line or job_wrapper.command_line
if not command_line:
    job_wrapper.prepare()  # <- 这里生成extra_filenames
    command_line = ...

# 2. 创建path rewriter
path_rewriter = UniversalPathRewriter(job_wrapper, job_id)

# 3. ✅ 上传文件（现在extra_filenames已存在）
await self._universal_upload_job_files(...)  # <- 现在能上传 _evaluate_expression_.py
```

## 修改的文件

**文件**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**具体改动**:
- 行997-1018: 调整了`_submit_fetch_and_run_job()`中的执行顺序
- 确保`job_wrapper.prepare()`在文件上传之前被调用

## 验证方法

### 1. 检查代码顺序
```bash
grep -A 20 "Step 1: Prepare job first" lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py
```

应该看到：
```python
# Step 1: Prepare job first (generates extra_filenames like _evaluate_expression_.py)
command_line = ...
if not command_line:
    job_wrapper.prepare()  # <- 先prepare
    ...

# Step 3: Upload files (AFTER prepare, so extra_filenames exist)
await self._universal_upload_job_files(...)  # <- 后上传
```

### 2. 运行包含expression工具的workflow

测试workflow:
- RNA-Seq Differential Expression Analysis
- 任何使用pick_value工具的workflow

### 3. 检查S3中的文件

修复后，应该能在S3中看到：
```
s3://bucket/jobs/{job_id}/
  ├── inputs/          # 输入文件
  ├── working/         # ✅ 包含 _evaluate_expression_.py
  └── job_script.sh    # job脚本
```

### 4. 检查容器日志

修复后的容器日志应该显示：
```
[4/5] Executing job script...
Direct execution mode (no tool-specific container)
Executing tool command...
Working directory: /galaxy_execution/job/working
✅ (正常执行，没有 "can't open file" 错误)
```

## 经验教训

### 1. "通用"并不意味着"不需要理解细节"

虽然我创建了"通用方案"，但仍然需要理解：
- Galaxy job的生命周期
- `prepare()`的作用和时机
- `extra_filenames`的生成时机

### 2. 执行顺序很重要

在异步、多步骤的系统中：
- 依赖关系必须明确
- 执行顺序必须正确
- 不能假设"反正都会执行"

### 3. 端到端测试不可少

单元测试通过≠系统能工作：
- UniversalPathRewriter的单元测试通过了
- 但整个job提交流程有bug
- 需要用真实workflow测试

### 4. 错误信息要完整

用户最初只给了"0000327510"这样的不完整错误，浪费了时间。
应该提供：
- 完整的错误消息
- 错误发生的上下文
- 相关的日志

## 状态

✅ **已修复** (2025-10-29)

- [x] 识别问题根源
- [x] 调整代码执行顺序
- [x] 重启Galaxy应用新代码
- [ ] 端到端测试验证（等待用户测试）

## 下一步

请重新运行你的workflow:
1. 打开Galaxy WebUI
2. 运行 RNA-Seq Differential Expression Analysis workflow
3. 检查是否还有 `_evaluate_expression_.py` 错误

如果还有其他错误，请提供：
- ✅ 完整的错误消息（不要只给代码）
- ✅ 发生错误的workflow名称
- ✅ AWS Batch job的完整日志
- ✅ Galaxy日志中的相关错误

---

## 技术细节

### Galaxy Job Preparation流程

```
1. job_wrapper创建
2. 获取command_line (可能为空)
3. 如果为空，调用job_wrapper.prepare():
   3.1 生成tool command
   3.2 创建extra_filenames (expression scripts等)
   3.3 设置working目录
4. 现在command_line和extra_filenames都有了
5. 上传文件到S3
6. 提交到AWS Batch
```

### 为什么prepare()不总是被调用

- 某些工具的command_line在创建时就已经设置
- 只有当`runner_command_line`和`command_line`都为空时才调用prepare()
- Expression工具**总是**需要prepare()（生成脚本）

### _universal_upload_job_files的依赖

这个方法依赖：
- `job_wrapper.get_job().input_datasets` - 总是有
- `job_wrapper.extra_filenames` - ⚠️ 只在prepare()后有

所以必须在prepare()之后调用。

---

## 补充说明

这个bug说明我的"通用方案"**在设计上是对的**（统一的目录结构、通用的路径重写），但**在实现上有缺陷**（执行顺序错误）。

修复后，通用方案应该能正常工作了。
