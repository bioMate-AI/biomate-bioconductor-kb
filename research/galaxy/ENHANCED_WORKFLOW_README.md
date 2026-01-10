# 增强版Galaxy云Workflow测试系统

## 📌 概述

基于你的 **Simple Cloud Test Workflow**，我创建了一个增强版的复杂测试系统，用于全面验证Galaxy云执行的完整数据流。

## 🎯 改进点

### 原始 Simple Cloud Test Workflow
```
单个样本: FASTQ → FastQC → Trimmomatic → FastQC
总计: 1个输入，3个步骤
```

### 增强版 Enhanced Cloud Test Workflow
```
双样本并行处理:

Sample 1分支:                    Sample 2分支:
  FASTQ输入                        FASTQ输入
    ↓                               ↓
  FastQC初检                       FastQC初检
    ↓                               ↓
  Trimmomatic修剪                  Trimmomatic修剪
    ↓                               ↓
  FastQC复检                       FastQC复检

总计: 2个输入，8个步骤，4个并行任务
```

### 复杂度提升
1. **多输入**: 2个独立的FASTQ样本
2. **并行执行**: 两个样本同时处理
3. **多数据流**: 每个样本有独立的数据流
4. **完整流程**: 包含初检→修剪→复检的完整NGS质控流程
5. **真实场景**: 模拟实际的多样本分析场景

## 📁 文件结构

```
.
├── enhanced_cloud_workflow.ga          # 增强版workflow定义
├── test_enhanced_cloud_workflow.py     # 完整自动化测试脚本
├── quick_test.sh                       # 一键快速测试脚本
├── RUN_CLOUD_TEST.md                   # 详细使用指南
├── ENHANCED_WORKFLOW_README.md         # 本文件
│
├── test_data/                          # 测试数据目录
│   ├── sample1.fastq.gz               # 样本1 (2000 reads, 323KB)
│   └── sample2.fastq.gz               # 样本2 (2000 reads, 323KB)
│
└── lib/galaxy_cloud/galaxy_workflow/
    └── file_transfer_manager.py       # S3文件传输管理器
```

## 🚀 快速开始

### 方法1: 一键测试（推荐）

```bash
./quick_test.sh
```

这会自动：
1. 检查Galaxy是否运行
2. 请求/获取API key
3. 安装依赖（bioblend）
4. 启动日志监控
5. 运行完整测试
6. 显示结果

### 方法2: 手动测试

```bash
# 1. 获取API key (访问 http://localhost:8080 -> User -> Preferences -> API Keys)
export GALAXY_API_KEY="your-api-key-here"

# 2. 安装依赖
pip3 install bioblend

# 3. 运行测试
python3 test_enhanced_cloud_workflow.py

# 4. （可选）监控日志
tail -f database/gravity/log/gunicorn.log | grep -E "(GalaxyCloudJobRunner|prepared with file transfers)"
```

## ✅ 验证项目

测试会全面验证以下功能：

### 1. Galaxy调度
- ✓ 工具正确路由到云运行器
- ✓ job_conf_cloud.yml配置生效
- ✓ GalaxyCloudJobRunner被正确调用

### 2. 文件传输 (FileTransferManager)
- ✓ 识别输入/输出文件路径
- ✓ 上传输入文件到S3 (`s3://bucket/workflows/job-XXX/inputs/`)
- ✓ 命令路径重写（本地路径 → 容器路径）
- ✓ 生成setup命令（下载inputs）
- ✓ 生成cleanup命令（上传outputs）
- ✓ 下载输出文件回本地
- ✓ 清理S3临时数据

### 3. AWS Batch执行
- ✓ 容器成功启动
- ✓ 安装AWS CLI
- ✓ 从S3下载数据
- ✓ 执行Galaxy工具命令
- ✓ 上传结果到S3
- ✓ 正确的退出码

### 4. 数据完整性
- ✓ 所有输出文件生成
- ✓ FastQC HTML报告存在
- ✓ FastQC文本数据正确
- ✓ Trimmomatic修剪后的FASTQ正确

## 📊 预期结果

### 成功标志

1. **日志中应该看到:**
```
INFO galaxy_cloud...GalaxyCloudJobRunner Job 123 prepared with file transfers
INFO galaxy_cloud...GalaxyCloudJobRunner Uploaded 1 input files
INFO galaxy_cloud...GalaxyCloudJobRunner Expecting 2 output files
INFO galaxy_cloud...GalaxyCloudJobRunner Downloaded 2 output files
```

2. **S3中应该有:**
```
s3://galaxy-cloud-data-1760241377/workflows/job-XXX/
├── inputs/
│   └── input_0_*.fastq.gz
└── outputs/
    ├── output_0_*.html
    └── output_1_*.txt
```

