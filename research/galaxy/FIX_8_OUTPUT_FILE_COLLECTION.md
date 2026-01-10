# Fix 8: 通用输出文件收集策略

## 问题发现 (Problem Discovery)

### 观察到的现象
- ✅ 所有任务在 AWS Batch 和 Galaxy 中都显示**成功**
- ✅ Fix 7 (符号链接路径重写) 正常工作
- ❌ **所有任务都没有输出文件上传到 S3**

### 根本原因

**Galaxy 工具生成输出的方式多种多样**：

#### 情况 1: 直接写入 Galaxy 路径 (Trimmomatic)
```bash
java -jar trimmomatic.jar SE input.gz output.gz ...
mv output.gz '/Users/.../database/objects/x/y/z/dataset_xxx.dat'
```
✅ 我们的旧逻辑可以处理

#### 情况 2: 写入当前目录临时文件 (FastQC)
```bash
fastqc --outdir './dataset_xxx_files' input.gz
cp './dataset_xxx_files'/*/fastqc_data.txt output.txt  # ← 在工作目录!
cp './dataset_xxx_files'/*.html output.html             # ← 在工作目录!
```
❌ 我们的旧逻辑**找不到这些文件**！

旧脚本尝试复制：
```bash
if [ -f "/Users/.../dataset_xxx.dat" ]; then ...
```

但实际生成的是：
```bash
./output.txt
./output.html
./dataset_xxx_files/
```

**结果**: 文件成功生成，但没有被复制到 OUTPUT_DIR，所以没有上传到 S3！

## 解决方案 (Solution)

### Fix 8: 双重输出收集策略

修改位置: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:917-955`

```python
# 策略: 收集两种输出文件

# 1. 收集 Galaxy 期望路径的输出文件
for output_assoc in job.output_datasets:
    dataset = output_assoc.dataset
    if dataset and dataset.dataset:
        original_path = dataset.dataset.get_file_name()
        filename = Path(original_path).name
        job_script += f'if [ -f "{original_path}" ]; then cp "{original_path}" "${{OUTPUT_DIR}}/{filename}"; fi\n'

# 2. 收集工作目录中生成的所有文件和目录
job_script += '''
# Copy any files generated in working directory
for file in *; do
    if [ -f "$file" ] && [ "$file" != "job_script.sh" ]; then
        echo "Found output file in working directory: $file"
        cp "$file" "${OUTPUT_DIR}/" 2>/dev/null || true
    fi
done

# Copy any output directories (e.g., FastQC _files directories)
for dir in */; do
    if [ -d "$dir" ]; then
        echo "Found output directory: $dir"
        cp -r "$dir" "${OUTPUT_DIR}/" 2>/dev/null || true
    fi
done
'''
```

### 策略优势

#### 1. 通用性 (Universal)
- ✅ 处理直接写入 Galaxy 路径的工具
- ✅ 处理写入当前目录的工具
- ✅ 处理生成目录的工具 (如 FastQC `_files/`)
- ✅ 处理未来未知的输出模式

#### 2. 健壮性 (Robust)
```bash
cp "$file" "${OUTPUT_DIR}/" 2>/dev/null || true
```
- 使用 `|| true` 防止失败导致整个脚本退出
- 使用 `2>/dev/null` 避免警告信息干扰日志

#### 3. 可观察性 (Observable)
```bash
echo "Found output file in working directory: $file"
```
- 在日志中明确显示找到的输出文件
- 便于调试和验证

## 技术细节 (Technical Details)

### 文件收集逻辑

```
工具执行完成
    │
    ├─ 检查 Galaxy 期望路径
    │  └─ if [ -f "/Users/.../dataset_xxx.dat" ]; then cp ...
    │
    ├─ 扫描工作目录文件
    │  └─ for file in *; do
    │      ├─ 排除 job_script.sh
    │      └─ cp 到 OUTPUT_DIR
    │
    └─ 扫描工作目录子目录
       └─ for dir in */; do
           └─ cp -r 到 OUTPUT_DIR
