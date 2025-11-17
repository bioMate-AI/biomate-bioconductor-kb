#!/bin/bash
# Load Secrets from AWS Secrets Manager to Environment
# SOC 2 CC6.1 - Access Control
# Version: 1.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

AWS_REGION="${AWS_REGION:-us-west-2}"
SECRET_PREFIX="biomate/prod"
ENV_FILE="${1:-.env.production}"

echo "Loading secrets from AWS Secrets Manager..."
echo "Region: $AWS_REGION"
echo "Output: $ENV_FILE"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not installed${NC}"
    exit 1
fi

# Check credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

# Function to get secret
get_secret() {
    local secret_name=$1
    aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "{}"
}

echo "Retrieving secrets..."

# Get all secrets
APP_SECRETS=$(get_secret "$SECRET_PREFIX/app-secrets")
DB_SECRETS=$(get_secret "$SECRET_PREFIX/database")
REDIS_SECRETS=$(get_secret "$SECRET_PREFIX/redis")
BACKUP_SECRETS=$(get_secret "$SECRET_PREFIX/backup")

# Create .env file
cat > "$ENV_FILE" <<EOF
# BioMate Production Environment
# Loaded from AWS Secrets Manager: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT COMMIT THIS FILE

# Node Environment
NODE_ENV=production
PORT=5000

# Application Secrets
JWT_SECRET="$(echo "$APP_SECRETS" | jq -r '.jwt_secret')"
SESSION_SECRET="$(echo "$APP_SECRETS" | jq -r '.session_secret')"
ENCRYPTION_KEY="$(echo "$APP_SECRETS" | jq -r '.encryption_key')"
CSRF_SECRET="$(echo "$APP_SECRETS" | jq -r '.csrf_secret')"
COOKIE_SECRET="$(echo "$APP_SECRETS" | jq -r '.cookie_secret')"
INTERNAL_API_KEY="$(echo "$APP_SECRETS" | jq -r '.internal_api_key')"
WEBHOOK_SECRET="$(echo "$APP_SECRETS" | jq -r '.webhook_secret')"

# Database
DB_HOST="$(echo "$DB_SECRETS" | jq -r '.host')"
DB_PORT="$(echo "$DB_SECRETS" | jq -r '.port')"
DB_NAME="$(echo "$DB_SECRETS" | jq -r '.database')"
DB_USER="$(echo "$DB_SECRETS" | jq -r '.username')"
DB_PASSWORD="$(echo "$DB_SECRETS" | jq -r '.password')"
DB_SSL=true
DB_SSL_REJECT_UNAUTHORIZED=true

# Redis
REDIS_HOST="$(echo "$REDIS_SECRETS" | jq -r '.host')"
REDIS_PORT="$(echo "$REDIS_SECRETS" | jq -r '.port')"
REDIS_PASSWORD="$(echo "$REDIS_SECRETS" | jq -r '.password')"
REDIS_TLS=true

# Backup
BACKUP_ENCRYPTION_KEY="$(echo "$BACKUP_SECRETS" | jq -r '.encryption_key')"

# AWS
AWS_REGION=$AWS_REGION
AWS_S3_BUCKET=biomate-prod-uploads
AWS_S3_BACKUP_BUCKET=biomate-prod-backups

# Application
BASE_URL=https://biomate.ai
FRONTEND_URL=https://biomate.ai
BACKEND_URL=https://biomate.ai/galaxy

# Security Settings
SESSION_TIMEOUT=900
MAX_UPLOAD_SIZE=524288000
RATE_LIMIT_WINDOW=60000
RATE_LIMIT_MAX=100

# HIPAA Compliance
HIPAA_COMPLIANT=true
PHI_ENCRYPTION_ENABLED=true
AUDIT_LOG_RETENTION_DAYS=2555

# Monitoring
ENABLE_CLOUDWATCH=true
ENABLE_AUDIT_LOGGING=true
LOG_LEVEL=info
EOF

# Secure permissions
chmod 600 "$ENV_FILE"

echo -e "${GREEN}✓ Secrets loaded successfully${NC}"
echo "Environment file: $ENV_FILE"
echo ""
echo "To use these secrets:"
echo "  source $ENV_FILE"
echo ""
echo -e "${YELLOW}Remember to restart services after loading new secrets${NC}"
