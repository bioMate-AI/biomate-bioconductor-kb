#!/bin/bash
# 创建支持 Docker-in-Docker 的 EC2 计算环境

REGION="us-west-2"
COMPUTE_ENV_NAME="galaxy-cloud-compute-ec2-dind"
LAUNCH_TEMPLATE_NAME="galaxy-batch-dind-template"
SERVICE_ROLE="arn:aws:iam::399683337364:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch"
INSTANCE_ROLE="arn:aws:iam::399683337364:instance-profile/ecsInstanceRole"

echo "=========================================="
echo "创建支持 Docker-in-Docker 的 EC2 计算环境"
echo "=========================================="

# 1. 获取默认 VPC 和子网
echo "获取 VPC 和子网信息..."
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
SECURITY_GROUP=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text)

echo "VPC: $VPC_ID"
echo "Subnets: $SUBNET_IDS"
echo "Security Group: $SECURITY_GROUP"

# 2. 创建计算环境
echo ""
echo "创建 EC2 计算环境..."

aws batch create-compute-environment \
    --compute-environment-name "$COMPUTE_ENV_NAME" \
    --region "$REGION" \
    --type MANAGED \
    --state ENABLED \
    --compute-resources "{
        \"type\": \"EC2\",
        \"allocationStrategy\": \"BEST_FIT_PROGRESSIVE\",
        \"minvCpus\": 0,
        \"maxvCpus\": 16,
        \"desiredvCpus\": 0,
        \"instanceTypes\": [\"optimal\"],
        \"subnets\": [\"$(echo $SUBNET_IDS | tr ',' '","')\"],
        \"securityGroupIds\": [\"$SECURITY_GROUP\"],
        \"instanceRole\": \"$INSTANCE_ROLE\",
        \"launchTemplate\": {
            \"launchTemplateName\": \"$LAUNCH_TEMPLATE_NAME\"
        },
        \"tags\": {
            \"Name\": \"galaxy-batch-dind-instance\",
            \"Purpose\": \"Docker-in-Docker support\"
        }
    }" \
    --service-role "$SERVICE_ROLE"

if [ $? -eq 0 ]; then
    echo "✓ 计算环境创建成功: $COMPUTE_ENV_NAME"
else
    echo "✗ 创建失败，请检查错误信息"
    exit 1
fi

# 3. 更新作业队列使用新的计算环境
echo ""
echo "更新作业队列..."
echo "请手动更新作业队列 'galaxy-cloud-queue' 来使用计算环境: $COMPUTE_ENV_NAME"
echo ""
echo "或运行："
echo "aws batch update-job-queue \\"
echo "    --job-queue galaxy-cloud-queue \\"
echo "    --region $REGION \\"
echo "    --compute-environment-order order=1,computeEnvironment=$COMPUTE_ENV_NAME"

echo ""
echo "=========================================="
echo "完成！"
echo "=========================================="
echo "新计算环境: $COMPUTE_ENV_NAME"
echo "支持 Docker-in-Docker: 是"
echo ""
echo "下一步："
echo "1. 等待计算环境状态变为 VALID (可能需要几分钟)"
echo "2. 更新作业队列使用新的计算环境"
echo "3. 在 config/job_conf_cloud.yml 中设置 use_fetch_and_run: \"true\""
echo "4. 重启 Galaxy 并测试"
