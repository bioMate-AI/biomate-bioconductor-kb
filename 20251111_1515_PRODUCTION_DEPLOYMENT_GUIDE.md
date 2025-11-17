# BioMate AI Production Deployment Guide
**Date:** 2025-11-11
**Version:** 1.0
**Status:** Production Ready
**Target Environment:** AWS (Ubuntu 22.04 LTS)

---

## Table of Contents

1. [Pre-Deployment Checklist](#1-pre-deployment-checklist)
2. [AWS Infrastructure Setup](#2-aws-infrastructure-setup)
3. [Server Provisioning](#3-server-provisioning)
4. [Database Setup](#4-database-setup)
5. [Application Deployment](#5-application-deployment)
6. [Security Configuration](#6-security-configuration)
7. [Monitoring Setup](#7-monitoring-setup)
8. [Post-Deployment Verification](#8-post-deployment-verification)
9. [Troubleshooting](#9-troubleshooting)
10. [Rollback Procedures](#10-rollback-procedures)

---

## 1. Pre-Deployment Checklist

### Required Before Starting

- [ ] AWS account with admin access
- [ ] Domain name registered (biomate.ai)
- [ ] DNS access to configure A/AAAA records
- [ ] GitHub repository access
- [ ] API keys: Anthropic, OpenAI
- [ ] Production secrets generated (see section 6.1)
- [ ] Business Associate Agreements executed
- [ ] Production readiness checklist 90%+ complete

### Required Tools

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-west-2), Output (json)

# Install other tools
sudo apt update
sudo apt install -y git jq postgresql-client redis-tools
```

### Estimated Timeline

- **Infrastructure Setup:** 2-3 hours
- **Server Configuration:** 2-4 hours
- **Application Deployment:** 1-2 hours
- **Security & Monitoring:** 2-3 hours
- **Testing & Verification:** 2-3 hours
- **Total:** 9-15 hours (can be parallelized)

---

## 2. AWS Infrastructure Setup

### 2.1 VPC Configuration

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=biomate-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=biomate-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# Attach IGW to VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID

# Create subnets (public and private in 2 AZs)
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-west-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=biomate-public-1}]' \
  --query 'Subnet.SubnetId' \
  --output text)

PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-west-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=biomate-public-2}]' \
  --query 'Subnet.SubnetId' \
  --output text)

PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.11.0/24 \
  --availability-zone us-west-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=biomate-private-1}]' \
  --query 'Subnet.SubnetId' \
  --output text)

PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.12.0/24 \
  --availability-zone us-west-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=biomate-private-2}]' \
  --query 'Subnet.SubnetId' \
  --output text)

# Create route table for public subnets
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=biomate-public-rt}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Add route to IGW
aws ec2 create-route \
  --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate public subnets with route table
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1 --route-table-id $RTB_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_2 --route-table-id $RTB_ID

echo "VPC setup complete!"
echo "VPC ID: $VPC_ID"
echo "Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo "Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
```

### 2.2 Security Groups

```bash
# Application Server Security Group
APP_SG=$(aws ec2 create-security-group \
  --group-name biomate-app-sg \
  --description "Security group for BioMate application servers" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Allow HTTPS from internet
aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow HTTP (for Let's Encrypt)
aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow SSH from bastion only (replace with bastion IP later)
aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG \
  --protocol tcp \
  --port 22 \
  --cidr 10.0.0.0/16

# Database Security Group
DB_SG=$(aws ec2 create-security-group \
  --group-name biomate-db-sg \
  --description "Security group for RDS PostgreSQL" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Allow PostgreSQL from app servers only
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $APP_SG

# Redis Security Group
REDIS_SG=$(aws ec2 create-security-group \
  --group-name biomate-redis-sg \
  --description "Security group for Redis ElastiCache" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Allow Redis from app servers only
aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG \
  --protocol tcp \
  --port 6379 \
  --source-group $APP_SG

echo "Security Groups created:"
echo "App SG: $APP_SG"
echo "DB SG: $DB_SG"
echo "Redis SG: $REDIS_SG"
```

### 2.3 RDS PostgreSQL Setup

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name biomate-db-subnet-group \
  --db-subnet-group-description "Subnet group for BioMate RDS" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --tags Key=Name,Value=biomate-db-subnet-group

# Create RDS instance (PostgreSQL 15)
aws rds create-db-instance \
  --db-instance-identifier biomate-prod-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.4 \
  --master-username biomateadmin \
  --master-user-password "$(openssl rand -base64 32)" \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --kms-key-id alias/aws/rds \
  --vpc-security-group-ids $DB_SG \
  --db-subnet-group-name biomate-db-subnet-group \
  --backup-retention-period 30 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "sun:04:00-sun:05:00" \
  --multi-az \
  --publicly-accessible false \
  --enable-cloudwatch-logs-exports '["postgresql","upgrade"]' \
  --deletion-protection \
  --tags Key=Name,Value=biomate-prod-db Key=Environment,Value=production

echo "RDS instance creation initiated (will take 10-15 minutes)"
echo "Monitor status: aws rds describe-db-instances --db-instance-identifier biomate-prod-db"

# Wait for RDS to be available
aws rds wait db-instance-available --db-instance-identifier biomate-prod-db

# Get RDS endpoint
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier biomate-prod-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "RDS Endpoint: $DB_ENDPOINT"
```

### 2.4 ElastiCache Redis Setup

```bash
# Create ElastiCache subnet group
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name biomate-redis-subnet-group \
  --cache-subnet-group-description "Subnet group for BioMate Redis" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2

# Create Redis replication group (cluster mode disabled)
aws elasticache create-replication-group \
  --replication-group-id biomate-prod-redis \
  --replication-group-description "BioMate production Redis" \
  --engine redis \
  --engine-version 7.0 \
  --cache-node-type cache.t3.medium \
  --num-cache-clusters 2 \
  --automatic-failover-enabled \
  --multi-az-enabled \
  --cache-subnet-group-name biomate-redis-subnet-group \
  --security-group-ids $REDIS_SG \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token "$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)" \
  --snapshot-retention-limit 7 \
  --snapshot-window "02:00-03:00" \
  --preferred-maintenance-window "sun:03:00-sun:04:00" \
  --tags Key=Name,Value=biomate-prod-redis Key=Environment,Value=production

echo "Redis creation initiated (will take 10-15 minutes)"

# Wait for Redis to be available
aws elasticache wait replication-group-available --replication-group-id biomate-prod-redis

# Get Redis endpoint
REDIS_ENDPOINT=$(aws elasticache describe-replication-groups \
  --replication-group-id biomate-prod-redis \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' \
  --output text)

echo "Redis Endpoint: $REDIS_ENDPOINT"
```

### 2.5 S3 Buckets

```bash
# Create S3 bucket for file uploads
aws s3api create-bucket \
  --bucket biomate-prod-uploads \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket biomate-prod-uploads \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket biomate-prod-uploads \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket biomate-prod-uploads \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable access logging
aws s3api create-bucket \
  --bucket biomate-prod-logs \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

aws s3api put-bucket-logging \
  --bucket biomate-prod-uploads \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "biomate-prod-logs",
      "TargetPrefix": "uploads/"
    }
  }'

# Create backup bucket
aws s3api create-bucket \
  --bucket biomate-prod-backups \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

aws s3api put-bucket-versioning \
  --bucket biomate-prod-backups \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket biomate-prod-backups \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Lifecycle policy for backups (move to Glacier after 30 days)
aws s3api put-bucket-lifecycle-configuration \
  --bucket biomate-prod-backups \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "archive-old-backups",
      "Status": "Enabled",
      "Transitions": [{
        "Days": 30,
        "StorageClass": "GLACIER"
      }],
      "Expiration": {
        "Days": 2555
      }
    }]
  }'

echo "S3 buckets created:"
echo "- biomate-prod-uploads"
echo "- biomate-prod-backups"
echo "- biomate-prod-logs"
```

### 2.6 AWS Secrets Manager

```bash
# Store database credentials
aws secretsmanager create-secret \
  --name biomate/prod/database \
  --description "BioMate production database credentials" \
  --secret-string "{
    \"host\": \"$DB_ENDPOINT\",
    \"port\": \"5432\",
    \"database\": \"biomate\",
    \"username\": \"biomateadmin\",
    \"password\": \"REPLACE_WITH_ACTUAL_PASSWORD\"
  }" \
  --kms-key-id alias/aws/secretsmanager

# Store Redis credentials
aws secretsmanager create-secret \
  --name biomate/prod/redis \
  --description "BioMate production Redis credentials" \
  --secret-string "{
    \"host\": \"$REDIS_ENDPOINT\",
    \"port\": \"6379\",
    \"auth_token\": \"REPLACE_WITH_ACTUAL_TOKEN\"
  }"

# Store application secrets
aws secretsmanager create-secret \
  --name biomate/prod/app-secrets \
  --description "BioMate production application secrets" \
  --secret-string "{
    \"jwt_secret\": \"$(openssl rand -base64 64)\",
    \"session_secret\": \"$(openssl rand -base64 64)\",
    \"encryption_key\": \"$(openssl rand -base64 32)\",
    \"csrf_secret\": \"$(openssl rand -base64 32)\"
  }"

# Store API keys
aws secretsmanager create-secret \
  --name biomate/prod/api-keys \
  --description "BioMate production API keys" \
  --secret-string "{
    \"anthropic_api_key\": \"REPLACE_WITH_KEY\",
    \"openai_api_key\": \"REPLACE_WITH_KEY\"
  }"

echo "Secrets created in AWS Secrets Manager"
echo "IMPORTANT: Update placeholder values with actual credentials"
```

### 2.7 CloudWatch Log Groups

```bash
# Create log groups with 6-year retention (2555 days for HIPAA)
for log_group in \
  "/biomate/production/nginx/access" \
  "/biomate/production/nginx/error" \
  "/biomate/production/backend/access" \
  "/biomate/production/backend/error" \
  "/biomate/production/audit" \
  "/biomate/production/security" \
  "/biomate/production/backup"; do

  aws logs create-log-group --log-group-name "$log_group"
  aws logs put-retention-policy \
    --log-group-name "$log_group" \
    --retention-in-days 2555

  echo "Created log group: $log_group"
done
```

---

## 3. Server Provisioning

### 3.1 Launch EC2 Instance

```bash
# Create IAM role for EC2 (with CloudWatch and Secrets Manager access)
aws iam create-role \
  --role-name biomate-ec2-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach policies
aws iam attach-role-policy \
  --role-name biomate-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

aws iam attach-role-policy \
  --role-name biomate-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

aws iam attach-role-policy \
  --role-name biomate-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name biomate-ec2-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name biomate-ec2-profile \
  --role-name biomate-ec2-role

# Launch EC2 instance (Ubuntu 22.04 LTS)
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c2ab3b8efb09f272 \
  --instance-type t3.xlarge \
  --key-name biomate-prod-key \
  --security-group-ids $APP_SG \
  --subnet-id $PUBLIC_SUBNET_1 \
  --iam-instance-profile Name=biomate-ec2-profile \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 100,
        "VolumeType": "gp3",
        "Encrypted": true,
        "DeleteOnTermination": false
      }
    }
  ]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=biomate-prod-app}]' \
  --user-data file://user-data.sh \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Instance running at: $PUBLIC_IP"
