# Workflow 测试工具的输入数据说明

## 🎯 核心概念

当前的测试工具有**两种用途**：

### 1. `run_any_workflow.py` - 结构测试工具（当前版本）⭐

**目的**：测试 workflow 的执行结构，不处理真实数据

**工作方式**：
```python
# 输入步骤（step 0）
命令: echo "Mock data for step 0" > /tmp/output.txt
上传: s3://bucket/test-id/step_0_output.txt

# 处理步骤（step 1）
1. 下载: s3://bucket/test-id/step_0_output.txt → /tmp/input_0.txt
2. 执行: echo "Processing step 1" > /tmp/output.txt
3. 合并: cat /tmp/input_0.txt >> /tmp/output.txt
4. 上传: s3://bucket/test-id/step_1_output.txt
```

**测试内容**：
- ✅ Workflow DAG 结构是否正确
- ✅ 步骤依赖关系是否正确
- ✅ AWS Batch 作业调度
- ✅ S3 数据传递
- ✅ 并行执行策略

**不测试内容**：
- ❌ 真实的生物信息学工具
- ❌ 真实的数据处理结果
- ❌ 工具的正确性

---

### 2. `run_workflow_with_real_data.py` - 真实数据执行（未完成）

**目的**：执行真实的工具和数据

**需要的条件**：
1. 真实的输入文件（FASTQ、FASTA 等）
2. 正确的 Docker 镜像（BioContainers）
3. 工具的完整参数配置
4. 输入/输出格式匹配

**示例用法**：
```bash
python3 run_workflow_with_real_data.py workflow.json \\
    --input 0:/path/to/reads.fastq \\
    --input 1:/path/to/reference.fasta \\
    --output-dir ./results
```

---

## 📊 输入数据的三种场景

### 场景 1: 测试 Workflow 结构（推荐）

**使用工具**: `run_any_workflow.py`

**不需要真实数据**，脚本自动生成模拟数据：

```bash
cd testing
python3 run_any_workflow.py ../../ai/data/workflows/workflow_xxx.json
```

**workflow JSON 中的输入步骤**：
```json
{
  "steps": {
    "0": {
      "type": "data_input",
      "label": "Input dataset",
      "tool_id": null
    }
  }
}
```

**脚本自动生成**：
```bash
# 对于输入步骤，生成假数据
echo "Mock input data for step 0" > /tmp/input.txt
aws s3 cp /tmp/input.txt s3://bucket/test-id/step_0_output.txt
```

---

### 场景 2: 使用真实数据测试（未来）

**使用工具**: `run_workflow_with_real_data.py`（需要完善）

**需要提供真实文件**：

```bash
# 1. 准备输入文件
ls -lh /data/sample1.fastq  # 100MB
ls -lh /data/ref.fasta      # 3GB

# 2. 运行 workflow
python3 run_workflow_with_real_data.py workflow.json \\
    --input 0:/data/sample1.fastq \\
    --input 1:/data/ref.fasta \\
    --output-dir ./results

# 3. 下载结果
aws s3 sync s3://bucket/test-id/ ./results/
```

**需要的额外配置**：
- 正确的 Docker 镜像（BioContainers）
- 工具参数（从 workflow JSON 提取）
- 资源配置（CPU、内存）

---

### 场景 3: Galaxy UI 中运行（生产环境）

**推荐方式**：在 Galaxy UI 中上传数据并运行

**工作流程**：
1. 用户在 Galaxy UI 上传输入文件
2. Galaxy 存储文件到 `database/files/`
3. 用户选择 workflow 并选择输入数据集
4. Galaxy 调用 `GalaxyCloudJobRunner`
5. Runner 自动：
   - 上传输入文件到 S3
   - 提交 AWS Batch 作业
   - 执行真实工具（BioContainers）
   - 下载输出文件
   - 导入到 Galaxy history

**这是最终目标**，当前我们在做的是步骤 4-5 的底层测试。

---

## 🔍 详细示例：Workflow 如何处理输入

### 示例 Workflow（3步）

```json
{
  "steps": {
    "0": {
      "type": "data_input",
      "label": "Input reads",
      "outputs": [{"name": "output", "type": "fastqsanger"}]
    },
    "1": {
      "type": "tool",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc",
      "input_connections": {
        "input_file": {"id": 0, "output_name": "output"}
      }
    },
    "2": {
      "type": "tool",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/multiqc",
      "input_connections": {
        "results": {"id": 1, "output_name": "html_file"}
      }
    }
  }
}
```

### 当前测试工具的执行过程

#### Step 0（输入步骤）
```bash
# 生成模拟数据
echo "Mock FASTQ data" > /tmp/output.txt
echo "@SEQ1" >> /tmp/output.txt
echo "ATCGATCG" >> /tmp/output.txt

# 上传到 S3
aws s3 cp /tmp/output.txt s3://bucket/test-20251015/step_0_output.txt
```

