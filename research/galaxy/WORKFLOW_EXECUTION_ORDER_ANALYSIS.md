# Workflow 流式执行机制详解

## 你的问题

**"你如何保证 workflow 是一步步的流式执行的，就是 A->B->C->D 这种流式，先执行完 A 以后，A 的输出喂给 B，然后执行完 B 以后，B 的输出喂给 C，执行完 C 以后，把 C 的输出给 D。"**

这是一个非常核心的问题！让我详细分析当前实现是如何保证这个流式执行的。

---

## 核心答案：两层依赖保证机制

当前系统通过**两层机制**来保证 workflow 的正确执行顺序：

### Layer 1: Galaxy 核心的依赖管理（本地）
Galaxy 的 job handler 在任务入队前会检查输入数据状态

### Layer 2: DAG Executor 的拓扑排序（云端）
`WorkflowDAGExecutor` 通过拓扑排序确保依赖顺序

**关键发现**: 当前实现有**两个独立的执行路径**，它们的依赖管理方式完全不同！

---

## 执行路径 1: Galaxy Job Runner (单任务模式) - **当前使用**

### 代码位置
[galaxy_job_runner.py:235-313](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L235-L313)

### 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Galaxy 核心 (lib/galaxy/jobs/__init__.py)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  for job in workflow:                                            │
│      # Galaxy 核心检查依赖                                        │
│      if all_inputs_ready(job):  # ← 关键！                      │
│          job_handler.queue_job(job)                              │
│      else:                                                        │
│          wait_for_inputs()                                       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│ Cloud Job Runner (galaxy_job_runner.py)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  def queue_job(job_wrapper):                                     │
│      # 此时所有输入已经就绪（Galaxy 核心已检查）                │
│      # 注释中明确说明:                                            │
│      # "Galaxy's job handler already checks input dataset       │
│      #  readiness before calling this method"                   │
│                                                                   │
│      # 提交到云端执行                                             │
│      submit_to_aws_batch(job)                                    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│ AWS Batch Job (容器)                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. 下载输入文件 (从 S3)                                          │
│  2. 执行工具命令                                                  │
│  3. 上传输出文件 (到 S3)                                          │
│  4. 通知 Galaxy 完成                                              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│ Galaxy 核心更新状态                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  # Galaxy 收到任务完成通知                                        │
│  job.mark_as_completed()                                         │
│  output_dataset.state = 'ok'  # ← 标记输出就绪                  │
│                                                                   │
│  # 检查 workflow 中的下一个任务                                   │
│  # 如果 next_job 的输入现在都就绪了，则入队                       │
│  if all_inputs_ready(next_job):                                  │
│      job_handler.queue_job(next_job)                             │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 依赖检查代码（Galaxy 核心）

Galaxy 核心的关键代码（不在我们的代码库中，但逻辑如下）:

```python
# lib/galaxy/jobs/__init__.py (Galaxy 核心代码)
def check_ready_to_run(job):
    """检查任务是否准备好运行"""
    for input_assoc in job.input_datasets:
        dataset = input_assoc.dataset

        # 检查数据集状态
        if dataset.state != 'ok':
            # 输入数据尚未就绪，不能运行
            return False

        # 检查数据集文件是否存在
        if not dataset.dataset.file_exists():
            return False

    # 所有输入都就绪
    return True

def __monitor_workflow(workflow_invocation):
    """监控 workflow 执行"""
    while not workflow_invocation.is_complete():
        for step in workflow_invocation.steps:
            if step.state == 'ready':  # 所有依赖都满足
                # 创建 job 并提交到 job handler
                job = create_job_for_step(step)
                self.job_manager.enqueue(job)  # ← 这里会调用 queue_job
```

### 我们代码中的证据

[galaxy_job_runner.py:236-259](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L236-L259):

```python
def queue_job(self, job_wrapper):
    """
    Queue a job for execution.

    Note: Galaxy's job handler already checks input dataset readiness before calling
    this method, so we don't need to duplicate that check here. The handler ensures
    that workflow dependencies are respected by only queueing jobs when their inputs
    are ready (i.e., when previous jobs have completed and marked outputs as OK).
    """

    # 记录输入数据集状态（用于调试）
    job = job_wrapper.get_job()
    input_info = []
    for dataset_assoc in job.input_datasets:
        if dataset_assoc.dataset:
            input_info.append(
                f"{dataset_assoc.dataset.hid}:{dataset_assoc.dataset.state}"
            )
    self.logger.info(
        f"Queueing job {job_wrapper.get_id_tag()} with input datasets: "
        f"{', '.join(input_info) if input_info else 'none'}"
    )
```