```

### 3.2 DNS Configuration

```bash
# Create A record pointing to EC2 public IP
# (This is done via your DNS provider's console or CLI)

echo "Configure DNS:"
echo "A Record: biomate.ai -> $PUBLIC_IP"
echo "A Record: www.biomate.ai -> $PUBLIC_IP"
echo ""
echo "Wait for DNS propagation (5-30 minutes)"
echo "Test: dig biomate.ai +short"
```

### 3.3 Initial Server Setup

SSH into the server:

```bash
ssh -i ~/.ssh/biomate-prod-key.pem ubuntu@$PUBLIC_IP
```

Run initial setup:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y \
  git curl wget vim htop \
  build-essential \
  python3 python3-pip python3-venv \
  postgresql-client \
  redis-tools \
  nginx \
  certbot python3-certbot-nginx \
  ufw fail2ban \
  unzip jq

# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb

# Create biomate user
sudo useradd -m -s /bin/bash biomate
sudo usermod -aG sudo biomate

# Create directory structure
sudo mkdir -p /home/biomate/{logs,backups,uploads}
sudo chown -R biomate:biomate /home/biomate
sudo chmod 750 /home/biomate

# Configure firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

echo "Initial server setup complete"
```

### 3.4 OS Hardening

```bash
# Disable root login
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password authentication
sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Configure fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Set automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Restart SSH
sudo systemctl restart sshd

echo "OS hardening complete"
```

