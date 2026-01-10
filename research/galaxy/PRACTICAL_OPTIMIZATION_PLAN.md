# Galaxy云原生架构优化实施方案
## 基于Nextflow思想的渐进式改造

---

## 当前问题总结

### 性能瓶颈分析

1. **Docker-in-Docker 开销** - 每个任务启动额外容器 (30-60秒)
2. **运行时依赖安装** - R包/Python包编译时间 (2-10分钟)
3. **手动S3传输** - 多次aws s3 cp命令，串行传输
4. **Fetch-and-run wrapper** - 额外的包装层，增加复杂度

### 你已经做得很好的部分

✅ 实现了fetch-and-run的预装环境 (A+B方案)
✅ 动态BiocManager包安装
✅ 支持90%的工具快速启动
✅ 完整的S3文件管理

---

## 优化方案: 三阶段演进

### 🚀 阶段1: 快速优化 (1-2周)
**目标:** 在现有架构上提升50%性能，零风险

#### 1.1 使用AWS Mountpoint for S3 替代手动传输

**原理:** 将S3挂载为POSIX文件系统，消除显式的aws s3 cp命令

**实施步骤:**

```bash
# 1. 在fetch-and-run容器中安装Mountpoint
# Dockerfile更新:
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest

# 安装AWS Mountpoint for S3
RUN wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb && \
    apt-get install -y ./mount-s3.deb && \
    rm mount-s3.deb

# 更新entrypoint脚本
COPY fetch_and_run_mountpoint.sh /usr/local/bin/
```

**新的fetch_and_run_mountpoint.sh:**

```bash
#!/bin/bash
set -e

# 1. 挂载S3 bucket到/mnt/s3
echo "Mounting S3 bucket..."
mkdir -p /mnt/s3
mount-s3 \
    --region ${AWS_REGION} \
    --cache /tmp/s3-cache \
    --max-threads 16 \
    ${S3_BUCKET} /mnt/s3

# 2. 设置环境变量
export GALAXY_INPUT_DIR="/mnt/s3/jobs/${JOB_ID}/datasets"
export GALAXY_OUTPUT_DIR="/mnt/s3/jobs/${JOB_ID}/datasets"
export GALAXY_WORK_DIR="/tmp/work"

# 3. 下载并执行job script (script现在直接读写/mnt/s3)
aws s3 cp "${JOB_SCRIPT_S3_URL}" /tmp/job_script.sh
chmod +x /tmp/job_script.sh
/tmp/job_script.sh

# 4. 卸载S3 (自动上传缓存的写入)
umount /mnt/s3

echo "Job completed successfully"
```

**预期效果:**
- ✅ 消除显式的aws s3 cp命令
- ✅ 自动并行上传/下载
- ✅ 按需lazy读取 (只下载需要的数据块)
- ✅ 后台异步写入
- 🎯 **文件传输时间减少 50-70%**

---

#### 1.2 优化容器镜像 - 预装TOP 20工具

**策略:** 为高频工具构建专用镜像，而不是全部动态安装

**实施步骤:**

```bash
# 1. 统计工具使用频率
cd /Users/renyuankai/work/biometa/galaxy
python3 <<EOF
from galaxy.model import Job
from galaxy.model.orm.now import now
from sqlalchemy import create_engine, func
from datetime import datetime, timedelta

# 连接Galaxy数据库
engine = create_engine("sqlite:///database/universe.sqlite")

# 查询最近30天使用最多的工具
query = """
SELECT tool_id, COUNT(*) as usage_count
FROM job
WHERE create_time > datetime('now', '-30 days')
GROUP BY tool_id
ORDER BY usage_count DESC
LIMIT 20
"""

result = engine.execute(query)
for row in result:
    print(f"{row.tool_id}: {row.usage_count}")
EOF

# 2. 为TOP 20工具构建专用容器
# 例如：FastQC, Trimmomatic, STAR, DESeq2...
```

**专用容器Dockerfile示例 (FastQC):**

```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest

# 安装FastQC (BioContainer方式)
RUN conda install -c bioconda fastqc=0.12.1 -y && \
    conda clean -afy

# 预装Mountpoint
RUN wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb && \
    apt-get install -y ./mount-s3.deb && \
    rm mount-s3.deb

# 标记为专用容器
ENV GALAXY_TOOL_ID="fastqc"
ENV CONTAINER_TYPE="tool-specific"
```

**job_conf.yml 配置:**

