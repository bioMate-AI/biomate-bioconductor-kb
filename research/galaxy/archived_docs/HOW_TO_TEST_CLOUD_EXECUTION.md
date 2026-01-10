# 如何测试Galaxy云执行

## 当前状态
✅ Galaxy已启动并运行在 http://localhost:8080
✅ GalaxyCloudJobRunner已成功初始化
✅ AWS配置已验证（Batch Queue + S3 Bucket）
✅ 云执行规则已配置（IUC工具 → AWS Batch）

## 问题：没有安装Tool Shed工具

你的Galaxy是新安装的，没有从Tool Shed安装任何工具。要测试云执行，你需要安装一些Tool Shed工具（因为内置工具不会路由到云端）。

## 🎯 测试方案（3个选项）

### 方案1：通过Galaxy UI手动安装工具（最简单，推荐新手）

**步骤：**

1. **设置管理员账户**
   ```bash
   # 编辑 config/galaxy.yml
   nano config/galaxy.yml

   # 找到 admin_users 行，取消注释并设置你的邮箱：
   admin_users: your-email@example.com

   # 重启Galaxy
   pkill -f gunicorn ; pkill -f celery
   bash start_galaxy_cloud.sh &
   ```

2. **访问Galaxy并注册账户**
   - 打开 http://localhost:8080
   - 注册账户（使用上面设置的管理员邮箱）
   - 登录

3. **安装测试工具**
   - 访问 http://localhost:8080/admin/toolshed
   - 搜索 `collection_element_identifiers`（简单的IUC工具）
   - 点击 Install
   - 等待安装完成（约2-5分钟）

4. **创建测试workflow**
   - Workflow → Create New
   - 添加 "Input Dataset"
   - 添加 "Extract element identifiers" 工具
   - 连接输入
   - 保存workflow

5. **运行测试**
   - 上传一个collection数据集
   - 运行workflow
   - 查看历史记录 - IUC工具应该显示运行在云端

---

### 方案2：使用API脚本自动安装（快速，推荐高级用户）

**步骤：**

1. **设置管理员并获取API Key**
   ```bash
   # 1. 编辑config/galaxy.yml设置admin_users（参考方案1）
   # 2. 重启Galaxy
   # 3. 登录Galaxy UI
   # 4. User → Preferences → Manage API Key → Create
   # 5. 复制API Key
   ```

2. **编辑安装脚本**
   ```bash
   nano install_test_tools.py

   # 设置你的API Key:
   API_KEY = "your-api-key-here"
   ```

3. **运行安装脚本**
   ```bash
   python3 install_test_tools.py
   ```

4. **验证安装**
   - 刷新Galaxy UI
   - Tools面板应该显示新安装的工具

---

### 方案3：使用galaxy-cloud-executor独立模式测试（不需要UI）

如果你只想测试云执行功能本身，不需要通过Galaxy UI：

```bash
cd lib/galaxy/galaxy-cloud-executor

# 使用已有的测试脚本
bash scripts/workflow/run_qiime2_cloud.sh

# 或者使用Python测试
cd examples
python3 run_any_galaxy_workflow.py \
  --workflow /path/to/workflow.ga \
  --provider aws \
  --queue galaxy-cloud-queue \
  --bucket galaxy-cloud-data-1760241377
```

这个方案会：
- 解析workflow
- 查找工具的容器镜像
- 直接提交到AWS Batch
- 不依赖Galaxy UI/工具安装

---

## 🔍 如何验证云执行正在工作

### 在Galaxy UI中：
1. 运行workflow后，查看历史记录
2. 点击作业详情
3. 检查：
   - Job destination应该是 `cloud_small` 或 `cloud_medium`
   - Tool runner应该是 `galaxy_cloud`

### 在AWS中：
```bash
# 检查Batch作业
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 检查S3上传
aws s3 ls s3://galaxy-cloud-data-1760241377/

# 查看日志
bash scripts/debug/check_aws_logs.sh <job-id>
```

### 在Galaxy日志中：
```bash
# 查看job runner活动
tail -f galaxy_startup.log | grep -i "galaxy_cloud\|batch"
```

---

## 📝 推荐的测试workflow

如果你想要一个现成的测试workflow，这里有一个简单的IUC工具workflow：

```json
{
  "name": "Cloud Test - Collection Tools",
  "steps": {
    "0": {
      "type": "data_collection_input",
      "label": "Input Collection"
    },
    "1": {
      "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2",
      "label": "Extract Identifiers (云端运行)"
    }
  }
}
```

根据你的 `job_conf_cloud.yml` 配置，这个工具会自动：
- 匹配规则：`toolshed.g2.bx.psu.edu/repos/iuc/.*`
- 路由到：`cloud_small` 环境
- 执行在：AWS Batch（2 vCPUs, 4GB RAM）

---

## ⚠️ 常见问题

**Q: 工具安装很慢怎么办？**
A: Tool Shed安装需要下载和安装依赖，第一次可能需要5-10分钟。可以在Terminal查看进度：
```bash
tail -f galaxy_startup.log | grep -i "install\|tool"
```

**Q: 如何确认工具会在云端运行？**
A: 检查 `config/job_conf_cloud.yml` 中的 `tools:` 部分。只有匹配pattern的工具才会路由到云端。

**Q: 我的workflow工具不在Tool Shed怎么办？**
A: 可以在 `job_conf_cloud.yml` 的 `tools:` 部分添加规则，指定工具ID pattern和执行环境。

**Q: 能否全部工具都云端执行？**
A: 可以，但不推荐。简单工具本地执行更快更便宜。建议只让计算密集型工具（QIIME2、机器学习等）云端执行。

---

## 🚀 下一步

1. 选择一个方案安装工具
2. 运行测试workflow
3. 验证作业在AWS Batch运行
4. 检查结果是否正确

需要帮助？查看：
- Galaxy Tool Shed: https://toolshed.g2.bx.psu.edu
- Galaxy Admin文档: https://docs.galaxyproject.org/en/master/admin/
- AWS Batch控制台: https://console.aws.amazon.com/batch/

---

**当前Galaxy状态：**
```bash
# 检查Galaxy是否运行
curl -s http://localhost:8080/api/version

# 检查云runner状态
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud"

# 查看AWS资源
echo "Batch Queue: galaxy-cloud-queue"
echo "S3 Bucket: galaxy-cloud-data-1760241377"
```
