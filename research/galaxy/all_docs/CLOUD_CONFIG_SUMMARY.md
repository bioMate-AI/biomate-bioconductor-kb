# Galaxy云执行配置总结

## ✅ 现在已配置为完全云端执行！

### 📊 配置对比

#### ❌ 之前的配置（部分云端）

```yaml
execution:
  default: local  # 默认本地

tools:
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_small  # 只有Tool Shed工具云端

  - id: ".*"
    environment: local  # 其他全部本地
```

**结果：**
- Tool Shed工具 → 云端 ✓
- 内置工具 → 本地 ✗
- 未知工具 → 本地 ✗

#### ✅ 现在的配置（完全云端）

```yaml
execution:
  default: cloud_small  # 默认云端！

tools:
  # 例外：必须本地的
  - id: "__UPLOAD__"
    environment: local

  - id: "__SET_METADATA__"
    environment: local

  # 所有Tool Shed工具 → 云端
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_small

  # 其他所有工具 → 云端
  - id: ".*"
    environment: cloud_small
```

**结果：**
- Tool Shed工具 → 云端 ✓
- 内置工具 → 云端 ✓
- 所有其他工具 → 云端 ✓
- **例外**：上传和元数据工具 → 本地（必须）

---

## 🎯 现在的执行策略

### 云端执行（99%的工具）

✅ 所有Tool Shed工具
✅ 所有生物信息学工具
✅ 所有数据处理工具
✅ 所有统计分析工具
✅ 所有可视化工具
✅ 几乎所有内置工具

### 本地执行（仅2个特殊工具）

❌ `__UPLOAD__` - 数据上传工具
❌ `__SET_METADATA__` - 元数据设置工具

**为什么这两个必须本地？**
- 上传工具需要直接访问Galaxy的文件系统
- 元数据工具需要直接操作Galaxy数据库
- 这两个工具执行很快，没必要云端

---

## 📋 资源配置

### 云端环境配置

| 环境 | vCPUs | 内存 | 用途 |
|------|-------|------|------|
| **cloud_small** | 2 | 4GB | 默认环境、轻量工具 |
| **cloud_medium** | 4 | 8GB | 中等计算工具 |
| **cloud_large** | 8 | 16GB | 计算密集工具 |

### 工具资源分配

```yaml
FastQC        → cloud_small  (2 vCPUs, 4GB)
Trimmomatic   → cloud_medium (4 vCPUs, 8GB)
Bowtie2       → cloud_large  (8 vCPUs, 16GB)
BAM Stats     → cloud_small  (2 vCPUs, 4GB)
IUC工具       → cloud_small  (2 vCPUs, 4GB)
DevTeam工具   → cloud_small  (2 vCPUs, 4GB)
QIIME2工具    → cloud_medium (4 vCPUs, 8GB)
其他所有工具  → cloud_small  (2 vCPUs, 4GB)
```

---

## 🔍 如何验证完全云端配置

### 测试方法1：运行任意workflow

```
1. 在Galaxy UI运行任意workflow
2. 查看历史记录中的作业
3. 点击作业详情
4. 检查 "Job Destination"
```

**预期结果：**
- Tool Shed工具：`destination: cloud_small/medium/large` ✓
- 内置工具：`destination: cloud_small` ✓
- 上传工具：`destination: local` ✓（这是正常的）

### 测试方法2：查看AWS Batch

```bash
# 运行workflow后查看
aws batch list-jobs --job-queue galaxy-cloud-queue --job-status RUNNING

# 应该看到多个作业
```

### 测试方法3：查看S3存储

```bash
# 查看数据上传
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive

# 应该看到输入输出文件
```

### 测试方法4：查看Galaxy日志

```bash
tail -f galaxy_startup.log | grep -i "submit.*batch\|destination.*cloud"

# 应该看到：
# Job XXX submitted to destination 'cloud_small'
# Submitting to AWS Batch: job-123
```

---

## 💰 成本考虑

### 完全云端的优缺点

#### ✅ 优势

1. **弹性扩展**
   - 可以同时运行100+个workflow
   - 自动按需扩展EC2实例

2. **按需付费**
   - 只为实际使用的计算时间付费
   - 不用时不产生费用

3. **释放本地资源**
   - Galaxy服务器只处理web请求
   - 不需要强大的本地硬件

4. **隔离性好**
   - 每个作业独立容器
   - 失败不影响其他作业

#### ⚠️  注意事项

1. **数据传输成本**
   - 数据上传到S3有成本
   - 大文件频繁传输会增加费用

2. **冷启动延迟**
   - 第一次运行工具需要拉取镜像
   - 启动EC2实例需要时间（1-3分钟）

3. **小任务不划算**
   - 非常快的任务（<10秒）本地更快
   - 但我们已经保留了上传等快速工具在本地

---

## 🎛️ 如何调整配置

### 场景1：某个工具想改回本地

```yaml
tools:
  # 添加规则（在其他规则之前）
  - id: "toolshed.g2.bx.psu.edu/repos/devteam/某工具/.*"
    environment: local
```

### 场景2：想让内置工具在本地

```yaml
execution:
  default: local  # 改回本地默认

tools:
  # Tool Shed工具继续云端
  - id: "toolshed.g2.bx.psu.edu/repos/.*"
    environment: cloud_small

  # 内置工具本地
  - id: ".*"
    environment: local
```

### 场景3：根据工具大小自动分配资源

```yaml
tools:
  # 超大型工具
  - id: "toolshed.g2.bx.psu.edu/repos/.*(assembly|alignment|mapping).*"
    environment: cloud_large

  # 大型工具
  - id: "toolshed.g2.bx.psu.edu/repos/.*(variant|snp).*"
    environment: cloud_medium

  # 其他默认小实例
  - id: ".*"
    environment: cloud_small
```

---

## 📝 配置文件位置

主配置文件：
```
/Users/renyuankai/work/biometa/galaxy/config/job_conf_cloud.yml
```

AWS配置：
```
/Users/renyuankai/work/biometa/galaxy/config/aws_cloud_config.yaml
```

---

## 🚀 重启Galaxy生效

配置修改后需要重启：

```bash
# 停止
pkill -f gunicorn ; pkill -f celery

# 启动
bash start_galaxy_cloud.sh &

# 等待启动（约1分钟）
sleep 60

# 验证
curl http://localhost:8080/api/version
tail -50 galaxy_startup.log | grep -i "galaxy.*cloud.*init"
```

---

## ✅ 总结

### 当前配置状态

- ✅ **默认执行环境**: cloud_small（云端）
- ✅ **Tool Shed工具**: 100%云端
- ✅ **内置工具**: 99%云端
- ✅ **特殊工具**: 上传和元数据在本地（必须）
- ✅ **资源配置**: 根据工具类型自动分配

### 这意味着

🎉 **你的Galaxy现在是完全云端执行配置！**

- 运行任何workflow，几乎所有工具都会在AWS Batch上执行
- 只有上传数据和设置元数据在本地（这两个必须本地）
- 计算密集型工具自动使用大实例
- 轻量工具使用小实例节省成本

---

**配置完成！重启Galaxy后生效！** 🚀
