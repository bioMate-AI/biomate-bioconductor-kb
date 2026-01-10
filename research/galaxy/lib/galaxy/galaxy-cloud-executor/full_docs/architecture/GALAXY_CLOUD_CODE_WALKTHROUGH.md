# galaxy_cloud/ 核心代码解析

## 🎯 galaxy_cloud/ 文件夹的作用

这是 Galaxy UI 真正调用的**生产代码**，不是测试工具！

---

## 📁 目录结构

```
galaxy_cloud/
├── galaxy_workflow/                     ← Galaxy 集成层
│   ├── galaxy_job_runner.py            ← ⭐ Galaxy 调用的入口点
│   ├── dag_executor.py                  ← Workflow DAG 执行引擎
│   ├── data_manager.py                  ← S3 数据上传/下载
│   ├── step_executor.py                 ← 单步任务执行
│   ├── tool_registry.py                 ← 工具容器查询
│   ├── job_config_parser.py             ← 解析 job_conf.xml
│   └── models.py                        ← 数据模型
│
├── providers/aws/                       ← AWS Batch 实现
│   ├── executor.py                      ← AWS Batch 执行器
│   ├── batch_client.py                  ← AWS Batch API 封装
│   └── s3_storage.py                    ← S3 存储管理
│
├── core/                                ← 核心抽象接口
│   ├── executor.py                      ← 云执行器抽象基类
│   ├── job.py                           ← 作业规范定义
│   └── storage.py                       ← 存储抽象接口
│
└── config/                              ← 配置管理
    └── cloud_config.py                  ← 云配置加载
```

---

## ⭐ 核心入口：galaxy_job_runner.py

**位置**: `galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

### 这是什么？
Galaxy 的 Job Runner 插件，让 Galaxy 可以把作业路由到云端执行。

### Galaxy 如何调用它？
在 `job_conf.xml` 中配置：

```xml
<plugins>
    <plugin id="cloud" type="runner"
            load="galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner"/>
</plugins>

<destinations>
    <destination id="aws_cloud" runner="cloud">
        <param id="cloud_provider">aws</param>
    </destination>
</destinations>
```

配置后，Galaxy 会在用户点击 "Run" 时自动调用这个 runner。

### 关键代码片段

#### 1. 初始化（启动时自动执行）

```python
class GalaxyCloudJobRunner(AsynchronousJobRunner):
    """Galaxy 的云执行器"""

    def __init__(self, app, nworkers, **kwargs):
        """
        Galaxy 启动时会自动调用这个方法

        参数:
            app: Galaxy 应用实例
            nworkers: 并发工作线程数
        """
        super().__init__(app, nworkers)

        # 初始化云组件
        self._init_cloud_components()

        # 工具注册表（查询 BioContainer 镜像）
        self.tool_registry = GalaxyToolRegistry(...)

        # 数据管理器（上传/下载 S3）
        self.data_manager = GalaxyDataManager(...)

        # AWS Batch 执行器
        self.cloud_executors = {}
```

**作用**: Galaxy 启动时自动初始化云执行器，准备好所有必要的组件。

---

#### 2. 提交作业（用户点击 Run 时调用）

```python
def queue_job(self, job_wrapper):
    """
    Galaxy 在用户点击 "Run Workflow" 或 "Run Tool" 时调用这个方法

    参数:
        job_wrapper: Galaxy 的作业包装对象，包含：
            - 工具 ID（例如：bwa_mem）
            - 输入文件路径（例如：/galaxy/data/123.fastq）
            - 工具参数（例如：-t 8）
            - 用户信息

    返回:
        None（异步执行）
    """
    try:
        # 1. 获取作业目标配置
        job_destination = job_wrapper.job_destination

        # 2. 确定云提供商（AWS/GCP/Azure）
        cloud_provider = self._get_cloud_provider(job_destination)

        # 3. 创建作业规范（JobSpec）
        job_spec = self._create_job_spec(job_wrapper, job_destination)

        # 4. 异步提交到云端
        future = asyncio.run_coroutine_threadsafe(
            self._submit_cloud_job(job_spec, cloud_provider),
            self._loop
        )

        # 5. 追踪作业状态
        self.active_jobs[job_wrapper.job_id] = CloudJobState(future, job_spec)

    except Exception as e:
        self.logger.error(f"Failed to queue job: {e}")
        job_wrapper.fail(f"Cloud submission failed: {e}")
