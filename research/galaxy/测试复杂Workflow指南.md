# 测试复杂Workflow完整指南

---

## 🎯 你要测试的复杂Workflow

**名称**: Real Bioinformatics Pipeline - QC and Analysis

**类型**: 真实的生物信息学分析流程

**复杂度**: ⭐⭐⭐⭐⭐
- 6个步骤（1个输入 + 5个工具）
- 5个真实的Tool Shed工具
- 多种资源需求（small/medium/large）
- 完整的数据流转

---

## 📊 Workflow详细结构

```
步骤0: Input FASTQ
  │ 输入: 原始测序数据（FASTQ格式）
  │ 大小: ~100KB (1000条reads)
  ↓

步骤1: FastQC (质量评估)
  │ 工具: toolshed.g2.bx.psu.edu/repos/devteam/fastqc
  │ 资源: cloud_small (2 vCPU, 4GB)
  │ 输出: HTML报告 + 文本统计
  ↓

步骤2: Trimmomatic (质量修剪)
  │ 工具: toolshed.g2.bx.psu.edu/repos/pjbriggs/trimmomatic
  │ 资源: cloud_medium (4 vCPU, 8GB)
  │ 输出: 修剪后的FASTQ
  ↓

步骤3: FastQC (修剪后质量评估)
  │ 工具: toolshed.g2.bx.psu.edu/repos/devteam/fastqc
  │ 资源: cloud_small (2 vCPU, 4GB)
  │ 输出: HTML报告 + 文本统计
  ↓

步骤4: Bowtie2 (序列比对)
  │ 工具: toolshed.g2.bx.psu.edu/repos/devteam/bowtie2
  │ 资源: cloud_large (8 vCPU, 16GB)
  │ 输出: BAM文件
  ↓

步骤5: BAM Stats (比对统计)
  │ 工具: toolshed.g2.bx.psu.edu/repos/devteam/bamtools_stats
  │ 资源: cloud_small (2 vCPU, 4GB)
  │ 输出: 统计报告
  ↓

最终输出: 5个分析结果文件
```

---

## 🚀 完整测试步骤

### 方式1: 使用交互式脚本（推荐）

```bash
bash test_cloud_execution.sh
```

选择 **选项2: 完整测试**

脚本会引导你：
1. ✅ 检查所有前置条件
2. ✅ 询问是否需要安装工具（首次需要）
3. ✅ 提供详细的操作步骤
4. ✅ 告诉你如何验证云执行

---

### 方式2: 手动完整步骤

#### 步骤1: 前置检查

```bash
# 1.1 检查AWS凭证
aws sts get-caller-identity
# ✅ 应该显示你的AWS账号信息

# 1.2 检查Batch Queue
aws batch describe-job-queues --job-queues galaxy-cloud-queue \
  --query 'jobQueues[0].state' --output text
# ✅ 应该输出: ENABLED

# 1.3 检查S3
aws s3 ls s3://galaxy-cloud-data-1760241377/
# ✅ 应该正常列出（可能为空）

# 1.4 检查Galaxy配置
grep "default: cloud_small" config/job_conf_cloud.yml
# ✅ 应该看到: default: cloud_small

# 1.5 检查Galaxy服务
ps aux | grep gunicorn | grep -v grep
# ✅ 应该看到gunicorn进程

# 1.6 检查Galaxy API
curl -s http://localhost:8080/api/version
# ✅ 应该返回JSON格式的版本信息
```

---

#### 步骤2: 获取Galaxy API Key

**通过Web界面**（推荐）:

1. 访问 http://localhost:8080
2. 登录或注册账号（如果还没有）
3. 点击右上角用户名 → **Preferences**
4. 左侧菜单 → **Manage API Key**
5. 点击 **"Create a new key"**
6. 复制显示的API Key

**保存到环境变量**:
```bash
export GALAXY_API_KEY="your_api_key_here"

# 或永久保存到 ~/.bashrc
echo 'export GALAXY_API_KEY="your_api_key_here"' >> ~/.bashrc
```

---