---

## 4. Database Setup

### 4.1 Initialize Database

```bash
# Get database password from Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id biomate/prod/database \
  --query 'SecretString' \
  --output text | jq -r '.password')

DB_HOST=$(aws secretsmanager get-secret-value \
  --secret-id biomate/prod/database \
  --query 'SecretString' \
  --output text | jq -r '.host')

# Create database
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U biomateadmin -d postgres -c "CREATE DATABASE biomate;"

# Create application user
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U biomateadmin -d postgres <<EOF
CREATE USER biomate_app WITH PASSWORD '$(openssl rand -base64 32)';
GRANT ALL PRIVILEGES ON DATABASE biomate TO biomate_app;
\c biomate
GRANT ALL PRIVILEGES ON SCHEMA public TO biomate_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO biomate_app;
EOF

echo "Database initialized"
```

### 4.2 Run Migrations

```bash
# This will be done after application deployment
# Using Galaxy's database migration tools
```

---

## 5. Application Deployment

### 5.1 Clone Repository

```bash
# Switch to biomate user
sudo su - biomate

# Clone repository
cd /home/biomate
git clone https://github.com/your-org/biomate.git
cd biomate

# Checkout production branch or tag
git checkout v1.0.0  # or production branch

echo "Repository cloned"
```

### 5.2 Configure Environment Variables