**关键点**: 注释明确说明 Galaxy 核心已经检查了输入就绪性！

### 实际执行时间线（A->B->C->D）

```
时间线：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T0: Workflow 开始
    - Galaxy: 分析 workflow，识别 A, B, C, D 及其依赖关系
    - Galaxy: A 没有依赖，立即入队
    - queue_job(A) 被调用
    - A 提交到 AWS Batch

T1: A 在云端执行
    - 容器启动
    - 下载 A 的输入
    - 执行 A 的命令
    - 生成 output_A
    - 上传 output_A 到 S3

T2: A 完成
    - Galaxy: 收到 A 完成通知
    - Galaxy: 下载 output_A 到本地数据库
    - Galaxy: dataset_output_A.state = 'ok'  ← 标记输出就绪
    - Galaxy: 检查 B 的依赖
    - Galaxy: B 依赖 output_A，现在就绪了！
    - queue_job(B) 被调用
    - B 提交到 AWS Batch

T3: B 在云端执行
    - 容器启动
    - 下载 B 的输入（包括 output_A）
    - 执行 B 的命令
    - 生成 output_B
    - 上传 output_B 到 S3

T4: B 完成
    - Galaxy: 收到 B 完成通知
    - Galaxy: dataset_output_B.state = 'ok'
    - Galaxy: 检查 C 的依赖
    - queue_job(C) 被调用
    - C 提交到 AWS Batch

... (同样的流程 C -> D)
```

### 数据传递路径

```
A 的输出 → B 的输入：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. A 执行完成
   容器: /tmp/outputs/output_A.txt

2. A 上传输出
   S3: s3://bucket/jobs/A/outputs/output_A.txt

3. Galaxy 收集输出
   本地: /database/objects/a/b/c/dataset_xxx.dat

4. Galaxy 标记数据集就绪
   dataset.state = 'ok'

5. Galaxy 入队 B（依赖满足）
   queue_job(B)

6. B 准备输入
   Galaxy: 上传 dataset_xxx.dat 到 S3
   S3: s3://bucket/jobs/B/inputs/dataset_xxx.dat

7. B 下载输入
   容器: /galaxy_inputs/dataset_xxx.dat

8. B 创建符号链接
   ln -s /galaxy_inputs/dataset_xxx.dat input_B.txt

9. B 执行命令
   tool_command input_B.txt > output_B.txt
```

---

## 执行路径 2: DAG Executor (批量 workflow 模式) - **未使用**