#### 步骤3: 安装Workflow所需工具（首次需要）

这个复杂workflow需要5个工具，如果是第一次测试，需要先安装。

**检查工具是否已安装**:
```bash
# 在Galaxy UI查看
# 访问: http://localhost:8080/admin/toolshed
# 查看 "Installed repositories"
```

**使用脚本安装工具**:

```bash
# 创建安装脚本
cat > install_complex_workflow_tools.py << 'EOF'
#!/usr/bin/env python3
"""
安装复杂workflow所需的所有工具
"""
import os
import requests
import time
import sys

GALAXY_URL = "http://localhost:8080"
API_KEY = os.environ.get("GALAXY_API_KEY")

if not API_KEY:
    print("❌ 错误: 请先设置 GALAXY_API_KEY 环境变量")
    print("   export GALAXY_API_KEY='your_key'")
    sys.exit(1)

# 工具列表
TOOLS = [
    {
        "name": "fastqc",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "5ec9f6bceaee",
        "description": "FastQC - 测序质量评估",
    },
    {
        "name": "trimmomatic",
        "owner": "pjbriggs",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "d94aff5ee623",
        "description": "Trimmomatic - 质量修剪",
    },
    {
        "name": "bowtie2",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "a9d4f71dbfb0",
        "description": "Bowtie2 - 序列比对",
    },
    {
        "name": "bamtools_stats",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "77f51726f39b",
        "description": "BAM Tools Stats - BAM统计",
    },
]

headers = {"x-api-key": API_KEY}

print("=" * 70)
print("开始安装复杂Workflow所需工具")
print("=" * 70)
print(f"\n需要安装 {len(TOOLS)} 个工具")
print("预计时间: 20-30分钟（首次需要下载Docker镜像）\n")

installed = 0
skipped = 0

for i, tool in enumerate(TOOLS, 1):
    print(f"\n[{i}/{len(TOOLS)}] 📦 {tool['description']}")
    print(f"         工具: {tool['name']}")
    print(f"         所有者: {tool['owner']}")

    data = {
        "tool_shed_url": tool["tool_shed_url"],
        "name": tool["name"],
        "owner": tool["owner"],
        "changeset_revision": tool["changeset_revision"],
        "install_tool_dependencies": True,
        "install_repository_dependencies": True,
    }

    try:
        response = requests.post(
            f"{GALAXY_URL}/api/tool_shed_repositories",
            json=data,
            headers=headers,
            timeout=10
        )

        if response.status_code in [200, 201]:
            print(f"         ✅ 安装请求已提交")
            installed += 1
        elif response.status_code == 400 and "already installed" in response.text.lower():
            print(f"         ⏭️  已安装，跳过")
            skipped += 1
        else:
            print(f"         ⚠️  状态码: {response.status_code}")
            print(f"         响应: {response.text[:100]}")

        time.sleep(2)  # 避免请求过快

    except Exception as e:
        print(f"         ❌ 错误: {e}")

print("\n" + "=" * 70)
print("安装请求完成")
print("=" * 70)
print(f"\n✅ 提交安装: {installed} 个工具")
print(f"⏭️  已安装跳过: {skipped} 个工具")

if installed > 0:
    print("\n⏳ 工具安装需要时间，请在Galaxy UI监控进度:")
    print("   访问: http://localhost:8080/admin/toolshed")
    print("   查看: Monitor installing repositories")
    print("\n💡 安装完成后即可运行workflow")
else:
    print("\n✅ 所有工具已安装，可以直接运行workflow!")
EOF

# 运行安装脚本
python3 install_complex_workflow_tools.py
```

**监控安装进度**:

访问 Galaxy UI:
- URL: http://localhost:8080/admin/toolshed
- 点击 "Monitor installing repositories"
- 等待所有工具状态变为 "Installed" ✅

---

#### 步骤4: 导入Workflow

**方式A: 通过Web界面**（推荐）

