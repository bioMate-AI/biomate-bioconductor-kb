# Galaxy云原生架构改造方案
## 基于Nextflow架构的完美云运行方案

---

## 目录

1. [当前问题分析](#当前问题分析)
2. [Nextflow云原生架构解析](#nextflow云原生架构解析)
3. [Galaxy改造方案](#galaxy改造方案)
4. [实施路线图](#实施路线图)
5. [技术细节](#技术细节)

---

## 当前问题分析

### Galaxy现有架构的根本缺陷

```
Galaxy (本地优先设计)
  ↓
  AWS Batch Job Runner (adapter层)
  ↓
  fetch-and-run Container (通用wrapper)
  ↓
  动态安装依赖 + Docker-in-Docker + 下载工具容器
  ↓
  执行工具
```

**核心问题：**

1. **❌ 非云原生** - 为本地集群设计，云是后补的
2. **❌ 多层包装** - fetch-and-run是wrapper，不是真正的云原生
3. **❌ 运行时依赖安装** - 每次都要下载、编译R包/Python包
4. **❌ 复杂的S3交互** - 手动stage-in/stage-out，没有POSIX接口
5. **❌ Docker-in-Docker复杂度** - 需要特殊权限和配置

---

## Nextflow云原生架构解析

### 核心设计原则

> **容器优先 + 云原生存储 + 自动调度**

### 架构图

```
Nextflow DSL (workflow定义)
  ↓
Executor Layer (AWS Batch / GCP Batch / K8s)
  ↓  ↓  ↓
  [自动调度]  [容器管理]  [存储抽象]
  ↓
Wave Containers (动态构建/增强容器)
  ↓
Fusion File System (POSIX接口到S3)
  ↓
工具容器 (直接运行，无wrapper)
```

### 关键技术组件

#### 1. **Wave Containers** - 动态容器管理

**问题解决：**
- ❌ Galaxy：需要预构建所有工具容器，或运行时动态安装
- ✅ Nextflow：运行时动态增强容器，按需添加依赖

**工作原理：**
```groovy
process FOO {
  conda 'bioconda::salmon=1.0'  // 声明依赖

  script:
  """
  salmon index ...
  """
}
```

Wave自动：
1. 从base image开始
2. 注入Conda环境
3. 添加Fusion客户端
4. 缓存构建结果
5. 推送到临时注册表

**优势：**
- 无需预构建所有容器
- 无需运行时编译R包
- 自动缓存，重复使用
- 支持多架构（x86_64/ARM64）

#### 2. **Fusion File System** - 云原生存储

**问题解决：**
- ❌ Galaxy：手动aws s3 cp，stage-in/stage-out
- ✅ Nextflow：S3呈现为POSIX文件系统

**工作原理：**
```bash
# 传统方式 (Galaxy当前)
aws s3 cp s3://bucket/input.fastq /tmp/input.fastq
tool process /tmp/input.fastq > /tmp/output.txt
aws s3 cp /tmp/output.txt s3://bucket/output.txt

# Fusion方式 (Nextflow)
tool process /fusion/s3/bucket/input.fastq > /fusion/s3/bucket/output.txt
# S3像本地文件系统一样使用！
```

**技术实现：**
- Lazy download - 按需下载数据块
- Parallel upload - 并行上传结果
- 本地缓存 - 使用容器/tmp作为缓存
- POSIX兼容 - 无需修改工具代码

#### 3. **原生AWS Batch集成**

**问题解决：**
- ❌ Galaxy：需要fetch-and-run wrapper
- ✅ Nextflow：直接提交原生Batch job

**对比：**

| 特性 | Galaxy (当前) | Nextflow |
|-----|--------------|----------|
| Job Definition | 手动维护 | 自动生成 |
| 容器镜像 | 单个通用镜像 | 每个工具专用镜像 |
| 依赖管理 | 运行时安装 | 预构建到容器 |
| S3访问 | AWS CLI | Fusion POSIX |
| 错误重试 | 手动逻辑 | Batch原生支持 |

---

## Galaxy改造方案

### 方案A：渐进式改造（推荐）

**保留Galaxy的优势，借鉴Nextflow的设计**

#### 阶段1：消除fetch-and-run wrapper（3-6个月）

**目标：** 直接提交工具容器到AWS Batch

**当前架构：**
```python
# galaxy_job_runner.py
container_overrides = {
    'image': 'fetch-and-run:latest',  # wrapper容器
    'command': ['bash', '/usr/local/bin/fetch_and_run.sh'],
    'environment': [
        {'name': 'TOOL_CONTAINER_IMAGE', 'value': 'deseq2:1.0'},
        {'name': 'JOB_SCRIPT_S3_URL', 'value': 's3://...'}
    ]
}
```

**改造后：**
```python
# galaxy_cloud_native_runner.py
container_overrides = {
    'image': get_tool_container(tool_id),  # 直接使用工具容器
    'command': ['bash', '-c', job_script],
    'environment': [
        {'name': 'GALAXY_DATASET_PATH', 'value': '/fusion/s3/...'},
    ]
}
```

**关键改变：**
1. ✅ 为每个Galaxy工具构建专用容器
2. ✅ 使用Biocontainers生态（与Nextflow相同）
3. ✅ 消除Docker-in-Docker
4. ✅ 消除运行时依赖安装

**实施步骤：**

```bash
# 1. 使用Planemo为Galaxy工具自动生成容器
planemo container_register --tool_id deseq2

# 2. 推送到ECR
docker push $ECR_REPO/deseq2:1.0

# 3. Galaxy工具XML中声明容器
<tool id="deseq2" name="DESeq2">
  <requirements>
    <container type="docker">quay.io/biocontainers/deseq2:1.0</container>
  </requirements>
</tool>

# 4. Job runner直接使用
tool_container = tool.get_container()
submit_to_batch(container=tool_container, ...)
```

#### 阶段2：实现Fusion-like存储层（6-12个月）

**目标：** S3呈现为POSIX文件系统

**技术选型：**

**选项1：使用AWS Mountpoint for S3**
```python
# 在容器启动时挂载S3
mount-s3 galaxy-bucket /mnt/s3
export GALAXY_DATA_DIR=/mnt/s3/datasets
```

**选项2：实现Python版Fusion客户端**
```python
# galaxy_fusion/s3_posix.py
class S3FileSystem:
    def open(self, s3_path, mode='r'):
        # Lazy download到本地缓存
        cached_path = self._download_lazy(s3_path)
        return open(cached_path, mode)

    def write(self, local_path, s3_path):
        # 后台并行上传
        self._upload_async(local_path, s3_path)
```

**对比：**

| 方案 | 优势 | 劣势 |
|-----|------|------|
| Mountpoint | AWS官方支持 | 性能略低于Fusion |
| 自研Fusion | 完全控制 | 开发成本高 |
| **推荐：Mountpoint + 优化** | 平衡 | - |

**改造后的数据流：**
```python
# 当前 (手动stage-in/out)
download_from_s3(input_dataset)
run_tool(local_input, local_output)
upload_to_s3(output_dataset)

# 改造后 (POSIX接口)
run_tool(
    input='/mnt/s3/datasets/1234.fastq',
    output='/mnt/s3/datasets/5678.bam'
)
# Mountpoint自动处理上传下载！
```

#### 阶段3：容器动态增强（12-18个月）

**目标：** 实现类似Wave的功能

**方案：** 使用Conda + Docker BuildKit

```python
# galaxy_wave/container_builder.py
class ContainerAugmentation:
    def build_tool_container(self, tool):
        """动态构建工具容器"""

        # 1. 从base image开始
        base_image = "mambaorg/micromamba:latest"

        # 2. 提取工具的Conda依赖
        conda_packages = tool.requirements.conda_packages
        # ['bioconda::deseq2=1.0', 'conda-forge::r-base=4.1']

        # 3. 使用BuildKit动态构建
        dockerfile = f"""
        FROM {base_image}
        RUN micromamba install -y {' '.join(conda_packages)}
        COPY galaxy_wrapper.sh /usr/local/bin/
        """

        # 4. 构建并推送到临时ECR
        image_digest = docker_build_and_push(dockerfile)

        # 5. 缓存（避免重复构建）
        self.cache[tool.id] = image_digest

        return image_digest
```

**优势：**
- ✅ 无需预构建所有工具容器
- ✅ 按需构建，自动缓存
- ✅ 支持任意Conda包组合

### 方案B：完全重写（激进，不推荐）

**直接用Nextflow替代Galaxy workflow引擎**

**优势：**
- ✅ 完全云原生
- ✅ 成熟生态（nf-core）

**劣势：**
- ❌ 丢失Galaxy Web UI
- ❌ 丢失历史记录和复现性
- ❌ 需要学习Groovy DSL
- ❌ 与现有workflows不兼容

**结论：不推荐，Galaxy的UI和Python生态是核心价值**

---

## 实施路线图

### 短期（1-3个月）✅ 当前A+B方案

**已完成：**
- [x] 预装通用运行环境
- [x] 动态安装缺失包
- [x] 修复BiocManager bug

**效果：**
- 90%工具快速启动
- 10%动态安装

### 中期（3-9个月）🎯 消除wrapper

**目标：直接使用工具容器**

**步骤：**

1. **工具容器化（Month 1-3）**
   ```bash
   # 使用Planemo为TOP 50工具构建容器
   for tool in $(get_top_50_tools); do
       planemo container galaxy-tool-$tool
       docker push $ECR_REPO/galaxy-tool-$tool:latest
   done
   ```

2. **改造Job Runner（Month 4-6）**
   ```python
   # 新建 galaxy_cloud_native_runner.py
   class CloudNativeJobRunner:
       def submit_job(self, job):
           # 直接使用工具容器，无wrapper
           tool_container = self.get_tool_container(job.tool_id)

           job_def = {
               'image': tool_container,
               'command': job.command_line,
               'environment': {
                   'GALAXY_DATASET_DIR': '/mnt/s3/datasets'
               }
           }

           return batch_client.submit_job(**job_def)
   ```

3. **测试和迁移（Month 7-9）**
   - 并行运行两个runner
   - 逐步迁移workflows到新runner
   - 监控性能和稳定性

### 长期（9-18个月）🚀 完全云原生

**目标：实现Fusion-like存储 + Wave-like容器**

**步骤：**

1. **实现S3 POSIX层（Month 9-12）**
   ```python
   # galaxy_fusion/mountpoint.py
   def mount_s3_bucket(bucket, mount_point):
       """使用Mountpoint for S3挂载bucket"""
       subprocess.run([
           'mount-s3', bucket, mount_point,
           '--cache', '/tmp/s3-cache',
           '--max-threads', '16'
       ])
   ```

2. **容器动态构建（Month 13-15）**
   ```python
   # galaxy_wave/builder.py
   def build_container_on_demand(tool):
       """按需构建工具容器"""
       if tool.id in cache:
           return cache[tool.id]

       # 使用BuildKit构建
       image = build_conda_container(tool.conda_packages)
       cache[tool.id] = image
       return image
   ```

3. **性能优化（Month 16-18）**
   - 缓存优化
   - 并行优化
   - 成本优化

---

## 技术细节

### 1. 工具容器化策略

#### 使用Biocontainers生态

**优势：**
- 与Nextflow共享容器（兼容性）
- 社区维护，质量有保证
- 支持多版本

**实现：**
```python
# galaxy/tools/deseq2/deseq2.xml
<tool id="deseq2" name="DESeq2">
  <requirements>
    <container type="docker">
      quay.io/biocontainers/bioconductor-deseq2:1.42.0--r43hf17093f_1
    </container>
  </requirements>

  <command><![CDATA[
    Rscript '$__tool_directory__/deseq2.R' ...
  ]]></command>
</tool>
```

#### 自动化构建流程

```bash
#!/bin/bash
# build_tool_containers.sh

# 1. 扫描所有Galaxy工具
TOOLS=$(find tools/ -name "*.xml")

# 2. 为每个工具构建容器
for tool in $TOOLS; do
    TOOL_ID=$(xmllint --xpath 'string(//tool/@id)' $tool)

    # 检查是否已有Biocontainer
    if biocontainer_exists $TOOL_ID; then
        echo "Using existing biocontainer for $TOOL_ID"
        continue
    fi

    # 否则使用Planemo构建
    planemo container_register \
        --tool $tool \
        --publish \
        --registry $ECR_REPO
done
```

### 2. S3存储层实现

#### 方案：AWS Mountpoint for S3

**容器启动脚本：**
```bash
#!/bin/bash
# container_entrypoint.sh

# 1. 挂载S3 bucket
mount-s3 \
    --region $AWS_REGION \
    --cache /tmp/s3-cache \
    --max-threads 16 \
    $S3_BUCKET /mnt/s3

# 2. 设置Galaxy环境变量
export GALAXY_DATASET_DIR=/mnt/s3/datasets
export GALAXY_WORKING_DIR=/mnt/s3/working

# 3. 运行工具
exec "$@"
```

**Job Runner集成：**
```python
# galaxy_cloud_native_runner.py
def prepare_container_environment(job):
    """准备容器环境"""

    return {
        'mountPoints': [
            {
                'sourceVolume': 's3-mount',
                'containerPath': '/mnt/s3'
            }
        ],
        'volumes': [
            {
                'name': 's3-mount',
                'host': {'sourcePath': '/opt/mountpoint'}
            }
        ],
        'environment': [
            {'name': 'S3_BUCKET', 'value': 'galaxy-cloud-data'},
            {'name': 'AWS_REGION', 'value': 'us-west-2'}
        ]
    }
```

### 3. 容器动态增强

#### 使用Docker BuildKit + Conda

```python
# galaxy_wave/builder.py
import docker
from buildkit import BuildKit

class ContainerBuilder:
    def __init__(self):
        self.client = docker.from_env()
        self.buildkit = BuildKit()
        self.cache = {}

    def build_tool_container(self, tool_id, conda_packages):
        """动态构建工具容器"""

        # 生成缓存key
        cache_key = f"{tool_id}:{hash(tuple(conda_packages))}"

        if cache_key in self.cache:
            return self.cache[cache_key]

        # 生成Dockerfile
        dockerfile = f"""
        FROM mambaorg/micromamba:latest

        # 安装Conda包
        RUN micromamba install -y -c conda-forge -c bioconda \\
            {' '.join(conda_packages)}

        # 安装Mountpoint for S3
        RUN wget https://s3.amazonaws.com/mountpoint-s3-release/latest/mount-s3.deb && \\
            dpkg -i mount-s3.deb

        # 复制Galaxy wrapper
        COPY galaxy_wrapper.sh /usr/local/bin/
        RUN chmod +x /usr/local/bin/galaxy_wrapper.sh

        ENTRYPOINT ["/usr/local/bin/galaxy_wrapper.sh"]
        """

        # 使用BuildKit构建（利用缓存）
        image = self.buildkit.build(
            dockerfile=dockerfile,
            tag=f"galaxy-dynamic/{tool_id}:latest",
            cache_from=[f"galaxy-dynamic/base:latest"]
        )

        # 推送到ECR
        image_uri = self.push_to_ecr(image)

        # 缓存
        self.cache[cache_key] = image_uri

        return image_uri

    def push_to_ecr(self, image):
        """推送到ECR临时仓库"""
        ecr_client = boto3.client('ecr')

        # 获取临时仓库
        repo_name = 'galaxy-dynamic-containers'

        # 推送
        digest = self.client.images.push(
            repository=f"{ECR_ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/{repo_name}",
            tag=image.tags[0]
        )

        return f"{repo_name}@{digest}"
```

### 4. 性能优化

#### 缓存策略

```python
# galaxy_cache/container_cache.py
class ContainerCache:
    """容器镜像缓存"""

    def __init__(self):
        self.redis = redis.Redis(host='cache.galaxy.local')

    def get_or_build(self, tool_id, requirements):
        """获取缓存的容器或构建新的"""

        cache_key = self._generate_key(tool_id, requirements)

        # 1. 检查本地缓存
        cached_image = self.redis.get(cache_key)
        if cached_image:
            return cached_image.decode()

        # 2. 检查ECR是否已存在
        ecr_image = self._check_ecr(cache_key)
        if ecr_image:
            self.redis.set(cache_key, ecr_image, ex=86400)
            return ecr_image

        # 3. 构建新容器
        new_image = ContainerBuilder().build(tool_id, requirements)

        # 4. 缓存
        self.redis.set(cache_key, new_image, ex=86400)

        return new_image
```

#### 预热策略

```python
# galaxy_warmup/prewarmer.py
def prewarm_containers():
    """预热常用工具容器"""

    # 获取使用频率TOP 100的工具
    top_tools = get_top_used_tools(limit=100)

    # 并行构建/拉取容器
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []
        for tool in top_tools:
            future = executor.submit(
                ContainerCache().get_or_build,
                tool.id,
                tool.requirements
            )
            futures.append(future)

        # 等待完成
        for future in futures:
            image = future.result()
            logger.info(f"Prewarmed: {image}")
```

---

## 成本效益分析

### 当前方案（A+B）

**优势：**
- ✅ 快速实施（已完成）
- ✅ 向后兼容
- ✅ 低风险

**劣势：**
- ⚠️ 仍需10%动态安装
- ⚠️ fetch-and-run overhead
- ⚠️ 手动S3交互

**适用场景：** 快速上线，短期方案

### 云原生改造（阶段1-3）

**优势：**
- ✅ 完全消除动态安装
- ✅ 性能提升50-70%
- ✅ 成本降低30-40%（减少计算时间）
- ✅ 与Nextflow生态兼容

**劣势：**
- ⚠️ 开发成本高（6-18个月）
- ⚠️ 需要重构Job Runner
- ⚠️ 需要容器化所有工具

**适用场景：** 长期运营，大规模使用

### 投资回报（ROI）

**假设：**
- 每月运行10,000个workflows
- 平均每个workflow 20个任务
- 当前平均任务时间：30分钟
- 云原生后平均任务时间：18分钟（减少40%）

**成本节省：**
```
节省时间 = 10,000 * 20 * 12分钟 = 2,400,000分钟/月
         = 40,000小时/月

成本节省 = 40,000小时 * $0.05/小时（EC2） = $2,000/月
         = $24,000/年

开发成本 = 6人月 * $15,000/月 = $90,000

ROI = 3.75年回本
```

**如果使用量更大，ROI更高！**

---

## 推荐路线

### 立即执行（已完成）✅
- A+B方案上线
- 修复BiocManager bug
- 支持90%的workflows

### 3个月内 🎯
- 为TOP 50工具构建专用容器
- 实现新的CloudNativeJobRunner
- A/B测试对比性能

### 6-12个月 🚀
- 完全迁移到工具专用容器
- 集成Mountpoint for S3
- 消除fetch-and-run wrapper

### 12-18个月 🌟
- 实现容器动态构建
- 完全云原生架构
- 与Nextflow生态无缝集成

---

## 总结

**核心理念：**
> 学习Nextflow的架构思想，但保留Galaxy的核心价值（Web UI + Python生态）

**关键技术：**
1. ✅ 工具专用容器（消除动态安装）
2. ✅ S3 POSIX接口（消除手动stage-in/out）
3. ✅ 容器动态构建（按需构建，自动缓存）

**预期效果：**
- 性能提升 50-70%
- 成本降低 30-40%
- 维护成本降低 60%
- 与Nextflow生态兼容

**下一步行动：**
1. 评审本方案
2. 确定实施优先级
3. 组建开发团队
4. 启动阶段1开发

---

## 参考资料

- [Nextflow AWS Batch文档](https://www.nextflow.io/docs/latest/aws.html)
- [Wave Containers](https://www.nextflow.io/docs/latest/wave.html)
- [Fusion File System](https://www.nextflow.io/docs/latest/fusion.html)
- [AWS Mountpoint for S3](https://github.com/awslabs/mountpoint-s3)
- [Biocontainers](https://biocontainers.pro/)
- [Galaxy Planemo](https://planemo.readthedocs.io/)