```yaml
tools:
  - id: fastqc
    environment: fastqc_cloud

execution:
  environments:
    fastqc_cloud:
      runner: galaxy_cloud
      params:
        use_fetch_and_run: true
        fetch_and_run_image: 399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tool-fastqc:latest
        provider: aws
        aws_region: us-west-2
        aws_batch_queue: galaxy-cloud-queue
        aws_s3_bucket: galaxy-cloud-data-1760241377
```

**预期效果:**
- ✅ TOP 20工具启动时间: 2-3分钟 → 30秒
- ✅ 消除R包编译等待
- ✅ 覆盖80%的实际使用场景
- 🎯 **平均任务启动时间减少 60%**

---

#### 1.3 实现智能容器选择逻辑

**在galaxy_job_runner.py中增强容器选择:**

```python
async def _get_optimal_container_image(self, job_wrapper, job_destination) -> str:
    """
    智能选择最优容器镜像

    优先级:
    1. 工具专用容器 (如果存在)
    2. BioContainers官方镜像
    3. 通用fetch-and-run容器 (fallback)
    """
    tool_id = job_wrapper.tool.id if job_wrapper.tool else None

    # 1. 检查是否有工具专用容器
    tool_specific_images = {
        'fastqc': f'{ECR_REPO}/galaxy-tool-fastqc:latest',
        'trimmomatic': f'{ECR_REPO}/galaxy-tool-trimmomatic:latest',
        'star': f'{ECR_REPO}/galaxy-tool-star:latest',
        'deseq2': f'{ECR_REPO}/galaxy-tool-deseq2:latest',
        # ... TOP 20 工具
    }

    if tool_id in tool_specific_images:
        self.logger.info(f"Using tool-specific container for {tool_id}")
        return tool_specific_images[tool_id]

    # 2. 尝试获取BioContainers镜像
    if hasattr(job_wrapper.tool, 'requirements'):
        packages = job_wrapper.tool.requirements.packages
        if packages:
            primary_package = packages[0]
            biocontainer = await self._lookup_biocontainer(
                primary_package.name,
                primary_package.version
            )
            if biocontainer:
                self.logger.info(f"Using BioContainer: {biocontainer}")
                return biocontainer

    # 3. Fallback: 通用fetch-and-run容器
    self.logger.info(f"Using generic fetch-and-run container for {tool_id}")
    return job_destination.params.get(
        'fetch_and_run_image',
        f'{ECR_REPO}/galaxy-fetch-and-run:latest'
    )

async def _lookup_biocontainer(self, package_name: str, version: str) -> Optional[str]:
    """查询BioContainers仓库"""
    try:
        # 尝试Quay.io
        image = f"quay.io/biocontainers/{package_name}:{version}"
        # 验证镜像是否存在 (可以用docker manifest或API)
        # ...
        return image
    except:
        return None
```

**预期效果:**
- ✅ 自动使用最优容器
- ✅ 减少依赖安装时间
- ✅ 提高缓存命中率

---

### 🔥 阶段2: 架构优化 (1-2个月)
**目标:** 借鉴Nextflow设计，但保留Galaxy核心

#### 2.1 实现轻量级Fusion-like存储层

**不使用Nextflow本身，只借鉴其Fusion设计思想**

```python
# lib/galaxy/galaxy-cloud-executor/galaxy_cloud/storage/fusion_lite.py

import os
from pathlib import Path
from typing import Optional

class FusionLiteFileSystem:
    """
    轻量级Fusion文件系统实现

    原理: 在容器中透明代理S3访问
    - 读取: Lazy download + 本地缓存
    - 写入: 本地缓存 + 后台异步上传
    """

    def __init__(self, s3_bucket: str, mount_point: str = "/fusion"):
        self.s3_bucket = s3_bucket
        self.mount_point = mount_point
        self.cache_dir = "/tmp/fusion-cache"
        os.makedirs(self.cache_dir, exist_ok=True)

    def setup_mount(self):
        """使用Mountpoint for S3实现挂载"""
        cmd = [
            'mount-s3',
            '--region', os.environ['AWS_REGION'],
            '--cache', self.cache_dir,
            '--max-threads', '16',
            self.s3_bucket,
            self.mount_point
        ]
        subprocess.run(cmd, check=True)

        # 设置环境变量，让Galaxy以为文件在本地
        os.environ['GALAXY_FUSION_MOUNT'] = self.mount_point

    def rewrite_path(self, galaxy_path: str) -> str:
        """
        重写Galaxy路径到Fusion挂载点

        例如:
        /galaxy/database/files/001/dataset_123.dat
        → /fusion/datasets/001/dataset_123.dat
        """
        if galaxy_path.startswith('/galaxy/database/files'):
            rel_path = galaxy_path.replace('/galaxy/database/files', '')
            return f"{self.mount_point}/datasets{rel_path}"
        return galaxy_path
```