```bash
# Fetch secrets from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id biomate/prod/database \
  --query 'SecretString' \
  --output text > /tmp/db-secrets.json

aws secretsmanager get-secret-value \
  --secret-id biomate/prod/redis \
  --query 'SecretString' \
  --output text > /tmp/redis-secrets.json

aws secretsmanager get-secret-value \
  --secret-id biomate/prod/app-secrets \
  --query 'SecretString' \
  --output text > /tmp/app-secrets.json

aws secretsmanager get-secret-value \
  --secret-id biomate/prod/api-keys \
  --query 'SecretString' \
  --output text > /tmp/api-keys.json

# Create .env.production from template
cp .env.production.template .env.production

# Populate from secrets (example for key variables)
cat > .env.production <<EOF
# Node Environment
NODE_ENV=production
PORT=5000

# Database
DB_HOST=$(jq -r '.host' /tmp/db-secrets.json)
DB_PORT=5432
DB_NAME=biomate
DB_USER=$(jq -r '.username' /tmp/db-secrets.json)
DB_PASSWORD=$(jq -r '.password' /tmp/db-secrets.json)
DB_SSL=true
DB_SSL_REJECT_UNAUTHORIZED=true

# Redis
REDIS_HOST=$(jq -r '.host' /tmp/redis-secrets.json)
REDIS_PORT=6379
REDIS_PASSWORD=$(jq -r '.auth_token' /tmp/redis-secrets.json)
REDIS_TLS=true

# Security
JWT_SECRET=$(jq -r '.jwt_secret' /tmp/app-secrets.json)
SESSION_SECRET=$(jq -r '.session_secret' /tmp/app-secrets.json)
ENCRYPTION_KEY=$(jq -r '.encryption_key' /tmp/app-secrets.json)
CSRF_SECRET=$(jq -r '.csrf_secret' /tmp/app-secrets.json)

# API Keys
ANTHROPIC_API_KEY=$(jq -r '.anthropic_api_key' /tmp/api-keys.json)
OPENAI_API_KEY=$(jq -r '.openai_api_key' /tmp/api-keys.json)

# AWS
AWS_REGION=us-west-2
AWS_S3_BUCKET=biomate-prod-uploads
AWS_S3_BACKUP_BUCKET=biomate-prod-backups

# Application
BASE_URL=https://biomate.ai
FRONTEND_URL=https://biomate.ai
BACKEND_URL=https://biomate.ai/galaxy

# Monitoring
ENABLE_CLOUDWATCH=true
ENABLE_AUDIT_LOGGING=true
LOG_LEVEL=info

# Security Settings
SESSION_TIMEOUT=900
MAX_UPLOAD_SIZE=524288000
RATE_LIMIT_WINDOW=60000
RATE_LIMIT_MAX=100

# HIPAA Compliance
HIPAA_COMPLIANT=true
PHI_ENCRYPTION_ENABLED=true
AUDIT_LOG_RETENTION_DAYS=2555

# Galaxy Configuration
GALAXY_CONFIG_FILE=/home/biomate/biomate/backend/config/galaxy.yml
GALAXY_ROOT=/home/biomate/biomate/backend
GALAXY_VIRTUAL_ENV=/home/biomate/biomate/backend/.venv
EOF

# Secure permissions
chmod 600 .env.production

# Clean up temporary files
shred -u /tmp/db-secrets.json /tmp/redis-secrets.json /tmp/app-secrets.json /tmp/api-keys.json

echo "Environment configured"
```

