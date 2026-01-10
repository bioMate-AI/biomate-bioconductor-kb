#!/bin/bash
# 创建 ecsTaskExecutionRole 用于 AWS Batch

ROLE_NAME="ecsTaskExecutionRole"
REGION="us-west-2"

echo "Creating ECS Task Execution Role: $ROLE_NAME"

# 1. 创建信任策略文件
cat > /tmp/ecs-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 2. 创建角色
echo "Creating role..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
  --description "ECS Task Execution Role for AWS Batch" \
  --region "$REGION"

# 3. 附加 AWS 托管策略
echo "Attaching AmazonECSTaskExecutionRolePolicy..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
  --region "$REGION"

# 4. 附加 ECR 访问权限
echo "Attaching AmazonEC2ContainerRegistryReadOnly..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" \
  --region "$REGION"

# 5. 附加 CloudWatch Logs 权限
echo "Attaching CloudWatchLogsFullAccess..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" \
  --region "$REGION"

echo ""
echo "✅ Role created successfully!"
echo "ARN: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$ROLE_NAME"

# 清理
rm /tmp/ecs-trust-policy.json