1. 访问 http://localhost:8080
2. 顶部菜单 → **Workflow**
3. 点击 **"Import"** 按钮（右上角）
4. 选择 **"Upload file from your computer"**
5. 选择文件: `real_complex_workflow.ga`
6. 点击 **"Import workflow"**
7. 等待导入完成 ✅

**方式B: 通过API**

```bash
python3 << 'EOF'
import os
import requests
import json

API_KEY = os.environ.get("GALAXY_API_KEY")
GALAXY_URL = "http://localhost:8080"
headers = {"x-api-key": API_KEY}

# 读取workflow文件
with open("real_complex_workflow.ga", "r") as f:
    workflow_data = json.load(f)

# 导入workflow
resp = requests.post(
    f"{GALAXY_URL}/api/workflows",
    json={"workflow": workflow_data},
    headers=headers
)

if resp.status_code == 200:
    workflow = resp.json()
    print(f"✅ Workflow已导入!")
    print(f"   ID: {workflow['id']}")
    print(f"   名称: {workflow['name']}")
    print(f"   步骤数: {len(workflow.get('steps', {}))}")
else:
    print(f"❌ 导入失败: {resp.status_code}")
    print(resp.text[:500])
EOF
```

---

#### 步骤5: 上传测试数据

测试数据位置: `real_test_data/sample_reads.fastq.gz`

**方式A: 通过Web界面**（推荐）

1. 访问 http://localhost:8080
2. 左侧工具栏 → **Upload Data** 图标（⬆️）
3. 点击 **"Choose local files"**
4. 选择: `real_test_data/sample_reads.fastq.gz`
5. Type: 选择 **"fastqsanger.gz"** 或 **"Auto-detect"**
6. 点击 **"Start"**
7. 等待上传完成 ✅

**方式B: 通过API**

```bash
python3 << 'EOF'
import os
import requests

API_KEY = os.environ.get("GALAXY_API_KEY")
GALAXY_URL = "http://localhost:8080"
headers = {"x-api-key": API_KEY}

# 获取或创建历史记录
resp = requests.get(f"{GALAXY_URL}/api/histories", headers=headers)
if resp.json():
    history_id = resp.json()[0]["id"]
    print(f"使用现有历史记录: {history_id}")
else:
    resp = requests.post(
        f"{GALAXY_URL}/api/histories",
        json={"name": "Complex Workflow Test"},
        headers=headers
    )
    history_id = resp.json()["id"]
    print(f"创建新历史记录: {history_id}")

# 上传文件
print("\n上传测试数据...")
with open("real_test_data/sample_reads.fastq.gz", "rb") as f:
    files = {"files_0|file_data": f}
    data = {
        "history_id": history_id,
        "tool_id": "upload1",
        "targets[0]|destination|type": "hdas",
    }

    resp = requests.post(
        f"{GALAXY_URL}/api/tools",
        data=data,
        files=files,
        headers=headers
    )

    if resp.status_code in [200, 201]:
        print("✅ 数据上传成功!")
        print(f"   历史记录ID: {history_id}")
    else:
        print(f"❌ 上传失败: {resp.status_code}")
        print(resp.text[:500])
EOF
```

---

#### 步骤6: 运行Workflow

**方式A: 通过Web界面**（推荐）

1. 访问 http://localhost:8080
2. 顶部菜单 → **Workflow**
3. 找到 **"Real Bioinformatics Pipeline - QC and Analysis"**
4. 点击右侧的 **▶️ 运行按钮**
5. **配置输入**:
   - Input FASTQ: 选择刚上传的 `sample_reads.fastq.gz`
6. 点击 **"Run Workflow"**
7. 等待执行开始 ✅

**方式B: 通过API**

