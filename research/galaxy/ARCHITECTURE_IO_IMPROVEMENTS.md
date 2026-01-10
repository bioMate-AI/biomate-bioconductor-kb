# Galaxy Cloud Executor - I/O 传递架构改进建议

## 当前架构分析

### 现状：三层收集策略（过度防御）

```bash
# Layer 1: 检查 Galaxy 期望路径
if [ -f "/Users/.../dataset_xxx.dat" ]; then cp ...; fi

# Layer 2: 检查重写路径
if [ -f "/tmp/outputs/dataset_xxx.dat" ]; then cp ...; fi

# Layer 3: 收集工作目录所有文件（危险！）
for file in *; do
    cp "$file" "${OUTPUT_DIR}/"
done

# Layer 4: 收集 /tmp/outputs/
cp -r /tmp/outputs/* "${OUTPUT_DIR}/"
```

**问题**:
1. **过度收集**: Layer 3 会收集所有文件，包括临时文件、日志、中间结果
2. **重复收集**: Layer 2 和 Layer 4 收集同样的 `/tmp/outputs/` 文件
3. **性能浪费**: 大量不必要的文件传输
4. **难以调试**: 不知道哪些文件是真正需要的

---

## 改进方案 1: 声明式输出定义（推荐）

### 灵感来源：Nextflow + Cromwell

让 Galaxy 工具明确声明期望的输出模式，而不是盲目收集所有文件。

### 实现方案

#### Step 1: 从 Galaxy Tool XML 提取输出模式

Galaxy 工具已经在 XML 中声明了输出：

```xml
<!-- FastQC 工具 XML -->
<outputs>
    <data name="html_file" format="html" from_work_dir="output.html"/>
    <data name="text_file" format="txt" from_work_dir="output.txt"/>
</outputs>
```

**关键属性**:
- `from_work_dir`: 告诉 Galaxy 从哪里找输出文件
- 这正是我们需要的信息！

#### Step 2: 在 Job Runner 中解析输出声明

```python
def _get_tool_output_patterns(self, job) -> List[str]:
    """
    从工具 XML 提取输出文件模式

    Returns:
        输出文件模式列表，例如:
        - "output.html"
        - "output.txt"
        - "fastqc_results/*.html"
        - "*_fastqc.zip"
    """
    output_patterns = []

    if not self.galaxy_app:
        return output_patterns

    try:
        tool = self.galaxy_app.toolbox.get_tool(job.tool_id)
        if not tool or not hasattr(tool, 'outputs'):
            return output_patterns

        for output in tool.outputs.values():
            # 检查 from_work_dir 属性
            if hasattr(output, 'from_work_dir') and output.from_work_dir:
                output_patterns.append(output.from_work_dir)

            # 检查 discover_datasets（动态输出）
            elif hasattr(output, 'discover_datasets'):
                # 例如: pattern="__name_and_ext__"
                # 这种情况需要更复杂的处理
                output_patterns.append("*")  # 通配符

        return output_patterns

    except Exception as e:
        self.logger.warning(f"Could not extract output patterns: {e}")
        return []
```

#### Step 3: 生成精确的收集脚本

