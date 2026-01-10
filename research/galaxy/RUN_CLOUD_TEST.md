# 增强版云Workflow完整测试指南

## 📋 测试内容

这个测试验证完整的Galaxy云执行流程：

### Workflow结构
```
输入数据 (2个FASTQ样本)
    ↓
├─ Sample 1 分支                 ├─ Sample 2 分支
│   ↓                            │   ↓
│  FastQC (初始质量检查)          │  FastQC (初始质量检查)
│   ↓                            │   ↓
│  Trimmomatic (质量修剪)         │  Trimmomatic (质量修剪)
│   ↓                            │   ↓
│  FastQC (修剪后质量检查)        │  FastQC (修剪后质量检查)
│                                │
└────────────────────────────────┘
          总计8个步骤
```

### 验证项目
- ✓ FileTransferManager被调用
- ✓ 输入文件上传到S3
- ✓ 命令包含S3下载/上传
- ✓ AWS Batch容器成功执行
- ✓ 输出文件下载回本地
- ✓ Galaxy显示正确结果

## 🚀 快速开始

### 1. 获取Galaxy API Key

访问: http://localhost:8080/user
- 登录Galaxy
- 点击 "Preferences" -> "Manage API keys"
- 点击 "Create a new key"
- 复制生成的API key

### 2. 运行测试

```bash
# 方法1: 使用环境变量
export GALAXY_API_KEY="your-api-key-here"
python3 test_enhanced_cloud_workflow.py

# 方法2: 直接传参数
python3 test_enhanced_cloud_workflow.py your-api-key-here

# 方法3: 保存到文件
echo "your-api-key-here" > ~/.galaxy_api_key
python3 test_enhanced_cloud_workflow.py
```

### 3. 监控执行（新开终端）

在测试运行时，另开一个终端监控详细日志：

```bash
# 监控Galaxy日志 - 查看文件传输
tail -f database/gravity/log/gunicorn.log | grep -E "(GalaxyCloudJobRunner|prepared with file transfers|Uploaded|Downloaded)"

# 监控AWS Batch任务
watch -n 5 "aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING --region us-west-2 --query 'jobSummaryList[*].[jobName,jobId,createdAt]' --output table"

# 监控S3数据
watch -n 10 "aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive --region us-west-2 | tail -10"
```

## 📊 预期输出

### 成功输出示例

```
================================================================================
  增强版Galaxy云Workflow完整测试
  测试项: 多样本NGS质控流程 (FastQC + Trimmomatic)
  验证: S3文件传输 + AWS Batch容器执行
================================================================================

================================================================================
  1. 检查Galaxy服务
================================================================================

✓ Galaxy正在运行: 25.1.dev0

================================================================================
  2. 上传测试数据到Galaxy
================================================================================

✓ 创建History: Enhanced Cloud Test - 20251021-080530 (ID: abc123)

  上传 sample1...
    ✓ Dataset ID: def456
  上传 sample2...
    ✓ Dataset ID: ghi789

  等待数据上传完成...
    ✓ 所有数据上传完成

================================================================================
  3. 导入增强版Workflow
================================================================================

✓ Workflow已导入: Enhanced Cloud Test Workflow - NGS QC Pipeline
  ID: workflow123
  步骤数: 8

================================================================================
  4. 运行Workflow
================================================================================

输入数据映射:
  Step 0 (Sample 1): def456
  Step 1 (Sample 2): ghi789

提交Workflow执行...
✓ Workflow已提交
  Invocation ID: inv123
  History ID: abc123

================================================================================
  5. 监控Workflow执行
================================================================================

实时监控任务状态...

提示: 同时运行以下命令查看详细日志:
  tail -f database/gravity/log/gunicorn.log | grep -E '(GalaxyCloudJobRunner|prepared with file transfers|Uploaded|Downloaded)'

  [   0s] Sample 1 - Initial QC          -> new
  [   5s] Sample 1 - Initial QC          -> queued
  [  10s] Sample 1 - Initial QC          -> running
  [  45s] Sample 1 - Initial QC          -> ok
  [  50s] Sample 2 - Initial QC          -> running
  ...
  [ 280s] Sample 2 - Post-trim QC        -> ok

✓ Workflow执行成功！ (耗时: 285秒)

================================================================================
  6. 检查S3数据传输
================================================================================

查找最近的S3数据...
✓ S3中的workflow数据:
2025-10-21 08:10:23    78203 workflows/job-abc/inputs/input_0.fastq.gz
2025-10-21 08:10:45    56234 workflows/job-abc/outputs/output_0.html
...

================================================================================
  7. 检查AWS Batch任务
================================================================================

查询最近的AWS Batch任务...
最近成功的任务:
  - galaxy-job-abc123: abc-123-def-456
  - galaxy-job-def456: def-456-ghi-789
  ...

================================================================================
  8. 验证输出结果
================================================================================

History中的所有数据集:
  [ 1] sample1.fastq.gz                                  -> ok
  [ 2] sample2.fastq.gz                                  -> ok
  [ 3] FastQC on data 1: Webpage                         -> ok
  [ 4] FastQC on data 1: RawData                         -> ok
  [ 5] FastQC on data 2: Webpage                         -> ok
  [ 6] FastQC on data 2: RawData                         -> ok
  [ 7] Trimmomatic on data 1 (fastq)                     -> ok
  [ 8] Trimmomatic on data 2 (fastq)                     -> ok
  [ 9] FastQC on data 7: Webpage                         -> ok
  [10] FastQC on data 7: RawData                         -> ok
  [11] FastQC on data 8: Webpage                         -> ok
  [12] FastQC on data 8: RawData                         -> ok

✓ 找到 8 个FastQC输出文件

================================================================================
  测试总结
================================================================================

✓✓✓ 所有测试通过！✓✓✓

验证完成:
  1. ✓ Galaxy工具成功调度到云端
  2. ✓ 输入数据成功上传到S3
  3. ✓ AWS Batch容器成功执行
  4. ✓ 输出数据成功下载回本地
  5. ✓ 所有任务产生了正确的结果
```