### 5.3 Install Dependencies

```bash
# Frontend dependencies
cd /home/biomate/biomate/frontend
npm ci --production

# Backend dependencies (Galaxy)
cd /home/biomate/biomate/backend
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Build frontend (if needed)
cd /home/biomate/biomate/frontend
npm run build

echo "Dependencies installed"
```

### 5.4 Database Migration

```bash
# Run Galaxy database migrations
cd /home/biomate/biomate/backend
source .venv/bin/activate

# Create database schema
python scripts/create_db.py

# Run migrations
sh manage_db.sh upgrade

echo "Database schema created"
```

### 5.5 SSL Certificate Setup

```bash
# Exit biomate user, return to ubuntu user
exit

# Stop nginx if running
sudo systemctl stop nginx

# Obtain Let's Encrypt certificate
sudo certbot certonly --standalone \
  -d biomate.ai \
  -d www.biomate.ai \
  --non-interactive \
  --agree-tos \
  --email admin@biomate.ai \
  --preferred-challenges http

# Set up auto-renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

echo "SSL certificate obtained"
```

### 5.6 Deploy Configuration Files

```bash
# Deploy nginx configuration
sudo cp /home/biomate/biomate/deployment/nginx/biomate.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/biomate.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
sudo nginx -t

# Deploy systemd service files
sudo cp /home/biomate/biomate/deployment/systemd/biomate-frontend.service /etc/systemd/system/
sudo cp /home/biomate/biomate/deployment/systemd/biomate-backend.service /etc/systemd/system/
sudo cp /home/biomate/biomate/deployment/systemd/biomate-backup.service /etc/systemd/system/
sudo cp /home/biomate/biomate/deployment/systemd/biomate-backup.timer /etc/systemd/system/
sudo cp /home/biomate/biomate/deployment/systemd/biomate-security-check.service /etc/systemd/system/
sudo cp /home/biomate/biomate/deployment/systemd/biomate-security-check.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Make scripts executable
chmod +x /home/biomate/biomate/scripts/backup/*.sh
chmod +x /home/biomate/biomate/scripts/security/*.sh
chmod +x /home/biomate/biomate/scripts/monitoring/*.sh

echo "Configuration files deployed"
```

### 5.7 Start Services

```bash
# Start backend (Galaxy)
sudo systemctl start biomate-backend
sudo systemctl enable biomate-backend

# Wait for backend to be ready
sleep 10

# Start frontend
sudo systemctl start biomate-frontend
sudo systemctl enable biomate-frontend

# Start nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Enable backup automation
sudo systemctl enable biomate-backup.timer
sudo systemctl start biomate-backup.timer

# Enable security monitoring
sudo systemctl enable biomate-security-check.timer
sudo systemctl start biomate-security-check.timer

# Check service status
sudo systemctl status biomate-backend
sudo systemctl status biomate-frontend
sudo systemctl status nginx

echo "Services started"
```

---

## 6. Security Configuration

### 6.1 Generate Production Secrets

Already handled in section 2.6 (AWS Secrets Manager)

### 6.2 Configure Security Monitoring

```bash
# Deploy security check script
sudo su - biomate
cd /home/biomate/biomate

# Test security check
./scripts/monitoring/check-security-status.sh

# Should output security score and findings
```

### 6.3 Enable Audit Logging

```bash
# Create audit log directory
sudo mkdir -p /var/log/biomate
sudo chown biomate:biomate /var/log/biomate
sudo chmod 750 /var/log/biomate

# Configure log rotation
sudo tee /etc/logrotate.d/biomate <<EOF
/var/log/biomate/*.log {
    daily
    rotate 2555
    compress
    delaycompress
    notifempty
    create 0640 biomate biomate
    sharedscripts
    postrotate
        systemctl reload biomate-frontend
        systemctl reload biomate-backend
    endscript
}
EOF
```