```python
def _generate_output_collection_script(self, job) -> str:
    """
    生成基于声明的输出收集脚本
    """
    script = "echo 'Collecting outputs based on tool declaration...'\n"

    # 获取工具声明的输出模式
    output_patterns = self._get_tool_output_patterns(job)

    if output_patterns:
        # 精确收集：只收集声明的输出
        script += "# Collecting declared outputs\n"
        for pattern in output_patterns:
            script += f'''
# Pattern: {pattern}
for file in {pattern}; do
    if [ -e "$file" ]; then
        echo "Collecting output: $file"
        cp -r "$file" "${{OUTPUT_DIR}}/"
    fi
done
'''
    else:
        # 回退：使用智能收集（排除已知临时文件）
        script += "# Tool has no declared outputs, using smart collection\n"
        script += self._generate_smart_collection_script()

    # 额外检查 /tmp/outputs/（路径重写目标）
    script += '''
# Collect from rewritten paths (/tmp/outputs/)
if [ -d "/tmp/outputs" ]; then
    echo "Collecting from /tmp/outputs/"
    cp -r /tmp/outputs/* "${OUTPUT_DIR}/" 2>/dev/null || true
fi
'''

    return script

def _generate_smart_collection_script(self) -> str:
    """
    智能收集：排除已知的临时文件和目录
    """
    return '''
# Smart collection: exclude known temporary files
EXCLUDE_PATTERNS="*.log *.tmp .command.* *.pyc __pycache__ .git"

for file in *; do
    # 跳过脚本本身
    if [ "$file" = "job_script.sh" ]; then
        continue
    fi

    # 检查是否在排除列表中
    excluded=0
    for pattern in $EXCLUDE_PATTERNS; do
        case "$file" in
            $pattern) excluded=1; break ;;
        esac
    done

    if [ $excluded -eq 0 ] && [ -e "$file" ]; then
        echo "Collecting: $file"
        cp -r "$file" "${OUTPUT_DIR}/"
    fi
done
'''
```

### 效果对比

#### Before (当前实现)

```bash
# 收集所有文件（包括垃圾）
Collecting: output.html           ✅ 需要
Collecting: output.txt            ✅ 需要
Collecting: .command.log          ❌ 不需要
Collecting: .command.err          ❌ 不需要
Collecting: temp_12345.tmp        ❌ 不需要
Collecting: intermediate.dat      ❌ 不需要（中间结果）
Collecting: tool.log              ❌ 不需要

# 结果：7 个文件，只有 2 个有用（28% 效率）
```

#### After (声明式收集)

```bash
# 只收集声明的输出
Pattern: output.html
Collecting output: output.html    ✅ 需要

Pattern: output.txt
Collecting output: output.txt     ✅ 需要

# 结果：2 个文件，都有用（100% 效率）
```

---

## 改进方案 2: 标准化输出目录（简单但有效）

### 核心思想

强制所有工具输出到统一的输出目录，避免路径重写的复杂性。

### 实现

```python
def _rewrite_command_line_paths(self, command_line: str, job, job_id: str) -> str:
    """
    改进版：使用一致的输出目录
    """
    # 定义标准输出目录
    STANDARD_OUTPUT_DIR = "/galaxy/outputs"

    # 所有输出路径统一重写到这个目录
    for output_assoc in job.output_datasets:
        if output_assoc.dataset and output_assoc.dataset.dataset:
            original_path = output_assoc.dataset.dataset.get_file_name()
            filename = Path(original_path).name

            # 统一映射
            path_mapping[original_path] = f"{STANDARD_OUTPUT_DIR}/{filename}"
            path_mapping[f"{original_path}_files"] = f"{STANDARD_OUTPUT_DIR}/{filename}_files"

    # ... 替换逻辑 ...
```

### 脚本生成

```bash
# 创建标准输出目录
mkdir -p /galaxy/outputs

# 工具命令（已重写路径）
fastqc --outdir /galaxy/outputs/dataset_xxx_files input.fastq

# 收集输出（简单！）
cp -r /galaxy/outputs/* "${OUTPUT_DIR}/"
```

**优点**:
- 极简：一行命令收集所有输出
- 清晰：所有输出都在一个已知位置
- 可靠：不会遗漏文件

**缺点**:
- 需要确保工具支持自定义输出目录
- 某些工具可能硬编码输出路径

---

## 改进方案 3: 输出 Manifest（最彻底）

### 核心思想

让工具执行完成后生成一个 manifest 文件，列出所有实际生成的输出。

### 实现