## 🔍 日志关键信息

在 `database/gravity/log/gunicorn.log` 中应该看到：

```
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Job 123 prepared with file transfers
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Uploaded 1 input files
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Expecting 2 output files
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Final command (first 150 chars): mkdir -p /galaxy/work/inputs && mkdir -p /galaxy/work/outputs && aws s3 cp s3://...
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Submitted Galaxy job 123 as cloud job abc-def-ghi
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Downloading output files for job abc-def-ghi
INFO galaxy_cloud.galaxy_workflow.galaxy_job_runner Downloaded 2 output files
```

## ⚠️ 故障排除

### 问题1: "未找到API key"
```bash
# 解决方案: 设置API key
export GALAXY_API_KEY="your-key"
# 或
echo "your-key" > ~/.galaxy_api_key
```

### 问题2: "Galaxy未运行"
```bash
# 检查Galaxy
curl http://localhost:8080/api/version

# 重启Galaxy
sh run.sh --daemon
```

### 问题3: "任务一直pending"
```bash
# 检查job_conf_cloud.yml是否被加载
grep "job_config_file" config/galaxy.yml

# 应该显示: job_config_file: config/job_conf_cloud.yml
```

### 问题4: "没有文件传输日志"
```bash
# 检查FileTransferManager是否存在
ls -lh lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py

# 检查s3_bucket配置
grep "s3_bucket" config/job_conf_cloud.yml
```

## 📁 生成的文件

测试会生成以下文件：

```
test_data/
├── sample1.fastq.gz          # 测试输入数据1
└── sample2.fastq.gz          # 测试输入数据2

enhanced_cloud_workflow.ga    # Workflow定义
test_enhanced_cloud_workflow.py  # 测试脚本
```

## 🎯 下一步

测试通过后，你可以：

1. **在Galaxy UI中手动运行workflow**
   - 访问 http://localhost:8080
   - Workflow -> Import -> 选择 `enhanced_cloud_workflow.ga`
   - 运行并查看结果

2. **查看AWS控制台**
   - 访问 AWS Batch 控制台查看任务详情
   - 访问 S3 控制台查看上传的数据

3. **使用真实数据**
   - 替换 test_data 中的文件为真实的FASTQ数据
   - 重新运行测试

4. **扩展workflow**
   - 添加更多工具（比对、变异检测等）
   - 增加数据集规模
   - 测试更复杂的数据流
