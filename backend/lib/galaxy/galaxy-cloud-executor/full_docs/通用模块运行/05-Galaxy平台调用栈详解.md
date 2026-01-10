# Galaxy平台云执行完整调用栈

当你在Galaxy平台上运行workflow时，完整的代码执行流程如下：

---

## 📊 完整调用栈图

```
用户在Galaxy UI点击运行workflow
    ↓
Galaxy Core (galaxy/jobs/manager.py)
    ↓ 读取job_conf.yml配置
    ↓ 根据tool ID匹配destination
    ↓
Galaxy Job Manager
    ↓ 加载对应的Runner
    ↓
[galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner]
    ├─ __init__()                                    # 初始化Job Runner
    │   ├─ _init_cloud_components()                  # 初始化云组件
    │   │   ├─ GalaxyToolRegistry                    # 工具注册表
    │   │   ├─ GalaxyDataManager                     # 数据管理器
    │   │   └─ GalaxyJobConfigParser                 # 解析job_conf.yml
    │   └─ _start_event_loop()                       # 启动异步事件循环
    ↓
    ├─ queue_job(job_wrapper)                        # 队列作业
    │   ├─ _get_cloud_provider()                     # 获取云提供商 (aws/azure/gcp/k8s)
    │   ├─ _create_job_spec()                        # 创建作业规格
    │   │   ├─ GalaxyToolRegistry.get_tool_container() # 获取工具容器镜像
    │   │   ├─ ContainerSpec()                       # 容器规格 (镜像/命令/环境变量)
    │   │   └─ ResourceSpec()                        # 资源规格 (CPU/内存/GPU)
    │   └─ _submit_cloud_job()                       # 提交到云端
    │       └─ _get_cloud_executor()                 # 获取云执行器
    ↓
[galaxy_cloud.factory:CloudExecutorFactory]
    ├─ create(executor_name, config)                 # 创建执行器
    │   ├─ registry.get_executor('aws-batch')        # 从注册表获取
    │   └─ return AWSBatchExecutor(config)           # 实例化
    ↓
[galaxy_cloud.providers.aws.executor:AWSBatchExecutor]
    ├─ __init__(config, auth)                        # 初始化AWS Batch执行器
    │   ├─ AWSAuth(config)                           # AWS认证
    │   ├─ self.job_queue = config.batch_queue       # AWS Batch队列
    │   ├─ self.s3_bucket = config.s3_bucket         # S3存储桶
    │   └─ boto3 clients (batch/ecs/logs/s3)         # AWS客户端
    ↓
    ├─ initialize()                                  # 初始化
    │   ├─ auth.initialize()                         # 初始化认证
    │   ├─ get_boto3_client('batch')                 # 创建Batch客户端
    │   ├─ get_boto3_client('ecs')                   # 创建ECS客户端
    │   ├─ get_boto3_client('logs')                  # 创建CloudWatch Logs客户端
    │   └─ _validate_job_queue()                     # 验证队列存在
    ↓
    ├─ submit_job(job_spec)                          # 提交作业
    │   ├─ _upload_input_data(job_spec)              # 上传输入数据到S3
    │   ├─ _register_job_definition(job_spec)        # 注册作业定义
    │   │   └─ batch.register_job_definition()       # 调用AWS Batch API
    │   ├─ batch.submit_job()                        # 提交作业到AWS Batch
    │   │   ├─ jobQueue = self.job_queue             # 指定队列
    │   │   ├─ jobDefinition = job_def_arn           # 作业定义ARN
    │   │   └─ containerOverrides = {...}            # 容器覆盖配置
    │   └─ return job_id                             # 返回AWS Batch作业ID
    ↓
AWS Batch Service (云端)
    ├─ 在队列中排队作业
    ├─ 分配计算资源 (EC2/Fargate)
    │   ├─ 根据ResourceSpec选择实例类型
    │   ├─ 如果是spot: 使用Spot实例
    │   └─ 如果是onDemand: 使用按需实例
    ├─ 拉取Docker容器镜像
    ├─ 从S3下载输入数据
    ├─ 执行容器中的命令
    ├─ 将输出上传到S3
    └─ 更新作业状态
    ↓
[AWSBatchExecutor] (继续监控)
    ├─ wait_for_completion(job_id)                   # 等待完成
    │   ├─ get_job_status(job_id)                    # 轮询作业状态
    │   │   └─ batch.describe_jobs([job_id])         # 调用AWS API
    │   ├─ 状态: SUBMITTED → PENDING → RUNNABLE → STARTING → RUNNING → SUCCEEDED/FAILED
    │   └─ 每30秒检查一次
    ↓
    ├─ get_job_result(job_id)                        # 获取结果
    │   ├─ _download_output_data(job_id)             # 从S3下载输出
    │   ├─ _get_job_logs(job_id)                     # 从CloudWatch获取日志
    │   │   └─ logs.get_log_events()                 # 获取容器日志
    │   └─ return JobResult(status, stdout, stderr)  # 返回结果
    ↓
[GalaxyCloudJobRunner]
    ├─ _monitor_cloud_job(job_state, cloud_job_id)   # 监控云作业
    │   ├─ cloud_executor.wait_for_completion()      # 等待完成
    │   └─ 更新Galaxy作业状态
    │       ├─ 如果成功: job_wrapper.finish()        # 标记完成
    │       └─ 如果失败: job_wrapper.fail()          # 标记失败
    ↓
Galaxy Core
    ├─ 更新作业状态到数据库
    ├─ 保存输出文件到Galaxy数据集
    └─ 在UI中显示结果
```

