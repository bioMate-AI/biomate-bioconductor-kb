# 🚀 测试云执行 Workflow - 操作指南

## ✅ Galaxy 已就绪

```
✅ Galaxy运行中: http://localhost:8080
✅ Galaxy版本: 25.1.dev0
✅ 云Runner已初始化: GalaxyCloudJobRunner
✅ AWS配置:
   - Batch Queue: galaxy-cloud-queue
   - S3 Bucket: galaxy-cloud-data-1760241377
✅ 已安装工具: collection_element_identifiers (IUC)
```

---

## 📁 测试 Workflow 文件路径

### Workflow 文件：
```
/Users/renyuankai/work/biometa/galaxy/test_cloud_workflow.ga
```

### 测试数据文件：
```
/Users/renyuankai/work/biometa/galaxy/test_collection_data/sample1.txt
/Users/renyuankai/work/biometa/galaxy/test_collection_data/sample2.txt
/Users/renyuankai/work/biometa/galaxy/test_collection_data/sample3.txt
```

---

## 🎯 测试步骤（3分钟）

### 第1步：访问 Galaxy
```
打开浏览器访问: http://localhost:8080
使用管理员账户登录: 635248762@qq.com
```

### 第2步：导入 Workflow

**方式A - 通过 UI 导入（推荐）：**
```
1. 点击顶部菜单 "Workflow"
2. 点击右上角 "Import" 按钮（⬆️ 图标）
3. 选择 "Upload file from your computer"
4. 浏览并选择文件:
   /Users/renyuankai/work/biometa/galaxy/test_cloud_workflow.ga
5. 点击 "Import workflow"
6. 等待导入完成，应该看到 "Cloud Test - Extract Identifiers"
```

**方式B - 使用文件路径（更快）：**
```
在浏览器中可以直接复制粘贴这个路径：
/Users/renyuankai/work/biometa/galaxy/test_cloud_workflow.ga
```

### 第3步：上传测试数据

```
1. 在 Galaxy UI 左侧，点击 "Upload Data" 按钮（↑ 图标）
2. 点击 "Choose local files"
3. 浏览到目录并选择3个文件:
   /Users/renyuankai/work/biometa/galaxy/test_collection_data/
   - sample1.txt ✓
   - sample2.txt ✓
   - sample3.txt ✓
4. 点击 "Start" 开始上传
5. 等待上传完成（应该很快，都是小文件）
6. 点击 "Close" 关闭上传窗口
```

### 第4步：创建 Dataset Collection

```
1. 在右侧历史记录面板，应该看到3个txt文件
2. 点击历史记录面板右上角的 ☑️ 图标（批量操作模式）
3. 选中这3个 txt 文件（点击每个文件名前的复选框）
4. 点击 "For all selected..." 下拉按钮
5. 选择 "Build Dataset List"
6. 在弹出的对话框中：
   - Collection name: test_collection (或任意名称)
   - 确认3个文件都在列表中
   - 可以调整顺序（不影响结果）
7. 点击 "Create list" 按钮
8. 现在历史记录中应该出现一个 📁 collection 图标
```

### 第5步：运行 Workflow

```
1. 点击顶部菜单 "Workflow"
2. 找到 "Cloud Test - Extract Identifiers"
3. 点击右侧的 ▶️ 播放按钮（Run）
4. 在 Workflow 运行页面：
   - Step 1: Input Collection
     → 从下拉菜单选择 "test_collection"
5. 页面底部点击 "Run Workflow" 按钮
6. 应该看到提示 "Workflow invoked successfully"
```

---

## 🎉 验证云执行

### 在 Galaxy UI 中验证：

```
1. 查看右侧历史记录面板
2. 应该看到新的作业项（黄色/转圈表示运行中）
3. 作业名称: "Extract element identifiers on data X"
4. 点击作业名称展开详情
5. 点击 "ℹ️ View details" 或 "i" 图标
6. 在作业详情页面查找：

   ✅ Job Destination: cloud_small
   ✅ Runner: galaxy_cloud
   ✅ Tool: toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers
```

### 在 AWS 控制台验证：

```bash
# 方式1：列出运行中的作业
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 方式2：列出最近的作业（如果已完成）
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status SUCCEEDED --max-results 5

# 方式3：查看 S3 上传的文件
aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive --human-readable

# 方式4：查看 Batch 作业详情（替换 JOB_ID）
aws batch describe-jobs --jobs <JOB_ID>
```

### 在终端查看实时日志：

```bash
# 查看 Galaxy 日志（实时）
tail -f galaxy_startup.log | grep -i "batch\|cloud\|s3"

# 查看云执行相关日志
tail -100 galaxy_startup.log | grep -i "galaxy_cloud"

# 使用调试脚本查看 AWS 日志
bash scripts/debug/check_aws_logs.sh <job-id>
```

---

## 📊 预期结果

### 成功的标志：

1. **Galaxy 历史记录**
   - ✅ 作业状态变为绿色 ✓（完成）
   - ✅ 有输出文件：`identifiers_output`
   - ✅ 输出内容应该是：
     ```
     sample1
     sample2
     sample3
     ```

2. **作业详情页面**
   - ✅ Destination: `cloud_small`
   - ✅ Runner: `galaxy_cloud`
   - ✅ 环境配置：2 vCPUs, 4GB RAM

