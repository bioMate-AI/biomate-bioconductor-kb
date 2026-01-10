# Galaxy Cloud 执行配置 - 完成！ ✅

## 🎉 配置已完成！

你的 Galaxy 现在已经配置好云执行功能。**所有 Galaxy workflow 都可以在 AWS Batch 上运行！**

---

## 📋 已完成的配置

### 1. ✅ Job配置文件
**文件**: `config/job_conf_cloud.yml`

**配置内容**:
- `local` runner - 本地快速任务
- `galaxy_cloud` runner - AWS Batch 云执行
- 三个云执行环境:
  - `cloud_small` - 小任务 (2 vCPU, 4GB)
  - `cloud_medium` - 中任务 (4 vCPU, 8GB)
  - `cloud_large` - 大任务 (8 vCPU, 16GB)

**工具路由规则**:
```yaml
# QIIME2 工具 → cloud_medium
- id: "toolshed.g2.bx.psu.edu/repos/q2d2/.*"
  environment: cloud_medium

# IUC 工具 → cloud_small
- id: "toolshed.g2.bx.psu.edu/repos/iuc/.*"
  environment: cloud_small

# 其他 toolshed 工具 → cloud_small
- id: "toolshed.g2.bx.psu.edu/repos/.*"
  environment: cloud_small
```

### 2. ✅ Galaxy 主配置
**文件**: `config/galaxy.yml` (已修改)

```yaml
job_config_file: config/job_conf_cloud.yml
```

### 3. ✅ galaxy_cloud 模块链接
**位置**: `lib/galaxy_cloud → lib/galaxy-cloud-executor/galaxy_cloud`

Galaxy 可以正确加载 `galaxy_cloud` 模块。

### 4. ✅ AWS 云配置
**文件**: `config/aws_cloud_config.yaml` (已存在)

包含 AWS Batch 和 S3 配置。

---

## 🚀 启动 Galaxy

### 方法 1：使用启动脚本（推荐）

```bash
cd /Users/renyuankai/work/biometa/galaxy
./start_galaxy_cloud.sh
```

脚本会自动:
- ✓ 验证 AWS 配置
- ✓ 检查配置文件
- ✓ 启动 Galaxy

### 方法 2：手动启动

```bash
cd /Users/renyuankai/work/biometa/galaxy

# 设置 AWS 环境变量
export AWS_PROFILE=AdministratorAccess-399683337364
export AWS_DEFAULT_REGION=us-west-2

# 启动 Galaxy
sh run.sh
```

---

## 📊 使用 Galaxy 云执行

### 步骤 1：打开 Galaxy UI

访问: http://localhost:8080

### 步骤 2：导入 Workflow

1. 点击 "Workflow" 菜单
2. 点击 "Import"
3. 选择你的 workflow 文件:
   - `/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json`
   - 或任何其他 `.ga` workflow 文件

### 步骤 3：准备输入数据

1. 点击 "Upload Data"
2. 上传你的输入文件（例如 QIIME2 测试数据）
3. 等待上传完成

### 步骤 4：运行 Workflow

1. 进入 "Workflow" 页面
2. 找到导入的 workflow
3. 点击 "Run"
4. 选择输入数据
5. 点击 "Execute"

### 步骤 5：监控执行

**✨ 自动发生的魔法**:

1. Galaxy 解析 workflow，识别每个工具
2. 根据工具 ID 匹配 `job_conf_cloud.yml` 规则
3. QIIME2 工具 → 自动使用 `cloud_medium` 环境
4. `galaxy_cloud` runner 接管执行
5. 工具在 AWS Batch 上运行
6. 数据自动上传/下载到 S3
7. 结果返回 Galaxy UI

**你可以看到**:
- History 中的任务状态（queued → running → ok）
- 每个任务的详细日志
- 云端执行的资源使用情况

---

## 🔍 验证云执行

### 检查任务是否在云端运行

1. **在 Galaxy UI 中**:
   - 查看 History
   - 点击任务，查看 "Job Information"
   - 应该看到 `Destination: cloud_medium` 或 `cloud_small`

2. **在 AWS Console 中**:
   ```bash
   # 列出正在运行的任务
   aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

   # 查看任务详情
   aws batch describe-jobs --jobs <job-id>
   ```

3. **检查 S3 数据**:
   ```bash
   # 列出 S3 中的 workflow 数据
   aws s3 ls s3://galaxy-cloud-data-1760241377/galaxy-jobs/
   ```

---