```

**作用**: 这是用户点击按钮后 Galaxy 调用的**第一个方法**，负责准备作业并提交到云端。

---

#### 3. 创建作业规范（解析工具需求）

```python
def _create_job_spec(self, job_wrapper, job_destination):
    """
    从 Galaxy 作业中提取信息，创建云作业规范

    这个方法会：
    1. 查询工具的 BioContainer 镜像
    2. 解析工具的资源需求（CPU/内存）
    3. 构建执行命令
    4. 准备环境变量
    """

    # 1. 获取工具信息
    tool = job_wrapper.tool
    tool_id = tool.id  # 例如：'bwa_mem'

    # 2. 从工具注册表查询容器镜像
    container_info = await self.tool_registry.get_tool_container(tool_id)
    # 返回：{'image': 'quay.io/biocontainers/bwa:0.7.17', ...}

    # 3. 构建容器规范
    container_spec = ContainerSpec(
        image=container_info['image'],
        command=['bwa', 'mem'],
        args=self._build_command_args(job_wrapper),
        env=self._build_environment(job_wrapper),
        working_dir='/galaxy-central'
    )

    # 4. 确定资源需求
    resource_spec = ResourceSpec(
        vcpus=job_destination.params.get('cores', 1),
        memory_mb=job_destination.params.get('memory', 2048),
        gpu=job_destination.params.get('gpu', 0)
    )

    # 5. 创建作业规范
    job_spec = JobSpec(
        job_id=f"galaxy-{job_wrapper.get_id_tag()}",
        name=f"Galaxy Job: {tool_id}",
        container=container_spec,
        resources=resource_spec,
        timeout_seconds=self._get_job_timeout(job_wrapper),
        retry_attempts=2,
        labels={
            'galaxy_job_id': str(job_wrapper.job_id),
            'galaxy_tool_id': tool_id,
            'galaxy_user': str(job_wrapper.user.id)
        }
    )

    return job_spec
```

**作用**: 把 Galaxy 的作业信息转换成云执行器能理解的规范，包含所有执行所需的细节。

---

#### 4. 提交到云端（调用 AWS Batch）

```python
async def _submit_cloud_job(self, job_spec, cloud_provider):
    """
    提交作业到云平台

    这个方法会：
    1. 上传输入数据到 S3
    2. 调用 AWS Batch 执行器
    3. 监控作业状态
    4. 下载输出结果
    """

    # 1. 上传输入数据到 S3
    input_files = await self.data_manager.upload_input_data(job_spec)
    # 上传用户的真实文件到 S3

    # 2. 获取云执行器
    executor = self.cloud_executors[cloud_provider]
    # 这里会调用 galaxy_cloud/providers/aws/executor.py

    # 3. 提交作业
    job_id = await executor.submit_job(job_spec)
    # 调用 AWS Batch API 提交作业

    # 4. 监控作业状态
    status = await executor.wait_for_completion(job_id)

    # 5. 下载输出结果
    if status == JobStatus.COMPLETED:
        await self.data_manager.download_output_data(job_spec)
        # 从 S3 下载结果回 Galaxy

    return status
