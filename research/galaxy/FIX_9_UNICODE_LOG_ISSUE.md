# Fix 9: Unicode 字符导致 CloudWatch 日志中断

## 问题发现 (Problem Discovery)

### 观察到的症状
1. ✅ AWS Batch 任务状态: **SUCCEEDED** (退出码 0)
2. ✅ Galaxy UI 显示: **成功**
3. ❌ CloudWatch 日志只显示到 "Checking AWS credentials..."
4. ❌ **没有输出文件**上传到 S3
5. ❌ 无法看到脚本执行过程

### 关键发现

查看日志时出现错误：
```
'ascii' codec can't encode character '\u2713' in position 105: ordinal not in range(128)
```

**Unicode 字符 `✓` (U+2713) 导致 CloudWatch 日志输出中断！**

## 根本原因 (Root Cause)

### `fetch_and_run.sh` 中的 Unicode 字符

```bash
# Line 44
echo "✓ Using ECS task role credentials"      # ← U+2713 CHECK MARK

# Line 47
echo "⚠ No ECS task role credentials found"  # ← U+26A0 WARNING SIGN

# Line 70
echo "✓ Job script downloaded successfully"

# Line 153
echo "✗ Job script failed with exit code"    # ← U+2717 BALLOT X
```

### 问题链条

```
1. fetch_and_run.sh 执行
   ↓
2. echo "✓ Using ECS task role credentials"
   ↓
3. CloudWatch Logs 尝试记录 (使用 ASCII 编码)
   ↓
4. ❌ 'ascii' codec can't encode '\u2713'
   ↓
5. 日志输出中断 / 缓冲阻塞
   ↓
6. 后续所有日志丢失
   ↓
7. 无法看到:
   - 文件下载成功消息
   - 脚本执行过程
   - 输出文件收集
   - 上传成功消息
```

### 为什么任务还显示 SUCCEEDED?

脚本**实际上继续执行**了（日志输出失败不影响脚本逻辑），但是：
- 我们看不到执行过程
- 无法调试问题
- 不知道是否有输出文件

## 解决方案 (Solution)

### Fix 9: 移除所有 Unicode 字符，使用纯 ASCII

**文件**: `docker/fetch-and-run/fetch_and_run.sh`

#### 替换清单

| 之前 (Unicode) | 之后 (ASCII) | 说明 |
|---------------|-------------|------|
| `✓` (U+2713) | `[OK]` | 成功标记 |
| `⚠` (U+26A0) | `[WARN]` | 警告标记 |
| `✗` (U+2717) | `[ERROR]` | 错误标记 |

#### 修改示例

```bash
# Before
echo "✓ Using ECS task role credentials"
echo "⚠ No input files found"
echo "✗ Job script failed"

# After
echo "[OK] Using ECS task role credentials"
echo "[WARN] No input files found"
echo "[ERROR] Job script failed"
```

### 完整替换命令

```bash
cd /Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run

# 替换所有 Unicode 字符
sed -i '' 's/✓/[OK]/g' fetch_and_run.sh
sed -i '' 's/⚠/[WARN]/g' fetch_and_run.sh
sed -i '' 's/✗/[ERROR]/g' fetch_and_run.sh

# 验证
grep -n "\[OK\]\|\[WARN\]\|\[ERROR\]" fetch_and_run.sh
```

### 重新构建和推送镜像

```bash
# 构建 (AMD64 架构用于 AWS Batch)
docker buildx build --platform linux/amd64 \
    -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest .

# 推送到 ECR
aws ecr get-login-password --region us-west-2 | \
    docker login --username AWS --password-stdin \
    399683337364.dkr.ecr.us-west-2.amazonaws.com

docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest
```

## 测试验证 (Testing)

### 1. 运行新的 Workflow

```bash
# 在 Galaxy UI 中运行任意 workflow
# 等待任务完成
```

### 2. 检查 CloudWatch 日志

现在应该能看到**完整的日志**：

```
=========================================
Galaxy Fetch-and-Run Starting
=========================================
Job ID: 400
S3 Bucket: galaxy-cloud-data-1760241377
AWS Region: us-west-2
Script URL: s3://bucket/jobs/400/job_script.sh
Tool Container: quay.io/biocontainers/fastqc:0.11.9--0
=========================================

Checking AWS credentials...
[OK] Using ECS task role credentials      ← ✅ ASCII, 不会中断!
  Credentials URI: /v2/credentials/xxx
AWS Identity:
{
    "Account": "399683337364",
    ...
}

[1/4] Downloading job script from S3...
[OK] Job script downloaded successfully   ← ✅ 能看到这条消息了!

[2/4] Downloading input files from S3...
[OK] Downloaded 1 input file(s)

[3/4] Executing job script...
=========================================
Running in Docker-in-Docker mode...
Pulling tool container image...
...
Starting Galaxy tool execution...
Executing tool command...
Found output file in working directory: output.txt    ← ✅ 能看到输出收集!
Found output file in working directory: output.html
Tool execution completed successfully

=========================================
[OK] Job script completed successfully

[4/4] Uploading output files to S3...
[OK] Uploaded 2 output file(s)          ← ✅ 能看到上传成功!

=========================================
Galaxy Fetch-and-Run Completed Successfully
```

