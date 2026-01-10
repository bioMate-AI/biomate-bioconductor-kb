# 测试 Fix 7: 符号链接路径重写

## 当前状态 (Current Status)

✅ **Fix 7 已实现并部署**
✅ **Galaxy 已重启，新代码生效**
✅ **环境变量传递已验证正确**

## 测试步骤 (Test Steps)

### 1. 运行 Trimmomatic Workflow

```bash
# 在浏览器中打开 Galaxy
open http://localhost:8080

# 或者直接访问
# 运行之前失败的 Trimmomatic workflow
```

### 2. 监控日志 - 确认 Fix 7 应用

```bash
# 打开新终端，监控 Galaxy 日志
tail -f logs/galaxy_startup_*.log | grep -E "(Rewriting|symlink|Fix 7)"
```

**期望看到**:
```
[job_384] Rewriting script for cloud execution (making it container-compatible)
[job_384] Fixed 2 occurrences of 'readlink -e' → 'readlink -f' for BusyBox compatibility
[job_384] Adding Trimmomatic JAR path fallback logic
[job_384] Rewriting 1 symlink path(s) in tool command
[job_384] Rewrote symlink: /Users/renyuankai/.../dataset_xxx.dat → ${INPUT_DIR}/dataset_xxx.dat
[job_384] Script rewriting completed - now compatible with any cloud container
```

### 3. 下载并验证重写后的脚本

```bash
# 等待任务提交到 AWS Batch
# 从日志中找到 job ID (例如: 384)

# 下载重写后的脚本
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/384/job_script.sh /tmp/rewritten_384.sh

# 检查符号链接命令
grep "ln -s" /tmp/rewritten_384.sh
```

**期望看到**:
```bash
# ✅ 正确: 使用 ${INPUT_DIR} 变量
ln -s "${INPUT_DIR}/dataset_a7dcd028-9b6b-4c78-8f7a-11d05508c5fa.dat" fastq_in.'fastqsanger.gz'

# ❌ 错误: 如果还是绝对路径，说明 Fix 7 未生效
# ln -s '/Users/renyuankai/...' fastq_in.'fastqsanger.gz'
```

### 4. 检查 AWS Batch 执行

```bash
# 查看最新任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 获取任务 ID
JOB_ID=$(aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING --query 'jobSummaryList[0].jobId' --output text)

# 实时查看日志
aws logs tail /aws/batch/job --follow --log-stream-names $JOB_ID
```

**期望看到** (与之前对比):

#### 之前 (Job 383 - 失败) ❌
```
Running docker with stdin script execution:
  Input dir: /tmp/galaxy_job_383/inputs -> /galaxy_inputs
  Output dir: /tmp/galaxy_job_383/outputs -> /galaxy_outputs

Starting Galaxy tool execution...
Found Trimmomatic adapters at: /usr/local/share/trimmomatic-0.38-0/adapters
Executing tool command...
TrimmomaticSE: Started with arguments: ...

❌ Exception in thread "main" java.io.FileNotFoundException: fastq_in.fastqsanger.gz (No such file or directory)

Copying outputs...
Tool execution completed successfully
⚠ No output files found
```

#### 现在 (Job 384 - 应该成功) ✅
```
Running docker with stdin script execution:
  Input dir: /tmp/galaxy_job_384/inputs -> /galaxy_inputs
  Output dir: /tmp/galaxy_job_384/outputs -> /galaxy_outputs

Starting Galaxy tool execution...
Found Trimmomatic adapters at: /usr/local/share/trimmomatic-0.38-0/adapters
Executing tool command...
TrimmomaticSE: Started with arguments:
-threads 6 fastq_in.fastqsanger.gz fastq_out.fastqsanger.gz SLIDINGWINDOW:4:20 MINLEN:36

✅ Input Read Pairs: XXXXX Both Surviving: YYYYY Forward Only Surviving: ZZZ Reverse Only Surviving: AAA Dropped: BBB
✅ TrimmomaticSE: Completed successfully

Copying outputs...
✅ Uploaded 1 output file(s)
```

