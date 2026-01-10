# QIIME2 Workflow 测试数据

用于测试 QIIME2 Demultiplexed Data Workflow 的模拟测序数据。

## 📁 文件说明

### 测试数据
- `sample1_R1.fastq.gz` - 样本1 (500 reads, 76 KB)
- `sample2_R1.fastq.gz` - 样本2 (500 reads, 76 KB)
- `sample3_R1.fastq.gz` - 样本3 (500 reads, 76 KB)

### 工具脚本
- `generate_fastq_data.py` - 重新生成测试数据
- `快速测试.sh` - 模拟执行测试（使用amazonlinux容器）
- `测试真实QIIME2执行.sh` - **真实QIIME2工具执行**（使用QIIME2官方容器）⭐

### 文档
- `完整使用指南.md` - 详细使用文档

## 📊 数据规格

- **格式**: FASTQ (gzip 压缩)
- **质量编码**: Phred+33 (Illumina 1.8+)
- **测序类型**: 单端测序 (single-end)
- **读长**: 150 bp
- **Galaxy 数据类型**: `fastqsanger.gz`

## 🚀 快速开始

### 方法 1: 真实QIIME2执行 ⭐ (推荐)

**使用真实的QIIME2工具执行workflow**，输出真正的QIIME2结果文件（.qza/.qzv）

```bash
# 设置环境变量
export AWS_BATCH_QUEUE=galaxy-cloud-queue
export AWS_S3_BUCKET=galaxy-cloud-data-1760241377
export AWS_DEFAULT_REGION=us-west-2

# 运行真实QIIME2测试
./测试真实QIIME2执行.sh
```

**特点:**
- ✅ 使用QIIME2官方容器: `quay.io/qiime2/core:2023.5`
- ✅ 执行真实的QIIME2工具命令
- ✅ 输出真正的.qza和.qzv文件
- ✅ 包含完整的6步workflow:
  1. 输入数据集合
  2. 提取文件名标识符
  3. 正则表达式处理
  4. 重新标记文件
  5. qiime2 tools import
  6. qiime2 demux summarize

### 方法 2: 模拟执行（快速测试框架）

**快速验证workflow执行流程**，不使用真实工具

```bash
# 运行模拟测试
./快速测试.sh
```

### 方法 3: 直接使用命令行

```bash
cd ../../testing

# 真实QIIME2执行（传入目录）
python3 run_workflow_with_real_data.py \
    /Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json \
    --input 0:../test_data/qiime2_demo \
    --output-dir ./qiime2_results

# 或者预览执行计划（不实际运行）
python3 run_workflow_with_real_data.py \
    /Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json \
    --input 0:../test_data/qiime2_demo \
    --output-dir ./qiime2_results \
    --dry-run
```

## 🔄 重新生成数据

如果需要修改测试数据:

```bash
# 编辑生成脚本中的参数
vim generate_fastq_data.py

# 重新生成
python3 generate_fastq_data.py
```

## 📚 更多信息

查看 [完整使用指南.md](完整使用指南.md) 了解详细使用方法和故障排查。

## ⚠️ 注意

这是**模拟测试数据**，不包含真实生物信息，仅用于测试 workflow 执行流程。