```bash
# 在工具执行前记录时间戳
date +%s > /tmp/start_time

# 执行工具
{command_line}

# 工具执行后，查找所有新创建的文件
echo "Generating output manifest..."
find /tmp/work /tmp/outputs -type f -newer /tmp/start_time > /tmp/output_manifest.txt

# 根据 manifest 收集输出
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # 保持目录结构
        rel_path="${file#/tmp/work/}"
        rel_path="${rel_path#/tmp/outputs/}"
        mkdir -p "${OUTPUT_DIR}/$(dirname "$rel_path")"
        cp "$file" "${OUTPUT_DIR}/$rel_path"
    fi
done < /tmp/output_manifest.txt
```

**优点**:
- 精确：只收集工具执行后新创建的文件
- 自动：不需要预先声明
- 可追溯：manifest 可用于调试

**缺点**:
- 可能收集中间文件
- 时间戳比较不够精确

---

## 推荐的混合方案

结合以上三种方案的优点：

```python
def _collect_outputs(self, job, job_id: str) -> str:
    """
    智能输出收集策略

    优先级：
    1. 工具 XML 声明的输出（最精确）
    2. /tmp/outputs/ 标准目录（路径重写目标）
    3. 智能收集工作目录（排除临时文件）
    """
    script = ""

    # 策略 1: 声明式收集
    output_patterns = self._get_tool_output_patterns(job)
    if output_patterns:
        script += "# Strategy 1: Collecting declared outputs\n"
        for pattern in output_patterns:
            script += f'''
for file in {pattern}; do
    [ -e "$file" ] && cp -r "$file" "${{OUTPUT_DIR}}/" && echo "[OK] Collected: $file"
done
'''

    # 策略 2: 标准输出目录
    script += '''
# Strategy 2: Collecting from standard output directory
if [ -d "/tmp/outputs" ]; then
    echo "Collecting from /tmp/outputs/"
    for file in /tmp/outputs/*; do
        [ -e "$file" ] && cp -r "$file" "${OUTPUT_DIR}/" && echo "[OK] Collected: $(basename $file)"
    done
fi
'''

    # 策略 3: 智能兜底（仅在前两者都失败时）
    script += '''
# Strategy 3: Smart fallback collection (if needed)
if [ -z "$(ls -A ${OUTPUT_DIR})" ]; then
    echo "[WARN] No outputs collected yet, using smart collection"
    for file in *; do
        # 排除已知临时文件
        case "$file" in
            *.log|*.tmp|.command.*|job_script.sh) continue ;;
            *) [ -e "$file" ] && cp -r "$file" "${OUTPUT_DIR}/" && echo "[OK] Collected: $file" ;;
        esac
    done
fi
'''

    return script
```

---

## 性能优化建议

### 1. 大文件优化

对于大文件（> 1GB），使用流式上传：

```bash
# 当前方式：先复制到 OUTPUT_DIR，再统一上传
cp large_file.bam "${OUTPUT_DIR}/"
# 然后 fetch_and_run.sh 上传所有文件

# 优化方式：直接流式上传到 S3
if [ -f large_file.bam ]; then
    echo "Streaming large file to S3..."
    aws s3 cp large_file.bam "s3://${S3_BUCKET}/jobs/${JOB_ID}/outputs/" --storage-class INTELLIGENT_TIERING
fi
```

### 2. 并行上传

```bash
# 并行上传多个小文件
for file in "${OUTPUT_DIR}"/*; do
    aws s3 cp "$file" "s3://${S3_BUCKET}/jobs/${JOB_ID}/outputs/$(basename $file)" &
done
wait  # 等待所有上传完成
```

### 3. 增量上传（断点续传）

```bash
# 对于超大文件，使用 multipart upload
aws s3 cp huge_file.bam "s3://bucket/path/" \
    --storage-class INTELLIGENT_TIERING \
    --metadata "job_id=${JOB_ID},tool_id=${TOOL_ID}"
```

---

## Workflow 级别优化

### 问题：任务间数据传递效率低