### 代码位置
[dag_executor.py:177-213](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/dag_executor.py#L177-L213)

### 执行流程

这是一个**完全独立的执行路径**，目前**没有被实际使用**（因为 Galaxy 核心不会调用它）。

```python
async def _execute_dag_steps(self, context: ExecutionContext):
    """Execute workflow steps in DAG order"""
    workflow_dag = context.workflow_execution.workflow_dag

    # 1. 构建依赖图
    dependency_graph = self._build_dependency_graph(workflow_dag)
    # dependency_graph = {
    #     'step_B': {'step_A'},      # B 依赖 A
    #     'step_C': {'step_B'},      # C 依赖 B
    #     'step_D': {'step_C'},      # D 依赖 C
    # }

    # 2. 拓扑排序 - 获取执行层级
    execution_levels = self._topological_sort(workflow_dag, dependency_graph)
    # execution_levels = [
    #     ['step_A'],           # Level 0: 无依赖，先执行
    #     ['step_B'],           # Level 1: 依赖 Level 0，等 A 完成后执行
    #     ['step_C'],           # Level 2: 依赖 Level 1，等 B 完成后执行
    #     ['step_D']            # Level 3: 依赖 Level 2，等 C 完成后执行
    # ]

    # 3. 逐层执行
    for level_idx, step_ids in enumerate(execution_levels):
        self.logger.info(f"Executing level {level_idx + 1} with steps: {step_ids}")

        # 并行执行本层的所有步骤
        await self._execute_steps_parallel(context, step_ids)

        # 检查失败
        if any_failed:
            raise Exception(f"Steps failed: {failed_steps}")

        # 本层全部完成后，才进入下一层
```

### 拓扑排序算法（Kahn's Algorithm）

[dag_executor.py:223-250](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/dag_executor.py#L223-L250):

```python
def _topological_sort(self, workflow_dag: WorkflowDAG, dependency_graph: Dict[str, Set[str]]) -> List[List[str]]:
    """
    执行拓扑排序以获取执行层级

    使用 Kahn's 算法的层级版本
    """
    # 1. 计算每个节点的入度（有多少个依赖）
    in_degree = {step_id: 0 for step_id in workflow_dag.steps.keys()}

    reverse_graph = defaultdict(set)
    for step_id, dependencies in dependency_graph.items():
        in_degree[step_id] = len(dependencies)  # 入度 = 依赖数量
        for dep in dependencies:
            reverse_graph[dep].add(step_id)  # 反向图: dep 完成后可以解锁 step_id

    # 2. 找到所有入度为 0 的节点（无依赖）
    queue = deque([step_id for step_id, degree in in_degree.items() if degree == 0])
    # 例如: queue = ['step_A']

    result = []

    # 3. 逐层处理
    while queue:
        # 当前层的所有节点（入度都为 0，可以并行执行）
        current_level = list(queue)
        queue.clear()
        result.append(current_level)

        # 处理当前层的每个节点
        for step_id in current_level:
            # 这个节点完成后，减少依赖它的节点的入度
            for neighbor in reverse_graph[step_id]:
                in_degree[neighbor] -= 1
                # 如果入度变为 0，说明所有依赖都满足了
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

    return result
```

### 示例：A->B->C->D

```python
# 输入
dependency_graph = {
    'B': {'A'},   # B 依赖 A
    'C': {'B'},   # C 依赖 B
    'D': {'C'}    # D 依赖 C
}

# 步骤 1: 计算入度
in_degree = {'A': 0, 'B': 1, 'C': 1, 'D': 1}
reverse_graph = {'A': {'B'}, 'B': {'C'}, 'C': {'D'}}

# 步骤 2: 初始队列（入度为 0）
queue = ['A']

# 迭代 1
current_level = ['A']  # Level 0
result = [['A']]
# A 完成后，B 的入度减 1 变为 0
in_degree = {'A': 0, 'B': 0, 'C': 1, 'D': 1}
queue = ['B']

# 迭代 2
current_level = ['B']  # Level 1
result = [['A'], ['B']]
# B 完成后，C 的入度减 1 变为 0
in_degree = {'A': 0, 'B': 0, 'C': 0, 'D': 1}
queue = ['C']

# 迭代 3
current_level = ['C']  # Level 2
result = [['A'], ['B'], ['C']]
# C 完成后，D 的入度减 1 变为 0
queue = ['D']

# 迭代 4
current_level = ['D']  # Level 3
result = [['A'], ['B'], ['C'], ['D']]

# 最终结果
execution_levels = [['A'], ['B'], ['C'], ['D']]
```

### 并行执行（同一层内）

如果 workflow 是这样的：

```
     A
    / \
   B   C    ← B 和 C 都依赖 A，但互不依赖
    \ /
     D      ← D 依赖 B 和 C
```

拓扑排序结果：

```python
execution_levels = [
    ['A'],      # Level 0: A 无依赖
    ['B', 'C'], # Level 1: B 和 C 依赖 A（并行！）
    ['D']       # Level 2: D 依赖 B 和 C
]
```

执行逻辑：

```python
# Level 1: 并行执行 B 和 C
await self._execute_steps_parallel(context, ['B', 'C'])

# 内部实现
async def _execute_steps_parallel(self, context, step_ids):
    max_parallel = 10  # 最大并行数
    semaphore = asyncio.Semaphore(max_parallel)

    # 创建所有任务
    tasks = []
    for step_id in step_ids:
        task = asyncio.create_task(
            self._execute_single_step_with_semaphore(context, step_id, semaphore)
        )
        tasks.append(task)

    # 等待所有任务完成
    await asyncio.gather(*tasks)  # ← 并行等待 B 和 C
```

### 数据传递（DAG Executor 模式）

[dag_executor.py:370-413](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/dag_executor.py#L370-L413):

```python
async def _prepare_job_inputs(self, context: ExecutionContext, step: WorkflowStep):
    """准备任务输入并更新 job specification"""
    job_spec = step.job_spec.model_copy()

    input_files = {}

    # 从前序步骤获取输出数据
    workflow_dag = context.workflow_execution.workflow_dag
    for dependency in workflow_dag.dependencies:
        if dependency.to_step == step.step_id:
            from_step = dependency.from_step
            from_output = dependency.from_output
            to_input = dependency.to_input

            # 从 context.step_outputs 获取前序步骤的输出
            if from_step in context.step_outputs:
                step_output = context.step_outputs[from_step].get(from_output)
                if step_output:
                    # 直接使用 S3 URI（不经过 Galaxy 本地）
                    cloud_uri = step_output['cloud_uri']  # ← 关键！
                    container_path = f"/input/{to_input}"
                    input_files[cloud_uri] = container_path

    job_spec.input_files = input_files
    return job_spec
```

**关键差异**: DAG Executor 模式下，数据直接在 S3 传递，**不经过 Galaxy 本地**！

```
A 输出 → B 输入 (DAG Executor 模式):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. A 执行完成
   容器: /tmp/outputs/output_A.txt

2. A 上传输出
   S3: s3://bucket/workflow_123/step_A/output_A.txt

3. DAG Executor 记录输出位置
   context.step_outputs['step_A']['output'] = {
       'type': 'dataset',
       'cloud_uri': 's3://bucket/workflow_123/step_A/output_A.txt'
   }

4. DAG Executor 准备 B 的输入
   # 直接使用 A 的 S3 URI，不下载到 Galaxy
   job_spec.input_files = {
       's3://bucket/workflow_123/step_A/output_A.txt': '/input/input_B.txt'
   }

5. B 下载输入
   容器: /input/input_B.txt  (直接从 S3 下载)

6. B 执行命令
   tool_command /input/input_B.txt > /output/output_B.txt
```

---

## 对比总结：两种执行模式

| 特性 | Galaxy Job Runner 模式 | DAG Executor 模式 |
|------|------------------------|-------------------|
| **当前使用** | ✅ 是（默认） | ❌ 否 |
| **依赖检查** | Galaxy 核心（job handler） | DAG Executor（拓扑排序） |
| **并行执行** | ❌ 否（严格串行） | ✅ 是（同层并行） |
| **数据传递** | S3 → Galaxy 本地 → S3 | S3 → S3（直接） |
| **任务调度** | Galaxy 核心控制 | DAG Executor 全权控制 |
| **优点** | 完全集成 Galaxy，可靠 | 高效，并行，减少传输 |
| **缺点** | 每个任务都要往返 Galaxy | 需要独立实现，未集成 |

---

## 当前实现的问题和优化建议

### 问题 1: 数据传递效率低（Galaxy Job Runner 模式）

**当前流程**:
```
A (云端) → S3 → Galaxy 本地 → S3 → B (云端)
           ↑               ↑
        浪费的往返！
```

**每个任务的数据流**:
```
1. A 上传输出: 10 GB
2. Galaxy 下载: 10 GB
3. Galaxy 上传给 B: 10 GB
4. B 下载: 10 GB

总传输: 40 GB（实际只需要 10 GB！）
```

**优化建议**: 使用 DAG Executor 模式，数据直接在 S3 传递

### 问题 2: 无法并行执行（Galaxy Job Runner 模式）

**当前**:
```
A → 完成 → Galaxy 处理 → B → 完成 → Galaxy 处理 → C
```

**如果有并行机会**:
```
     A
    / \
   B   C    ← B 和 C 可以并行，但当前串行执行
    \ /
     D
```

**优化建议**: 集成 DAG Executor，识别并行机会

### 问题 3: Galaxy 本地成为瓶颈

**当前架构**:
```
所有数据必须经过 Galaxy 本地
    ↓
Galaxy 服务器磁盘和网络成为瓶颈
    ↓
即使云端有无限资源，也受限于本地处理速度
```

---

## 推荐的混合架构

### 方案 A: 渐进式优化（推荐）

**短期（当前可行）**:
1. 保持 Galaxy Job Runner 模式
2. 优化数据传递：
   - 添加 S3 直传选项（输出不下载到 Galaxy）
   - 使用 CloudFront 缓存常用数据
   - 实现增量传输（只传输变化部分）

**中期**:
1. 为简单 workflow 启用 DAG Executor
2. 条件判断：
   ```python
   if workflow_is_simple(workflow):
       use_dag_executor()  # S3 直传，高效
   else:
       use_galaxy_job_runner()  # 兼容性好
   ```

**长期**:
1. 完全迁移到 DAG Executor
2. Galaxy 只管理元数据
3. 数据完全在云端流动

### 方案 B: 智能元数据模式

**核心思想**: Galaxy 不存储实际数据，只存储 S3 引用

```python
class CloudDataset:
    """云端数据集（只存储引用）"""
    id: str
    s3_uri: str  # s3://bucket/path/to/file
    size: int
    metadata: Dict

    def get_file_name(self):
        # 不返回本地路径，返回 S3 URI
        return self.s3_uri

    def materialize(self):
        # 仅在必要时下载到本地（例如用户点击下载）
        if not self.local_cache_path:
            download_from_s3(self.s3_uri, self.local_cache_path)
        return self.local_cache_path
```

**Workflow 执行**:
```python
# A 执行完成
output_A = CloudDataset(
    id='dataset_123',
    s3_uri='s3://bucket/outputs/output_A.txt',
    size=10_000_000_000  # 10 GB
)

# Galaxy 只记录元数据，不下载数据
galaxy.save_dataset_metadata(output_A)

# B 准备输入
# 直接使用 S3 URI，不经过 Galaxy 本地
input_spec = {
    's3://bucket/outputs/output_A.txt': '/input/input_B.txt'
}
```

**效果**:
```
A (云端) → S3 ─────────────────────→ B (云端)
            ↓
         Galaxy 记录元数据（几 KB）
```

---

## 立即可行的改进（不破坏现有架构）

### 改进 1: 添加"快速通道"标记

```python
# galaxy_job_runner.py
def _finish_job(self, job_wrapper):
    """任务完成后的处理"""
    job = job_wrapper.get_job()

    # 检查输出是否可以保留在 S3（不下载）
    if self._can_use_fast_path(job):
        # 只记录 S3 URI，不下载数据
        for output_assoc in job.output_datasets:
            dataset = output_assoc.dataset
            dataset.cloud_uri = f"s3://bucket/jobs/{job.id}/outputs/{dataset.name}"
            dataset.state = 'ok'
            dataset.file_size = get_s3_file_size(dataset.cloud_uri)
            # 不调用 dataset.save_file()
    else:
        # 传统方式：下载到本地
        self._download_outputs_from_s3(job)
```

### 改进 2: 输入准备优化

```python
# galaxy_job_runner.py
def _stage_inputs_to_s3(self, job):
    """准备输入文件"""
    for input_assoc in job.input_datasets:
        dataset = input_assoc.dataset

        # 检查数据是否已经在 S3
        if hasattr(dataset, 'cloud_uri') and dataset.cloud_uri:
            # 数据已在 S3，直接引用（零拷贝！）
            self.logger.info(f"Using existing S3 URI: {dataset.cloud_uri}")
            return dataset.cloud_uri
        else:
            # 数据在本地，上传到 S3
            s3_uri = self._upload_to_s3(dataset.get_file_name())
            # 缓存 S3 URI
            dataset.cloud_uri = s3_uri
            return s3_uri
```

### 改进 3: Workflow 级别的 S3 staging area

```python
# 为每个 workflow invocation 创建专用的 S3 区域
staging_area = f"s3://bucket/workflows/invocation_{invocation_id}/"

# A 的输出
output_A = f"{staging_area}/step_A/output.txt"

# B 的输入配置
# 直接引用 A 的 S3 输出位置
input_config = {
    'input_B': output_A  # ← 零拷贝！
}
```

---

## 总结：如何保证 A->B->C->D 的执行顺序？

### 当前实现（Galaxy Job Runner）

✅ **通过 Galaxy 核心的 job handler 保证**:

1. Galaxy 分析 workflow 依赖关系
2. 只有当任务的所有输入都是 `state='ok'` 时，才调用 `queue_job()`
3. 任务完成后，Galaxy 标记输出为 `'ok'`，触发依赖任务入队
4. 这个机制是**自动的**、**可靠的**、**久经考验的**

❌ **但存在效率问题**:

1. 数据必须经过 Galaxy 本地（往返开销）
2. 无法并行执行（严格串行）
3. Galaxy 服务器成为瓶颈

### 未来优化（DAG Executor）

✅ **通过拓扑排序保证**:

1. 构建依赖图
2. Kahn's 算法计算执行层级
3. 逐层执行，层内并行
4. 数据在 S3 直传

✅ **优势**:

1. 高效（减少 4 倍数据传输）
2. 并行（充分利用云资源）
3. 可扩展（Galaxy 不是瓶颈）

❌ **挑战**:

1. 需要与 Galaxy 核心深度集成
2. 需要处理边缘情况
3. 需要大量测试

### 推荐方案

**短期**: 优化现有 Galaxy Job Runner
- 添加 S3 直传选项
- 缓存 S3 URI
- 减少不必要的数据下载

**长期**: 迁移到 DAG Executor
- 先支持简单 workflow
- 逐步扩展到复杂场景
- 最终完全云原生化

---

**核心理念**: 依赖管理和数据传递分离
- **依赖管理**: 确保执行顺序（两种模式都能保证）
- **数据传递**: 优化传输效率（DAG Executor 更优）
