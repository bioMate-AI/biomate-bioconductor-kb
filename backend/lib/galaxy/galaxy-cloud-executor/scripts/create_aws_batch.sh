#!/bin/bash
# 保存为 create_aws_batch_v2.sh

set -e  # 出错时退出

echo "======================================"
echo "创建 Galaxy Cloud Executor AWS Batch 基础设施"
echo "======================================"

# 配置变量
REGION="us-west-2"
COMPUTE_ENV_NAME="galaxy-cloud-compute"
JOB_QUEUE_NAME="galaxy-cloud-queue"
S3_BUCKET="galaxy-cloud-data-$(date +%s)"

echo "区域: $REGION"
echo "计算环境: $COMPUTE_ENV_NAME"
echo "作业队列: $JOB_QUEUE_NAME"
echo "S3 桶: $S3_BUCKET"
echo ""

# 步骤 1: 创建 S3 桶
echo "步骤 1: 创建 S3 桶..."
if aws s3 ls "s3://${S3_BUCKET}" 2>/dev/null; then
    echo "✅ S3 桶已存在: s3://${S3_BUCKET}"
else
    aws s3 mb s3://${S3_BUCKET} --region ${REGION}
    echo "✅ S3 桶创建成功: s3://${S3_BUCKET}"
fi
echo ""

# 步骤 2: 获取默认 VPC 和子网
echo "步骤 2: 获取 VPC 和子网信息..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region ${REGION})

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[*].SubnetId' \
  --output text \
  --region ${REGION} | tr '\t' ',')

SECURITY_GROUP=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region ${REGION})

echo "VPC: $VPC_ID"
echo "子网: $SUBNET_IDS"
echo "安全组: $SECURITY_GROUP"
echo ""

# 步骤 3: 创建或验证 IAM 角色
echo "步骤 3: 创建 IAM 角色..."

# 3.1 创建 ECS 实例角色（如果不存在）
if aws iam get-role --role-name ecsInstanceRole &>/dev/null; then
    echo "✅ ecsInstanceRole 已存在"
else
    echo "创建 ecsInstanceRole..."
    
    # 创建信任策略
    cat > /tmp/ecs-instance-role-trust.json <<EOF
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
      --assume-role-policy-document file:///tmp/ecs-instance-role-trust.json

    # 附加策略
    aws iam attach-role-policy \
      --role-name ecsInstanceRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

    aws iam attach-role-policy \
      --role-name ecsInstanceRole \
      --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

    echo "✅ ecsInstanceRole 创建成功"
fi

# 3.2 创建实例配置文件（关键修复！）
if aws iam get-instance-profile --instance-profile-name ecsInstanceRole &>/dev/null; then
    echo "✅ 实例配置文件已存在"
else
    echo "创建实例配置文件..."
    
    # 创建实例配置文件
    aws iam create-instance-profile \
      --instance-profile-name ecsInstanceRole

    # 将角色添加到实例配置文件
    aws iam add-role-to-instance-profile \
      --instance-profile-name ecsInstanceRole \
      --role-name ecsInstanceRole

    echo "✅ 实例配置文件创建成功"
    
    # 等待角色传播
    echo "等待 IAM 配置传播（15秒）..."
    sleep 15
fi

# 获取实例配置文件 ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile \
  --instance-profile-name ecsInstanceRole \
  --query 'InstanceProfile.Arn' \
  --output text)

echo "实例配置文件 ARN: $INSTANCE_PROFILE_ARN"
echo ""

# 3.3 创建 Batch 服务角色（如果不存在）
if aws iam get-role --role-name AWSBatchServiceRole &>/dev/null; then
    echo "✅ AWSBatchServiceRole 已存在"
else
    echo "创建 AWSBatchServiceRole..."
    
    cat > /tmp/batch-service-role-trust.json <<EOF
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

    aws iam create-role \
      --role-name AWSBatchServiceRole \
      --assume-role-policy-document file:///tmp/batch-service-role-trust.json

    aws iam attach-role-policy \
      --role-name AWSBatchServiceRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole

    echo "✅ AWSBatchServiceRole 创建成功"
    sleep 5
fi

SERVICE_ROLE_ARN=$(aws iam get-role \
  --role-name AWSBatchServiceRole \
  --query 'Role.Arn' \
  --output text)

echo "服务角色 ARN: $SERVICE_ROLE_ARN"
echo ""

# 步骤 4: 创建计算环境
echo "步骤 4: 创建计算环境..."

# 检查是否已存在
if aws batch describe-compute-environments \
  --compute-environments ${COMPUTE_ENV_NAME} \
  --region ${REGION} \
  --query 'computeEnvironments[0]' 2>/dev/null | grep -q computeEnvironmentName; then
    echo "✅ 计算环境已存在"
else
    echo "创建计算环境..."
    
    aws batch create-compute-environment \
      --compute-environment-name ${COMPUTE_ENV_NAME} \
      --type MANAGED \
      --state ENABLED \
      --service-role ${SERVICE_ROLE_ARN} \
      --compute-resources \
        type=EC2,\
