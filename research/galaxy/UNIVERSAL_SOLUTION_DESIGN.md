# Galaxy Cloud Executor - 通用方案设计

## 问题：当前方案不够通用

### 当前方案的局限性

```python
# ❌ 不通用的做法
if '_evaluate_expression_.py' in command_line:
    rewritten = re.sub(r'cd\s+\.\./?\s*;?\s*', '', rewritten)

if 'some_other_tool' in command_line:
    # 又要加新的if...

if 'another_special_case' in command_line:
    # 没完没了...
```

**问题**：
1. 每个特殊工具都要加判断
2. 无法预见所有可能的工具行为
3. 维护成本高，容易出错
4. 不是"通用"方案，是"枚举所有case"

---

## 通用方案：环境模拟 (Environment Emulation)

### 核心原则

**让容器环境看起来和Galaxy本地环境一样！**

不改变Galaxy生成的命令，改变执行环境：
- 本地路径在容器中也存在（通过symlink）
- 工作目录结构完全一致
- 环境变量完全一致

### 方案对比

#### ❌ 当前方案：命令重写 (Command Rewriting)
```
Galaxy生成命令 → 分析命令 → 识别工具类型 → 针对性重写 → 执行
                    ↑
            需要了解每个工具的特殊行为
```

#### ✅ 通用方案：环境模拟 (Environment Emulation)
```
Galaxy生成命令 → 创建一致的环境 → 原样执行
                    ↑
            通过环境让任何命令都能工作
```

---

## 设计：两种可行的通用方案

### 方案A: 完整路径映射 (Full Path Mapping)

**思路**：在容器中重建Galaxy的完整目录结构

#### 实现

```bash
#!/bin/bash
# fetch_and_run.sh

# 1. 创建Galaxy本地路径的镜像结构
# 例如本地是 /Users/renyuankai/work/biometa/galaxy/database/jobs/000/538/
GALAXY_LOCAL_JOBS_DIR="/Users/renyuankai/work/biometa/galaxy/database/jobs/000/538"

# 2. 在容器中创建相同的目录结构
mkdir -p "$GALAXY_LOCAL_JOBS_DIR"

# 3. 将实际工作目录内容链接到这个位置
# 实际文件在: /host-tmp/galaxy_job_538/
# 映射到:     /Users/renyuankai/.../538/
mount --bind /host-tmp/galaxy_job_538 "$GALAXY_LOCAL_JOBS_DIR"
# 或者用符号链接：
ln -s /host-tmp/galaxy_job_538/* "$GALAXY_LOCAL_JOBS_DIR/"

# 4. 切换到这个目录
cd "$GALAXY_LOCAL_JOBS_DIR"

# 5. 执行Galaxy原始命令（完全不修改）
eval "$ORIGINAL_COMMAND"
```

**优点**：
- ✅ Galaxy命令完全不需要修改
- ✅ 所有路径都"自然"工作
- ✅ 支持任意 `cd` 命令
- ✅ 支持相对路径、绝对路径

**缺点**：
- ⚠️ 需要在容器中创建可能很深的目录结构
- ⚠️ 如果本地路径包含用户名等，可能有权限问题
- ⚠️ 不同用户的路径不同，需要动态获取

### 方案B: 智能工作目录包装 (Smart Working Directory Wrapper)

**思路**：理解Galaxy的工作目录约定，创建兼容层

#### Galaxy的工作目录约定

Galaxy job的目录结构：
```
/galaxy/database/jobs/000/538/           # job working directory
├── working/                             # 实际执行目录 (GALAXY_WORK_DIR)
│   ├── _evaluate_expression_.py
│   └── expression_inputs.json
├── inputs/                              # 输入软链接
├── outputs/                             # 输出目录
├── configs/                             # 配置文件
└── metadata/                            # 元数据
```

Galaxy命令可能的形式：
1. `cd /full/path/to/working; tool`
2. `cd ../working; tool`  (从上一级目录)
3. `cd ../; python script.py`  (从working回到job目录)
4. 直接执行（假设在working目录）

#### 实现

