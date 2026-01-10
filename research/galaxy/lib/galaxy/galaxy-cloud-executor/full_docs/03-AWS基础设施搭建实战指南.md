# AWS Batch 基础设施搭建实战指南

## 概述

本文档记录了 Galaxy Cloud Executor AWS Batch 基础设施的完整搭建过程，包括所有遇到的问题和解决方案。这是基于**实际操作经验**的指南。

**⚠️ 重要提示**: 你已经完成了所有这些步骤！本文档是为了：
1. 记录你解决的所有问题
2. 帮助其他人避免相同的坑
3. 作为故障排查的参考

---

## 搭建流程概览

```
1. 配置 AWS 凭证
   ↓
2. 创建 IAM 角色
   ├── ecsInstanceRole (EC2 实例角色)
   ├── BatchJobRole (容器作业角色) ⚠️ 关键!
   └── awsBatchServiceRole (Batch 服务角色)
   ↓
3. 创建 Compute Environment
   ├── 配置 minvCpus=0 (动态扩展) ⚠️ 坑
   └── 配置实例类型 (optimal)
   ↓
4. 创建 Job Queue
   ↓
5. 创建 S3 存储桶
   ↓
6. 修复 Launch Template ⚠️ 关键!
   └── 添加 IAM Instance Profile
   ↓
7. 配置 BatchJobRole S3 权限 ⚠️ 关键!
   ↓
8. 测试验证
   ├── 单作业测试
   └── 2步 Workflow 测试
```

---

## 第一步: 配置 AWS 凭证

### 1.1 安装 AWS CLI

```bash
# macOS
brew install awscli

# 验证安装
aws --version
```

### 1.2 配置凭证

```bash
aws configure

# 输入:
# AWS Access Key ID: your-access-key
# AWS Secret Access Key: your-secret-key
# Default region name: us-west-2
# Default output format: json
```

### 1.3 验证凭证

```bash
# 应该返回账户信息
aws sts get-caller-identity
```

**预期输出**:
```json
{
    "UserId": "AIDXXXXXXXXXXXXXXXXX",
    "Account": "399683337364",
    "Arn": "arn:aws:iam::399683337364:user/your-username"
}
```

---

## 第二步: 创建 IAM 角色

### 2.1 创建 ecsInstanceRole (EC2 实例角色)

**用途**: 允许 EC2 实例注册到 ECS Cluster

```bash
# 创建信任策略
cat > trust-policy-ec2.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建角色
aws iam create-role \
  --role-name ecsInstanceRole \
  --assume-role-policy-document file://trust-policy-ec2.json

# 附加 AWS 托管策略
aws iam attach-role-policy \
  --role-name ecsInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
```

### 2.2 创建 Instance Profile

```bash
# 创建 Instance Profile
aws iam create-instance-profile \
  --instance-profile-name ecsInstanceRole

# ⚠️ 关键步骤: 将角色添加到 Instance Profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ecsInstanceRole \
  --role-name ecsInstanceRole
```

**❌ 常见错误**: 忘记执行 `add-role-to-instance-profile`
- **症状**: `NoSuchEntity: Instance Profile ecsInstanceRole cannot be found`
- **原因**: Instance Profile 创建了但没有关联角色
- **解决**: 运行上面的 `add-role-to-instance-profile` 命令

### 2.3 创建 BatchJobRole (容器作业角色) ⚠️ **最关键!**

**用途**: 允许容器访问 S3 存储桶

```bash
# 创建信任策略
cat > trust-policy-ecs-tasks.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建角色
aws iam create-role \
  --role-name BatchJobRole \
  --assume-role-policy-document file://trust-policy-ecs-tasks.json

# 创建 S3 访问策略
cat > batch-job-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::galaxy-cloud-data-1760241377",
        "arn:aws:s3:::galaxy-cloud-data-1760241377/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF

# 创建并附加策略
aws iam put-role-policy \
  --role-name BatchJobRole \
  --policy-name BatchJobS3Access \
  --policy-document file://batch-job-s3-policy.json
```

**获取 ARN** (后面配置文件需要):
```bash
aws iam get-role --role-name BatchJobRole --query 'Role.Arn' --output text
# 输出: arn:aws:iam::399683337364:role/BatchJobRole
```

**⚠️ 为什么这个角色如此关键？**
- 没有这个角色，容器无法访问 S3
- 会报错: `403 Forbidden when calling HeadObject`
- 这是你遇到的第5个关键问题！

### 2.4 创建 awsBatchServiceRole

**用途**: 允许 AWS Batch 服务管理资源

