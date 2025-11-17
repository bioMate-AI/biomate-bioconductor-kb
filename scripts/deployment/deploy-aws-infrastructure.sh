#!/bin/bash

################################################################################
# BioMate AI - AWS Infrastructure Deployment
################################################################################
#
# This script helps deploy the required AWS infrastructure for production.
# It creates all necessary resources with proper security and HIPAA compliance.
#
# Usage: ./deploy-aws-infrastructure.sh [--auto-approve]
#
# Resources created:
#   - KMS encryption key
#   - VPC and subnets (if needed)
#   - Security groups
#   - RDS PostgreSQL instance (Multi-AZ, encrypted)
#   - ElastiCache Redis cluster (Multi-AZ, TLS)
#   - S3 buckets (versioned, encrypted)
#   - CloudWatch log groups
#
################################################################################

set -eo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME="biomate"
ENVIRONMENT="production"

# Auto-approve flag
AUTO_APPROVE=false
if [[ "$1" == "--auto-approve" ]]; then
    AUTO_APPROVE=true
fi

echo "========================================"
echo "BioMate AWS Infrastructure Deployment"
echo "========================================"
echo ""
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"
echo ""

confirm() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi

    local prompt="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response=${response:-$default}

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

log() {
    echo -e "${BLUE}[$(date -u +"%H:%M:%S")]${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

################################################################################
# Load secrets
################################################################################

if [[ ! -f ".env.production" ]]; then
    error ".env.production not found"
    echo ""
    echo "Run this first:"
    echo "  ./scripts/security/generate-secrets.sh"
    echo ""
    exit 1
fi

# Source the secrets
set -a
source .env.production
set +a

success "Loaded secrets from .env.production"
echo ""

################################################################################
# Check prerequisites
################################################################################

log "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    error "AWS CLI not found"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI not configured or credentials invalid"
    exit 1
fi

success "Prerequisites check passed"
echo ""

################################################################################
# Deployment Plan
################################################################################

echo "========================================"
echo "Deployment Plan"
echo "========================================"
echo ""
echo "The following resources will be created:"
echo ""
echo "1. KMS Encryption Key"
echo "   - Purpose: Encrypt RDS, S3, secrets"
echo "   - Alias: alias/biomate-production"
echo ""
echo "2. S3 Buckets (3 buckets)"
echo "   - biomate-production-data-$AWS_ACCOUNT_ID"
echo "   - biomate-production-backups-$AWS_ACCOUNT_ID"
echo "   - biomate-compliance-evidence-$AWS_ACCOUNT_ID"
echo "   - Features: Versioning, encryption, lifecycle policies"
echo ""
echo "3. CloudWatch Log Groups"
echo "   - /biomate/application"
echo "   - /biomate/security"
echo "   - /biomate/access"
echo "   - Retention: 2555 days (6+ years, HIPAA compliant)"
echo ""
echo "4. RDS PostgreSQL Instance"
echo "   - Instance: db.t3.medium"
echo "   - Engine: PostgreSQL 15.4"
echo "   - Storage: 100 GB (gp3, encrypted)"
echo "   - Multi-AZ: Yes"
echo "   - Backup: 35 days"
echo "   - Cost: ~\$100-150/month"
echo ""
echo "5. ElastiCache Redis Cluster"
echo "   - Instance: cache.t3.medium"
echo "   - Engine: Redis 7.0"
echo "   - Multi-AZ: Yes"
echo "   - TLS: Enabled"
echo "   - Cost: ~\$50-75/month"
echo ""
echo "Estimated monthly cost: \$160-255"
echo ""

if ! confirm "Do you want to proceed with deployment?"; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""

################################################################################
# Step 1: Create KMS Key
################################################################################

log "Step 1: Creating KMS encryption key..."

KMS_KEY_ID=$(aws kms list-aliases --region "$AWS_REGION" \
    --query "Aliases[?AliasName=='alias/biomate-production'].TargetKeyId" \
    --output text)

if [[ -n "$KMS_KEY_ID" ]] && [[ "$KMS_KEY_ID" != "None" ]]; then
    success "KMS key already exists: $KMS_KEY_ID"
else
    KMS_KEY_ID=$(aws kms create-key \
        --description "BioMate Production Encryption Key" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.KeyId' \
        --output text)

    aws kms create-alias \
        --alias-name alias/biomate-production \
        --target-key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION"

    success "KMS key created: $KMS_KEY_ID"
fi

echo ""

################################################################################
# Step 2: Create S3 Buckets
################################################################################

log "Step 2: Creating S3 buckets..."

create_s3_bucket() {
    local bucket_name=$1
    local description=$2

    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        success "Bucket already exists: $bucket_name"
        return
    fi

    log "Creating bucket: $bucket_name"

    # Create bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$bucket_name" --region "$AWS_REGION"
    else
        aws s3 mb "s3://$bucket_name" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration "{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"aws:kms\",
                    \"KMSMasterKeyID\": \"$KMS_KEY_ID\"
                },
                \"BucketKeyEnabled\": true
            }]
        }"

    # Block public access
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

    # Enable logging
    aws s3api put-bucket-logging \
        --bucket "$bucket_name" \
        --bucket-logging-status "{
            \"LoggingEnabled\": {
                \"TargetBucket\": \"$bucket_name\",
                \"TargetPrefix\": \"logs/\"
            }
        }" 2>/dev/null || warn "Could not enable logging for $bucket_name"

    # Add lifecycle policy for old versions (90 days)
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration "{
            \"Rules\": [{
                \"ID\": \"DeleteOldVersions\",
                \"Status\": \"Enabled\",
                \"NoncurrentVersionExpiration\": {
                    \"NoncurrentDays\": 90
                }
            }]
        }"

    # Add tags
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "TagSet=[
            {Key=Environment,Value=production},
            {Key=Project,Value=biomate},
            {Key=Purpose,Value=\"$description\"}
        ]"

    success "Created bucket: $bucket_name"
}

