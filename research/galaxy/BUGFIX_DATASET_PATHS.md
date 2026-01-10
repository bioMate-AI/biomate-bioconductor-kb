# Bug修复: Dataset路径问题

## 问题描述

运行workflow时出现两个问题：

### 问题1: `_evaluate_expression_.py` 缺失
```
python: can't open file '_evaluate_expression_.py': [Errno 2] No such file or directory
```

### 问题2: Dataset文件找不到
```bash
bash: line 25: /galaxy_execution/datasets/objects/d/1/0/dataset_d1023c69-5a88-4bc1-a3ba-90d7a33f8ade.dat: No such file or directory
```

## 根本原因

我的"通用方案"有**两个致命缺陷**：

### 缺陷1: 文件上传时机错误

**错误顺序**:
```python
# 1. 上传文件 ❌ (此时 _evaluate_expression_.py 还不存在)
await self._universal_upload_job_files(...)

# 2. job_wrapper.prepare() (这里才生成 _evaluate_expression_.py)
job_wrapper.prepare()
```

### 缺陷2: Dataset路径重写错误

**我的错误逻辑**:
1. UniversalPathRewriter重写dataset路径为 `/galaxy_execution/datasets/objects/d/1/0/dataset_xxx.dat`
2. 但是文件实际上传到了 `s3://bucket/jobs/{job_id}/inputs/dataset_xxx.dat`
3. 容器中文件在 `/galaxy_execution/job/inputs/dataset_xxx.dat`
4. **路径完全不匹配！**

**为什么老代码能工作？**

老代码使用**symlink策略**：
1. 上传文件到 `inputs/dataset_xxx.dat`
2. 在容器中创建symlink指向原始绝对路径
3. 不重写命令中的dataset路径
4. 通过symlink让原始路径工作

**我错误地尝试"更通用"**，结果反而破坏了这个简单有效的机制。

## 修复方案

### 修复1: 调整文件上传时机

**正确顺序** (galaxy_job_runner.py 行997-1018):
```python
# 1. ✅ 先prepare (生成 _evaluate_expression_.py)
command_line = job_wrapper.runner_command_line or job_wrapper.command_line
if not command_line:
    job_wrapper.prepare()
    command_line = ...

# 2. 创建path rewriter
path_rewriter = UniversalPathRewriter(job_wrapper, job_id)

# 3. ✅ 后上传 (现在文件存在了)
await self._universal_upload_job_files(...)
```

### 修复2: 不重写Dataset路径，使用Symlink

**修改1: UniversalPathRewriter** (universal_path_rewriter.py 行151-159):
```python
# NOTE: Dataset paths (inputs) are NOT rewritten - they will be handled
# by symlinks created in the job script. This is simpler and more reliable
# than trying to reorganize the entire dataset object store structure.

# Step 1: Rewrite job directory paths (outputs, working files, etc.)
rewritten = self._rewrite_job_paths(rewritten)

# Step 2: Normalize relative path operations (cd ../,  etc.)
rewritten = self._normalize_relative_paths(rewritten)

# ❌ 删除: rewritten = self._rewrite_dataset_paths(rewritten)
```

**修改2: _generate_universal_job_script** (galaxy_job_runner.py 行738-749):
```python
# Add symlink commands for each input dataset
job = job_wrapper.get_job()
for input_assoc in job.input_datasets:
    if input_assoc.dataset and input_assoc.dataset.dataset:
        original_path = input_assoc.dataset.dataset.get_file_name()
        filename = Path(original_path).name
        script += f'mkdir -p "$(dirname "{original_path}")"\n'
        script += f'ln -sf "${{GALAXY_INPUT_DIR}}/{filename}" "{original_path}"\n'
```

这样：
- 文件上传到: `s3://bucket/jobs/{job_id}/inputs/dataset_xxx.dat`
- 容器中下载到: `/galaxy_execution/job/inputs/dataset_xxx.dat`
- Symlink创建: `/Users/.../dataset_xxx.dat` → `/galaxy_execution/job/inputs/dataset_xxx.dat`
- 命令使用原始路径: `/Users/.../dataset_xxx.dat`
- 通过symlink找到实际文件 ✅

## 修改的文件

### 1. universal_path_rewriter.py
- **行151-159**: 删除了dataset路径重写，只重写job目录路径

