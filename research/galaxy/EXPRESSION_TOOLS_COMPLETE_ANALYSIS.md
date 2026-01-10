# Expression工具完整分析与云执行方案

## 1. Expression工具是什么？

Expression工具是Galaxy中一种特殊类型的工具，用于**参数选择和简单的数据处理**，不需要运行外部程序。

### 典型用途

- `pick_value`: 从多个可选值中选择一个（带默认值）
- `compose_text_param`: 组合文本参数
- `filter_failed_datasets`: 过滤失败的datasets
- `param_value_from_file`: 从文件解析参数值

### 在你的workflow中的使用

**Step 8** (pick_value):
```xml
<tool name="Pick parameter value" id="pick_value" tool_type="expression">
  <!-- 从输入参数或默认值0.05中选择adjusted p-value阈值 -->
</tool>
```

**Step 9** (pick_value):
```xml
<!-- 从输入参数或默认值1.0中选择log2 fold change阈值 -->
</tool>
```

**作用**: 让workflow可以接受可选参数，如果用户不提供就使用默认值。

---

## 2. Expression工具的执行流程（本地）

### 2.1 工具定义

```python
class ExpressionTool(Tool):
    requires_js_runtime = True          # 需要JS运行时(cwl-utils)
    tool_type = "expression"
    tool_type_local = True              # ⚠️ 标记为本地工具
    EXPRESSION_INPUTS_NAME = "_expression_inputs_.json"
```

### 2.2 执行流程

#### Step 1: 解析命令 (`parse_command`)
```python
def parse_command(self, tool_source):
    self.command = f"cd ../; {expressions.EXPRESSION_SCRIPT_CALL}"
    # 实际命令: "cd ../; python _evaluate_expression_.py"
    self._expression = tool_source.parse_expression().strip()
```

**关键**: 命令是固定的 `cd ../; python _evaluate_expression_.py`

#### Step 2: 作业准备 (`exec_before_job`)
```python
def exec_before_job(self, app, inp_data, out_data, param_dict=None):
    local_working_directory = param_dict["__local_working_directory__"]

    # 1. 写入评估脚本
    expressions.write_evalute_script(local_working_directory)
    # 创建文件: working_dir/_evaluate_expression_.py
    # 内容: from galaxy_ext.expressions.handle_job import run; run()

    # 2. 准备输入数据JSON
    expression_inputs_path = os.path.join(
        local_working_directory,
        "_expression_inputs_.json"
    )

    expression_inputs = {
        "job": {...},           # 输入参数
        "script": self._expression,  # 表达式脚本
        "outputs": [...]        # 输出定义
    }

    with open(expression_inputs_path, "w") as f:
        json.dump(expression_inputs, f)
```

**生成的文件**:
1. `_evaluate_expression_.py` - Python脚本
2. `_expression_inputs_.json` - 输入数据

#### Step 3: 执行脚本

命令: `cd ../; python _evaluate_expression_.py`

执行时：
1. `cd ../` - 从working目录回到job目录
2. `python _evaluate_expression_.py` - 执行脚本
3. 脚本读取 `_expression_inputs_.json`（通过环境变量或相对路径）
4. 使用`cwl-utils`库评估表达式
5. 输出结果到JSON文件

#### Step 4: 脚本内部逻辑 (`handle_job.py:run()`)

```python
def run(environment_path=None):
    # 1. 读取输入
    if environment_path is None:
        environment_path = os.environ.get("GALAXY_EXPRESSION_INPUTS")
    with open(environment_path) as f:
        raw_inputs = json.load(f)

    # 2. 评估表达式
    result = evaluate(None, inputs)

    # 3. 插值输出表达式 (使用cwl-utils)
    from_expression = f"$({from_expression})"
    output_value = expression.interpolate(from_expression, result)

    # 4. 写入输出文件
    with open(path, "w") as f:
        json.dump(output_value, f)
```

---

## 3. 为什么在云上失败？

### 3.1 本地执行环境