```bash
python3 << 'EOF'
import os
import requests
import time

API_KEY = os.environ.get("GALAXY_API_KEY")
GALAXY_URL = "http://localhost:8080"
headers = {"x-api-key": API_KEY}

# 获取workflow
resp = requests.get(f"{GALAXY_URL}/api/workflows", headers=headers)
workflows = resp.json()
target_wf = None

for wf in workflows:
    if "Real Bioinformatics Pipeline" in wf.get("name", ""):
        target_wf = wf
        break

if not target_wf:
    print("❌ 未找到workflow")
    exit(1)

workflow_id = target_wf["id"]
print(f"✅ 找到workflow: {target_wf['name']}")

# 获取历史记录和数据集
resp = requests.get(f"{GALAXY_URL}/api/histories", headers=headers)
history_id = resp.json()[0]["id"]

resp = requests.get(
    f"{GALAXY_URL}/api/histories/{history_id}/contents",
    headers=headers
)
datasets = [d for d in resp.json() if d["type"] == "file" and "fastq" in d.get("name", "").lower()]

if not datasets:
    print("❌ 未找到FASTQ数据集")
    exit(1)

input_dataset_id = datasets[0]["id"]
print(f"✅ 使用数据集: {datasets[0]['name']}")

# 运行workflow
print("\n🚀 启动workflow...")
run_data = {
    "history_id": history_id,
    "inputs": {
        "0": {"id": input_dataset_id, "src": "hda"}
    },
}

resp = requests.post(
    f"{GALAXY_URL}/api/workflows/{workflow_id}/invocations",
    json=run_data,
    headers=headers
)

if resp.status_code in [200, 201]:
    invocation = resp.json()
    print(f"\n✅ Workflow已启动!")
    print(f"   Invocation ID: {invocation['id']}")
    print(f"   历史记录: {history_id}")
    print(f"\n🔍 查看进度:")
    print(f"   http://localhost:8080/workflows/invocations")
    print(f"\n⏳ 预计执行时间: 10-20分钟")
else:
    print(f"❌ 启动失败: {resp.status_code}")
    print(resp.text[:500])
EOF
```

---

#### 步骤7: 验证云端执行（重要！）

**7.1 在Galaxy UI验证**

1. 访问 http://localhost:8080
2. 右侧历史记录面板查看作业状态
3. 点击任意作业（如"FastQC"）
4. 查看 **"Job Information"** 部分
5. 检查 **"Job Destination"**

**✅ 应该显示**:
- `cloud_small` (FastQC, BAM Stats)
- `cloud_medium` (Trimmomatic)
- `cloud_large` (Bowtie2)

**7.2 在AWS Batch验证**

```bash
# 查看运行中的作业
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status RUNNING \
  --query 'jobSummaryList[*].[jobName,status,createdAt]' \
  --output table

# 预期输出: 显示5个作业（对应5个workflow步骤）

# 查看所有状态
for status in SUBMITTED PENDING RUNNABLE STARTING RUNNING SUCCEEDED FAILED; do
  echo "=== $status ==="
  COUNT=$(aws batch list-jobs \
    --job-queue galaxy-cloud-queue \
    --job-status $status \
    --query 'length(jobSummaryList)' \
    --output text)
  echo "作业数: $COUNT"
  echo
done
```

**7.3 在S3验证数据传输**

```bash
# 查看上传的输入数据
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep input

# 查看下载的输出数据
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep output

# 查看workflow staging区
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/ --recursive
```

**7.4 实时监控**

```bash
# 在一个终端监控Galaxy日志
tail -f galaxy_startup.log | grep -i "cloud\|batch\|submit"

# 在另一个终端监控AWS Batch
watch -n 5 'aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status RUNNING \
  --query "length(jobSummaryList)"'
```

---

## ✅ 测试成功标志

### Galaxy作业详情
```
每个作业应该显示:
  ✅ Tool: FastQC/Trimmomatic/Bowtie2/BAM Stats
  ✅ State: ok (绿色)
  ✅ Job Destination: cloud_small/medium/large
  ✅ Job Runner: GalaxyCloudJobRunner
```

### AWS Batch
```bash
$ aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED

应该看到5个SUCCEEDED作业:
  ✅ galaxy-fastqc-xxx (SUCCEEDED)
  ✅ galaxy-trimmomatic-xxx (SUCCEEDED)
  ✅ galaxy-fastqc-xxx (SUCCEEDED)
  ✅ galaxy-bowtie2-xxx (SUCCEEDED)
  ✅ galaxy-bamtools_stats-xxx (SUCCEEDED)
```

