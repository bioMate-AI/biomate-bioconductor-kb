# 标准云端执行 - 快速开始

## 🎯 核心价值 (Core Value)

**任何 Galaxy workflow 自动在 AWS Batch 上运行，无需手动调试！**

## ✅ 已完成 (Completed)

1. ✅ 自动脚本重写系统
2. ✅ BusyBox 兼容性修复
3. ✅ Trimmomatic JAR 自动查找
4. ✅ 健壮的错误处理
5. ✅ 工作目录自动设置
6. ✅ Galaxy 服务已启动

## 🚀 立即使用 (Immediate Usage)

### 1. 打开 Galaxy
```
浏览器访问: http://localhost:8080
```

### 2. 运行任意 Workflow
- 选择任意已有的 workflow (FastQC, Trimmomatic, 等)
- 点击运行
- **系统会自动应用所有修复**
- 无需任何手动操作！

### 3. 监控执行
```bash
# 查看 Galaxy 日志 (会看到脚本重写消息)
tail -f logs/galaxy_startup_*.log | grep "Rewriting script"

# 查看 AWS Batch 任务
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 查看任务详细日志
aws logs tail /aws/batch/job --follow
```

## 📊 期望看到的日志 (Expected Logs)

### Galaxy 日志
```
[job_123] Rewriting script for cloud execution (making it container-compatible)
[job_123] Fixed 2 occurrences of 'readlink -e' → 'readlink -f' for BusyBox compatibility
[job_123] Adding Trimmomatic JAR path fallback logic
[job_123] Script rewriting completed - now compatible with any cloud container
```

### AWS 日志
```
Downloading script from s3://.../job_script.sh
Found Trimmomatic JAR at: /usr/local/share/trimmomatic-0.38
Starting Galaxy tool execution...
Executing tool command...
Tool execution completed successfully
```

## 🔧 自动修复列表 (Automatic Fixes)

| 修复 | 解决的问题 | 影响的工具 |
|------|----------|-----------|
| **Fix 1** | BusyBox readlink 不支持 -e | 所有使用 readlink 的工具 |
| **Fix 2** | JAR 文件路径不同 | Trimmomatic 等 Java 工具 |
| **Fix 3** | 目录创建失败 | 所有创建输出的工具 |
| **Fix 4** | 缺少工作目录 | 所有需要临时文件的工具 |
| **Fix 5** | 错误难以定位 | 所有工具（调试用） |
| **Fix 6** | 输出目录不存在 | 所有生成输出的工具 |

## 📚 关键文件 (Key Files)

### 代码
- **主要实现**: [lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py) (Line 348-508)
- **核心函数**: `_rewrite_script_for_cloud()`

### 配置
- **任务配置**: [config/job_conf_cloud.yml](config/job_conf_cloud.yml)
- **容器映射**: [config/tool_containers.yaml](config/tool_containers.yaml)
- **AWS 配置**: [config/aws_cloud_config.yaml](config/aws_cloud_config.yaml)

### 文档
- **完整文档**: [STANDARD_CLOUD_EXECUTION.md](STANDARD_CLOUD_EXECUTION.md)
- **实施总结**: [SOLUTION_SUMMARY.md](SOLUTION_SUMMARY.md)
- **本快速指南**: [QUICK_START.md](QUICK_START.md)

## 🔍 验证重写是否生效 (Verify Rewriting Works)

### 下载重写后的脚本
```bash
# 从 AWS Batch 任务中获取 job ID (例如: 377)
JOB_ID=377

# 下载重写后的脚本
aws s3 cp s3://galaxy-cloud-data-1760241377/jobs/$JOB_ID/job_script.sh rewritten_script.sh

# 检查修复是否应用
cat rewritten_script.sh
```

### 应该看到的内容
```bash
# 1. readlink -f (不是 -e)
readlink -f $(which trimmomatic)

# 2. Trimmomatic JAR 查找循环
for jar_path in \
    /usr/local/share/trimmomatic-*/trimmomatic-*.jar \
    /usr/share/java/trimmomatic-*.jar \
    ...

# 3. 错误处理器
handle_error() {
    echo "ERROR: Script failed at line $1" >&2
    ...
}
trap 'handle_error $LINENO' ERR

# 4. 工作目录设置
if [ -n "$GALAXY_WORK_DIR" ]; then
    cd "$GALAXY_WORK_DIR" || cd /tmp/work
```

## 🐛 故障排查 (Troubleshooting)

### 问题: 日志中没有看到 "Rewriting script"
**检查**:
```bash
# 确认 Galaxy 使用了正确的配置
grep "job_config_file" config/galaxy.yml

# 应该是: config/job_conf_cloud.yml
```

### 问题: AWS Batch 任务仍然失败
**检查**:
1. 下载重写后的脚本查看是否应用了修复
2. 查看 AWS 日志找出具体错误
3. 如果是新的兼容性问题，在 `_rewrite_script_for_cloud` 中添加新的 fix

### 问题: 容器找不到
**检查**:
```bash
# 查看容器映射配置
cat config/tool_containers.yaml

# 检查是否需要添加新的映射
```

## 💡 最佳实践 (Best Practices)

### 1. 定期监控日志
```bash
# 创建日志监控别名
alias galaxy-logs="tail -f logs/galaxy_startup_*.log | grep -E '(Rewriting|Fixed|Adding|completed|ERROR)'"

# 使用
galaxy-logs
```

### 2. 测试新工具
当添加新工具时:
1. 先运行一次
2. 检查是否成功
3. 如果失败，查看日志和重写后的脚本
4. 添加针对性修复（如果需要）

### 3. 保存重写后的脚本用于调试
```bash
# 为每个新工具类型保存一个重写示例
mkdir -p debug/rewritten_scripts
aws s3 cp s3://.../jobs/$JOB_ID/job_script.sh \
    debug/rewritten_scripts/${TOOL_NAME}_rewritten.sh
```

## 🎓 工作原理 (How It Works)

```
┌─────────────────────────────────────────┐
│ 1. 用户在 UI 中点击运行 workflow        │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│ 2. Galaxy 生成原始脚本                  │
│    (包含本地路径、GNU 命令)              │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│ 3. 自动重写脚本 ⭐ MAGIC HAPPENS HERE!  │
│    ✓ readlink -e → -f                  │
│    ✓ JAR 查找逻辑                       │
│    ✓ 错误处理                           │
│    ✓ 工作目录                           │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│ 4. 上传重写后的脚本到 S3                │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│ 5. AWS Batch 执行                       │
│    ├─ Fetch-and-Run 容器启动            │
│    ├─ 下载脚本和输入文件                 │
│    ├─ 启动工具容器                       │
│    └─ 执行重写后的脚本 ✅               │
└─────────────────────────────────────────┘
```

## 🎉 成功！(Success!)

现在你有了一个**标准化、可复用、完全自动化**的云端执行方案！

**无需逐个 workflow 调试，所有工具自动适配云端容器。**

---

## 📞 需要帮助？(Need Help?)

### 查看详细文档
- [STANDARD_CLOUD_EXECUTION.md](STANDARD_CLOUD_EXECUTION.md) - 完整技术文档
- [SOLUTION_SUMMARY.md](SOLUTION_SUMMARY.md) - 实施总结

### 检查代码
- [galaxy_job_runner.py:348-508](lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py) - 脚本重写函数

### 添加新的修复
如果遇到新的兼容性问题，在 `_rewrite_script_for_cloud` 中添加新的 Fix 7、Fix 8...

---

**Happy Cloud Computing! 🚀☁️**