```bash
# 创建信任策略
cat > trust-policy-batch.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "batch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建角色
aws iam create-role \
  --role-name awsBatchServiceRole \
  --assume-role-policy-document file://trust-policy-batch.json

# 附加 AWS 托管策略
aws iam attach-role-policy \
  --role-name awsBatchServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole
```

---

## 第三步: 创建 Compute Environment

### 3.1 获取网络资源

```bash
# 获取默认 VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

# 获取子网
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' \
  --output text)

# 获取默认安全组
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)
```

### 3.2 创建 Compute Environment

```bash
aws batch create-compute-environment \
  --compute-environment-name galaxy-cloud-compute \
  --type MANAGED \
  --state ENABLED \
  --service-role arn:aws:iam::399683337364:role/awsBatchServiceRole \
  --compute-resources '{
    "type": "EC2",
    "minvCpus": 0,
    "maxvCpus": 256,
    "desiredvCpus": 0,
    "instanceTypes": ["optimal"],
    "subnets": ["'$(echo $SUBNET_IDS | tr ' ' '","')'"],
    "securityGroupIds": ["'$SG_ID'"],
    "instanceRole": "arn:aws:iam::399683337364:instance-profile/ecsInstanceRole",
    "tags": {
      "Name": "galaxy-cloud-compute"
    }
  }'
```

**⚠️ minvCpus=0 的含义**:
- **优点**: 空闲时无实例运行，成本为零
- **缺点**: 首次运行需要 5-10 分钟冷启动
- **适用**: 间歇性工作负载（推荐）
- **不适用**: 需要即时响应的场景

**验证**:
```bash
aws batch describe-compute-environments \
  --compute-environments galaxy-cloud-compute \
  --query 'computeEnvironments[0].{State:state,Status:status}'

# 应该看到:
# State: ENABLED
# Status: VALID
```

**❌ 常见问题**:
- **Status: INVALID**: 通常是 IAM 角色或网络配置问题
- 检查 `statusReason` 字段获取详细错误

---

## 第四步: 创建 Job Queue

```bash
aws batch create-job-queue \
  --job-queue-name galaxy-cloud-queue \
  --state ENABLED \
  --priority 1 \
  --compute-environment-order order=1,computeEnvironment=galaxy-cloud-compute
```

**验证**:
```bash
aws batch describe-job-queues \
  --job-queues galaxy-cloud-queue \
  --query 'jobQueues[0].{State:state,Status:status}'

# 应该看到:
# State: ENABLED
# Status: VALID
```

---

## 第五步: 创建 S3 存储桶

```bash
# 生成唯一的存储桶名称
BUCKET_NAME="galaxy-cloud-data-$(date +%s)"

# 创建存储桶
aws s3 mb s3://$BUCKET_NAME --region us-west-2

# 你的存储桶: galaxy-cloud-data-1760241377
```

**验证**:
```bash
aws s3 ls s3://galaxy-cloud-data-1760241377
```

---

## 第六步: 修复 Launch Template ⚠️ **关键问题!**

### 6.1 问题背景

**症状**: EC2 实例启动后立即终止

**诊断过程**:
1. 提交作业 → RUNNABLE 状态
2. Compute Environment 更新 DesiredCapacity → 1
3. ASG 启动 EC2 实例
4. 实例运行几秒后变成 `terminated` 状态
5. IAM Profile 显示 "未设置"

**根本原因**: AWS Batch 自动创建的 Launch Template **缺少 IamInstanceProfile 字段**

### 6.2 诊断步骤

```bash
# 1. 查找 Launch Template
LT_ID=$(aws ec2 describe-launch-templates \
  --filters "Name=tag:Name,Values=*galaxy-cloud*" \
  --query 'LaunchTemplates[0].LaunchTemplateId' \
  --output text)

echo "Launch Template ID: $LT_ID"

# 2. 检查配置
aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile'

# 如果输出为 null 或空，说明缺少 IamInstanceProfile
```

### 6.3 修复方法

```bash
# 1. 获取 Instance Profile ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile \
  --instance-profile-name ecsInstanceRole \
  --query 'InstanceProfile.Arn' \
  --output text)

# 2. 获取当前配置
CURRENT_CONFIG=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData')

# 3. 创建新版本（添加 IamInstanceProfile）
# 保存当前配置到文件
echo "$CURRENT_CONFIG" > /tmp/lt-config.json

# 手动编辑添加 IamInstanceProfile，或使用以下命令
cat > /tmp/lt-config-fixed.json <<EOF
{
  "IamInstanceProfile": {
    "Arn": "$INSTANCE_PROFILE_ARN"
  },
  "ImageId": "ami-xxxxxxxxx",
  "InstanceType": "optimal",
  "SecurityGroupIds": ["sg-xxxxxxxxx"],
  "UserData": "...",
  "TagSpecifications": [...]
}
EOF

# 4. 创建新版本
aws ec2 create-launch-template-version \
  --launch-template-id "$LT_ID" \
  --launch-template-data file:///tmp/lt-config-fixed.json

# 5. 获取新版本号
NEW_VERSION=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --query 'LaunchTemplateVersions[0].VersionNumber' \
  --output text)

# 6. 更新 ASG 使用新版本
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `galaxy-cloud`)].AutoScalingGroupName' \
  --output text)

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template LaunchTemplateId="$LT_ID",Version="$NEW_VERSION"
```

