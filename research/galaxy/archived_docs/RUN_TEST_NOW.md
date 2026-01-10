# 🚀 现在就测试云执行！

## ✅ 你已经完成
- ✅ Galaxy运行中
- ✅ 安装了 collection_element_identifiers 工具
- ✅ Workflow已创建好
- ✅ 测试数据已准备好

## 📝 导入和运行Workflow（3分钟）

### 步骤1：导入Workflow（30秒）

**方式A - 通过UI导入（推荐）：**
```
1. 打开 http://localhost:8080
2. 点击顶部 "Workflow" 菜单
3. 点击右上角的 ⬆️ 导入按钮
4. 选择 "Upload file from your computer"
5. 上传文件：test_cloud_workflow.ga
6. 点击 "Import workflow"
```

**方式B - 通过命令行导入：**
```bash
# 获取你的API key（在Galaxy UI: User -> Preferences -> Manage API Key）
export GALAXY_API_KEY="your-api-key"

# 使用API导入workflow
curl -X POST "http://localhost:8080/api/workflows" \
  -H "x-api-key: $GALAXY_API_KEY" \
  -H "Content-Type: application/json" \
  -d @test_cloud_workflow.ga
```

---

### 步骤2：上传测试数据（1分钟）

```
1. 在Galaxy UI中，点击左侧的 "Upload Data" 按钮（↑ 图标）
2. 点击 "Choose local files"
3. 选择以下3个文件：
   - test_collection_data/sample1.txt
   - test_collection_data/sample2.txt
   - test_collection_data/sample3.txt
4. 点击 "Start" 开始上传
5. 点击 "Close" 关闭上传窗口
```

---

### 步骤3：创建Dataset Collection（1分钟）

```
1. 在右侧的历史记录面板，你应该看到3个上传的文件
2. 点击历史记录面板右上角的 ☑️ 图标（批量操作）
3. 选中这3个txt文件
4. 点击 "For all selected..." 按钮
5. 选择 "Build Dataset List"
6. 在弹出窗口中：
   - Name: test_collection
   - 确认3个文件都在列表中
7. 点击 "Create list"
8. 现在历史记录中应该出现一个 📁 collection图标
```

---

### 步骤4：运行Workflow（30秒）

```
1. 点击顶部 "Workflow" 菜单
2. 找到 "Cloud Test - Extract Identifiers"
3. 点击右侧的 ▶️ 运行按钮
4. 在运行页面：
   - Step 1: Input Collection
     → 选择刚创建的 "test_collection"
5. 点击底部的 "Run Workflow" 按钮
```

---

## 🎉 验证云执行

### 在Galaxy UI中查看：

```
1. 查看右侧历史记录面板
2. 应该看到一个新的作业在运行（黄色/转圈图标）
3. 点击作业名称展开详情
4. 点击 "ℹ️ View details" 查看作业信息
5. 查找：
   ✓ Job Destination: 应该显示 "cloud_small"
   ✓ Runner: 应该显示 "galaxy_cloud"
```

### 在AWS控制台查看：

```bash
# 列出正在运行的Batch作业
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status RUNNING

# 查看S3上传的数据
aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive

# 如果作业已完成，查看历史
aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --job-status SUCCEEDED
```

### 在Galaxy日志中查看：

```bash
# 实时查看云执行相关日志
tail -f galaxy_startup.log | grep -i "batch\|cloud\|s3"

# 查看最近的云runner活动
tail -100 galaxy_startup.log | grep -i "galaxy_cloud"
```

---

## 📊 预期结果

### 成功的标志：

1. **Galaxy历史记录**
   - ✅ 作业完成（绿色✓图标）
   - ✅ 输出文件：identifiers_output.txt
   - ✅ 内容应该是：
     ```
     sample1
     sample2
     sample3
     ```

2. **AWS Batch**
   - ✅ 作业出现在队列中
   - ✅ 状态：SUBMITTED → RUNNABLE → RUNNING → SUCCEEDED
   - ✅ 有CloudWatch日志

3. **S3 Bucket**
   - ✅ 输入文件已上传
   - ✅ 输出文件已生成
   - ✅ 文件路径类似：`workflows/job-{id}/input/` 和 `output/`

---

## 🐛 故障排除

### 问题1：作业一直是灰色（等待状态）

**可能原因：**
- Galaxy job handler还没启动
- 或者需要等待几秒钟

**解决方案：**
```bash
# 检查Galaxy进程
ps aux | grep -E "gunicorn|celery" | grep galaxy

# 如果没有celery worker，重启Galaxy
pkill -f gunicorn ; pkill -f celery
bash start_galaxy_cloud.sh &
```

---

### 问题2：作业失败（红色X）

**查看错误信息：**
```
1. 在Galaxy历史记录中点击失败的作业
2. 点击 "ℹ️ View details"
3. 查看 "Tool Standard Error" 部分
```

**检查日志：**
```bash
# Galaxy日志
tail -100 galaxy_startup.log | grep -i error

# 如果有AWS Batch job ID，查看详细日志
bash scripts/debug/check_aws_logs.sh <job-id>
```

---

### 问题3：作业在本地运行（不在云端）

**检查匹配规则：**
```bash
# 查看job配置
grep -A 3 "iuc" config/job_conf_cloud.yml

# 确认工具ID匹配pattern
# collection_element_identifiers的完整ID应该是：
# toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/...
```

**验证runner加载：**
```bash
grep -i "galaxy.*cloud.*init" galaxy_startup.log | tail -5
```

---

## 📸 截图指南

如果要验证云执行，可以截图以下内容：

1. **Galaxy作业详情页面** - 显示destination: cloud_small
2. **AWS Batch控制台** - 显示作业列表
3. **S3控制台** - 显示上传的文件
4. **历史记录面板** - 显示作业完成

---

## 🎯 下一步

测试成功后，你可以：

1. **测试更复杂的workflow**
   - 安装更多IUC工具
   - 创建多步骤workflow
   - 测试不同的数据类型

2. **调整云配置**
   - 修改 `config/job_conf_cloud.yml`
   - 添加更多工具映射规则
   - 配置不同的资源大小

3. **监控和优化**
   - 查看作业执行时间
   - 优化资源配置
   - 设置成本告警

4. **部署QIIME2 workflow**
   - 安装QIIME2工具套件
   - 导入你的真实workflow
   - 处理实际数据

---

## 📚 相关文档

- [完整测试指南](HOW_TO_TEST_CLOUD_EXECUTION.md)
- [Job配置文件](config/job_conf_cloud.yml)
- [AWS配置](config/aws_cloud_config.yaml)
- [调试脚本](scripts/debug/)

---

## 🆘 需要帮助？

遇到问题时检查：
```bash
# Galaxy状态
curl http://localhost:8080/api/version

# 云runner状态
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud"

# AWS连接
aws sts get-caller-identity
aws batch describe-compute-environments
```

**现在就开始测试吧！** 🚀

打开浏览器访问：http://localhost:8080