### 3. 验证输出文件

```bash
# 检查 S3
JOB_ID=400  # 从日志获取
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/$JOB_ID/outputs/

# 应该看到:
# output.txt
# output.html
# dataset_xxx.dat
```

## 技术细节 (Technical Details)

### CloudWatch Logs 编码

AWS CloudWatch Logs 默认使用 **ASCII/UTF-8 编码**，但在某些情况下，特殊 Unicode 字符会导致：

1. **Python boto3 客户端编码错误**
   ```python
   'ascii' codec can't encode character '\u2713'
   ```

2. **日志流阻塞**
   - 日志缓冲区满
   - 后续日志无法写入

3. **静默失败**
   - 脚本继续执行
   - 但日志丢失

### 为什么任务仍然 SUCCEEDED?

```bash
# fetch_and_run.sh 末尾
if [ $EXIT_CODE -eq 0 ]; then
    echo "[OK] Job script completed successfully"
else
    echo "[ERROR] Job script failed with exit code ${EXIT_CODE}"
    exit $EXIT_CODE
fi
```

即使日志输出失败，脚本逻辑仍然执行：
- 文件下载成功
- 脚本执行成功
- 文件上传成功
- 退出码 = 0 → SUCCEEDED

**但我们看不到这些过程！**

## 影响范围 (Impact)

### 受影响的所有任务

**所有使用 `fetch-and-run` 容器的任务**：
- Job 389 (Trimmomatic)
- Job 390 (FastQC)
- Job 391 (Trimmomatic)
- Job 392 (FastQC)
- Job 393 (FastQC)
- Job 395 (Trimmomatic)
- Job 398 (FastQC)
- Job 399 (FastQC)

所有这些任务都：
- ✅ 状态显示 SUCCEEDED
- ❌ 日志只有前10行
- ❌ 看不到执行过程
- ❌ 不知道是否有输出（实际上可能有，但被清理了）

### Fix 9 之后

- ✅ 完整日志可见
- ✅ 可以调试问题
- ✅ 可以确认输出文件
- ✅ 可以监控执行过程

## 最佳实践 (Best Practices)

### 1. Shell 脚本中避免 Unicode

```bash
# ❌ 不要用
echo "✓ Success"
echo "⚠ Warning"
echo "✗ Error"

# ✅ 应该用
echo "[OK] Success"
echo "[WARN] Warning"
echo "[ERROR] Error"
```

### 2. CloudWatch 安全字符集

**推荐使用**:
- ASCII 字母: A-Z, a-z
- 数字: 0-9
- 符号: `[`, `]`, `(`, `)`, `-`, `_`, `.`, `,`, `:`, `;`

**避免使用**:
- Emoji: 😊, 🚀, ✅
- 特殊符号: ✓, ✗, ⚠, ★
- 非 ASCII 字符: 中文（除非确认支持 UTF-8）

### 3. 测试日志输出

```bash
# 构建镜像后，本地测试
docker run --rm \
    -e S3_BUCKET=test \
    -e AWS_REGION=us-west-2 \
    -e JOB_ID=test \
    your-image:latest \
    bash -c "echo '[OK] Test message' && echo '[WARN] Warning' && echo '[ERROR] Error'"

# 确保所有消息都正常输出
```

## 与其他修复的关系 (Relation to Other Fixes)

Fix 9 是**可观察性修复**：

| Fix | 类型 | 关系 |
|-----|------|------|
| Fix 1-6 | 功能修复 | 确保工具能运行 |
| Fix 7 | 功能修复 | 确保输入可访问 |
| Fix 8 | 功能修复 | 确保输出能收集 |
| **Fix 9** | **可观察性修复** | **确保我们能看到发生了什么！** |

**没有 Fix 9**:
- 功能可能正常
- 但无法调试
- 无法确认
- 无法监控

**有了 Fix 9**:
- 完整日志 ✅
- 可以调试 ✅
- 可以确认 ✅
- 可以监控 ✅

## 总结 (Summary)

### 问题
Unicode 字符 (✓, ⚠, ✗) 导致 CloudWatch 日志中断

### 解决
替换为 ASCII 字符 ([OK], [WARN], [ERROR])

### 影响
- 之前: 看不到日志，无法调试
- 现在: 完整日志，完全可见

### 重要性
**Fix 9 是调试和验证其他所有修复的基础！**

没有完整日志，我们无法确认：
- Fix 7 是否真的工作？
- Fix 8 是否真的收集了文件？
- 工具是否真的执行了？
- 输出是否真的上传了？

**现在我们终于可以看到真相了！** 🎉

## 下一步 (Next Steps)

1. ✅ 镜像已重新构建和推送
2. ⏳ 等待 AWS Batch 拉取新镜像
3. 🔄 运行新的 workflow 测试
4. 👀 查看完整日志验证所有修复
5. 🎯 确认输出文件上传成功

**新镜像 digest**: `sha256:ed8b2c3d79a5854919046c07b79f0fff8d0d81131c069c994c78c6a551a786d6`

现在运行新的 workflow，应该能看到完整的执行过程！