---

## 7. Monitoring Setup

### 7.1 Deploy CloudWatch Agent

```bash
# Copy CloudWatch configuration
sudo cp /home/biomate/biomate/deployment/cloudwatch/cloudwatch-config.json \
  /opt/aws/amazon-cloudwatch-agent/etc/config.json

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Enable on boot
sudo systemctl enable amazon-cloudwatch-agent

echo "CloudWatch agent configured"
```

### 7.2 Create CloudWatch Alarms

```bash
# Create SNS topic for alerts
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name biomate-prod-alerts \
  --query 'TopicArn' \
  --output text)

# Subscribe email to topic
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint ops@biomate.ai

echo "Check your email and confirm SNS subscription"
read -p "Press enter after confirming..."

# Run alarm creation script
cd /home/biomate/biomate/deployment/cloudwatch
export SNS_TOPIC_ARN=$SNS_TOPIC_ARN
./create-alarms.sh

echo "CloudWatch alarms created"
```

### 7.3 Set Up Status Page (Optional)

```bash
# Configure external uptime monitoring
# Options: Pingdom, UptimeRobot, StatusCake

# Example: UptimeRobot (via web interface)
# - Monitor: https://biomate.ai/health
# - Alert contacts: ops@biomate.ai
# - Check interval: 5 minutes
```

---

## 8. Post-Deployment Verification

### 8.1 Service Health Checks

```bash
# Check all services are running
sudo systemctl is-active biomate-frontend
sudo systemctl is-active biomate-backend
sudo systemctl is-active nginx

# Check service logs for errors
sudo journalctl -u biomate-frontend -n 50 --no-pager
sudo journalctl -u biomate-backend -n 50 --no-pager
sudo journalctl -u nginx -n 50 --no-pager
```

### 8.2 Application Testing

```bash
# Test health endpoint
curl -I https://biomate.ai/health
# Expected: HTTP/2 200

# Test HTTPS redirect
curl -I http://biomate.ai
# Expected: HTTP/1.1 301 Moved Permanently
# Location: https://biomate.ai/

# Test security headers
curl -I https://biomate.ai | grep -i "strict-transport-security"
curl -I https://biomate.ai | grep -i "x-frame-options"
curl -I https://biomate.ai | grep -i "x-content-type-options"

# Test SSL/TLS configuration
openssl s_client -connect biomate.ai:443 -tls1_3 </dev/null
# Should show TLS 1.3 connection

# Test API endpoints
curl https://biomate.ai/api/health
# Expected: {"status": "ok"}
```

### 8.3 Security Validation

```bash
# Run security test suite
cd /home/biomate/biomate
sudo -u biomate ./scripts/security/test-security.sh

# Should pass all 12 test categories

# Run security status check
sudo -u biomate ./scripts/monitoring/check-security-status.sh

# Target: Security score >= 80%
```

### 8.4 SSL/TLS Validation

```bash
# Test with SSL Labs (external)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=biomate.ai
# Target: A+ rating

# Quick local test
testssl.sh https://biomate.ai

# Or use nmap
nmap --script ssl-enum-ciphers -p 443 biomate.ai
```

### 8.5 Backup Verification

```bash
# Run manual backup
sudo -u biomate /home/biomate/biomate/scripts/backup/backup-database.sh

# Verify backup was created
aws s3 ls s3://biomate-prod-backups/database/ --recursive

# Test restore (to temporary database)
sudo -u biomate /home/biomate/biomate/scripts/backup/restore-database.sh --verify-only --date $(date +%Y%m%d)
```

### 8.6 Performance Testing

```bash
# Install Apache Bench
sudo apt install apache2-utils -y

# Test homepage load
ab -n 100 -c 10 https://biomate.ai/

# Test API endpoint
ab -n 100 -c 10 https://biomate.ai/api/health

# Expected:
# - Requests per second: > 100
# - 95th percentile: < 500ms
```

### 8.7 Load Testing (Optional)

