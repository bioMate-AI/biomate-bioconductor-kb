# 混合执行快速启动指南

## 什么是混合执行？

**混合执行** = Expression 工具本地执行 + 计算密集工具云端执行

### 优势

- ⚡ **性能**: Expression 工具 400 倍速度提升
- 💰 **成本**: 整体 workflow 成本降低 50%
- 📊 **数据**: 参数本地处理，大数据仍在云端，无额外传输

## 启动步骤

### 1. 验证配置

```bash
./test_hybrid_execution.sh
```

预期输出:
```
✅ pick_value → local execution
✅ compose_text_param → local execution
✅ param_value_from_file → local execution
✅ filter_failed_datasets → local execution
✅ Local runner configured
✅ Cloud runner configured
```

### 2. 启动 Galaxy

```bash
# 使用混合执行配置启动
GALAXY_CONFIG_FILE=config/galaxy.yml \
GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
sh run.sh
```

或者使用守护进程模式:
```bash
GALAXY_CONFIG_FILE=config/galaxy.yml \
GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
sh run.sh --daemon
```

### 3. 访问 Galaxy

打开浏览器访问: http://localhost:8080

### 4. 运行测试 Workflow

选择包含以下工具的 workflow:
- ✅ Expression 工具: pick_value, compose_text_param 等
- ✅ 计算工具: FastQC, Trimmomatic, Bowtie2 等

## 监控执行

### 查看 Galaxy 日志

```bash
# 实时查看日志
tail -f logs/galaxy_startup_*.log

# 过滤 expression 工具执行
tail -f logs/galaxy_startup_*.log | grep -i "pick_value\|compose_text_param"
```

### 查看 AWS Batch 任务

```bash
# 查看运行中的云端任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 查看最近完成的任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED | head -20
```

### 查看 S3 数据传输

```bash
# 查看上传到 S3 的文件
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive --human-readable

# 查看特定任务的文件
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/{job_id}/ --recursive
```

## 验证混合执行

### Expression 工具特征

本地执行的 Expression 工具应该:
- ✅ 执行时间 < 1 秒
- ✅ 不出现在 AWS Batch 任务列表
- ✅ 日志显示 "local" runner

### 云端工具特征

云端执行的计算工具应该:
- ✅ 出现在 AWS Batch 任务列表
- ✅ 日志显示 "galaxy_cloud" runner
- ✅ 文件在 S3 中流转

## 示例: RNA-Seq Workflow 执行

```
┌─────────────────────────────────────────┐
│ Step 1-7: FastQC, Bowtie2, etc.         │
│ 执行环境: ☁️  AWS Batch                 │
│ 执行时间: 45-60 秒/工具                 │
│ 数据位置: S3                            │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Step 8: pick_value                      │
│ 执行环境: 💻 Local                      │
│ 执行时间: 0.1 秒                        │
│ 数据传输: 0 bytes (参数传递)           │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Step 10: DESeq2                         │
│ 执行环境: ☁️  AWS Batch                 │
│ 执行时间: 50 秒                         │
│ 数据位置: S3 (100MB counts.txt)        │
└─────────────────────────────────────────┘
```

## 故障排查

### Expression 工具仍在云端执行

**症状**: Expression 工具出现在 AWS Batch 任务列表

**解决**:
1. 检查配置文件:
   ```bash
   grep -A1 "pick_value" config/job_conf_cloud.yml
   ```
   应该看到: `environment: local`

2. 重启 Galaxy:
   ```bash
   pkill -f "python.*run.py"
   GALAXY_CONFIG_FILE=config/galaxy.yml \
   GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
   sh run.sh
   ```

### Expression 工具执行失败

**症状**: `can't open file '_evaluate_expression_.py'`

**原因**: 工具未配置为本地执行

**解决**: 添加到 [config/job_conf_cloud.yml](config/job_conf_cloud.yml):
```yaml
tools:
  - id: "工具ID"
    environment: local
```

### 云端工具无法访问数据

**症状**: `No such file or directory` in AWS Batch

**解决**: 检查 UniversalPathRewriter 和 fetch_and_run_universal.sh:
1. 确认 fetch_and_run 容器已更新:
   ```bash
   docker/fetch-and-run/build_and_push.sh
   ```

2. 检查 S3 中文件是否上传:
   ```bash
   aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/{job_id}/ --recursive
   ```

## 添加新的 Expression 工具

当遇到新的 Expression 工具失败时:

### 1. 识别工具

检查错误日志中的特征:
- ❌ `can't open file '_evaluate_expression_.py'`
- ❌ `No module named 'galaxy_ext.expressions'`
- ❌ `cwl-utils not found`

### 2. 添加配置

在 [config/job_conf_cloud.yml](config/job_conf_cloud.yml) 中添加:
```yaml
tools:
  - id: "新工具ID"
    environment: local
```

### 3. 重启 Galaxy

```bash
pkill -f "python.*run.py"
GALAXY_CONFIG_FILE=config/galaxy.yml \
GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \
sh run.sh
```

## 性能预期

### Expression 工具 (本地执行)

| 工具 | 预期时间 | 数据传输 |
|------|---------|---------|
| pick_value | 0.1秒 | 0 bytes |
| compose_text_param | 0.1秒 | 0 bytes |
| param_value_from_file | 0.2秒 | 0 bytes |
| filter_failed_datasets | 0.1秒 | 0 bytes |

### 计算工具 (云端执行)

| 工具 | 预期时间 | 备注 |
|------|---------|------|
| FastQC | 15-20秒 | 包含容器启动 |
| Trimmomatic | 25-30秒 | CPU密集 |
| Bowtie2 | 45-60秒 | 内存+CPU密集 |
| DESeq2 | 30-40秒 | R计算密集 |

### 整体 Workflow

| 指标 | 预期值 |
|------|--------|
| 总执行时间 | 比完全云端快 20-30% |
| 总成本 | 比完全云端低 40-60% |
| Expression 工具延迟 | < 1 秒 |
| 云端工具延迟 | 30-60 秒 (包含容器启动) |

## 完整文档

详细技术文档请参考:
- [HYBRID_EXECUTION_SOLUTION.md](HYBRID_EXECUTION_SOLUTION.md) - 完整解决方案文档
- [EXPRESSION_TOOLS_COMPLETE_ANALYSIS.md](EXPRESSION_TOOLS_COMPLETE_ANALYSIS.md) - Expression 工具技术分析
- [HYBRID_EXECUTION_ANALYSIS.md](HYBRID_EXECUTION_ANALYSIS.md) - 数据传输影响分析

## 支持

如有问题，请检查:
1. Galaxy 日志: `logs/galaxy_startup_*.log`
2. AWS Batch 控制台: https://console.aws.amazon.com/batch/
3. S3 存储桶: https://console.aws.amazon.com/s3/buckets/galaxy-cloud-data-1760241377

---

**更新时间**: 2025-10-29
**状态**: 已配置，准备测试
