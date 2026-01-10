# 真实复杂Workflow云执行完整测试指南

## 📋 概览

这是一个**真实的生物信息学分析流程**，包含多个步骤和计算密集型工具：

```
输入FASTQ → FastQC评估 → Trimmomatic修剪 → FastQC再评估 → Bowtie2比对 → BAM统计
```

### Workflow特点
- ✅ **6个步骤**：多步骤复杂流程
- ✅ **5个工具**：FastQC(2次), Trimmomatic, Bowtie2, BAM Stats
- ✅ **计算密集**：序列比对需要大量CPU和内存
- ✅ **真实场景**：模拟实际测序数据分析
- ✅ **云端执行**：所有工具配置为在AWS Batch运行

### 资源配置
| 工具 | 环境 | vCPUs | 内存 | 说明 |
|------|------|-------|------|------|
| FastQC | cloud_small | 2 | 4GB | 快速质量评估 |
| Trimmomatic | cloud_medium | 4 | 8GB | 质量修剪 |
| Bowtie2 | cloud_large | 8 | 16GB | 序列比对（计算密集） |
| BAM Stats | cloud_small | 2 | 4GB | 统计分析 |

---

## 🎯 完整测试步骤

### 步骤1：安装所需工具（一次性，约20-40分钟）

```bash
cd /Users/renyuankai/work/biometa/galaxy

# 1. 获取API Key
# 访问 http://localhost:8080
# User → Preferences → Manage API Key → Create

# 2. 编辑安装脚本
nano install_workflow_tools.py
# 设置: API_KEY = "your-api-key-here"

# 3. 运行安装
python3 install_workflow_tools.py
```

**需要安装的工具：**
1. FastQC (devteam) - 质量评估
2. Trimmomatic (pjbriggs) - 质量修剪
3. Bowtie2 (devteam) - 序列比对
4. BAM Tools Stats (devteam) - 统计分析

**注意：** 第一次安装这些工具会下载很多依赖（尤其是Bowtie2），可能需要20-40分钟。

---

### 步骤2：重启Galaxy（加载新配置）

```bash
# 停止Galaxy
pkill -f gunicorn ; pkill -f celery

# 启动Galaxy（加载更新的job配置）
bash start_galaxy_cloud.sh > galaxy_startup.log 2>&1 &

# 等待启动（约1分钟）
sleep 60

# 验证启动
curl http://localhost:8080/api/version

# 验证云runner加载
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud.*init"
```

---

### 步骤3：导入Workflow

**方式A - 通过UI（推荐）：**
```
1. 访问 http://localhost:8080
2. Workflow → Import
3. 上传文件：
   /Users/renyuankai/work/biometa/galaxy/real_complex_workflow.ga
4. 导入成功后应该看到：
   "Real Bioinformatics Pipeline - QC and Analysis"
```

**方式B - 通过API：**
```bash
export GALAXY_API_KEY="your-key"

curl -X POST "http://localhost:8080/api/workflows" \
  -H "x-api-key: $GALAXY_API_KEY" \
  -H "Content-Type: application/json" \
  -d @real_complex_workflow.ga
```

---

### 步骤4：上传测试数据

```
1. Galaxy UI → Upload Data (↑ 图标)
2. Choose local files
3. 选择文件：
   /Users/renyuankai/work/biometa/galaxy/real_test_data/sample_reads.fastq.gz
4. Type: fastqsanger.gz
5. Start → 等待上传完成
```

---

### 步骤5：运行Workflow

```
1. Workflow → "Real Bioinformatics Pipeline" → Run (▶️)
2. Step 1: Raw Sequencing Data
   → 选择刚上传的 sample_reads.fastq.gz
3. Run Workflow
```

---

## 🔍 验证云执行

### 在Galaxy UI中验证

运行workflow后，查看历史记录面板：

```
应该看到多个作业（Job）按顺序执行：
  ✓ FastQC on data 1
  ✓ Trimmomatic on data 1
  ✓ FastQC on data 2
  ✓ Bowtie2 on data 2
  ✓ BAM Stats on data 3
```

**点击任意作业查看详情：**
- **FastQC**: destination: cloud_small
- **Trimmomatic**: destination: cloud_medium
- **Bowtie2**: destination: cloud_large
- **BAM Stats**: destination: cloud_small

### 在AWS中验证

```bash
# 查看正在运行的Batch作业
watch -n 5 'aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING'

# 查看完成的作业
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 10

# 查看S3上传的数据
aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive --human-readable | tail -20

# 查看作业详细信息（替换JOB_ID）
aws batch describe-jobs --jobs <JOB-ID>
```

### 在Galaxy日志中验证

```bash
# 实时查看云执行活动
tail -f galaxy_startup.log | grep -i "batch\|cloud\|s3"

# 查看作业提交记录
grep -i "submit.*batch" galaxy_startup.log | tail -20

# 查看完成的作业
grep -i "job.*complete\|success" galaxy_startup.log | tail -20
```

---

## 📊 预期结果

### 执行时间预估

| 步骤 | 工具 | 预计时间 | 说明 |
|------|------|----------|------|
| 1 | FastQC (首次) | 2-5分钟 | 包含容器启动 |
| 2 | Trimmomatic | 1-3分钟 | 1000条reads处理快 |
| 3 | FastQC (第二次) | 1-2分钟 | 容器已warm |
| 4 | Bowtie2 | 5-10分钟 | 需要下载参考基因组* |
| 5 | BAM Stats | 1-2分钟 | 快速统计 |
| **总计** | **10-22分钟** | 首次运行 |