### S3数据
```bash
$ aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive

应该看到输入和输出文件:
  ✅ jobs/xxx/inputs/sample_reads.fastq.gz
  ✅ jobs/xxx/outputs/fastqc_report.html
  ✅ jobs/xxx/outputs/trimmed.fastq
  ✅ jobs/xxx/outputs/aligned.bam
  ✅ jobs/xxx/outputs/stats.txt
```

### Galaxy输出
```
历史记录中应该有5个成功的输出:
  ✅ FastQC报告1 (HTML)
  ✅ 修剪后的FASTQ
  ✅ FastQC报告2 (HTML)
  ✅ 比对结果 (BAM)
  ✅ 比对统计 (TXT)
```

---

## 📊 执行时间估计

| 步骤 | 工具 | 资源 | 预计时间 |
|------|------|------|----------|
| 1 | FastQC | cloud_small | 2-3分钟 |
| 2 | Trimmomatic | cloud_medium | 3-5分钟 |
| 3 | FastQC | cloud_small | 2-3分钟 |
| 4 | Bowtie2 | cloud_large | 5-8分钟 |
| 5 | BAM Stats | cloud_small | 1-2分钟 |

**总执行时间**: 约15-25分钟（取决于AWS资源可用性）

---

## ❌ 常见问题

### 问题1: 工具未安装

**症状**: Workflow导入失败或运行时提示工具不存在

**解决**:
```bash
# 检查工具安装状态
curl -s http://localhost:8080/api/tool_shed_repositories \
  -H "x-api-key: $GALAXY_API_KEY" | grep -i "fastqc\|trimmomatic\|bowtie"

# 重新运行安装脚本
python3 install_complex_workflow_tools.py
```

### 问题2: 作业失败

**症状**: 作业状态为 "error" (红色)

**检查**:
1. 点击失败的作业
2. 查看 "Tool Standard Error" 或 "Job Information"
3. 查看AWS Batch作业日志

```bash
# 获取失败的Batch作业
FAILED_JOB=$(aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status FAILED \
  --query 'jobSummaryList[0].jobId' \
  --output text)

# 查看失败原因
aws batch describe-jobs --jobs $FAILED_JOB \
  --query 'jobs[0].statusReason'
```

### 问题3: 作业一直在队列中

**症状**: 作业状态一直是 "queued" (灰色)

**检查**:
```bash
# 检查Galaxy日志
grep -i "error\|fail" galaxy_startup.log | tail -20

# 检查云执行模块
python3 -c "import galaxy_cloud; print(galaxy_cloud.__file__)"
```

**解决**:
- 重启Galaxy服务
- 检查AWS凭证是否过期

---

## 🎯 测试检查清单

运行复杂workflow前的检查清单:

- [ ] AWS凭证有效（`aws sts get-caller-identity`）
- [ ] Batch Queue状态ENABLED
- [ ] S3 Bucket可访问
- [ ] Galaxy配置为完全云端（`default: cloud_small`）
- [ ] Galaxy服务运行正常
- [ ] API Key已获取并设置
- [ ] 所有工具已安装（FastQC, Trimmomatic, Bowtie2, BAM Stats）
- [ ] Workflow已导入
- [ ] 测试数据已上传
- [ ] 准备好监控工具（AWS CLI, Galaxy UI）

---

## 🎊 成功！

如果你看到:
- ✅ Galaxy中5个作业全部成功（绿色）
- ✅ AWS Batch中5个作业状态SUCCEEDED
- ✅ S3中有完整的输入输出文件
- ✅ 历史记录中有所有输出结果

**恭喜！复杂workflow云执行测试成功！** 🎉

这证明你的Galaxy云执行配置完全正常，可以处理真实的复杂生物信息学分析流程！

---

**文档版本**: 1.0
**更新时间**: 2025-10-18
**Workflow复杂度**: ⭐⭐⭐⭐⭐
**预计总时间**: 40-60分钟（含工具安装）