#### Step 1（FastQC - 依赖 step 0）
```bash
# 下载 step 0 的输出
aws s3 cp s3://bucket/test-20251015/step_0_output.txt /tmp/input_0.txt

# 模拟 FastQC 执行
echo "Executing FastQC" > /tmp/output.txt
cat /tmp/input_0.txt >> /tmp/output.txt
echo "FastQC completed" >> /tmp/output.txt

# 上传输出
aws s3 cp /tmp/output.txt s3://bucket/test-20251015/step_1_output.txt
```

#### Step 2（MultiQC - 依赖 step 1）
```bash
# 下载 step 1 的输出
aws s3 cp s3://bucket/test-20251015/step_1_output.txt /tmp/input_1.txt

# 模拟 MultiQC 执行
echo "Executing MultiQC" > /tmp/output.txt
cat /tmp/input_1.txt >> /tmp/output.txt
echo "MultiQC report generated" >> /tmp/output.txt

# 上传输出
aws s3 cp /tmp/output.txt s3://bucket/test-20251015/step_2_output.txt
```

---

## ❓ 常见问题

### Q1: 为什么不直接使用真实数据测试？

**A**: 因为真实数据测试需要：

1. **正确的工具镜像**：
   ```bash
   # 需要知道每个 tool_id 对应的 Docker 镜像
   fastqc → quay.io/biocontainers/fastqc:0.11.9--0
   bwa    → quay.io/biocontainers/bwa:0.7.17--h5bf99c6_8
   ```

2. **工具参数解析**：
   ```python
   # 需要从 workflow JSON 提取参数
   tool_state = json.loads(step_data['tool_state'])
   # 转换为命令行参数
   fastqc --threads 4 --outdir /output input.fastq
   ```

3. **数据格式验证**：
   ```bash
   # 确保输入输出格式匹配
   step 0 输出: fastqsanger
   step 1 期望: fastqsanger ✅
   ```

4. **资源配置**：
   ```python
   # 不同工具需要不同资源
   fastqc: 2 vCPU, 4GB 内存
   bwa:    8 vCPU, 16GB 内存
   ```

**当前的测试工具专注于验证执行结构**，这些是在 Galaxy UI 集成后自动处理的。

---

### Q2: 输入步骤（data_input）的数据从哪来？

**测试工具**：自动生成模拟数据
```bash
echo "Mock data" > /tmp/input.txt
```

**Galaxy UI**：用户上传的文件
```python
# Galaxy 会提供真实文件路径
input_file = "/galaxy/database/files/000/dataset_123.dat"
```

---

### Q3: 如何验证 workflow 能否处理真实数据？

**推荐流程**：

1. **使用 `run_any_workflow.py` 测试结构**：
   ```bash
   python3 run_any_workflow.py workflow.json
   # 验证：依赖关系、并行执行、S3传递
   ```

2. **检查 workflow 中的工具**：
   ```bash
   python3 analyze_real_workflow.py workflow.json
   # 查看使用的工具列表
   ```

3. **查询工具的 Docker 镜像**：
   - 访问：https://biocontainers.pro/
   - 搜索工具名称
   - 确认镜像存在

4. **在 Galaxy UI 中测试**：
   - 上传小数据集（1-10MB）
   - 运行 workflow
   - 检查结果

---

## 🚀 下一步计划

要支持真实数据，需要实现：

### 1. 工具注册表
```python
TOOL_REGISTRY = {
    'toolshed.g2.bx.psu.edu/repos/devteam/fastqc': {
        'image': 'quay.io/biocontainers/fastqc:0.11.9--0',
        'command_template': 'fastqc {input} -o {output_dir}',
        'resources': {'vcpus': 2, 'memory': 4096}
    }
}
```

### 2. 参数解析器
```python
def parse_tool_params(tool_state: str) -> dict:
    """从 tool_state JSON 提取参数"""
    state = json.loads(tool_state)
    # 转换为命令行参数
    return convert_to_cli_args(state)
```

### 3. 数据上传/下载
```python
def upload_galaxy_dataset(dataset_id: int) -> str:
    """上传 Galaxy dataset 到 S3"""
    file_path = galaxy.get_dataset_path(dataset_id)
    s3_key = f'inputs/{dataset_id}'
    s3.upload_file(file_path, bucket, s3_key)
    return s3_key
```

---

## 📚 总结

| 维度 | run_any_workflow.py | Galaxy UI 集成 |
|------|-------------------|---------------|
| **输入数据** | 自动生成模拟数据 | 用户上传真实文件 |
| **工具执行** | echo 模拟命令 | BioContainers 真实工具 |
| **测试目标** | Workflow 结构 | 完整数据分析 |
| **使用场景** | 开发测试 | 生产环境 |
| **当前状态** | ✅ 完成 | ⏳ 集成中 |

**推荐**：
1. 使用 `run_any_workflow.py` 测试复杂 workflow 的结构
2. 使用 `analyze_real_workflow.py` 分析 workflow 复杂度
3. 在 Galaxy UI 中运行真实数据分析

---

**更新时间**: 2025-10-15
**相关文档**: [full_docs/05-Workflow云测试工具详解.md](../full_docs/05-Workflow云测试工具详解.md)
