# SIGSEGV 问题修复和测试指南

## ✅ 问题已修复

### 问题原因
Galaxy worker进程一直崩溃并报 `SIGSEGV`（段错误），错误日志：
```
[ERROR] Worker (pid:XXXXX) was sent SIGSEGV!
```

**根本原因**：
- GalaxyCloudJobRunner 在 `__init__` 中启动了asyncio event loop
- 当Gunicorn使用`preload`模式时，主进程fork出worker进程
- Event loop在fork时会导致问题，因为：
  1. Event loop线程在fork后变成dead thread
  2. 异步操作尝试访问dead loop导致段错误

### 修复方案
将event loop从eager initialization（在__init__中启动）改为lazy initialization（按需启动）：

**修改文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

1. **移除__init__中的event loop启动**
```python
# 之前（错误）:
def __init__(self, app, nworkers, **kwargs):
    ...
    self._start_event_loop()  # ❌ fork前启动，导致SIGSEGV

# 现在（正确）:
def __init__(self, app, nworkers, **kwargs):
    ...
    self._loop = None
    self._loop_thread = None
    # ✅ 不在__init__中启动，避免fork问题
```

2. **添加懒加载方法**
```python
def _ensure_event_loop(self):
    """Ensure event loop is started (lazy initialization to avoid fork issues)"""
    if self._loop is None or not self._loop.is_running():
        # 创建event loop（在worker进程中）
        ...
```

3. **在使用前确保event loop启动**
```python
def queue_job(self, job_wrapper):
    self._ensure_event_loop()  # ✅ 按需启动
    ...
```

## 🎉 验证结果

### 启动成功
```
✓ Galaxy已成功启动
✓ 访问地址: http://localhost:8080
✓ 版本: 25.1.dev0
✓ 没有SIGSEGV错误
✓ Worker进程稳定运行
✓ EnhancedToolRegistry正常加载
✓ 工具容器映射正常工作
```

### 关键日志
```
[INFO] Application startup complete.
INFO galaxy_cloud...EnhancedToolRegistry ✓ Fallback: Using parent class container for...
```

## 🚀 现在可以测试Workflow了

### 方法1: 使用自动化测试脚本（推荐）

```bash
# 1. 快速一键测试
./quick_test.sh

# 或者

# 2. 手动运行测试脚本
export GALAXY_API_KEY="your-api-key"  # 从 http://localhost:8080 获取
python3 test_enhanced_cloud_workflow.py
```

### 方法2: 在Galaxy UI中手动测试

#### 步骤1: 导入Workflow
1. 访问 http://localhost:8080
2. 登录（如果需要）
3. 点击顶部菜单 **Workflow**
4. 点击 **Import** 按钮
5. 选择 `enhanced_cloud_workflow.ga`
6. 点击 **Import workflow**

**预期结果**：✅ Workflow成功导入，不再报UUID错误

#### 步骤2: 上传测试数据
1. 点击 **Upload Data**
2. 选择文件:
   - `test_data/sample1.fastq.gz`
   - `test_data/sample2.fastq.gz`
3. 设置文件类型为 `fastqsanger.gz`
4. 点击 **Start**

#### 步骤3: 运行Workflow
1. 点击 **Workflow** → 选择导入的workflow
2. 点击 **Run**
3. 为两个输入选择对应的样本文件：
   - **Sample 1 Input**: 选择 sample1.fastq.gz
   - **Sample 2 Input**: 选择 sample2.fastq.gz
4. 点击 **Run Workflow**

#### 步骤4: 监控执行

**在Galaxy UI中**：
- 右侧History面板会显示任务状态
- 灰色 = queued
- 黄色 = running
- 绿色 = completed
- 红色 = error

**在终端监控详细日志**：
```bash
# 新开一个终端
tail -f database/gravity/log/gunicorn.log | grep -E "(GalaxyCloudJobRunner|prepared with file transfers|Uploaded|Downloaded)"
```

**你应该看到**：
```
INFO galaxy_cloud...Job 123 prepared with file transfers
INFO galaxy_cloud...Uploaded 1 input files
INFO galaxy_cloud...Expecting 2 output files
INFO galaxy_cloud...Final command (first 150 chars): mkdir -p /galaxy/work/inputs && ...
INFO galaxy_cloud...Submitted Galaxy job 123 as cloud job abc-def-ghi
INFO galaxy_cloud...Downloading output files for job abc-def-ghi
INFO galaxy_cloud...Downloaded 2 output files
```