```

**作用**: 这是真正执行云作业的核心逻辑，协调数据上传、作业提交、状态监控和结果下载。

---

## 📦 data_manager.py - 数据管理

**位置**: `galaxy_cloud/galaxy_workflow/data_manager.py`

### 作用
管理 Galaxy 和 S3 之间的数据传输。

### 关键功能

#### 1. 上传输入数据

```python
class GalaxyDataManager:
    async def upload_input_data(self, job_spec):
        """
        上传 Galaxy 的输入文件到 S3

        工作流程:
        1. 从 Galaxy 数据库获取文件路径
        2. 上传到 S3 存储桶
        3. 返回 S3 URI

        例子:
            输入: /galaxy/database/files/000/dataset_123.dat
            输出: s3://galaxy-cloud-data/jobs/job-123/inputs/input.fastq
        """
        s3_uris = []

        for input_file in job_spec.input_files:
            # 读取 Galaxy 本地文件
            local_path = self._get_galaxy_file_path(input_file)

            # 上传到 S3
            s3_uri = await self.s3_client.upload_file(
                local_path,
                bucket=self.bucket_name,
                key=f"jobs/{job_spec.job_id}/inputs/{input_file.name}"
            )

            s3_uris.append(s3_uri)

        return s3_uris
```

**真实场景**:
```
用户上传: sample.fastq (100 MB)
Galaxy 存储: /galaxy/database/files/000/dataset_456.dat
上传到 S3: s3://galaxy-cloud-data/jobs/job-789/inputs/sample.fastq
```

---

#### 2. 下载输出结果

```python
async def download_output_data(self, job_spec):
    """
    从 S3 下载结果回 Galaxy

    工作流程:
    1. 从 S3 下载输出文件
    2. 导入到 Galaxy 数据库
    3. 关联到用户的 History

    例子:
        S3: s3://galaxy-cloud-data/jobs/job-123/outputs/aligned.sam
        Galaxy: /galaxy/database/files/000/dataset_124.dat
    """
    for output_file in job_spec.output_files:
        # 从 S3 下载
        s3_uri = output_file.s3_uri
        local_path = await self.s3_client.download_file(
            s3_uri,
            local_dir=self.temp_dir
        )

        # 导入到 Galaxy 数据库
        dataset = self._import_to_galaxy(
            local_path,
            name=output_file.name,
            ext=output_file.ext
        )

        # 关联到用户的 History
        self._add_to_history(dataset, job_spec.user_id)
```

**真实场景**:
```
S3 下载: s3://.../outputs/aligned.sam (500 MB)
导入 Galaxy: dataset_457.dat
用户在 UI 看到: "aligned.sam" 文件可用 ✅
```

---

## 🔧 tool_registry.py - 工具注册表

**位置**: `galaxy_cloud/galaxy_workflow/tool_registry.py`

### 作用
自动查询 BioContainer 镜像，无需手动配置。

### 关键功能

```python
class GalaxyToolRegistry:
    async def get_tool_container(self, tool_id: str):
        """
        查询工具的 BioContainer 镜像

        查询顺序:
        1. 本地缓存
        2. BioContainers API
        3. 默认镜像

        例子:
            tool_id: 'bwa_mem'
            返回: {
                'image': 'quay.io/biocontainers/bwa:0.7.17--h7132678_9',
                'command': ['bwa'],
                'env': {...}
            }
        """

        # 1. 检查缓存
        if tool_id in self.cache:
            return self.cache[tool_id]

        # 2. 查询 BioContainers API
        api_url = f"{self.biocontainers_api_url}/{tool_id}"
        response = await self.http_client.get(api_url)

        if response.status_code == 200:
            data = response.json()
            container_info = {
                'image': data['images'][0]['url'],
                'command': data.get('command', [tool_id]),
                'version': data['version']
            }

            # 缓存结果
            self.cache[tool_id] = container_info
            return container_info

        # 3. 返回默认镜像
        return self.get_default_container()
```

**真实场景**:
```
工具: BWA (基因组比对)
查询: BioContainers API
返回: quay.io/biocontainers/bwa:0.7.17--h7132678_9