```bash
# Install k6 for comprehensive load testing
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Create load test script
cat > load-test.js <<'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp up to 100 users
    { duration: '5m', target: 100 },  // Stay at 100 users
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests under 500ms
    http_req_failed: ['rate<0.01'],     // < 1% errors
  },
};

export default function () {
  let response = http.get('https://biomate.ai/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
EOF

# Run load test
k6 run load-test.js
```

---

## 9. Troubleshooting

### 9.1 Services Won't Start

**Frontend service fails:**
```bash
# Check logs
sudo journalctl -u biomate-frontend -n 100

# Common issues:
# 1. Port already in use
sudo lsof -i :5000

# 2. Environment variables missing
sudo -u biomate cat /home/biomate/biomate/frontend/.env.production

# 3. Dependencies not installed
cd /home/biomate/biomate/frontend
npm ci

# 4. Permissions issue
sudo chown -R biomate:biomate /home/biomate/biomate
```

**Backend (Galaxy) service fails:**
```bash
# Check logs
sudo journalctl -u biomate-backend -n 100

# Common issues:
# 1. Python environment issue
sudo -u biomate bash
source /home/biomate/biomate/backend/.venv/bin/activate
python --version

# 2. Database connection
psql -h $DB_HOST -U $DB_USER -d biomate -c "SELECT 1;"

# 3. Port conflict
sudo lsof -i :8081
```

### 9.2 SSL Certificate Issues

```bash
# Certificate not found
ls -la /etc/letsencrypt/live/biomate.ai/

# Renew certificate manually
sudo certbot renew --force-renewal

# Test certificate auto-renewal
sudo certbot renew --dry-run
```

### 9.3 Database Connection Issues

```bash
# Test connection from app server
psql -h $DB_HOST -U $DB_USER -d biomate

# Check security group rules
aws ec2 describe-security-groups --group-ids $DB_SG

# Verify RDS instance is available
aws rds describe-db-instances \
  --db-instance-identifier biomate-prod-db \
  --query 'DBInstances[0].DBInstanceStatus'
```

### 9.4 High CPU/Memory Usage

```bash
# Check resource usage
htop

# Check application logs for errors
sudo journalctl -u biomate-frontend -f

# Check for memory leaks
sudo -u biomate node --trace-gc /home/biomate/biomate/frontend/server/index.js

# Scale vertically (increase instance size)
# Or scale horizontally (add more instances behind load balancer)
```

### 9.5 502 Bad Gateway

```bash
# Nginx can't reach backend
sudo nginx -t
sudo systemctl restart nginx

# Check upstream services
curl http://localhost:5000/health
curl http://localhost:8081/api/health

# Check nginx error log
sudo tail -f /var/log/nginx/biomate-error.log
```

### 9.6 Rate Limiting Issues

```bash
# Check rate limit configuration in nginx
sudo grep -A 5 "limit_req_zone" /etc/nginx/sites-available/biomate.conf

# Temporarily increase limits for debugging
sudo vi /etc/nginx/sites-available/biomate.conf
# Increase rate values (e.g., 100r/s -> 500r/s)
sudo nginx -t && sudo systemctl reload nginx

# Monitor rate limit hits
sudo tail -f /var/log/nginx/biomate-access.log | grep " 429 "
```

### 9.7 CloudWatch Agent Not Reporting

```bash
# Check agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2 -c default -s

# Check agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Restart agent
sudo systemctl restart amazon-cloudwatch-agent

# Verify IAM role permissions
aws sts get-caller-identity
```

---

## 10. Rollback Procedures

### 10.1 Application Rollback

```bash
# Stop services
sudo systemctl stop biomate-frontend
sudo systemctl stop biomate-backend

# Switch to biomate user
sudo su - biomate
cd /home/biomate/biomate

# Checkout previous version
git fetch --all --tags
git checkout tags/v0.9.0  # or previous version

# Reinstall dependencies
cd frontend && npm ci --production
cd ../backend && source .venv/bin/activate && pip install -r requirements.txt

# Exit to root
exit

# Restart services
sudo systemctl start biomate-backend
sudo systemctl start biomate-frontend

# Verify services
sudo systemctl status biomate-frontend
sudo systemctl status biomate-backend
```

### 10.2 Database Rollback