## 验证清单 (Verification Checklist)

- [ ] Galaxy 日志显示 "Rewriting X symlink path(s)"
- [ ] 下载的脚本中 ln -s 使用 `${INPUT_DIR}/filename`
- [ ] AWS 日志不再有 FileNotFoundException
- [ ] AWS 日志显示 "Completed successfully"
- [ ] 有输出文件上传到 S3
- [ ] Galaxy UI 中任务状态变为 "Success" (绿色)

## 路径变换验证 (Path Transformation Verification)

### 完整路径流程

```
1. Galaxy 本地路径:
   /Users/renyuankai/work/biometa/galaxy/database/objects/a/7/d/dataset_a7dcd028.dat

2. 提取文件名:
   dataset_a7dcd028-9b6b-4c78-8f7a-11d05508c5fa.dat

3. 上传到 S3:
   s3://galaxy-cloud-data-1760241377/jobs/384/inputs/dataset_a7dcd028.dat

4. Fetch-and-Run 下载:
   /tmp/galaxy_job_384/inputs/dataset_a7dcd028.dat

5. 设置环境变量:
   GALAXY_INPUT_DIR=/tmp/galaxy_job_384/inputs

6. 传递到工具容器:
   docker run -v /tmp/galaxy_job_384/inputs:/galaxy_inputs:ro \
              -e GALAXY_INPUT_DIR=/galaxy_inputs

7. 脚本中设置:
   INPUT_DIR="${GALAXY_INPUT_DIR}"  # → /galaxy_inputs

8. 符号链接 (重写后):
   ln -s "${INPUT_DIR}/dataset_a7dcd028.dat" fastq_in.gz
   # 展开为:
   ln -s "/galaxy_inputs/dataset_a7dcd028.dat" fastq_in.gz

9. 文件位置:
   /galaxy_inputs/dataset_a7dcd028.dat ← 文件实际存在! ✅

10. 工具访问:
    fastq_in.gz → /galaxy_inputs/dataset_a7dcd028.dat → 成功读取! ✅
```

## 调试技巧 (Debugging Tips)

### 如果仍然失败

#### 检查 1: 确认脚本重写生效
```bash
# 下载脚本
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/<JOB_ID>/job_script.sh -

# 搜索 ln -s 命令
grep -n "ln -s" job_script.sh

# 应该看到 ${INPUT_DIR}，不应该看到 /Users/
```

#### 检查 2: 确认文件已下载
```bash
# 从 AWS 日志中查看
# 应该看到: "✓ Downloaded X input file(s)"
```

#### 检查 3: 确认环境变量传递
```bash
# 从 AWS 日志中查看
# 应该看到:
#   -e GALAXY_INPUT_DIR="/galaxy_inputs"
#   -e GALAXY_OUTPUT_DIR="/galaxy_outputs"
```

#### 检查 4: 查看工具容器内部
```bash
# 修改 fetch_and_run.sh 临时添加调试
# 在 docker run 命令后添加:
docker run --rm -i \
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \
    ... \
    bash -c "ls -la /galaxy_inputs && cat" < "${SCRIPT_FILE}"
    # ↑ 添加 ls 查看文件是否存在

# 然后重新构建并推送镜像
```

## 成功标志 (Success Indicators)

### Galaxy UI
- 任务状态: ✅ Success (绿色)
- 输出数据集: 有绿色的输出文件
- 日志: 没有错误消息

### AWS Batch
- 任务状态: SUCCEEDED
- 退出码: 0
- 日志: "Completed successfully"

### S3 输出
```bash
# 检查输出文件
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/384/outputs/

# 应该看到输出文件
dataset_xxx.dat
```

## 下一步测试 (Next Tests)

完成 Trimmomatic 测试后，测试其他工具：

1. **FastQC** (简单工具)
2. **Bowtie2** (复杂工具)
3. **多步骤 Workflow** (测试多个工具连续执行)

每个都应该"零配置"成功运行！

---

**准备好了吗？开始测试吧！🚀**