自动配置，无需手动查找镜像！
```

---

## ⚙️ providers/aws/executor.py - AWS Batch 执行器

**位置**: `galaxy_cloud/providers/aws/executor.py`

### 作用
封装 AWS Batch API，提供统一的作业提交接口。

### 关键功能

```python
class AWSBatchExecutor(CloudExecutor):
    async def submit_job(self, job_spec: JobSpec) -> str:
        """
        提交作业到 AWS Batch

        步骤:
        1. 注册作业定义
        2. 提交作业
        3. 返回作业 ID
        """

        # 1. 构建作业定义
        job_definition = {
            'jobDefinitionName': f"{job_spec.name}-def",
            'type': 'container',
            'containerProperties': {
                'image': job_spec.container.image,
                'vcpus': job_spec.resources.vcpus,
                'memory': job_spec.resources.memory_mb,
                'command': job_spec.container.command,
                'environment': [
                    {'name': k, 'value': v}
                    for k, v in job_spec.container.env.items()
                ],
                'jobRoleArn': self.config.batch_job_role_arn
            }
        }

        # 2. 注册作业定义
        response = await self.batch_client.register_job_definition(
            **job_definition
        )
        job_def_arn = response['jobDefinitionArn']

        # 3. 提交作业
        submit_response = await self.batch_client.submit_job(
            jobName=job_spec.job_id,
            jobQueue=self.config.batch_queue_name,
            jobDefinition=job_def_arn
        )

        job_id = submit_response['jobId']
        self.logger.info(f"Submitted job {job_id} to AWS Batch")

        return job_id
```

**真实场景**:
```
输入: JobSpec (包含工具、资源、命令等)
调用: AWS Batch API
返回: AWS 作业 ID (例如：abc123-def456-789)
```

---

## 🔄 完整执行流程示例

### 用户操作: 运行 BWA 比对

```
1. 用户在 Galaxy UI:
   - 选择工具: BWA-MEM
   - 输入文件: sample.fastq (用户上传的)
   - 参考基因组: hg38.fasta (Galaxy 库中的)
   - 点击 "Run Tool"

2. Galaxy 内部 (自动):
   galaxy_job_runner.py:171
   → queue_job() 被调用

3. 创建作业规范:
   → tool_registry.get_tool_container('bwa_mem')
   → 返回: quay.io/biocontainers/bwa:0.7.17

4. 上传数据:
   → data_manager.upload_input_data()
   → 上传 sample.fastq 到 S3
   → 上传 hg38.fasta 到 S3

5. 提交到 AWS Batch:
   → aws_executor.submit_job()
   → AWS Batch 启动容器
   → 容器执行: bwa mem hg38.fasta sample.fastq

6. 等待完成:
   → 监控作业状态
   → 作业完成: SUCCEEDED

7. 下载结果:
   → data_manager.download_output_data()
   → 从 S3 下载 aligned.sam
   → 导入到 Galaxy 数据库

8. 用户在 UI 看到:
   → "aligned.sam" 文件可用 ✅
   → 可以查看、下载、继续分析
```

---

## 💡 总结

### galaxy_cloud/ 的核心价值

1. **galaxy_job_runner.py** - Galaxy 集成入口
   - Galaxy 启动时自动加载
   - 用户点击 Run 时自动调用
   - 协调所有云执行流程

2. **data_manager.py** - 数据自动管理
   - 自动上传用户数据到 S3
   - 自动下载结果回 Galaxy
   - 用户无感知，完全自动化

3. **tool_registry.py** - 容器自动查询
   - 自动查询 BioContainers API
   - 无需手动配置镜像
   - 支持数千种生物信息学工具

4. **aws/executor.py** - AWS Batch 封装
   - 统一的作业提交接口
   - 自动管理作业定义
   - 支持状态监控和错误处理

### 与测试工具的区别

| 项目 | 测试工具 | galaxy_cloud/ |
|------|---------|---------------|
| 目的 | 验证基础设施 | 生产执行 |
| 触发 | 手动命令行 | Galaxy UI 自动 |
| 数据 | Mock 假数据 | 真实用户数据 |
| 工具 | 简单 echo | 真实 BioContainers |
| 集成 | 独立运行 | Galaxy 完全集成 |
| 用户 | 开发者 | 最终用户 |

---

## 📖 相关文档

- **架构说明**: `ARCHITECTURE_EXPLAINED.md`
- **流程对比**: `FLOW_COMPARISON.md`
- **集成指南**: `full_docs/01-快速开始指南.md`