```bash
#!/bin/bash
# fetch_and_run.sh

# 容器中的目录结构：
CONTAINER_JOB_DIR="/galaxy_job"          # 模拟job目录
CONTAINER_WORK_DIR="$CONTAINER_JOB_DIR/working"

# 创建标准结构
mkdir -p "$CONTAINER_JOB_DIR"/{working,inputs,outputs,configs,metadata}

# 从S3下载的文件分类放置：
# - inputs/* → $CONTAINER_JOB_DIR/inputs/
# - working/* → $CONTAINER_JOB_DIR/working/  (包括expression脚本)
# - outputs/ → $CONTAINER_JOB_DIR/outputs/

# 设置环境变量
export GALAXY_WORK_DIR="$CONTAINER_WORK_DIR"
export GALAXY_JOB_DIR="$CONTAINER_JOB_DIR"

# 默认在working目录执行
cd "$CONTAINER_WORK_DIR"

# 命令重写变得简单：只需要替换绝对路径前缀
# /Users/.../database/jobs/000/538/ → /galaxy_job/
REWRITTEN_COMMAND="${COMMAND//\/Users\/.*\/database\/jobs\/[0-9]+\/${JOB_ID}/\/galaxy_job}"

# 执行
eval "$REWRITTEN_COMMAND"
```

**优点**：
- ✅ 符合Galaxy的目录约定
- ✅ 大部分命令自动工作
- ✅ 只需要简单的路径前缀替换
- ✅ 容器路径简单，易于调试

**缺点**：
- ⚠️ 仍需要一定的路径重写
- ⚠️ 需要准确识别Galaxy job目录的路径模式

---

## 推荐方案：混合方案 (Hybrid Approach)

结合两种方案的优点：

### 1. 标准化容器结构

```
容器内固定结构：
/galaxy_execution/
├── job/                    # 模拟Galaxy job目录
│   ├── working/           # 工作目录（脚本在这里）
│   ├── inputs/            # 输入文件（symlink或实际文件）
│   ├── outputs/           # 输出文件
│   └── configs/           # 配置文件
└── original_paths/        # 原始路径的symlink（如果需要）
```

### 2. 通用路径重写规则

不针对特定工具，而是针对路径模式：

```python
def rewrite_command_universal(command: str, job_wrapper) -> str:
    """
    通用命令重写：基于路径模式，不依赖工具类型
    """
    # 1. 获取Galaxy job的工作目录
    local_job_dir = job_wrapper.working_directory
    # 例如: /Users/xxx/galaxy/database/jobs/000/538

    # 2. 提取路径模式（正则匹配）
    job_id_pattern = re.escape(str(job_wrapper.job_id))
    local_dir_pattern = re.escape(os.path.dirname(local_job_dir))

    # 3. 替换所有匹配的路径
    rewritten = command

    # 替换绝对路径
    rewritten = re.sub(
        f'{local_dir_pattern}/[^/]+/{job_id_pattern}',
        '/galaxy_execution/job',
        rewritten
    )

    # 4. 处理相对路径中的cd命令
    # 不是删除，而是转换为等价的绝对路径操作
    rewritten = normalize_cd_commands(rewritten)

    return rewritten

def normalize_cd_commands(command: str) -> str:
    """
    规范化cd命令：转换相对路径为绝对路径操作
    """
    # cd ../ → cd /galaxy_execution/job (从working返回job目录)
    # cd ../../ → cd /galaxy_execution (返回上两级)
    # cd /absolute/path → 保持不变（已被上面的规则处理）

    # 这里的关键是：我们知道执行起点是 /galaxy_execution/job/working
    # 所以可以计算相对路径的目标
    pass
```

### 3. 容器初始化脚本

```bash
#!/bin/bash
# container_init.sh - 在fetch-and-run中调用

setup_galaxy_environment() {
    local JOB_ID=$1
    local S3_BUCKET=$2

    # 创建标准目录结构
    mkdir -p /galaxy_execution/job/{working,inputs,outputs,configs,metadata}

    # 下载所有文件到对应位置
    aws s3 sync "s3://$S3_BUCKET/jobs/$JOB_ID/inputs/" /galaxy_execution/job/inputs/
    aws s3 sync "s3://$S3_BUCKET/jobs/$JOB_ID/working/" /galaxy_execution/job/working/

    # 设置环境变量
    export GALAXY_WORK_DIR="/galaxy_execution/job/working"
    export GALAXY_JOB_DIR="/galaxy_execution/job"

    # 切换到工作目录（Galaxy命令的默认执行位置）
    cd /galaxy_execution/job/working
}
```

---

## 实现步骤

### 阶段1: 重构路径重写逻辑