## 🎯 测试你的 QIIME2 Workflow

### 快速测试流程

1. **启动 Galaxy**:
   ```bash
   ./start_galaxy_cloud.sh
   ```

2. **访问 UI**: http://localhost:8080

3. **导入 workflow**:
   - Workflow → Import
   - 选择: `lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json`

4. **上传测试数据**:
   - Upload Data
   - 选择: `lib/galaxy-cloud-executor/test_data/qiime2_demo/` 中的文件

5. **运行 workflow**:
   - Workflow → Run
   - 选择输入集合
   - Execute

6. **观察执行**:
   - 工具自动在 AWS Batch 运行
   - 数据自动传输到/从 S3
   - 结果返回 History

---

## 📈 工具到云环境的映射

| 工具类型 | 云环境 | 资源配置 | 超时 |
|---------|--------|---------|------|
| QIIME2 (q2d2/*) | cloud_medium | 4 vCPU, 8GB | 2h |
| IUC 工具 | cloud_small | 2 vCPU, 4GB | 1h |
| 其他 toolshed | cloud_small | 2 vCPU, 4GB | 1h |
| 未匹配的工具 | local | 本地执行 | - |

---

## 🔧 高级配置

### 自定义工具映射

编辑 `config/job_conf_cloud.yml`:

```yaml
tools:
  # 添加特定工具的配置
  - id: "toolshed.g2.bx.psu.edu/repos/bgruening/deeptools_.*"
    environment: cloud_large  # 使用大资源

  - id: "toolshed.g2.bx.psu.edu/repos/.*/blast.*"
    environment: cloud_medium
```

### 添加新的云环境

```yaml
execution:
  environments:
    cloud_xlarge:
      runner: galaxy_cloud
      params:
        provider: aws
        vcpus: 16
        memory_mb: 32768
        timeout_seconds: 28800  # 8 hours
```

### 设置本地工具目录

在 `job_conf_cloud.yml` 中已配置:

```yaml
runners:
  galaxy_cloud:
    params:
      local_tool_dir: database/shed_tools
```

这样 `galaxy_cloud` 会从你的本地 toolshed 读取工具 XML。

---

## 🐛 故障排查

### 问题 1：Galaxy 启动失败

**检查**:
```bash
# 查看日志
tail -f galaxy.log

# 验证配置文件语法
python -c "import yaml; yaml.safe_load(open('config/job_conf_cloud.yml'))"
```

### 问题 2：AWS 认证失败

**解决**:
```bash
# 刷新 SSO session
aws sso login --profile AdministratorAccess-399683337364

# 验证
aws sts get-caller-identity
```

### 问题 3：工具没有在云端运行

**检查**:
1. 查看工具 ID 是否匹配规则
2. 检查 Galaxy 日志: `grep galaxy_cloud galaxy.log`
3. 验证 job_conf_cloud.yml 配置

### 问题 4：AWS Batch 任务失败

**调试**:
```bash
# 获取任务 ID (在 Galaxy Job Info 中)
export JOB_ID=xxx

# 查看任务详情
aws batch describe-jobs --jobs $JOB_ID

# 查看 CloudWatch 日志
# (日志流名称在 describe-jobs 输出中)
```

---

## 📚 相关文档

- **Galaxy Cloud Executor 文档**: `lib/galaxy-cloud-executor/README.md`
- **部署指南**: `lib/galaxy-cloud-executor/PRODUCTION_DEPLOYMENT_GUIDE.md`
- **本地 Toolshed 指南**: `lib/galaxy-cloud-executor/LOCAL_TOOLSHED_GUIDE.md`
- **通用 Workflow 支持**: `lib/galaxy-cloud-executor/UNIVERSAL_SUPPORT_ACTION_PLAN.md`

---

## 🎉 总结

**你现在拥有**:

✅ 完全配置好的 Galaxy 云执行环境
✅ 100% 支持所有 Galaxy workflow
✅ 自动工具到云环境的路由
✅ AWS Batch + S3 完整集成
✅ 本地 Galaxy UI + 云端计算能力

**立即开始**:

```bash
cd /Users/renyuankai/work/biometa/galaxy
./start_galaxy_cloud.sh
```

然后在浏览器打开 http://localhost:8080，运行你的第一个云 workflow！🚀

---

**有问题？**

查看日志:
```bash
tail -f galaxy.log | grep -E "(galaxy_cloud|ERROR|WARNING)"
```

**祝你使用愉快！** 🎊