minvCpus=0,\
maxvCpus=256,\
desiredvCpus=0,\
instanceTypes=optimal,\
subnets=${SUBNET_IDS},\
securityGroupIds=${SECURITY_GROUP},\
instanceRole=${INSTANCE_PROFILE_ARN} \
      --region ${REGION}

    echo "✅ 计算环境创建请求已提交"
fi

echo "等待计算环境变为 VALID..."

# 等待计算环境变为 VALID
MAX_WAIT=300
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STATUS=$(aws batch describe-compute-environments \
      --compute-environments ${COMPUTE_ENV_NAME} \
      --query 'computeEnvironments[0].status' \
      --output text \
      --region ${REGION} 2>/dev/null || echo "CREATING")
    
    if [ "$STATUS" == "VALID" ]; then
        echo "✅ 计算环境已就绪 (状态: VALID)"
        break
    fi
    
    echo "   等待中... 状态: $STATUS ($WAITED 秒)"
    sleep 10
    WAITED=$((WAITED + 10))
done

if [ "$STATUS" != "VALID" ]; then
    echo "❌ 计算环境创建超时或失败"
    echo "当前状态: $STATUS"
    
    # 显示错误信息
    echo "错误详情:"
    aws batch describe-compute-environments \
      --compute-environments ${COMPUTE_ENV_NAME} \
      --query 'computeEnvironments[0].statusReason' \
      --output text \
      --region ${REGION}
    
    exit 1
fi
echo ""

# 获取计算环境 ARN
COMPUTE_ENV_ARN=$(aws batch describe-compute-environments \
  --compute-environments ${COMPUTE_ENV_NAME} \
  --query 'computeEnvironments[0].computeEnvironmentArn' \
  --output text \
  --region ${REGION})

echo "计算环境 ARN: $COMPUTE_ENV_ARN"
echo ""

# 步骤 5: 创建作业队列
echo "步骤 5: 创建作业队列..."

# 检查是否已存在
if aws batch describe-job-queues \
  --job-queues ${JOB_QUEUE_NAME} \
  --region ${REGION} \
  --query 'jobQueues[0]' 2>/dev/null | grep -q jobQueueName; then
    echo "✅ 作业队列已存在"
else
    echo "创建作业队列..."
    
    aws batch create-job-queue \
      --job-queue-name ${JOB_QUEUE_NAME} \
      --state ENABLED \
      --priority 1 \
      --compute-environment-order order=1,computeEnvironment=${COMPUTE_ENV_ARN} \
      --region ${REGION}

    echo "✅ 作业队列创建请求已提交"
fi

echo "等待作业队列变为 VALID..."

# 等待作业队列变为 VALID
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STATUS=$(aws batch describe-job-queues \
      --job-queues ${JOB_QUEUE_NAME} \
      --query 'jobQueues[0].status' \
      --output text \
      --region ${REGION} 2>/dev/null || echo "CREATING")
    
    if [ "$STATUS" == "VALID" ]; then
        echo "✅ 作业队列已就绪 (状态: VALID)"
        break
    fi
    
    echo "   等待中... 状态: $STATUS ($WAITED 秒)"
    sleep 5
    WAITED=$((WAITED + 5))
done

if [ "$STATUS" != "VALID" ]; then
    echo "❌ 作业队列创建超时或失败"
    echo "当前状态: $STATUS"
    exit 1
fi
echo ""

# 步骤 6: 保存配置
echo "步骤 6: 保存配置..."

cat > aws_batch_config.env <<EOF
# AWS Batch 配置
# 创建时间: $(date)

export AWS_DEFAULT_REGION="${REGION}"
export AWS_BATCH_QUEUE="${JOB_QUEUE_NAME}"
export AWS_S3_BUCKET="${S3_BUCKET}"

# 资源 ARN
export COMPUTE_ENV_ARN="${COMPUTE_ENV_ARN}"
export SERVICE_ROLE_ARN="${SERVICE_ROLE_ARN}"
export INSTANCE_PROFILE_ARN="${INSTANCE_PROFILE_ARN}"
EOF

echo "✅ 配置已保存到: aws_batch_config.env"
echo ""

# 步骤 7: 显示摘要
echo "======================================"
echo "✅ 创建完成！"
echo "======================================"
echo ""
echo "资源摘要:"
echo "- 区域: ${REGION}"
echo "- 计算环境: ${COMPUTE_ENV_NAME}"
echo "- 作业队列: ${JOB_QUEUE_NAME}"
echo "- S3 桶: ${S3_BUCKET}"
echo ""
echo "下一步操作:"
echo ""
echo "1. 加载配置:"
echo "   source aws_batch_config.env"
echo ""
echo "2. 测试连接:"
echo "   cd .."
echo "   python3 testing/test_aws_connection.py"
echo ""
echo "3. 运行云测试:"
echo "   python3 testing/test_aws_cloud_executor.py"
echo ""
echo "4. 更新配置文件 (config/aws_cloud_config.yaml):"
echo "   batch_queue: \"${JOB_QUEUE_NAME}\""
echo "   s3_bucket: \"${S3_BUCKET}\""
echo "   region: \"${REGION}\""
echo ""