**在job script中使用:**

```bash
#!/bin/bash
# Galaxy job script with Fusion Lite

# 挂载S3
python3 -c "
from galaxy_cloud.storage.fusion_lite import FusionLiteFileSystem
fs = FusionLiteFileSystem('${S3_BUCKET}')
fs.setup_mount()
"

# 现在所有S3文件都像本地文件一样访问
fastqc /fusion/datasets/001/input.fastq -o /fusion/datasets/002/

# 自动上传到S3 (Mountpoint后台处理)
```

**预期效果:**
- ✅ 工具无需修改即可使用S3
- ✅ POSIX兼容性
- ✅ 自动缓存和预取
- 🎯 **I/O性能提升 40-60%**

---

#### 2.2 容器动态增强系统 (类Wave)

**使用BuildKit实现按需容器构建**

```python
# lib/galaxy/galaxy-cloud-executor/galaxy_cloud/containers/dynamic_builder.py

import hashlib
from typing import Dict, List
import docker
from docker import APIClient

class DynamicContainerBuilder:
    """
    动态容器构建器 - 借鉴Nextflow Wave

    工作流程:
    1. 解析工具的conda/pip依赖
    2. 生成Dockerfile
    3. 使用BuildKit构建 (利用层缓存)
    4. 推送到ECR临时仓库
    5. 缓存镜像URI (避免重复构建)
    """

    def __init__(self, ecr_repo: str, cache_backend='redis'):
        self.ecr_repo = ecr_repo
        self.docker_client = docker.from_env()
        self.cache = {}  # 可以用Redis替代

    async def build_tool_container(
        self,
        tool_id: str,
        conda_packages: List[str],
        pip_packages: List[str] = None
    ) -> str:
        """构建工具专用容器"""

        # 1. 生成缓存key
        cache_key = self._generate_cache_key(tool_id, conda_packages, pip_packages)

        # 2. 检查缓存
        if cache_key in self.cache:
            self.logger.info(f"Using cached container for {tool_id}")
            return self.cache[cache_key]

        # 3. 生成Dockerfile
        dockerfile = self._generate_dockerfile(conda_packages, pip_packages)

        # 4. 使用BuildKit构建 (自动缓存层)
        image_tag = f"{self.ecr_repo}/dynamic/{tool_id}:{cache_key[:8]}"

        self.logger.info(f"Building container for {tool_id}...")
        self.docker_client.images.build(
            fileobj=dockerfile,
            tag=image_tag,
            buildargs={'BUILDKIT_INLINE_CACHE': '1'},
            cache_from=[f"{self.ecr_repo}/dynamic/base:latest"]
        )

        # 5. 推送到ECR
        self.docker_client.images.push(image_tag)

        # 6. 缓存结果
        self.cache[cache_key] = image_tag

        return image_tag

    def _generate_dockerfile(self, conda_packages: List[str], pip_packages: List[str]) -> str:
        """生成Dockerfile"""
        dockerfile = f"""
FROM mambaorg/micromamba:latest

# 安装Mountpoint for S3
RUN wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb && \\
    apt-get update && apt-get install -y ./mount-s3.deb && \\
    rm mount-s3.deb

# 安装Conda包 (使用mamba加速)
RUN micromamba install -y -c conda-forge -c bioconda \\
    {' '.join(conda_packages)} && \\
    micromamba clean -afy
"""

        if pip_packages:
            dockerfile += f"""
# 安装Python包
RUN pip install --no-cache-dir {' '.join(pip_packages)}
"""

        dockerfile += """
# 设置工作目录
WORKDIR /galaxy-work

# Entrypoint
ENTRYPOINT ["/usr/local/bin/fetch_and_run_mountpoint.sh"]
"""
        return dockerfile

    def _generate_cache_key(self, tool_id: str, conda_pkgs: List[str], pip_pkgs: List[str]) -> str:
        """生成缓存key"""
        content = f"{tool_id}:{sorted(conda_pkgs)}:{sorted(pip_pkgs or [])}"
        return hashlib.sha256(content.encode()).hexdigest()
```

**集成到job runner:**