```
本地目录结构:
/Users/.../database/jobs_directory/000/566/
├── working/
│   ├── _evaluate_expression_.py        ← 生成
│   ├── _expression_inputs_.json        ← 生成
│   └── (其他临时文件)
└── outputs/
    └── float_param.json                 ← 输出

执行:
cd /Users/.../database/jobs_directory/000/566/working
cd ../                                   ← 回到job目录
python _evaluate_expression_.py         ← 在job目录执行
```

**关键**: 脚本在job目录执行，通过相对路径访问`working/_expression_inputs_.json`

### 3.2 云执行环境（当前）

```
容器目录结构:
/galaxy_execution/
└── job/
    ├── working/                         ← 工作目录
    │   └── (空 - 没有文件被上传!)      ← ❌ 问题
    ├── inputs/
    └── outputs/

S3结构:
s3://bucket/jobs/566/
└── job_script.sh                        ← 只有这个文件!
    (没有 working/ 目录!)                ← ❌ 问题

执行:
cd /galaxy_execution/job/working         ← job script的当前目录
cd /galaxy_execution/job                 ← cd ../
python _evaluate_expression_.py         ← ❌ 文件不存在!
```

### 3.3 失败的原因

#### 原因1: `_evaluate_expression_.py`没有被创建
- `write_evalute_script()` 在`exec_before_job()`中被调用
- 但`exec_before_job()`可能在云执行器提交job**之后**才运行
- 或者运行了但在**本地机器**上，而不是在容器中

#### 原因2: 即使创建了，也没有被上传到S3
- `extra_filenames`应该包含这个文件
- 但我们的`_universal_upload_job_files`没有上传它
- 检查S3只有`job_script.sh`

#### 原因3: `_expression_inputs_.json`也缺失
- 这个文件也在`exec_before_job()`中创建
- 同样的问题：没有上传到S3

#### 原因4: 命令路径问题
- 本地: `cd ../; python _evaluate_expression_.py`
- 我们的重写: `cd /galaxy_execution/job; python _evaluate_expression_.py`
- 但文件应该在哪里？working目录还是job目录？

---

## 4. Galaxy Job执行生命周期分析

### 4.1 本地Job Runner流程

```
1. prepare()
   ├─ tool.exec_before_job()
   │  ├─ 创建 _evaluate_expression_.py
   │  └─ 创建 _expression_inputs_.json
   └─ 生成 command_line = "cd ../; python _evaluate_expression_.py"

2. queue_job()
   └─ 添加到job队列

3. run_job()
   ├─ 设置工作目录
   ├─ 执行命令 (在本地)
   └─ 收集输出

4. finish_job()
   └─ tool.exec_after_process()
```

### 4.2 云Job Runner流程（当前）

```
1. queue_job()
   └─ GalaxyCloudJobRunner.queue_job()

2. run_next()
   └─ GalaxyCloudJobRunner.run_next()

3. _submit_fetch_and_run_job()
   ├─ prepare()                         ← 调用了
   │  ├─ tool.exec_before_job()?       ← ⚠️ 但可能不运行
   │  └─ 生成 command_line
   │
   ├─ _universal_upload_job_files()
   │  ├─ 上传 inputs
   │  └─ 上传 extra_filenames          ← ⚠️ 但列表可能是空的!
   │
   ├─ rewrite_command()
   │  └─ path_rewriter.rewrite_command()
   │
   ├─ _generate_universal_job_script()
   │  └─ 生成包含命令的bash脚本
   │
   └─ 提交到AWS Batch

4. 容器执行
   └─ ❌ 失败: 文件不存在
```

### 4.3 关键差异

| 方面 | 本地执行 | 云执行（当前） |
|------|---------|--------------|
| `exec_before_job()` 运行? | ✅ 总是运行 | ⚠️ 不确定 |
| 文件创建位置 | 本地工作目录 | ❌ 可能未创建 |
| 文件传输 | 不需要 | ❌ 未实现 |
| 执行环境 | Galaxy本地 | AWS Batch容器 |
| Galaxy库可用? | ✅ 是 | ❌ 否 (需要在容器中) |

---

## 5. 为什么`extra_filenames`为空？

让我检查调用链：

### 5.1 正常流程（应该的）