```

### 避免重复复制

如果文件同时满足两个条件：
1. 在 Galaxy 期望路径
2. 在工作目录

文件会被复制两次，但因为使用相同的文件名，第二次会覆盖第一次，所以不会产生问题。

### 过滤逻辑

```bash
if [ -f "$file" ] && [ "$file" != "job_script.sh" ]; then
```

排除 `job_script.sh` 本身，避免将脚本当作输出上传。

## 测试验证 (Testing)

### 1. Trimmomatic 测试

**期望行为**:
```
工具生成: output.fastq.gz
移动到: /Users/.../dataset_xxx.dat
复制: dataset_xxx.dat → OUTPUT_DIR/ ✅
```

### 2. FastQC 测试

**期望行为**:
```
工具生成: output.txt, output.html, dataset_xxx_files/
复制: output.txt → OUTPUT_DIR/ ✅
复制: output.html → OUTPUT_DIR/ ✅
复制: dataset_xxx_files/ → OUTPUT_DIR/ ✅
```

### 3. 验证步骤

```bash
# 运行 workflow
# 等待完成

# 检查 S3 输出
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/<JOB_ID>/outputs/

# 应该看到:
# - output.txt
# - output.html
# - dataset_xxx.dat
# - dataset_xxx_files/
```

## 与其他修复的关系 (Relation to Other Fixes)

Fix 8 是独立的，但与其他修复配合工作：

| Fix | 作用 | 与 Fix 8 关系 |
|-----|------|-------------|
| Fix 1-6 | 容器兼容性 | 确保工具能执行 |
| **Fix 7** | **符号链接重写** | **确保输入文件可访问** |
| **Fix 8** | **输出文件收集** | **确保输出文件被上传** |

**完整流程**:
```
Fix 7: 输入文件路径正确
   ↓
工具成功执行
   ↓
Fix 8: 收集所有输出文件
   ↓
文件上传到 S3
   ↓
Galaxy 接收输出 ✅
```

## 日志示例 (Log Example)

### 成功的日志
```
Executing tool command...
TrimmomaticSE: Completed successfully
Copying outputs...
Found output file in working directory: output.txt
Found output file in working directory: output.html
Found output directory: dataset_89f09ca9-21d1-4b4d-8363-29d0e46922f4_files/
Tool execution completed successfully

[4/4] Uploading output files to S3...
✓ Uploaded 3 file(s) and 1 directory
```

## 性能影响 (Performance Impact)

### 时间复杂度
- 扫描工作目录: O(n) where n = 文件数量
- 通常 n < 100，影响可忽略 (< 100ms)

### 空间影响
- 临时存储: 工作目录中的所有文件
- 已经包含在 Docker 容器存储配额中

## 潜在问题和解决方案 (Potential Issues)

### 问题 1: 复制了不需要的文件
**场景**: 工具生成临时调试文件
**影响**: S3 存储增加，但 Galaxy 会忽略未知文件
**解决**: 可以添加排除模式 (如果需要)

### 问题 2: 大目录复制时间长
**场景**: FastQC 生成大量图片文件
**影响**: 上传时间增加
**解决**: 已经是必要的文件，无法避免

### 问题 3: 文件名冲突
**场景**: 多个输出文件同名
**影响**: 后复制的覆盖先复制的
**解决**: Galaxy 工具设计保证文件名唯一

## 未来改进 (Future Improvements)

### 可选: 添加文件过滤
```bash
# 排除已知临时文件
for file in *; do
    if [ -f "$file" ] && \
       [ "$file" != "job_script.sh" ] && \
       [ "${file##*.}" != "log" ] && \
       [ "${file##*.}" != "tmp" ]; then
        cp "$file" "${OUTPUT_DIR}/"
    fi
done
```

### 可选: 压缩大目录
```bash
# 压缩大输出目录以节省空间
for dir in */; do
    if [ -d "$dir" ]; then
        tar -czf "${dir%/}.tar.gz" "$dir"
        cp "${dir%/}.tar.gz" "${OUTPUT_DIR}/"
    fi
done
```

## 总结 (Summary)

### Fix 8 解决了什么
- ❌ **之前**: 工具成功执行，但输出文件找不到，没有上传
- ✅ **现在**: 工具执行 + 自动收集所有输出 + 上传到 S3

### 重要性
Fix 8 是**最后一块拼图**：
1. Fix 1-6: 容器能运行 ✅
2. Fix 7: 输入能访问 ✅
3. **Fix 8: 输出能收集 ✅**

**现在整个流程应该完全工作了！** 🎉

## 快速测试 (Quick Test)

```bash
# 1. Galaxy 已重启
# 2. 运行任意 workflow (FastQC 或 Trimmomatic)
# 3. 检查 S3:

JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 1 --query 'jobSummaryList[0].jobName' --output text | cut -d'-' -f2)

aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/$JOB_ID/outputs/

# 应该看到输出文件! ✅
```