```python
# galaxy_job_runner.py

async def _submit_fetch_and_run_job(self, job_wrapper, job_destination):
    # ...

    # 检查是否需要动态构建容器
    if self._should_use_dynamic_container(job_wrapper):
        self.logger.info(f"Building dynamic container for {job_wrapper.tool.id}")

        # 提取依赖
        conda_packages = self._extract_conda_requirements(job_wrapper)

        # 动态构建
        container_builder = DynamicContainerBuilder(self.ecr_repo)
        fetch_and_run_image = await container_builder.build_tool_container(
            tool_id=job_wrapper.tool.id,
            conda_packages=conda_packages
        )

        self.logger.info(f"Using dynamic container: {fetch_and_run_image}")
    else:
        # 使用预构建容器或通用容器
        fetch_and_run_image = await self._get_optimal_container_image(
            job_wrapper, job_destination
        )

    # ... 继续提交job
```

**预期效果:**
- ✅ 无需预构建所有工具容器
- ✅ 按需构建，自动缓存
- ✅ 支持任意conda/pip组合
- 🎯 **支持100%的Galaxy工具，零手动维护**

---

### 🌟 阶段3: 高级特性 (2-3个月)
**目标:** 实现完整云原生体验

#### 3.1 Workflow级别优化

**问题:** 当前每个job独立提交，workflow中有依赖等待

**解决方案:** Workflow批量提交 + DAG调度

```python
# lib/galaxy/galaxy-cloud-executor/galaxy_cloud/workflow/batch_executor.py

class WorkflowBatchExecutor:
    """
    Workflow批量执行器

    将整个workflow的所有jobs一次性提交到AWS Batch
    利用AWS Batch的Job Dependencies实现DAG调度
    """

    async def submit_workflow(self, workflow, input_datasets):
        """
        批量提交workflow中的所有jobs

        AWS Batch支持job dependencies:
        job2.depends_on = [job1.id]
        job3.depends_on = [job2.id]
        """

        # 1. 解析workflow DAG
        dag = self._parse_workflow_dag(workflow)

        # 2. 为每个step准备job spec
        job_specs = {}
        for step in workflow.steps:
            job_spec = self._create_job_spec_for_step(step)
            job_specs[step.id] = job_spec

        # 3. 批量提交到AWS Batch (带依赖关系)
        batch_client = boto3.client('batch')
        job_ids = {}

        for step_id, job_spec in job_specs.items():
            # 找到依赖的jobs
            dependencies = []
            for dep_step_id in dag.get_dependencies(step_id):
                if dep_step_id in job_ids:
                    dependencies.append({
                        'jobId': job_ids[dep_step_id],
                        'type': 'SEQUENTIAL'
                    })

            # 提交job
            response = batch_client.submit_job(
                jobName=f"workflow_{workflow.id}_step_{step_id}",
                jobQueue=self.batch_queue,
                jobDefinition=self.job_definition,
                containerOverrides=job_spec.to_container_overrides(),
                dependsOn=dependencies  # AWS Batch原生依赖支持
            )

            job_ids[step_id] = response['jobId']
            self.logger.info(f"Submitted step {step_id} as job {response['jobId']}")

        return job_ids
```

**预期效果:**
- ✅ 消除Galaxy scheduler开销
- ✅ AWS Batch原生DAG调度
- ✅ 并行度最大化
- 🎯 **Workflow总执行时间减少 30-50%**

---

#### 3.2 成本优化 - Spot实例支持

**配置AWS Batch使用Spot实例:**

```yaml
# job_conf.yml
execution:
  environments:
    cloud_spot:
      runner: galaxy_cloud
      params:
        use_fetch_and_run: true
        provider: aws
        aws_region: us-west-2
        aws_batch_queue: galaxy-cloud-queue-spot  # 使用Spot队列
        aws_s3_bucket: galaxy-cloud-data-1760241377
        # Spot配置
        spot_bid_percentage: 80  # 比按需价格低80%
        retry_attempts: 3  # Spot中断自动重试
```

**AWS Batch Compute Environment配置:**

```bash
# 创建Spot计算环境
aws batch create-compute-environment \
  --compute-environment-name galaxy-spot \
  --type MANAGED \
  --compute-resources '{
    "type": "SPOT",
    "allocationStrategy": "SPOT_CAPACITY_OPTIMIZED",
    "bidPercentage": 80,
    "instanceTypes": ["optimal"],
    "minvCpus": 0,
    "maxvCpus": 256,
    "subnets": ["subnet-xxx"],
    "securityGroupIds": ["sg-xxx"],
    "instanceRole": "arn:aws:iam::xxx:instance-profile/ecsInstanceRole"
  }'
```

