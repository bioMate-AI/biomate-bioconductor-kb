# Galaxy Cloud Executor 测试数据

## 📁 可用的测试数据集

### QIIME2 Demultiplexed Workflow

**目录**: `qiime2_demo/`

**内容:**
- 3个模拟单端测序FASTQ文件 (sample1-3)
- 每个样本500条reads, 读长150bp
- Phred+33质量编码
- 总大小: ~230 KB

**对应Workflow:**
- 文件: `lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json`
- 名称: QIIME2 Ic: Demultiplexed data (single-end)

## 🚀 快速开始

```bash
cd qiime2_demo

# 设置环境
export AWS_BATCH_QUEUE=galaxy-cloud-queue
export AWS_S3_BUCKET=your-bucket-name

# 运行测试
./快速测试.sh
```

或直接使用命令行:

```bash
cd ../testing

python3 run_workflow_with_real_data.py \
    /path/to/workflow_0dc387dc861bdb61.json \
    --input 0:../test_data/qiime2_demo/sample1_R1.fastq.gz \
    --input 0:../test_data/qiime2_demo/sample2_R1.fastq.gz \
    --input 0:../test_data/qiime2_demo/sample3_R1.fastq.gz \
    --output-dir ./results
```

## 📚 更多信息

详细文档见各子目录的 README.md 文件。