```python
# galaxy_job_runner.py

class UniversalPathRewriter:
    """
    通用路径重写器：不依赖工具类型，只依赖路径模式
    """

    def __init__(self, job_wrapper):
        self.job_wrapper = job_wrapper
        self.local_job_dir = job_wrapper.working_directory
        self.container_job_dir = "/galaxy_execution/job"
        self.container_work_dir = f"{self.container_job_dir}/working"

    def rewrite_command(self, command: str) -> str:
        """重写命令中的所有路径引用"""
        rewritten = command

        # 1. 替换job目录的绝对路径
        rewritten = self._rewrite_absolute_paths(rewritten)

        # 2. 规范化相对路径cd命令
        rewritten = self._normalize_relative_paths(rewritten)

        # 3. 重写数据集路径
        rewritten = self._rewrite_dataset_paths(rewritten)

        return rewritten

    def _rewrite_absolute_paths(self, command: str) -> str:
        """替换所有指向job目录的绝对路径"""
        # 使用正则匹配，不依赖具体的用户路径
        pattern = re.escape(self.local_job_dir)
        return command.replace(pattern, self.container_job_dir)

    def _normalize_relative_paths(self, command: str) -> str:
        """
        规范化相对路径操作

        Galaxy默认在 working/ 目录执行
        cd ../ 意味着回到 job/ 目录
        cd ../../ 意味着回到 job/的上一级
        """
        # 不删除cd命令，而是转换为明确的路径
        rewritten = command

        # cd ../ 或 cd .. (从working回到job目录)
        rewritten = re.sub(
            r'cd\s+\.\./?\s*;',
            f'cd {self.container_job_dir};',
            rewritten
        )

        # cd ../../ (回到job的上级)
        rewritten = re.sub(
            r'cd\s+\.\./\.\./?\s*;',
            'cd /galaxy_execution;',
            rewritten
        )

        return rewritten

    def _rewrite_dataset_paths(self, command: str) -> str:
        """重写输入/输出数据集的路径"""
        # 输入保持绝对路径（通过symlink访问）
        # 输出重写到outputs目录
        for output in self.job_wrapper.get_output_fnames():
            old_path = output.get_file_name()
            new_path = f"{self.container_job_dir}/outputs/{os.path.basename(old_path)}"
            command = command.replace(old_path, new_path)

        return command
```

### 阶段2: 简化fetch-and-run

```bash
#!/bin/bash
# fetch_and_run.sh (简化版)

# 固定的容器结构
JOB_DIR="/galaxy_execution/job"
WORK_DIR="$JOB_DIR/working"

# 创建标准结构
mkdir -p "$JOB_DIR"/{working,inputs,outputs}

# 下载所有文件（不需要判断类型）
aws s3 sync "s3://$S3_BUCKET/jobs/$JOB_ID/" "$JOB_DIR/" --exclude "job_script.sh"

# 设置环境
export GALAXY_JOB_DIR="$JOB_DIR"
export GALAXY_WORK_DIR="$WORK_DIR"
export GALAXY_INPUT_DIR="$JOB_DIR/inputs"
export GALAXY_OUTPUT_DIR="$JOB_DIR/outputs"

# 默认在working目录执行
cd "$WORK_DIR"

# 执行脚本（路径已经被重写过）
bash "$JOB_DIR/job_script.sh"

# 上传输出
aws s3 sync "$JOB_DIR/outputs/" "s3://$S3_BUCKET/jobs/$JOB_ID/outputs/"
```

---

## 对比：特殊处理 vs 通用方案

### 当前方法（特殊处理）
```python
if '_evaluate_expression_.py' in command:
    # 删除 cd ../

if 'fastqc' in command:
    # 处理fastqc的输出目录

if 'trim' in command:
    # 处理trim工具的特殊需求

# ... 无穷无尽的if-else
```

### 通用方案
```python
rewriter = UniversalPathRewriter(job_wrapper)
rewritten_command = rewriter.rewrite_command(command)

# 任何工具都适用，不需要特殊判断
```

---

## 结论

### 当前方案的问题
- ❌ 针对特定工具的hack
- ❌ 需要不断添加新的特殊处理
- ❌ 难以维护和扩展
- ❌ 不是"通用"，是"枚举"

### 推荐的通用方案
- ✅ 基于路径模式，不基于工具类型
- ✅ 统一的容器目录结构
- ✅ 任何Galaxy工具都自动支持
- ✅ 易于维护和扩展

### 实施建议

1. **短期**：保持当前方案工作（已经投入的工作）
2. **中期**：重构为UniversalPathRewriter
3. **长期**：考虑更深层的抽象（Galaxy的容器运行时）

---

**关键洞察**：
> 真正的通用方案不是"知道每个工具的特殊行为"，
> 而是"创建一个任何工具都能工作的环境"。