**预期效果:**
- 🎯 **成本降低 60-80%**
- ✅ 自动fallback到按需实例
- ✅ 适合非紧急任务

---

## 实施计划时间表

### Week 1-2: 阶段1快速优化
- [ ] Day 1-2: 实现Mountpoint for S3集成
- [ ] Day 3-5: 构建TOP 20工具专用容器
- [ ] Day 6-8: 实现智能容器选择逻辑
- [ ] Day 9-10: 测试和性能对比

**预期效果:** 性能提升50%，零风险

### Week 3-8: 阶段2架构优化
- [ ] Week 3-4: 实现FusionLite存储层
- [ ] Week 5-6: 实现动态容器构建系统
- [ ] Week 7-8: 集成测试和性能调优

**预期效果:** 性能提升100%，支持所有工具

### Week 9-12: 阶段3高级特性
- [ ] Week 9-10: Workflow批量执行器
- [ ] Week 11: Spot实例支持
- [ ] Week 12: 全面测试和文档

**预期效果:** 总体性能提升150%，成本降低70%

---

## 性能预期对比

### 当前架构
```
Single Job:
- Container启动: 30s
- 依赖安装: 2-10min (R包编译)
- S3传输: 30s-2min (串行)
- 工具执行: 5-30min
总计: 8-45min

Workflow (10 steps):
- 串行等待: 每个step等待前置完成
- Galaxy调度开销: 每step 10-30s
总计: 80-450min
```

### 优化后架构 (阶段1+2+3)
```
Single Job:
- Container启动: 10s (专用容器)
- 依赖安装: 0s (预装或动态构建缓存)
- S3传输: 5-20s (Mountpoint并行+lazy)
- 工具执行: 5-30min
总计: 5-30min (提升 60-80%)

Workflow (10 steps):
- 并行执行: AWS Batch DAG调度
- 无Galaxy调度开销
- 最大并行度
总计: 15-90min (提升 80-90%)
```

---

## 与Nextflow对比

### Nextflow原生方案
**优势:**
- ✅ 成熟的云原生架构
- ✅ Wave + Fusion 完整生态
- ✅ nf-core社区支持

**劣势:**
- ❌ 丢失Galaxy Web UI
- ❌ 需要重写所有workflows为Groovy DSL
- ❌ 学习曲线陡峭
- ❌ 与现有Galaxy生态不兼容

### 我们的方案 (借鉴Nextflow思想)
**优势:**
- ✅ 保留Galaxy完整生态
- ✅ 借鉴Nextflow最佳实践
- ✅ 渐进式演进，低风险
- ✅ Python实现，易维护
- ✅ 与现有workflows 100%兼容

**劣势:**
- ⚠️ 需要自己维护Fusion-like和Wave-like组件
- ⚠️ 没有nf-core那样的workflow库

**结论:** 我们的方案更适合你的场景

---

## 下一步行动

### 立即开始 (今天)

1. **验证Mountpoint可用性**
```bash
# 测试Mountpoint for S3
cd /Users/renyuankai/work/biometa/galaxy
./test_mountpoint.sh
```

2. **识别TOP工具**
```bash
# 统计使用频率
python scripts/analyze_job_statistics.py
```

3. **构建第一个优化容器**
```bash
# 为最常用工具构建专用容器
cd docker/optimized-tools/
docker build -t galaxy-tool-fastqc:latest -f Dockerfile.fastqc .
```

### 需要我帮你实现什么?

我可以为你:
1. ✍️ 编写完整的Mountpoint集成代码
2. 🐳 生成TOP 20工具的Dockerfile
3. 🔧 实现动态容器构建系统
4. 📊 创建性能测试脚本
5. 📝 编写详细的实施指南

**请告诉我你想先实现哪一部分？**

---

## 总结

### 核心思想
> **不要完全重写为Nextflow，而是借鉴其设计思想，在Galaxy现有架构上渐进优化**

### 三个关键技术
1. **Mountpoint for S3** (替代手动aws s3 cp)
2. **专用工具容器** (消除动态安装)
3. **动态容器构建** (支持长尾工具)

### 预期收益
- 🚀 性能提升: **150%**
- 💰 成本降低: **70%**
- 🛡️ 风险: **最低** (渐进式)
- ⏱️ 时间: **3个月完成**

### 与Nextflow比较
- ✅ 保留Galaxy全部优势
- ✅ 获得Nextflow关键特性
- ✅ 零兼容性问题
- ✅ 团队熟悉Python生态

---

**准备好开始了吗？告诉我你想从哪里开始！** 🚀
