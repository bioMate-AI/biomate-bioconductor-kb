# AWS Batch 成本指南

## 快速回答

### 计算环境收费吗？
**不收费** ✓ - 计算环境只是配置，不产生费用

### 什么时候收费？
**只在有任务运行时** - EC2 实例启动才收费

### 当前配置成本
- **空闲时（无任务）**: $0/天
- **轻度使用（2小时/天）**: $0.03/天 (Spot)
- **中度使用（8小时/天）**: $0.10/天 (Spot)

## 详细成本分析

### 1. AWS Batch 服务费用
**免费** ✓ - AWS Batch 本身不收费

### 2. EC2 实例费用（主要成本）

#### 当前配置
```yaml
计算环境: galaxy-cloud-compute-ec2-dind-v2
配置:
  minvCpus: 0        # 空闲时不运行 → 不收费
  maxvCpus: 16       # 最多同时使用 16 vCPUs
  instanceTypes: optimal  # AWS 自动选择性价比最高的实例
```

#### 实例类型和价格（us-west-2）

| 实例类型 | vCPU | 内存 | On-Demand | Spot (70% 折扣) |
|---------|------|------|-----------|----------------|
| t3.small | 2 | 2GB | $0.0208/小时 | $0.0062/小时 |
| t3.medium | 2 | 4GB | $0.0416/小时 | $0.0125/小时 |
| t3.large | 2 | 8GB | $0.0832/小时 | $0.0250/小时 |
| c5.large | 2 | 4GB | $0.085/小时 | $0.0255/小时 |

### 3. 存储费用

#### EBS 卷（临时）
- **gp3**: $0.08/GB-月
- **典型配置**: 20GB → $1.60/月
- **实际成本**: 只在实例运行时计费

#### S3 存储
- **标准存储**: $0.023/GB-月
- **当前使用**: galaxy-cloud-data-1760241377
- **估算**:
  - 100个任务 × 500MB = 50GB
  - 成本: $1.15/月

#### ECR 镜像存储
- **价格**: $0.10/GB-月
- **当前使用**: galaxy-fetch-and-run + 工具镜像
- **估算**: 5GB → $0.50/月

### 4. 网络费用

#### 数据传输（同区域内）
- **S3 ↔ EC2**: 免费 ✓
- **ECR ↔ EC2**: 免费 ✓

#### 互联网出站（如果有）
- **前 1GB**: 免费
- **后续**: $0.09/GB
- **通常很少**：大部分数据在 AWS 内部传输

### 5. CloudWatch Logs
- **前 5GB**: 免费
- **后续**: $0.50/GB
- **估算**: 通常 < 1GB/月 → 免费

## 成本示例

### 场景 1: 开发/测试（轻度使用）
```
任务: 10个/天，每个运行 10 分钟
实例运行时间: 2小时/天
实例类型: t3.medium (Spot)

计算: 2小时 × $0.0125 = $0.025/天
月成本: $0.75/月
年成本: $9/年
```

### 场景 2: 小规模生产
```
任务: 50个/天，每个运行 30 分钟
实例运行时间: 8小时/天（并行执行）
实例类型: t3.medium (Spot)

计算: 8小时 × $0.0125 = $0.10/天
月成本: $3/月
年成本: $36/年
```

### 场景 3: 中规模生产
```
任务: 200个/天，每个运行 1 小时
实例运行时间: 20小时/天（4个并行）
实例类型: t3.medium (Spot)

计算: 20小时 × $0.0125 × 4实例 = $1/天
月成本: $30/月
年成本: $360/年
```

## 成本优化建议

### 1. 使用 Spot 实例（节省 70%）✓

**已配置**：当前计算环境会优先使用 Spot 实例

**风险**：Spot 实例可能被中断（概率 < 5%）

**缓解**：AWS Batch 自动重试失败的任务

### 2. 设置合理的超时时间

```yaml
# config/job_conf_cloud.yml
cloud_small:
  params:
    timeout_seconds: 3600  # 1小时，避免僵尸任务
```

**避免**：任务卡住导致实例一直运行

### 3. 使用预构建的 Docker 镜像

**节省时间** = **节省成本**

| 方式 | 启动时间 | 成本/任务 |
|------|---------|---------|
| 动态安装 conda | 5-10 分钟 | $0.002 |
| 预构建镜像 | 30 秒 | $0.0002 |
| **节省** | 90% | **10倍** |

### 4. 清理不用的资源

#### S3 旧数据
```bash
# 设置生命周期策略，30天后自动删除
aws s3api put-bucket-lifecycle-configuration \
    --bucket galaxy-cloud-data-1760241377 \
    --lifecycle-configuration '{
      "Rules": [{
        "Id": "DeleteOldJobs",
        "Status": "Enabled",
        "Prefix": "jobs/",
        "Expiration": {"Days": 30}
      }]
    }'
```