```python
# galaxy/jobs/__init__.py
class JobWrapper:
    def prepare(self):
        # ...
        self.tool.exec_before_job(
            self.app,
            self.inp_data,
            self.out_data,
            self.param_dict
        )
        # exec_before_job() 应该填充 extra_filenames
```

### 5.2 Expression工具的实现

```python
# galaxy/tools/__init__.py
class ExpressionTool(Tool):
    def exec_before_job(self, app, inp_data, out_data, param_dict=None):
        super().exec_before_job(...)  # 调用父类

        local_working_directory = param_dict["__local_working_directory__"]

        # 创建脚本
        expressions.write_evalute_script(local_working_directory)
        # ⚠️ 但是没有添加到 extra_filenames!

        # 创建输入JSON
        expression_inputs_path = os.path.join(...)
        with open(expression_inputs_path, "w") as f:
            json.dump(expression_inputs, f)
        # ⚠️ 也没有添加到 extra_filenames!
```

### 5.3 问题发现

**Expression工具没有将生成的文件添加到`extra_filenames`！**

这是因为Expression工具假设：
1. 执行在**本地**进行 (`tool_type_local = True`)
2. 文件在同一个文件系统上
3. 不需要传输

但在云执行中，这些假设都不成立！

---

## 6. 解决方案设计

### 方案A: 让Expression工具在本地执行（推荐）

**原理**: Expression工具标记为`tool_type_local = True`就是为了在本地执行

**实现**:

#### Step 1: 修改job_conf.yml

```yaml
execution:
  default: cloud_small
  environments:
    local:
      runner: local
    cloud_small:
      runner: galaxy_cloud_executor_plugin
      params:
        provider: aws
        # ...

tools:
  - id: pick_value
    environment: local               # ← 在本地执行
  - id: compose_text_param
    environment: local
  - id: param_value_from_file
    environment: local
  - id: filter_failed_datasets
    environment: local
```

#### Step 2: 无需修改代码

Expression工具会在Galaxy服务器本地执行，结果作为参数传给下一个云上的工具。

**优点**:
- ✅ 简单、可靠
- ✅ 不需要修改云执行器代码
- ✅ Expression工具执行很快（<1秒）
- ✅ 符合Galaxy的设计意图

**缺点**:
- ⚠️ Galaxy服务器需要保持运行
- ⚠️ 需要安装`cwl-utils`库

---

### 方案B: 完整支持Expression工具云执行（复杂）

**如果你坚持要在云上执行Expression工具**，需要以下改动：

#### 改动1: 捕获Expression工具生成的文件

```python
# galaxy_job_runner.py
def _submit_fetch_and_run_job(self, job_wrapper, ...):
    # 调用prepare
    job_wrapper.prepare()

    # ⚠️ 对Expression工具特殊处理
    if job_wrapper.tool.tool_type == "expression":
        # 获取工作目录
        working_dir = job_wrapper.working_directory

        # 手动收集Expression工具的文件
        expression_files = [
            os.path.join(working_dir, "_evaluate_expression_.py"),
            os.path.join(working_dir, "_expression_inputs_.json"),
        ]

        # 上传到S3 working/
        for f in expression_files:
            if os.path.exists(f):
                s3_client.upload_file(
                    f,
                    s3_bucket,
                    f"jobs/{job_id}/working/{os.path.basename(f)}"
                )
```

#### 改动2: 确保容器有必要的Python库

修改`docker/fetch-and-run/Dockerfile`:
```dockerfile
# 安装Galaxy所需的Python库
RUN pip3 install cwl-utils galaxy-tool-util
```

#### 改动3: 将Galaxy库复制到容器

```dockerfile
# 复制Galaxy库到容器
COPY lib/galaxy_ext /galaxy_lib/galaxy_ext
COPY lib/galaxy/tools/expressions /galaxy_lib/galaxy/tools/expressions
ENV PYTHONPATH=/galaxy_lib:$PYTHONPATH
```

#### 改动4: 修改命令路径