3. **AWS Batch**
   - ✅ 作业出现在队列中
   - ✅ 状态流转：SUBMITTED → RUNNABLE → RUNNING → SUCCEEDED
   - ✅ 执行时间：通常 30秒 - 2分钟（取决于实例启动时间）

4. **S3 存储**
   - ✅ 可以看到上传的输入文件
   - ✅ 可以看到生成的输出文件
   - ✅ 文件路径格式：`workflows/job-{id}/input/` 和 `output/`

---

## 🐛 故障排除

### 问题1：作业一直是灰色（等待状态）

**原因：** Celery worker 可能没启动

**解决：**
```bash
# 检查进程
ps aux | grep celery | grep galaxy

# 如果没有，重启 Galaxy
cd /Users/renyuankai/work/biometa/galaxy
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

---

### 问题2：作业失败（红色 X）

**原因：** 可能是工具、配置或 AWS 问题

**解决：**
```bash
# 1. 查看 Galaxy 错误信息（在 UI 中点击作业 → View details → Tool Standard Error）

# 2. 检查 Galaxy 日志
tail -100 galaxy_startup.log | grep -i error

# 3. 检查 AWS Batch 作业状态
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status FAILED

# 4. 查看详细错误日志
bash scripts/debug/check_aws_logs.sh <batch-job-id>

# 5. 验证 AWS 连接
aws sts get-caller-identity
aws batch describe-compute-environments
```

---

### 问题3：作业在本地运行（不是云端）

**原因：** 工具没有匹配到云执行规则

**检查：**
```bash
# 查看工具匹配规则
cat config/job_conf_cloud.yml | grep -A 3 "tools:"

# 确认工具 ID
# collection_element_identifiers 应该匹配:
# toolshed.g2.bx.psu.edu/repos/iuc/.*
```

**验证：**
- 在作业详情页面，Destination 应该是 `cloud_small`
- 如果是 `local`，说明没有匹配到规则

---

### 问题4：AWS 作业一直 RUNNABLE

**原因：** Compute Environment 没有可用实例

**解决：**
```bash
# 检查 Compute Environment 状态
aws batch describe-compute-environments \
  --compute-environments galaxy-cloud-compute

# 检查是否有实例启动
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=galaxy-cloud-*" \
  --query 'Reservations[].Instances[].State.Name'

# 可能需要等待 AWS 启动实例（首次运行较慢，1-3分钟）
```

---

## 📸 建议截图（用于验证）

测试时建议截图保存以下内容：

1. ✅ Galaxy Workflow 运行页面
2. ✅ 历史记录面板 - 显示作业完成
3. ✅ 作业详情页面 - 显示 `destination: cloud_small`
4. ✅ AWS Batch 控制台 - 作业列表
5. ✅ 输出文件内容 - 显示提取的标识符

---

## 📈 性能预期

| 阶段 | 预期时间 | 说明 |
|------|---------|------|
| 工作流提交 | 1-2秒 | Galaxy 接收并路由 |
| AWS Batch 排队 | 5-10秒 | 提交到 Batch |
| 实例启动 | 30-120秒 | 首次运行较慢 |
| 工具执行 | 5-15秒 | collection_element_identifiers 很快 |
| 结果返回 | 5-10秒 | 从 S3 下载 |
| **总计** | **1-3分钟** | 首次运行 |
| **后续运行** | **30-60秒** | 实例已warm |

---

## 🎯 下一步

测试成功后，你可以：

### 1. 测试更复杂的 Workflow
```
- 安装更多 IUC/QIIME2 工具
- 创建多步骤 workflow
- 测试大数据集
```

### 2. 调整云配置
```bash
# 编辑资源配置
nano config/job_conf_cloud.yml

# 例如：增加内存
cloud_medium:
  runner: galaxy_cloud
  params:
    vcpus: 8
    memory_mb: 16384  # 增加到 16GB
```

### 3. 添加更多工具映射
```yaml
# 在 job_conf_cloud.yml 的 tools: 部分添加
- id: "toolshed.g2.bx.psu.edu/repos/q2d2/.*"
  environment: cloud_large  # QIIME2 用大实例
```

---

## 📚 相关文档

- [快速测试步骤](RUN_TEST_NOW.md)
- [完整测试指南](HOW_TO_TEST_CLOUD_EXECUTION.md)
- [目录结构说明](DIRECTORY_STRUCTURE.md)
- [Job 配置文件](config/job_conf_cloud.yml)

---

## 🆘 需要帮助？

遇到问题时的检查清单：

```bash
# 1. Galaxy 运行状态
curl http://localhost:8080/api/version

# 2. 云 runner 加载状态
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud"

# 3. AWS 连接测试
aws sts get-caller-identity

# 4. Batch 队列状态
aws batch describe-job-queues --job-queues galaxy-cloud-queue

# 5. S3 桶访问
aws s3 ls s3://galaxy-cloud-data-1760241377/
```

---

**准备好了！现在就可以开始测试了！** 🚀

访问: http://localhost:8080
Workflow: /Users/renyuankai/work/biometa/galaxy/test_cloud_workflow.ga
测试数据: /Users/renyuankai/work/biometa/galaxy/test_collection_data/