---

## 🔍 关键代码位置

### 1. **入口点: Galaxy Job Runner**
**文件**: `galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

#### 初始化 (第41-57行)
```python
def __init__(self, app, nworkers, **kwargs):
    super().__init__(app, nworkers)
    self.app = app

    # 初始化云组件
    self._init_cloud_components()

    # 作业追踪
    self.active_jobs: Dict[str, 'CloudJobState'] = {}

    # 异步事件循环
    self._start_event_loop()
```

#### 队列作业 (第122-148行)
```python
def queue_job(self, job_wrapper):
    # 获取云提供商
    cloud_provider = self._get_cloud_provider(job_destination)

    # 创建作业规格
    job_spec = self._create_job_spec(job_wrapper, job_destination)

    # 异步提交
    future = asyncio.run_coroutine_threadsafe(
        self._submit_cloud_job(job_wrapper, job_spec, cloud_provider),
        self._loop
    )

    # 创建作业状态
    job_state = CloudJobState(job_wrapper, future)
    self.active_jobs[job_wrapper.get_id_tag()] = job_state
```

#### 提交云作业 (第287-301行)
```python
async def _submit_cloud_job(self, job_wrapper, job_spec: JobSpec, cloud_provider: str) -> str:
    # 获取或创建云执行器
    cloud_executor = await self._get_cloud_executor(cloud_provider)

    # 提交作业
    cloud_job_id = await cloud_executor.submit_job(job_spec)

    return cloud_job_id
```

---

### 2. **执行器工厂: CloudExecutorFactory**
**文件**: `galaxy_cloud/factory.py`

#### 创建执行器 (第27-63行)
```python
@staticmethod
def create(executor_name: str, config: Dict[str, Any], auth: Optional[CloudAuth] = None) -> CloudExecutor:
    # 从注册表获取执行器类
    executor_class = registry.get_executor(executor_name)

    if executor_class is None:
        available = registry.list_executors()
        raise ValueError(f"Executor '{executor_name}' not found. Available executors: {', '.join(available)}")

    # 创建执行器实例
    if auth:
        return executor_class(config, auth=auth)
    else:
        return executor_class(config)
```

---

### 3. **AWS Batch执行器: AWSBatchExecutor**
**文件**: `galaxy_cloud/providers/aws/executor.py`

#### 注册装饰器 (第30-35行)
```python
@cloud_executor("aws-batch", metadata={
    "requires": ["boto3"],
    "description": "AWS Batch executor for scalable job processing",
    "supports_arrays": True,
    "supports_spot": True
})
class AWSBatchExecutor(CloudExecutor):
```

#### 初始化 (第48-88行)
```python
def __init__(self, config: Dict[str, Any], auth: Optional[CloudAuth] = None):
    super().__init__(config)

    self.auth = auth or AWSAuth(config)

    # AWS Batch配置
    self.region = config.get('region', 'us-east-1')
    self.job_queue = config.get('batch_queue') or config.get('job_queue')
    self.job_definition_name = config.get('batch_job_definition', 'galaxy-cloud-executor')

    # Spot实例配置
    self.spot_allocation = config.get('spot_allocation', 'onDemand')

    # S3配置
    self.s3_bucket = config.get('s3_bucket')

    # AWS客户端
    self._batch_client = None
    self._ecs_client = None
    self._logs_client = None
    self._s3_client = None
```

#### 初始化客户端 (第90-108行)
```python
async def initialize(self) -> None:
    # 初始化认证
    await self.auth.initialize()

    # 创建AWS客户端
    self._batch_client = await self.auth.get_boto3_client('batch', region_name=self.region)
    self._ecs_client = await self.auth.get_boto3_client('ecs', region_name=self.region)
    self._logs_client = await self.auth.get_boto3_client('logs', region_name=self.region)

    if self.s3_bucket:
        self._s3_client = await self.auth.get_boto3_client('s3', region_name=self.region)

    # 验证队列存在
    await self._validate_job_queue()
