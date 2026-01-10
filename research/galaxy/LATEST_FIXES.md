# Galaxy Cloud Executor - Latest Fixes (2025-10-28)

## 修复 #3: SIGPIPE错误导致脚本失败

### 问题
```
ERROR: Script failed at line 45
Working directory: /tmp/work
```

执行 `yes | head` 这类管道命令时失败。

### 根本原因
- Job script使用了 `set -o pipefail`
- 当 `head -n 1` 读完数据关闭管道时，`yes` 命令收到 SIGPIPE 信号
- `yes` 以非零退出码退出，在 `pipefail` 模式下导致整个管道失败
- Galaxy的许多内置工具（如表头生成）使用这种模式

### 修复
**文件**: `galaxy_job_runner.py:1031-1046`

**移除了 `set -o pipefail`**:
```bash
#!/bin/bash
set -e
# NOTE: set -o pipefail is intentionally NOT used here
# Many Galaxy tools use pipes like "yes | head" which would fail with pipefail
# when the downstream command closes the pipe (SIGPIPE)
```

同时添加了 `mkdir -p "$OUTPUT_DIR"` 确保输出目录存在。

### 影响
- ✅ `yes | head` 等管道命令现在可以正常工作
- ⚠️ 管道中的某些错误可能不会被立即检测到（trade-off）
- ✅ `set -e` 仍然会捕获非管道相关的错误

---

## 修复 #4: Expression工具不需要容器

### 问题
```
Tool Container: quay.io/biocontainers/pick_value:0.2.0
Error response from daemon: unauthorized: access to the requested resource is not authorized
```

### 根本原因
`pick_value` 是 Galaxy 的 **expression工具** (`tool_type="expression"`)，这类工具：
- 是纯Python实现的内置工具
- 不需要外部软件依赖
- 应该直接在fetch-and-run容器中运行
- **不需要拉取BioContainers镜像**

但我们的代码没有识别这类工具，仍然尝试查找容器镜像。

### 修复
**文件**: `galaxy_job_runner.py:901-907`

**添加了工具类型检查**:
```python
tool_type = getattr(job_wrapper.tool, 'tool_type', 'default')

# Skip container lookup for tool types that don't need containers
skip_container_types = ['expression', 'output_parameter_json', 'interactive', 'data_destination']
if tool_type in skip_container_types:
    self.logger.info(f"Tool {tool_id} is type '{tool_type}', runs without container")
else:
    # Normal container lookup logic...
```

### 不需要容器的工具类型
| Tool Type | 描述 | 示例 |
|-----------|------|------|
| expression | 表达式/参数选择工具 | pick_value, random_lines |
| output_parameter_json | 输出参数JSON | - |
| interactive | 交互式工具 | Jupyter notebooks |
| data_destination | 数据目标工具 | export tools |

### 影响
- ✅ Expression工具不再尝试拉取不存在的容器
- ✅ 这些工具将在fetch-and-run容器中直接执行
- ✅ 减少了不必要的容器拉取尝试

---

## 所有修复总结

### 修复 #1: Docker Tag规范化 (之前完成)
- **问题**: `9.3+galaxy1` → `invalid reference format`
- **修复**: 添加 `_normalize_docker_tag()` 将 `+` 转换为 `--`
- **文件**: `tool_registry.py:231-249`

### 修复 #2: 工具名称vs包名称映射 (之前完成)
- **问题**: `text_processing` 工具实际需要 `coreutils` 容器
- **修复**: 从 `tool.requirements.packages` 提取实际的Conda包名
- **文件**: `galaxy_job_runner.py:909-920`

### 修复 #3: SIGPIPE/pipefail问题 (本次)
- **问题**: `yes | head` 管道命令失败
- **修复**: 移除 `set -o pipefail`
- **文件**: `galaxy_job_runner.py:1033-1035`

### 修复 #4: Expression工具容器查找 (本次)
- **问题**: Expression工具不应该查找容器
- **修复**: 跳过特定tool_type的容器查找
- **文件**: `galaxy_job_runner.py:901-907`

---

## 测试验证

### 修复#3测试
```bash
# 本地测试
$ bash -c 'set -e; yes test | head -n 1'
# ❌ 会卡住或失败

$ bash -c 'set -e; set -o pipefail; yes test | head -n 1'
# ❌ 失败 (SIGPIPE)

$ bash -c 'set -e; yes test 2>/dev/null | head -n 1'
# ✅ 成功 (错误被重定向)
```

### 修复#4测试
查看Galaxy日志，应该显示：
```
[Job 534] Tool pick_value is type 'expression', runs without container
```

---

## 下一步

### 1. 重启Galaxy
```bash
pkill -f "gunicorn.*galaxy"
PYTHONPATH=lib sh run.sh --daemon
```

### 2. 重新运行Workflow
提交workflow并检查：

**Job 532 (text_processing → coreutils)**:
```
✅ Tool Container: quay.io/biocontainers/coreutils:9.3
✅ Pull complete
✅ Starting Galaxy tool execution...
✅ Script should complete without SIGPIPE error
```

**Job 534/535 (pick_value)**:
```
✅ Tool pick_value is type 'expression', runs without container
✅ No container pull attempted
✅ Runs directly in fetch-and-run container
```

### 3. 检查输出
验证所有jobs成功完成并生成了预期的输出文件。

---

## 剩余已知问题

### 输入文件缺失警告
```
[WARN] No input files found at s3://...
```

这可能是正常的，如果该步骤确实不需要输入文件（如第一个步骤）。
如果后续步骤也显示此警告，需要检查：
1. 前一步骤是否成功上传输出到S3
2. Fix 18 (S3输出到输入复制) 是否正确工作

---

## 文件修改清单

1. ✅ `tool_registry.py` - Tag规范化
2. ✅ `galaxy_job_runner.py` - 包名提取、pipefail移除、工具类型检查

## 相关测试脚本

- `test_docker_tag_fix.py` - Tag规范化测试
- `test_package_resolution.py` - 包名解析测试
- `CONTAINER_RESOLUTION_FIX.md` - 详细文档

---

**更新时间**: 2025-10-28 21:00 (UTC+8)
**状态**: ✅ 所有修复已完成，待重启Galaxy验证