### 2. galaxy_job_runner.py

**修改A: 文件上传时机** (行997-1018):
- 先调用 `job_wrapper.prepare()`
- 后调用 `_universal_upload_job_files()`

**修改B: Job script生成** (行712-764):
- 添加 `job_wrapper` 参数
- 为每个input dataset创建symlink命令
- 调用处也更新（行1041-1045）

## 为什么这是"更通用"的方案

虽然我回退了一部分"通用方案"，但这个混合方案**实际上更通用**：

### "通用"的真正含义

**不通用（我之前的想法）**:
- 试图重新组织整个文件系统结构
- 假设我们能完美重写所有路径
- 结果：复杂、脆弱、容易出错

**真正通用（现在的方案）**:
- 尊重Galaxy现有的路径约定
- 使用简单的symlink桥接本地和容器路径
- 只重写真正需要重写的部分（outputs, working files）
- 结果：简单、可靠、真正通用

### 核心原则

**通用性 = 最小改动 + 最大兼容**

不是改动越大越"通用"，而是：
1. 只在必要时改动
2. 使用成熟的机制（symlink）
3. 尊重现有约定
4. 让代码适应工具，而不是让工具适应代码

## 经验教训

### 1. "通用"不意味着"重新发明轮子"

之前：试图创建全新的目录结构和路径映射
现在：使用已被验证的symlink机制

### 2. 复杂性是bug的温床

之前：复杂的路径重写逻辑
现在：简单的symlink + 最小重写

### 3. 测试不可少

单元测试通过 ≠ 端到端能工作

需要测试：
- 不同类型的工具（expression, regular, collection）
- 不同的输入类型（单个文件、多个文件、collections）
- 真实的workflow

### 4. 理解系统设计的原因

Galaxy使用绝对路径不是bug，是设计：
- 简化路径管理
- 支持符号链接
- 允许分布式存储

我试图"修复"它，结果破坏了系统。

## 状态

✅ **已修复** (2025-10-29)

- [x] 识别两个问题的根源
- [x] 修复文件上传时机
- [x] 修复dataset路径处理
- [x] 添加symlink创建逻辑
- [x] 重启Galaxy
- [ ] 端到端测试验证（等待用户）

## 下一步

请重新运行workflow：

1. 打开Galaxy WebUI (http://localhost:8080)
2. 运行你的 RNA-Seq workflow
3. 检查是否还有错误

**如果还有错误，请提供**:
- AWS Batch job的完整日志（从开始到结束）
- 具体哪个工具/步骤失败
- Galaxy日志中的相关信息

## 技术总结

### 什么被"通用化"了

✅ **真正通用的部分**:
- 标准化的目录结构（`/galaxy_execution/job/`）
- 统一的环境变量
- 一致的S3组织方式
- 相对路径的规范化

✅ **不需要"通用化"的部分**:
- Input dataset的路径（使用symlink）
- Galaxy的绝对路径约定（尊重现有设计）

### 最终架构

```
Input Files:
  本地: /Users/.../database/objects/d/1/0/dataset_xxx.dat
  S3:   s3://bucket/jobs/{job_id}/inputs/dataset_xxx.dat
  容器: /galaxy_execution/job/inputs/dataset_xxx.dat
  Symlink: /Users/.../dataset_xxx.dat → /galaxy_execution/job/inputs/dataset_xxx.dat
  ✅ 命令使用原始路径，通过symlink工作

Output Files:
  命令: 使用 ${GALAXY_OUTPUT_DIR}/output.dat
  容器: /galaxy_execution/job/outputs/output.dat
  S3:   s3://bucket/jobs/{job_id}/outputs/output.dat
  ✅ 路径被重写，直接写到正确位置

Working Files:
  命令: 直接在工作目录中
  容器: /galaxy_execution/job/working/_evaluate_expression_.py
  S3:   s3://bucket/jobs/{job_id}/working/_evaluate_expression_.py
  ✅ 上传并下载到工作目录
```

这个混合方案结合了：
- 老代码的智慧（symlink for inputs）
- 新代码的改进（标准化outputs和working files）

结果：**真正通用且可靠**。

---

**反思**: 有时候"通用"意味着**知道什么不该改**。