#### ECR 旧镜像
```bash
# 设置生命周期策略，保留最新 5 个版本
aws ecr put-lifecycle-policy \
    --repository-name galaxy-fetch-and-run \
    --lifecycle-policy-text '{
      "rules": [{
        "rulePriority": 1,
        "description": "Keep last 5 images",
        "selection": {
          "tagStatus": "any",
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": {"type": "expire"}
      }]
    }'
```

### 5. 监控和告警

#### 设置预算告警
```bash
# 创建预算告警：超过 $10/月时通知
aws budgets create-budget \
    --account-id 399683337364 \
    --budget '{
      "BudgetName": "galaxy-cloud-monthly",
      "BudgetLimit": {
        "Amount": "10",
        "Unit": "USD"
      },
      "TimeUnit": "MONTHLY",
      "BudgetType": "COST"
    }' \
    --notifications-with-subscribers '[{
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80
      },
      "Subscribers": [{
        "SubscriptionType": "EMAIL",
        "Address": "your-email@example.com"
      }]
    }]'
```

## 成本监控

### 查看当前月费用
```bash
# 查看本月截至目前的费用
aws ce get-cost-and-usage \
    --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --filter '{
      "Tags": {
        "Key": "Project",
        "Values": ["galaxy-cloud"]
      }
    }'
```

### 查看按服务分类的费用
```bash
aws ce get-cost-and-usage \
    --time-period Start=$(date -u -d '7 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
    --granularity DAILY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

### 查看 EC2 实例使用情况
```bash
# 查看最近 7 天的实例运行时间
aws cloudwatch get-metric-statistics \
    --namespace AWS/Batch \
    --metric-name RunningJobCount \
    --dimensions Name=ComputeEnvironmentName,Value=galaxy-cloud-compute-ec2-dind-v2 \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average,Maximum \
    --region us-west-2
```

## 免费套餐（新账户前 12 个月）

AWS 提供以下免费套餐：

### EC2
- **750 小时/月** t2.micro 或 t3.micro
- **注意**：t3.medium 不在免费套餐内

### S3
- **5GB 标准存储**
- **20,000 GET 请求**
- **2,000 PUT 请求**

### CloudWatch
- **5GB 日志摄取**
- **3 个仪表板**

### Data Transfer
- **15GB 出站** (到互联网)

## 成本对比：本地 vs 云端

### 本地服务器成本
```
硬件:
  服务器: $2,000
  维护: $500/年
  电费: $300/年
  折旧（3年）: $667/年
总计: $1,467/年

使用率假设: 20%（大部分时间闲置）
```

### 云端成本（中等使用）
```
EC2 (Spot): $360/年
S3: $15/年
ECR: $6/年
总计: $381/年

使用率: 按需付费，100% 利用率
```

**节省**: $1,086/年（74%）

## 常见问题

### Q: 如何避免意外高额账单？

**A**: 设置以下保护措施：

1. **预算告警** - 超过阈值时邮件通知
2. **最大 vCPU 限制** - 当前设置 maxvCpus: 16
3. **超时时间** - 避免僵尸任务
4. **定期审查** - 每月检查 Cost Explorer

### Q: minvCpus 设置为 0 是否影响性能？

**A**:
- **冷启动时间**: 首个任务需要等待 EC2 实例启动（~2-3 分钟）
- **后续任务**: 实例保持运行一段时间，无需等待
- **权衡**: 节省成本 vs 首个任务延迟

**建议**：
- **开发/测试**: minvCpus: 0 ✓（节省成本）
- **生产环境（高频）**: minvCpus: 2（保持 1 个实例预热）

### Q: 如何知道某个任务实际花费？

**A**: 使用资源标签（tagging）：

```yaml
# 在提交任务时添加标签
aws batch submit-job \
    --job-name my-job \
    --job-queue galaxy-cloud-queue \
    --job-definition my-job-def \
    --tags Project=galaxy,User=researcher1,Workflow=rnaseq
```

然后按标签查询成本：
```bash
aws ce get-cost-and-usage \
    --filter '{
      "Tags": {
        "Key": "Workflow",
        "Values": ["rnaseq"]
      }
    }'
```

## 总结

### 当前配置（推荐）
- **计算环境**: 免费 ✓
- **空闲时**: $0
- **典型使用**: $3-10/月
- **存储**: $2/月

### 总预估（小规模使用）
**$5-12/月** 或 **$60-144/年**

### 与本地服务器相比
节省 **70-90%** 的成本

### 最重要的成本控制
1. ✓ 使用 Spot 实例
2. ✓ minvCpus: 0（空闲时不运行）
3. ✓ 设置预算告警
4. ✓ 定期清理旧数据
5. ✓ 使用预构建镜像