```bash
# List available backups
sudo -u biomate /home/biomate/biomate/scripts/backup/restore-database.sh --list

# Restore to point-in-time
sudo -u biomate /home/biomate/biomate/scripts/backup/restore-database.sh --date 20251110

# Or restore from RDS automated backup
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier biomate-prod-db \
  --target-db-instance-identifier biomate-prod-db-restored \
  --restore-time 2025-11-10T12:00:00Z
```

### 10.3 Configuration Rollback

```bash
# Restore nginx configuration
sudo cp /etc/nginx/sites-available/biomate.conf.backup \
  /etc/nginx/sites-available/biomate.conf
sudo nginx -t && sudo systemctl reload nginx

# Restore systemd services
sudo cp /etc/systemd/system/biomate-frontend.service.backup \
  /etc/systemd/system/biomate-frontend.service
sudo systemctl daemon-reload
sudo systemctl restart biomate-frontend
```

---

## Appendix A: Production Readiness Checklist

Before going live, ensure all items in `20251111_1510_PRODUCTION_READINESS_CHECKLIST.md` are completed (target: 90%).

**Critical Items:**
- [ ] All production secrets generated and stored in AWS Secrets Manager
- [ ] SSL certificate obtained and configured
- [ ] Database encrypted with automated backups
- [ ] CloudWatch logging with 6-year retention configured
- [ ] Business Associate Agreements executed
- [ ] HIPAA risk assessment completed
- [ ] Security penetration testing conducted
- [ ] Terms of Service and Privacy Policy published
- [ ] Disaster recovery procedures tested
- [ ] All approvals obtained

---

## Appendix B: Useful Commands

### Service Management
```bash
# Restart all services
sudo systemctl restart biomate-backend biomate-frontend nginx

# View logs in real-time
sudo journalctl -u biomate-frontend -f

# Check service status
sudo systemctl status biomate-backend biomate-frontend nginx
```

### Database Operations
```bash
# Connect to database
psql -h $DB_HOST -U $DB_USER -d biomate

# Backup database manually
sudo -u biomate /home/biomate/biomate/scripts/backup/backup-database.sh

# Restore database
sudo -u biomate /home/biomate/biomate/scripts/backup/restore-database.sh --date YYYYMMDD
```

### Security
```bash
# Run security checks
sudo -u biomate /home/biomate/biomate/scripts/monitoring/check-security-status.sh

# Test security suite
sudo -u biomate /home/biomate/biomate/scripts/security/test-security.sh

# View audit logs
sudo tail -f /var/log/biomate/audit.log
```

### Monitoring
```bash
# Check CloudWatch logs
aws logs tail /biomate/production/backend/error --follow

# View alarms
aws cloudwatch describe-alarms --alarm-names biomate-high-cpu biomate-5xx-errors

# Check metrics
aws cloudwatch get-metric-statistics \
  --namespace BioMate/Production \
  --metric-name MEMORY_USED \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## Appendix C: Emergency Contacts

- **DevOps Lead:** [Contact Info]
- **Security Lead:** [Contact Info]
- **Database Admin:** [Contact Info]
- **AWS Support:** Premium Support (24/7)
- **On-Call Rotation:** [PagerDuty/Opsgenie Link]

---

## Appendix D: Related Documentation

- [Security Compliance Audit Report](20251111_1430_SECURITY_COMPLIANCE_AUDIT_REPORT.md)
- [Incident Response Plan](20251111_1435_INCIDENT_RESPONSE_PLAN.md)
- [Backup & Disaster Recovery](20251111_1440_BACKUP_DISASTER_RECOVERY.md)
- [Security Setup Guide](20251111_1445_SECURITY_SETUP_GUIDE.md)
- [Production Readiness Checklist](20251111_1510_PRODUCTION_READINESS_CHECKLIST.md)

---

**Document Owner:** DevOps Lead
**Last Updated:** 2025-11-11
**Version:** 1.0
**Classification:** INTERNAL USE ONLY

---

**IMPORTANT NOTES:**

1. This guide assumes you have the necessary AWS permissions and access
2. All sensitive credentials should be stored in AWS Secrets Manager, never in code or configuration files
3. Test each step in a staging environment before applying to production
4. Keep this document updated as infrastructure changes
5. Coordinate deployment with stakeholders during maintenance window
6. Have rollback plan ready before any production changes
7. Document any deviations from this guide for future reference