当前流程（低效）:
```
Tool A (容器) → S3 → Galaxy 本地 → S3 → Tool B (容器)
                 ↑                  ↑
              不必要的往返！
```

### 优化方案：S3 直接传递

```
Tool A (容器) → S3 → Tool B (容器)
                 ↑
            Galaxy 只记录元数据
```

实现思路：

```python
class WorkflowOptimizer:
    """
    Workflow 级别的数据传递优化
    """

    def optimize_data_flow(self, workflow):
        """
        分析 workflow，识别可以直接传递的数据
        """
        for step in workflow.steps:
            for input_conn in step.input_connections:
                source_step = input_conn.output_step

                # 检查 source 和当前 step 是否都在云端执行
                if self._both_cloud_executed(source_step, step):
                    # 优化：直接使用 S3 路径
                    self._enable_direct_s3_transfer(source_step, step, input_conn)

    def _enable_direct_s3_transfer(self, source, target, connection):
        """
        配置直接 S3 传递
        """
        # Source 输出直接到 S3
        source_output_s3 = f"s3://bucket/jobs/{source.job_id}/outputs/{connection.output_name}"

        # Target 直接从 S3 读取（无需 Galaxy 本地中转）
        target_input_s3 = source_output_s3

        # 在 job script 中直接引用 S3 URI
        # 工具容器需要支持 S3，或者 fetch_and_run 代为下载
```

---

## 总结：通用且高效的 I/O 传递原则

### 1. **声明优于推断**
   - 工具应明确声明输出（XML `<outputs>`）
   - 收集脚本应优先使用声明
   - 避免盲目收集所有文件

### 2. **标准化优于特殊化**
   - 使用统一的输出目录（`/tmp/outputs/`）
   - 所有工具遵循相同的路径约定
   - 简化收集和调试

### 3. **分层回退策略**
   ```
   Layer 1: 工具声明的输出  (最精确)
     ↓ (失败)
   Layer 2: 标准输出目录    (通用)
     ↓ (失败)
   Layer 3: 智能收集        (兜底)
   ```

### 4. **元数据驱动**
   - Galaxy 只管理元数据（文件位置、类型、关系）
   - 实际数据在 S3（或其他对象存储）
   - 容器直接访问对象存储

### 5. **最小化数据移动**
   - Workflow 内部任务直接通过 S3 传递
   - 只在必要时下载到本地
   - 优先使用引用而非复制

---

## 立即可行的改进（按优先级）

### 优先级 1: 修复过度收集（本周）
- [x] 实现智能收集（排除 `*.log`, `*.tmp` 等）
- [ ] 合并重复的收集逻辑（Layer 2 和 Layer 4）
- [ ] 添加输出大小检查（警告超大文件）

### 优先级 2: 声明式输出（下周）
- [ ] 实现 `_get_tool_output_patterns()`
- [ ] 更新 `_generate_output_collection_script()`
- [ ] 测试 FastQC, Trimmomatic 等工具

### 优先级 3: Workflow 优化（下月）
- [ ] 实现任务间 S3 直接传递
- [ ] 添加大文件流式上传
- [ ] 并行上传优化

### 优先级 4: 工具容器 S3 集成（长期）
- [ ] 为常用工具添加 S3 输入支持
- [ ] 构建支持 S3 的工具容器镜像
- [ ] 更新工具 XML 声明

---

## 参考资源

1. **Nextflow 文档**: https://www.nextflow.io/docs/latest/process.html#outputs
2. **Cromwell WDL**: https://github.com/openwdl/wdl/blob/main/versions/1.0/SPEC.md#outputs
3. **AWS Batch Best Practices**: https://docs.aws.amazon.com/batch/latest/userguide/best-practices.html
4. **Galaxy Tool XML Reference**: https://docs.galaxyproject.org/en/latest/dev/schema.html

---

**核心理念**: 让数据流动更加明确、可预测、高效，同时保持对现有工具的兼容性。
