# Galaxy Cloud Executor 测试环境配置指南

## 🎯 测试层次

### 1. 本地测试（不需要云资源）
使用Mock执行器进行功能测试，无需任何云账号。

```bash
# 直接运行基础测试
python test_galaxy_cloud_executor.py
```

### 2. AWS云端测试
需要AWS账号和相关资源配置。

### 3. 完整生产测试
在真实云环境中测试完整的生物信息学工作流。

---

## ☁️ AWS测试环境配置

### 前置要求

1. **AWS账号**: 有效的AWS账号
2. **AWS CLI**: 安装并配置AWS CLI
3. **IAM权限**: 足够的IAM权限创建和管理资源

### 步骤1: 安装依赖

```bash
# 安装AWS SDK
pip install boto3

# 安装AWS CLI（如果未安装）
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 步骤2: 配置AWS凭证

```bash
# 配置AWS凭证
aws configure
# 输入:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: us-east-1
# Default output format: json

# 或者设置环境变量
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### 步骤3: 创建AWS Batch资源

#### 3.1 创建IAM角色

```bash
# 创建Batch服务角色
aws iam create-role --role-name AWSBatchServiceRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "batch.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }
        ]
    }'

# 附加策略
aws iam attach-role-policy --role-name AWSBatchServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole

# 创建ECS实例角色
aws iam create-role --role-name ecsInstanceRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }
        ]
    }'

aws iam attach-role-policy --role-name ecsInstanceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

# 创建实例配置文件
aws iam create-instance-profile --instance-profile-name ecsInstanceProfile
aws iam add-role-to-instance-profile --instance-profile-name ecsInstanceProfile \
    --role-name ecsInstanceRole
```

#### 3.2 创建计算环境

```bash
# 创建计算环境
aws batch create-compute-environment \
    --compute-environment-name galaxy-compute-env \
    --type MANAGED \
    --state ENABLED \
    --compute-resources type=EC2,minvCpus=0,maxvCpus=256,desiredvCpus=0,instanceTypes=optimal,ec2Configuration='[{imageType=ECS_AL2}]',subnets=subnet-12345678,securityGroupIds=sg-12345678,instanceRole=arn:aws:iam::123456789012:instance-profile/ecsInstanceProfile,bidPercentage=50,allocationStrategy=SPOT_CAPACITY_OPTIMIZED \
    --service-role arn:aws:iam::123456789012:role/AWSBatchServiceRole
```

#### 3.3 创建作业队列

```bash
# 创建作业队列
aws batch create-job-queue \
    --job-queue-name galaxy-compute-queue \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order order=1,computeEnvironment=galaxy-compute-env
```

#### 3.4 创建S3存储桶

```bash
# 创建S3存储桶
aws s3 mb s3://galaxy-cloud-executor-test-bucket

# 设置环境变量
export AWS_BATCH_QUEUE=galaxy-compute-queue
export AWS_S3_BUCKET=galaxy-cloud-executor-test-bucket
export AWS_REGION=us-east-1
```

### 步骤4: 验证配置

```bash
# 验证Batch队列
aws batch describe-job-queues --job-queues galaxy-compute-queue

# 验证S3存储桶
aws s3 ls s3://galaxy-cloud-executor-test-bucket

# 运行测试
python test_galaxy_cloud_executor.py
```

---

## 🐳 Docker镜像准备

### 生物信息学工具镜像

```bash
# 拉取常用的生物信息学Docker镜像
docker pull staphb/fastqc:latest
docker pull staphb/trimmomatic:latest
docker pull quay.io/biocontainers/star:2.7.10a--h9ee0642_0
docker pull quay.io/biocontainers/subread:2.0.1--hed695b0_0

# 推送到ECR（如果使用私有镜像）
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

docker tag staphb/fastqc:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/fastqc:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/fastqc:latest
```

---

## 🧪 测试场景

### 场景1: 基础功能测试

```bash
# 测试基础功能（Mock执行器）
python test_galaxy_cloud_executor.py
```

### 场景2: AWS云端测试

```bash
# 设置环境变量
export AWS_BATCH_QUEUE=galaxy-compute-queue
export AWS_S3_BUCKET=galaxy-cloud-executor-test-bucket
export AWS_REGION=us-east-1

# 运行AWS测试
python test_galaxy_cloud_executor.py
```

### 场景3: 完整Workflow测试

```bash
# 使用Mock执行器测试Workflow逻辑
export EXECUTOR_TYPE=mock
python test_real_workflow.py

# 使用AWS执行器测试真实Workflow
export EXECUTOR_TYPE=aws
export AWS_BATCH_QUEUE=galaxy-compute-queue
export AWS_S3_BUCKET=galaxy-cloud-executor-test-bucket
python test_real_workflow.py
```

---

## 💰 成本估算

### AWS Batch成本
- **Spot实例**: 最高节省90%成本
- **按需实例**: 按秒计费
- **存储成本**: S3标准存储

### 示例成本计算
```
# 一个中等规模的RNA-seq分析
- 质量控制: t3.medium (Spot) × 0.5小时 ≈ $0.01
- 序列修剪: c5.large (Spot) × 1小时 ≈ $0.02
- 序列比对: c5.2xlarge (Spot) × 2小时 ≈ $0.08
- 基因定量: m5.xlarge (Spot) × 0.5小时 ≈ $0.02
- S3存储: 50GB × 1天 ≈ $0.02

总计: 约 $0.15 每个样本
```

---

## ⚠️ 注意事项

### 安全考虑
1. **IAM权限**: 使用最小权限原则
2. **网络安全**: 配置适当的安全组
3. **数据加密**: 启用S3和EBS加密

### 成本控制
1. **Spot实例**: 优先使用Spot实例
2. **自动扩缩**: 配置自动扩缩容
3. **监控告警**: 设置成本告警

### 故障排除
1. **权限错误**: 检查IAM角色和策略
2. **网络错误**: 验证VPC和子网配置
3. **镜像错误**: 确认Docker镜像可访问

---

## 🚀 快速开始脚本

创建一键配置脚本：

```bash
#!/bin/bash
# quick_setup.sh - AWS Batch快速配置脚本

set -e

echo "🚀 开始配置AWS Batch环境..."

# 设置变量
REGION=${AWS_DEFAULT_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "📍 区域: $REGION"
echo "🆔 账号: $ACCOUNT_ID"

# 创建角色（如果不存在）
echo "🔐 创建IAM角色..."
./scripts/create_batch_roles.sh

# 创建计算环境
echo "💻 创建计算环境..."
./scripts/create_compute_environment.sh

# 创建作业队列
echo "📋 创建作业队列..."
./scripts/create_job_queue.sh

# 创建S3存储桶
echo "🗄️ 创建S3存储桶..."
aws s3 mb s3://galaxy-cloud-executor-test-bucket-$ACCOUNT_ID

echo "✅ AWS Batch环境配置完成！"
echo "🧪 现在可以运行测试: python test_galaxy_cloud_executor.py"
```

---

## 📞 获取帮助

如果遇到问题，可以：

1. **查看日志**: 检查CloudWatch日志
2. **AWS支持**: 使用AWS支持中心
3. **社区**: Galaxy社区论坛
4. **文档**: AWS Batch官方文档

---

这个配置指南涵盖了从本地测试到完整云端部署的全过程。建议先从Mock测试开始，确认功能正常后再配置云资源。