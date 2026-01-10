# Galaxy服务认证设置指南

## 生产环境推荐方案

### 方案A：IAM服务用户 (推荐)

1. **创建专用IAM用户**：
```bash
# 创建服务用户
aws iam create-user --user-name galaxy-cloud-service

# 创建访问密钥
aws iam create-access-key --user-name galaxy-cloud-service
```

2. **创建服务策略**：
```bash
# 创建策略文件
cat > galaxy-service-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "batch:*",
                "s3:GetObject",
                "s3:PutObject", 
                "s3:DeleteObject",
                "s3:ListBucket",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": [
                "arn:aws:batch:us-west-2:399683337364:*",
                "arn:aws:s3:::galaxy-cloud-data-1760241377",
                "arn:aws:s3:::galaxy-cloud-data-1760241377/*",
                "arn:aws:logs:us-west-2:399683337364:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "arn:aws:iam::399683337364:role/BatchJobRole"
        }
    ]
}
EOF

# 创建策略
aws iam create-policy \
    --policy-name GalaxyCloudServicePolicy \
    --policy-document file://galaxy-service-policy.json

# 附加策略到用户
aws iam attach-user-policy \
    --user-name galaxy-cloud-service \
    --policy-arn arn:aws:iam::399683337364:policy/GalaxyCloudServicePolicy
```

### 方案B：AssumeRole (更安全)

1. **创建服务角色**：
```bash
# 创建信任策略
cat > galaxy-service-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::399683337364:user/galaxy-cloud-service"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "galaxy-service-unique-id"
                }
            }
        }
    ]
}
EOF

# 创建角色
aws iam create-role \
    --role-name GalaxyCloudServiceRole \
    --assume-role-policy-document file://galaxy-service-trust-policy.json

# 附加策略到角色
aws iam attach-role-policy \
    --role-name GalaxyCloudServiceRole \
    --policy-arn arn:aws:iam::399683337364:policy/GalaxyCloudServicePolicy
```

## 环境变量配置

### 方案A - 直接访问密钥：
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="xxx..."
export AWS_DEFAULT_REGION="us-west-2"
```

### 方案B - AssumeRole：
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="xxx..."
export AWS_DEFAULT_REGION="us-west-2"
export GALAXY_SERVICE_ROLE_ARN="arn:aws:iam::399683337364:role/GalaxyCloudServiceRole"
export GALAXY_SERVICE_EXTERNAL_ID="galaxy-service-unique-id"
```

## 安全最佳实践

1. **密钥轮换**：定期轮换访问密钥
2. **最小权限**：只授予必需的权限
3. **密钥保护**：
   - 使用环境变量，不要硬编码
   - 考虑使用AWS Secrets Manager
   - 容器化部署时使用secrets

## 生产部署建议

### Docker环境：
```dockerfile
# Dockerfile
FROM python:3.8
COPY . /app
WORKDIR /app

# 不在镜像中包含密钥
# 运行时通过环境变量注入
```

### Docker Compose：
```yaml
version: '3.8'
services:
  galaxy-cloud:
    build: .
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_DEFAULT_REGION=us-west-2
    env_file:
      - .env.production  # 不要提交到版本控制
```

### Kubernetes：
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
type: Opaque
data:
  AWS_ACCESS_KEY_ID: <base64-encoded>
  AWS_SECRET_ACCESS_KEY: <base64-encoded>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: galaxy-cloud
spec:
  template:
    spec:
      containers:
      - name: galaxy
        envFrom:
        - secretRef:
            name: aws-credentials
```