**或使用提供的脚本**:
```bash
bash lib/galaxy/galaxy-cloud-executor/scripts/fix_launch_template.sh
```

### 6.4 验证修复

```bash
# 1. 提交测试作业
# 2. 观察 EC2 实例
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*galaxy-cloud*" \
  --query 'Reservations[0].Instances[0].{State:State.Name,IamProfile:IamInstanceProfile.Arn}'

# 应该看到:
# State: running
# IamProfile: arn:aws:iam::399683337364:instance-profile/ecsInstanceRole

# 3. 检查 ECS 注册
aws ecs list-container-instances \
  --cluster <cluster-name> \
  --query 'containerInstanceArns'

# 应该能看到实例 ARN
```

---

## 第七步: 验证自动资源分配 ⚠️ **重要验证!**

### 7.1 理解 minvCpus=0 的工作流程

```
作业提交
  ↓
Job Queue: RUNNABLE 状态
  ↓
Compute Environment 检测到 RUNNABLE 作业
  ↓
更新 ASG DesiredCapacity: 0 → 1 (或更多)
  ↓
ASG 从 Launch Template 启动 EC2 实例
  ↓ (5-10 分钟)
EC2 实例启动，运行 ECS Agent
  ↓
ECS Agent 注册到 ECS Cluster
  ↓
AWS Batch 调度作业到实例
  ↓
作业状态: RUNNABLE → STARTING → RUNNING
  ↓
作业完成: RUNNING → SUCCEEDED
  ↓
空闲一段时间后
  ↓
ASG DesiredCapacity: 1 → 0
  ↓
EC2 实例终止
```

### 7.2 实时监控

**终端 1 - 监控 ASG**:
```bash
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, \"galaxy-cloud\")].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Current:Instances|length(@)}" \
  --output table'
```

**终端 2 - 监控作业**:
```bash
watch -n 5 'aws batch list-jobs \
  --job-queue galaxy-cloud-queue \
  --query "jobSummaryList[*].{ID:jobId,Status:status}" \
  --output table'
```

**终端 3 - 监控 EC2**:
```bash
watch -n 5 'aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*galaxy-cloud*" \
  --query "Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,Type:InstanceType}" \
  --output table'
```

### 7.3 问题排查

**问题 1: 作业一直停在 RUNNABLE**

**检查 1 - Compute Environment 状态**:
```bash
aws batch describe-compute-environments \
  --compute-environments galaxy-cloud-compute \
  --query 'computeEnvironments[0].{State:state,Status:status,Reason:statusReason}'
```

**检查 2 - ASG Activity History**:
```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name <asg-name> \
  --max-records 5 \
  --query 'Activities[*].{Time:StartTime,Status:StatusCode,Cause:Cause,Message:StatusMessage}'
```

**检查 3 - Launch Template**:
```bash
# 验证包含 IamInstanceProfile
aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile'
```

**问题 2: 实例类型不可用**

你遇到过: `m4.large` 在 `us-west-2d` 不可用

**解决方案**:
- AWS Batch 会自动重试其他可用区
- 或使用 `instanceTypes: ["optimal"]` 让 AWS 自动选择

---

## 第八步: 测试验证

### 8.1 简单作业测试

```bash
cd lib/galaxy/galaxy-cloud-executor
python3 testing/test_simple_job.py
```

**期望输出**:
```
✅ 作业提交成功: job-id-xxx
✅ 作业状态: SUCCEEDED
✅ 日志检索成功
```

### 8.2 2步 Workflow 测试

```bash
# 设置 Job Role ARN
export AWS_BATCH_JOB_ROLE_ARN="arn:aws:iam::399683337364:role/BatchJobRole"

# 运行测试
python3 testing/test_workflow_simple.py
```

**期望输出**:
```
测试摘要:
✅ 2 步顺序 workflow 测试通过
✅ 作业依赖关系正确
✅ S3 数据传递成功
✅ 作业状态监控正常
```

**❌ 如果失败: 403 错误**
- 检查 `AWS_BATCH_JOB_ROLE_ARN` 是否设置
- 检查 BatchJobRole 是否有 S3 权限
- 检查 Job Definition 是否包含 `jobRoleArn`