3. **AWS Batch任务:**
```
Status: SUCCEEDED
Exit Code: 0
Duration: 30-120秒（取决于任务）
Command: 包含 "mkdir -p /galaxy/work" 和 "aws s3 cp"
```

4. **Galaxy History:**
```
12个数据集全部为 'ok' 状态:
- 2个输入FASTQ
- 4个初检FastQC结果
- 2个修剪后FASTQ
- 4个复检FastQC结果
```

## 🔍 测试数据

### 自动生成的测试数据

```python
# test_data/sample1.fastq.gz 和 sample2.fastq.gz
- 格式: FASTQ (压缩)
- Reads数: 2000条/样本
- Read长度: 150bp
- 质量分布: 80%高质量 + 20%低质量 (用于测试Trimmomatic)
- 大小: ~323KB/文件
```

### 使用真实数据

替换 `test_data/` 中的文件为你自己的FASTQ数据：

```bash
cp /path/to/your/sample1.fastq.gz test_data/
cp /path/to/your/sample2.fastq.gz test_data/
```

然后重新运行测试。

## 🎓 学习价值

这个测试系统展示了：

### 1. 完整的云数据管理
```python
# FileTransferManager工作流程:
本地文件 → S3上传 → 容器内下载 → 工具处理 →
容器内上传 → S3存储 → 下载到本地 → Galaxy显示
```

### 2. 路径重写机制
```bash
# 原始命令（本地路径）:
fastqc /Users/user/galaxy/database/objects/abc.dat

# 重写后命令（容器路径）:
aws s3 cp s3://bucket/inputs/0.dat /galaxy/work/inputs/input.fastq && \
fastqc /galaxy/work/inputs/input.fastq && \
aws s3 cp output.html s3://bucket/outputs/0.html
```

### 3. 并行任务调度
- 2个样本的初检FastQC可以并行运行
- Trimmomatic根据前置任务完成情况调度
- 复检FastQC等待修剪完成

### 4. 错误处理
- 文件上传失败 → 任务不提交
- 容器执行失败 → 保留日志，标记失败
- 下载失败 → 重试机制

## 📈 性能基准

基于之前的AWS Batch测试数据：

| 任务 | 预计时间 | 资源 |
|------|---------|------|
| FastQC (初检) | 30-45秒 | 2 vCPU, 4GB |
| Trimmomatic | 25-35秒 | 4 vCPU, 8GB |
| FastQC (复检) | 30-45秒 | 2 vCPU, 4GB |
| **总计** | **~4-5分钟** | 并行执行 |

## 🛠️ 故障排除

详见 [RUN_CLOUD_TEST.md](RUN_CLOUD_TEST.md) 的故障排除章节。

常见问题：

1. **"Galaxy未运行"** → `sh run.sh --daemon`
2. **"未找到API key"** → 访问Galaxy UI创建
3. **"没有文件传输日志"** → 检查job_conf_cloud.yml配置
4. **"AWS认证失败"** → `aws sso login`

## 🔄 与Simple Cloud Test的对比

| 特性 | Simple Cloud Test | Enhanced Cloud Test |
|-----|------------------|-------------------|
| 输入样本 | 1个 | 2个 |
| 步骤数 | 3个 | 8个 |
| 并行度 | 顺序执行 | 最多4个并行 |
| 数据流 | 单一流 | 2个独立流 |
| 测试深度 | 基础 | 全面 |
| 自动化 | 手动 | 完全自动化 |
| 验证项 | 执行成功 | 完整数据流 |
| 日志监控 | 无 | 实时监控 |
| S3验证 | 无 | 完整验证 |
| AWS任务检查 | 无 | 自动检查 |

## 🎯 下一步扩展

1. **增加更多工具**
   - BWA/Bowtie2 比对
   - SAMtools 处理
   - 变异检测

2. **Collection支持**
   - 使用Galaxy Collection处理多个文件
   - 动态输入数量

3. **更大数据集**
   - 测试GB级别的FASTQ文件
   - 验证大文件传输性能

4. **混合执行**
   - 部分步骤本地执行
   - 部分步骤云端执行

## 📞 获取帮助

如果遇到问题：

1. 查看 [RUN_CLOUD_TEST.md](RUN_CLOUD_TEST.md)
2. 检查 `database/gravity/log/gunicorn.log`
3. 运行 `./check_aws_job.sh <job-id>` 查看AWS任务详情

## ✨ 总结

这个增强版测试系统提供了：

- ✅ **完整的复杂workflow测试**
- ✅ **全自动化验证流程**
- ✅ **真实的多样本场景**
- ✅ **详细的监控和日志**
- ✅ **端到端的数据流验证**

现在你可以自信地验证Galaxy云执行的所有关键功能！