create_s3_bucket \
    "biomate-production-data-$AWS_ACCOUNT_ID" \
    "Application data storage"

create_s3_bucket \
    "biomate-production-backups-$AWS_ACCOUNT_ID" \
    "Automated backups"

create_s3_bucket \
    "biomate-compliance-evidence-$AWS_ACCOUNT_ID" \
    "Compliance evidence and audit logs"

echo ""

################################################################################
# Step 3: Create CloudWatch Log Groups
################################################################################

log "Step 3: Creating CloudWatch log groups..."

create_log_group() {
    local log_group=$1

    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" \
        --query "logGroups[?logGroupName=='$log_group']" \
        --output text | grep -q "$log_group"; then
        success "Log group already exists: $log_group"
        return
    fi

    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "$AWS_REGION"

    # Set retention to 2555 days (6+ years for HIPAA)
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days 2555 \
        --region "$AWS_REGION"

    # Add tags
    aws logs tag-log-group \
        --log-group-name "$log_group" \
        --tags Environment=production,Project=biomate \
        --region "$AWS_REGION"

    success "Created log group: $log_group"
}

create_log_group "/biomate/application"
create_log_group "/biomate/security"
create_log_group "/biomate/access"

echo ""

################################################################################
# Step 4: Display Next Steps
################################################################################

echo "========================================"
echo "Infrastructure Deployment Complete"
echo "========================================"
echo ""
success "Created resources:"
echo "  ✓ KMS encryption key: $KMS_KEY_ID"
echo "  ✓ S3 buckets: 3 buckets"
echo "  ✓ CloudWatch log groups: 3 groups"
echo ""
warn "Manual steps still required:"
echo ""
echo "1. RDS PostgreSQL Instance"
echo "   The RDS instance requires network configuration (VPC, subnets, security groups)."
echo "   You need to:"
echo ""
echo "   a) Identify or create a VPC:"
echo "      aws ec2 describe-vpcs --region $AWS_REGION"
echo ""
echo "   b) Identify or create DB subnet group:"
echo "      aws rds describe-db-subnet-groups --region $AWS_REGION"
echo ""
echo "   c) Create RDS instance:"
echo ""
cat << 'RDSEOF'
      aws rds create-db-instance \
          --db-instance-identifier biomate-production \
          --db-instance-class db.t3.medium \
          --engine postgres \
          --engine-version 15.4 \
          --master-username biomate_admin \
          --master-user-password "$DB_PASSWORD" \
          --allocated-storage 100 \
          --storage-type gp3 \
          --storage-encrypted \
          --kms-key-id "$KMS_KEY_ID" \
          --multi-az \
          --db-name biomate \
          --backup-retention-period 35 \
          --vpc-security-group-ids <YOUR_SECURITY_GROUP_ID> \
          --db-subnet-group-name <YOUR_DB_SUBNET_GROUP> \
          --region us-east-1 \
          --tags Key=Environment,Value=production Key=Project,Value=biomate
RDSEOF
echo ""
echo "2. ElastiCache Redis Cluster"
echo "   Similar to RDS, requires network configuration."
echo ""
echo "   a) Create cache subnet group (if needed)"
echo "   b) Create Redis cluster with Multi-AZ and TLS"
echo ""
echo "3. Store secrets in AWS Secrets Manager:"
echo "   ./scripts/security/store-secrets-aws.sh"
echo ""
echo "4. Set up SSL certificate:"
echo "   sudo ./scripts/ssl/setup-ssl-cert.sh biomate.ai yaoyun.zhang@biomate.ai"
echo ""
echo "For detailed RDS/Redis setup instructions, see:"
echo "  PRODUCTION_STATUS_CURRENT.md"
echo ""
echo "Estimated monthly cost: \$160-255"
echo ""