---

## 关键问题总结

### 问题 1: Instance Profile 缺少角色 ✅

**错误**: `NoSuchEntity: Instance Profile ecsInstanceRole cannot be found`

**解决**:
```bash
aws iam add-role-to-instance-profile \
  --instance-profile-name ecsInstanceRole \
  --role-name ecsInstanceRole
```

### 问题 2: m4.large 在 us-west-2d 不可用 ✅

**错误**: `Your requested instance type (m4.large) is not supported in your requested Availability Zone (us-west-2d)`

**解决**: AWS Batch 自动重试其他 AZ，无需手动干预

### 问题 3: Launch Template 缺少 IAM Instance Profile ✅

**症状**: 实例启动后立即终止

**解决**: 运行 `fix_launch_template.sh`

### 问题 4: AWS 凭证过期 ✅

**错误**: `InvalidClientTokenId`

**解决**: `aws configure` 重新配置

### 问题 5: 容器 S3 访问被拒绝 ✅

**错误**: `403 Forbidden when calling HeadObject`

**解决**:
1. 创建 BatchJobRole
2. 添加 S3 权限
3. 在 Job Definition 中传递 `jobRoleArn`

### 问题 6: Galaxy UI 无法显示日志 ✅

**症状**: 作业完成但日志为空

**解决**: 修复 `galaxy_job_runner.py:360`
```python
# 修复前:
job_wrapper.finish("", "")

# 修复后:
job_wrapper.finish(result.stdout or "", result.stderr or "")
```

---

## 完整的验证清单

部署完成后，验证以下项目:

### IAM 角色
- [ ] ecsInstanceRole 存在
- [ ] Instance Profile 包含 ecsInstanceRole
- [ ] BatchJobRole 存在
- [ ] BatchJobRole 有 S3 访问策略
- [ ] awsBatchServiceRole 存在

### Compute Environment
- [ ] 状态: ENABLED
- [ ] 健康状态: VALID
- [ ] minvCpus: 0
- [ ] maxvCpus: 256

### Job Queue
- [ ] 状态: ENABLED
- [ ] 关联到 Compute Environment

### Launch Template
- [ ] 包含 IamInstanceProfile
- [ ] IamInstanceProfile ARN 正确

### S3 存储桶
- [ ] 存储桶可访问
- [ ] BatchJobRole 有读写权限

### 测试验证
- [ ] AWS 连接测试通过
- [ ] 单作业测试通过
- [ ] 2步 Workflow 测试通过
- [ ] 自动资源分配工作正常
- [ ] 日志可以检索

---

## 成本估算

### 当前配置成本 (minvCpus=0)

**计算成本**:
```
实例类型: m5.large (2 vCPUs, 8GB RAM)
定价: ~$0.096/hour (us-west-2)

示例: 运行 100 个作业/月
- 小型 (50个, 10分钟): 50 × 2 vCPUs × 0.17小时 × $0.048 = $0.82
- 中型 (30个, 1小时): 30 × 4 vCPUs × 1小时 × $0.048 = $5.76
- 大型 (20个, 2小时): 20 × 8 vCPUs × 2小时 × $0.048 = $15.36

月度计算成本: ~$22
```

**存储成本** (S3):
```
标准存储: $0.023/GB/月
临时数据 (平均 10GB): $0.23/月
数据传输 (100GB): $9/月

月度存储成本: ~$9.23
```

**日志成本** (CloudWatch):
```
日志摄取: $0.50/GB
日志存储 (7天): $0.03/GB/月

月度日志成本: ~$0.5
```

**总计**: ~$32/月

### 启用 Spot 实例后

计算成本降低 70%: $22 → $6.60

**新总计**: ~$16/月

---

## 下一步

1. **集成到 Galaxy**: 参考 [01-快速开始指南.md](01-快速开始指南.md)
2. **生产优化**: 参考 `../PRODUCTION_DEPLOYMENT_GUIDE.md`
3. **监控配置**: 设置 CloudWatch 告警

---

## 参考资料

### AWS 文档
- [AWS Batch 用户指南](https://docs.aws.amazon.com/batch/)
- [IAM 角色配置](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [Launch Template](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-templates.html)

### 脚本工具
- `scripts/create_aws_batch.sh` - 自动化创建
- `scripts/fix_launch_template.sh` - 修复 Launch Template
- `scripts/create_job_role.sh` - 创建 BatchJobRole
- `scripts/diagnose_batch.sh` - 完整诊断

---

**这份指南记录了你遇到的所有问题和解决方案！希望能帮助其他人避免同样的坑。** 🎯