```

#### 提交作业 (继续阅读文件可以看到)
```python
async def submit_job(self, job_spec: JobSpec) -> str:
    # 1. 上传输入数据到S3
    await self._upload_input_data(job_spec)

    # 2. 注册作业定义
    job_def_arn = await self._register_job_definition(job_spec)

    # 3. 提交到AWS Batch
    response = self._batch_client.submit_job(
        jobName=job_spec.job_id,
        jobQueue=self.job_queue,
        jobDefinition=job_def_arn,
        containerOverrides={
            'vcpus': job_spec.resources.cpus,
            'memory': job_spec.resources.memory_mb,
            'command': job_spec.container.command,
            'environment': [
                {'name': k, 'value': v}
                for k, v in job_spec.container.env.items()
            ]
        }
    )

    return response['jobId']
```

---

## 📋 配置文件的作用

### job_conf.yml (Galaxy配置)
```yaml
runners:
  galaxy_cloud:
    load: galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner  # ← 加载这个Runner类
    workers: 8
    params:
      cloud_config_file: config/aws_cloud_config.yaml
      default_provider: aws

destinations:
  aws_large:
    runner: galaxy_cloud          # ← 使用galaxy_cloud runner
    params:
      provider: aws               # ← 传递给GalaxyCloudJobRunner._get_cloud_provider()
      cpus: 4                     # ← 传递给ResourceSpec
      memory_mb: 16384
      disk_gb: 100

tools:
  - id: toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem
    destination: aws_large        # ← BWA工具自动路由到aws_large
```

### aws_cloud_config.yaml (云配置)
```yaml
aws:
  region: us-west-2
  batch_queue: galaxy-cloud-queue          # ← 传递给AWSBatchExecutor.job_queue
  s3_bucket: galaxy-cloud-data-1760241377  # ← 传递给AWSBatchExecutor.s3_bucket
  spot_allocation: spot
```

---

## 🔄 执行流程总结

### 步骤1: Galaxy加载配置
1. 读取 `job_conf.yml`
2. 实例化 `GalaxyCloudJobRunner`
3. 初始化云组件 (ToolRegistry, DataManager)

### 步骤2: 用户运行Workflow
1. Galaxy解析workflow
2. 对每个tool，查找对应的destination
3. 例如: `bwa_mem` → `aws_large` → `galaxy_cloud` runner

### 步骤3: 创建作业
1. `GalaxyCloudJobRunner.queue_job()` 被调用
2. 从destination提取云提供商 (`provider: aws`)
3. 创建 `JobSpec` (容器镜像、资源需求)

### 步骤4: 提交到云端
1. `CloudExecutorFactory.create('aws-batch', config)` 创建执行器
2. `AWSBatchExecutor.submit_job(job_spec)` 提交作业
3. 调用 `boto3.submit_job()` 提交到AWS Batch

### 步骤5: AWS执行
1. AWS Batch在队列中排队
2. 分配EC2/Fargate资源
3. 拉取Docker镜像
4. 从S3下载输入
5. 执行容器
6. 上传输出到S3

### 步骤6: 监控和完成
1. `AWSBatchExecutor.wait_for_completion()` 轮询状态
2. `GalaxyCloudJobRunner._monitor_cloud_job()` 监控
3. 完成后调用 `job_wrapper.finish()` 更新Galaxy
4. Galaxy保存结果到数据集
5. 用户在UI中看到结果

---

## 🎯 关键设计模式

### 1. **装饰器注册模式**
```python
@cloud_executor("aws-batch", metadata={...})
class AWSBatchExecutor(CloudExecutor):
    pass
```
- 自动注册到 `registry`
- 通过名称动态创建实例

### 2. **工厂模式**
```python
CloudExecutorFactory.create('aws-batch', config)
```
- 统一的创建接口
- 支持多种云提供商

### 3. **异步架构**
```python
async def submit_job(self, job_spec: JobSpec) -> str:
    ...
```
- 非阻塞执行
- 高并发支持

### 4. **桥接模式**
```python
GalaxyCloudJobRunner (Galaxy) → CloudExecutor (通用) → AWSBatchExecutor (AWS)
```
- Galaxy层 → 抽象层 → 具体实现
- 解耦Galaxy和云提供商

---

## ✅ 总结

当你在Galaxy平台上运行workflow时:

1. **不需要写任何代码** - 只需配置 `job_conf.yml`
2. **自动路由** - 根据tool ID自动选择云实例
3. **通用执行** - 任何workflow都能用,完全自动化
4. **多云支持** - 同样的方式支持AWS/Azure/GCP/K8s

核心代码路径:
```
Galaxy UI
  → galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner
  → galaxy_cloud.factory:CloudExecutorFactory
  → galaxy_cloud.providers.aws.executor:AWSBatchExecutor
  → AWS Batch Service (云端执行)
  → 结果返回Galaxy
```

这就是你的 `galaxy_cloud` 模块的强大之处 - **完全通用,无需定制**! 🚀