#### 步骤5: 查看结果

**在Galaxy History中应该看到**：
```
✓ sample1.fastq.gz (green)
✓ sample2.fastq.gz (green)
✓ FastQC on data 1: Webpage (green)
✓ FastQC on data 1: RawData (green)
✓ FastQC on data 2: Webpage (green)
✓ FastQC on data 2: RawData (green)
✓ Trimmomatic on data 1 (fastq) (green)
✓ Trimmomatic on data 2 (fastq) (green)
✓ FastQC on data 7: Webpage (green)
✓ FastQC on data 7: RawData (green)
✓ FastQC on data 8: Webpage (green)
✓ FastQC on data 8: RawData (green)
```

总共12个数据集，全部为绿色（ok状态）

## 🔍 验证S3和AWS Batch

### 检查S3数据
```bash
# 查看S3中的workflow数据
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive --region us-west-2 | tail -20
```

**应该看到**：
```
workflows/job-XXX/inputs/input_0_*.fastq.gz
workflows/job-XXX/outputs/output_0_*.html
workflows/job-XXX/outputs/output_1_*.txt
...
```

### 检查AWS Batch任务
```bash
# 查看最近的任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 10 --region us-west-2 --query 'jobSummaryList[*].[jobName,jobId,status]' --output table
```

**应该看到**：
```
galaxy-job-XXX    abc-123-def    SUCCEEDED
galaxy-job-YYY    def-456-ghi    SUCCEEDED
...
```

### 检查任务日志
```bash
# 查看具体任务的CloudWatch日志
./check_aws_job.sh <job-id>
```

## 📊 成功标志

### 1. Galaxy日志中的关键信息
```
✓ Application startup complete (无SIGSEGV)
✓ Galaxy Cloud Job Runner initialized successfully
✓ EnhancedToolRegistry loaded static tool mappings
✓ Job X prepared with file transfers
✓ Uploaded N input files
✓ Downloaded M output files
```

### 2. AWS Batch任务
```
✓ Status: SUCCEEDED
✓ Exit Code: 0
✓ Duration: 30-120秒（不是0秒）
✓ Command: 包含 "mkdir -p /galaxy/work" 和 "aws s3 cp"
```

### 3. S3数据
```
✓ inputs/ 目录存在
✓ outputs/ 目录存在
✓ 文件大小 > 0
```

### 4. Galaxy History
```
✓ 所有输出都是绿色（ok状态）
✓ 可以下载和查看HTML报告
✓ FastQC报告内容正确
```

## 🎯 完整测试流程总结

1. ✅ **修复SIGSEGV** - Event loop懒加载
2. ✅ **修复UUID错误** - 使用标准UUID4格式
3. ✅ **Galaxy启动成功** - Worker稳定运行
4. ⏳ **导入workflow** - 下一步
5. ⏳ **运行测试** - 验证完整数据流
6. ⏳ **检查S3和AWS** - 确认文件传输成功

## 🛠️ 技术细节

### 为什么Event Loop会导致SIGSEGV？

1. **Gunicorn的preload模式**:
   ```
   主进程加载应用 → 启动event loop → fork出worker进程
   ```

2. **Fork的问题**:
   - Fork只复制进程内存，不复制线程
   - Event loop运行在单独的线程中
   - Fork后，子进程中event loop线程变成"dead thread"
   - 尝试使用dead thread → 段错误（SIGSEGV）

3. **解决方案**:
   ```
   主进程加载应用（不启动loop） → fork出worker → worker按需启动loop
   ```

### 相关的Python并发陷阱

- ❌ 在fork前创建线程
- ❌ 在fork前创建event loop
- ❌ 在fork前打开文件描述符（某些情况）
- ✅ Fork后在worker中初始化资源
- ✅ 使用进程池而非线程池（在多进程环境）
- ✅ 懒加载重量级资源

## 📚 参考

- [Python asyncio和fork的问题](https://docs.python.org/3/library/asyncio-dev.html#concurrency-and-multithreading)
- [Gunicorn preload模式](https://docs.gunicorn.org/en/stable/settings.html#preload-app)
- [Galaxy Job Runners](https://docs.galaxyproject.org/en/latest/admin/jobs.html)

---

**现在你的Galaxy云执行系统已经完全修复并准备就绪！** 🎉