**注意：** Bowtie2需要参考基因组索引。如果Galaxy没有预先下载hg38，可能需要额外时间。

### 成功标志

1. **所有作业完成** ✓
   - 5个作业全部绿色（成功）
   - 没有红色（失败）或灰色（等待）

2. **输出文件生成** ✓
   - FastQC HTML报告 (2个)
   - Trimmed FASTQ文件
   - BAM比对文件
   - 统计报告

3. **AWS Batch记录** ✓
   - 5个作业在AWS Batch队列中
   - 状态全部SUCCEEDED
   - CloudWatch有日志记录

4. **S3存储** ✓
   - 输入文件已上传
   - 中间文件存在
   - 输出文件正确

---

## 🐛 故障排除

### 问题1：Bowtie2失败 - 找不到参考基因组

**症状：** Bowtie2作业失败，错误提示"index not found: hg38"

**原因：** Galaxy没有预先下载hg38参考基因组

**解决方案A：** 修改workflow使用built-in索引
```yaml
# 编辑 real_complex_workflow.ga
# 在Bowtie2步骤中修改：
"reference_genome": {
  "source": "history",  # 改为使用历史记录中的序列
  "own_file": {"__class__": "ConnectedValue"}
}
```

**解决方案B：** 下载参考基因组（需要管理员权限）
```bash
# 在Galaxy中使用Data Manager下载hg38
# Admin → Local Data → Data Managers → bowtie2 index builder
```

**解决方案C：** 简化workflow（推荐测试用）
```python
# 移除Bowtie2和BAM Stats步骤
# 只测试前3步：FastQC → Trimmomatic → FastQC
```

---

### 问题2：工具安装失败

**症状：** install_workflow_tools.py 报告安装失败

**检查：**
```bash
# 查看已安装工具
curl -s -H "x-api-key: $GALAXY_API_KEY" \
  http://localhost:8080/api/tool_shed_repositories | \
  python3 -c "import sys, json; repos=json.load(sys.stdin); [print(f\"{r['name']} - {r.get('status', 'unknown')}\") for r in repos]"

# 查看安装日志
tail -100 galaxy_startup.log | grep -i "install\|tool.*shed"
```

**解决：** 手动在UI中安装
```
Admin → Install and Uninstall → 搜索工具 → Install
```

---

### 问题3：作业一直pending（等待状态）

**原因：** AWS Compute Environment没有可用实例

**检查：**
```bash
# 查看Compute Environment状态
aws batch describe-compute-environments \
  --compute-environments galaxy-cloud-compute

# 查看EC2实例
aws ec2 describe-instances \
  --filters "Name=tag:aws:batch:compute-environment,Values=*galaxy*"
```

**解决：** 等待AWS启动实例（首次约2-3分钟）

---

### 问题4：作业在本地运行而不是云端

**检查匹配规则：**
```bash
# 查看作业destination
# 在Galaxy UI作业详情中应该看到：
# destination: cloud_small/cloud_medium/cloud_large

# 如果看到 destination: local，说明没有匹配到云端规则
```

**解决：** 检查job配置
```bash
cat config/job_conf_cloud.yml | grep -A 2 "fastqc\|trimmomatic\|bowtie"
```

---

## 📈 性能对比

运行完成后，可以对比本地vs云端性能：

```
本地执行（如果所有工具都在本地）：
  - FastQC: 30-60秒
  - Trimmomatic: 1-2分钟
  - Bowtie2: 5-10分钟
  - 总计: ~10分钟（单线程顺序）

云端执行（多作业并行）：
  - FastQC: 2-3分钟（包含冷启动）
  - Trimmomatic: 2-3分钟
  - Bowtie2: 5-8分钟（更多vCPUs）
  - 可并行执行无依赖的步骤
  - 总计: ~10-15分钟（但可扩展）
```

**云端优势：**
- ✅ 可扩展：可以同时运行多个workflow
- ✅ 按需付费：只为实际使用付费
- ✅ 无需本地资源：不占用本地计算资源
- ✅ 适合大规模：处理数百个样本时优势明显

---

## 🎉 成功验证清单

- [ ] 所有4个工具成功安装
- [ ] Workflow成功导入
- [ ] 测试数据成功上传
- [ ] Workflow成功运行
- [ ] 所有5个作业成功完成
- [ ] 作业详情显示正确的云端destination
- [ ] AWS Batch显示作业记录
- [ ] S3显示数据上传和输出
- [ ] 可以下载并查看结果文件

全部打勾 = 云执行测试完全成功！ 🚀

---

## 📁 相关文件

- **Workflow**: `real_complex_workflow.ga`
- **测试数据**: `real_test_data/sample_reads.fastq.gz`
- **安装脚本**: `install_workflow_tools.py`
- **Job配置**: `config/job_conf_cloud.yml`

---

## 🔗 有用的命令

```bash
# 监控Galaxy
tail -f galaxy_startup.log | grep -i "cloud\|batch"

# 监控AWS Batch
watch -n 10 'aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING'

# 查看S3
watch -n 10 'aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive | tail -5'

# 查看Galaxy进程
ps aux | grep -E "gunicorn|celery" | grep galaxy

# 检查Galaxy API
curl http://localhost:8080/api/version
```

---

**准备好了！开始测试真实复杂workflow在云端的执行！** 🎯