```python
# universal_path_rewriter.py
def rewrite_command(self, command: str) -> str:
    # 特殊处理 expression工具的 "cd ../"
    if "_evaluate_expression_.py" in command:
        # 原命令: cd ../; python _evaluate_expression_.py
        # 改为: cd $GALAXY_WORK_DIR; python _evaluate_expression_.py
        rewritten = re.sub(
            r'cd\s+\.\./?\s*;\s*',
            f'cd {self.CONTAINER_WORK_DIR}; ',
            command
        )
        # 设置环境变量指向输入JSON
        rewritten = f'export GALAXY_EXPRESSION_INPUTS={self.CONTAINER_WORK_DIR}/_expression_inputs_.json; {rewritten}'
        return rewritten
```

**优点**:
- ✅ 完全在云上执行
- ✅ 不依赖Galaxy服务器

**缺点**:
- ❌ 复杂，需要大量修改
- ❌ 需要在容器中包含Galaxy代码
- ❌ 增加容器大小
- ❌ Expression工具本来就很快，没必要云执行
- ❌ 违背了`tool_type_local = True`的设计意图

---

## 7. 推荐方案

**我强烈推荐方案A：让Expression工具在本地执行**

### 理由

1. **符合设计**: Expression工具标记为`tool_type_local = True`
2. **简单可靠**: 不需要修改代码
3. **性能合理**: Expression工具执行很快（毫秒级），没必要云执行
4. **资源高效**: 避免为简单任务启动云容器的开销

### 实现步骤

#### Step 1: 创建工具ID列表

```bash
# 找出所有expression类型的工具
grep -r 'tool_type="expression"' tools/ | grep -o 'id="[^"]*"' | cut -d'"' -f2 > expression_tools.txt
```

#### Step 2: 更新job_conf_cloud.yml

```yaml
tools:
  # Expression工具在本地执行
  - id: pick_value
    environment: local
  - id: compose_text_param
    environment: local
  - id: param_value_from_file
    environment: local
  - id: filter_failed_datasets
    environment: local

  # 其他工具默认云执行
  - id: default
    environment: cloud_small
```

#### Step 3: 确保本地runner配置正确

```yaml
execution:
  environments:
    local:
      runner: local
      workers: 4
    cloud_small:
      runner: galaxy_cloud_executor_plugin
      # ...
```

#### Step 4: 重启Galaxy

```bash
sh run.sh --daemon
```

---

## 8. 测试计划

### 测试1: 简单Expression Tool

```bash
# 使用pick_value工具
# 输入: 参数值 = 0.05, 默认值 = 0.1
# 预期: 输出 = 0.05
```

### 测试2: 你的RNA-Seq Workflow

运行完整workflow，检查:
- Step 8 (pick_value) - p-value阈值
- Step 9 (pick_value) - log2 FC阈值
- Step 11, 12 (compose_text_param)
- Step 16 (param_value_from_file)

### 测试3: 混合执行验证

确认:
- Expression工具在本地执行（查看job日志）
- 其他工具在AWS Batch执行
- 数据正确传递

---

## 9. FAQ

### Q: Expression工具在本地执行会拖慢workflow吗？

**A**: 不会。Expression工具执行非常快（<1秒），反而比启动AWS Batch容器快得多。

### Q: 如果Galaxy服务器宕机怎么办？

**A**: 云上的job会继续执行，但新的expression工具job无法开始。重启Galaxy后会恢复。

### Q: 能否只让部分expression工具在本地执行？

**A**: 可以。在job_conf.yml中为每个工具ID单独配置environment。

### Q: 这个方案通用吗？

**A**: 是的！这是Galaxy标准的工具路由机制，所有工具类型都支持。

---

## 10. 总结

### 问题根源

Expression工具是特殊的本地工具，需要：
1. Galaxy Python库 (`galaxy_ext`, `cwl-utils`)
2. 在job准备时创建临时文件
3. 访问这些临时文件执行

云执行器无法满足这些需求。

### 解决方案

让Expression工具在本地执行，其他工具在云上执行。这是**最简单、最可靠、最符合设计的方案**。

### 下一步

1. 更新`job_conf_cloud.yml`配置工具路由
2. 重启Galaxy
3. 测试workflow

---

**你想要我帮你实现方案A（本地执行），还是方案B（云执行）？**

我强烈推荐方案A。
