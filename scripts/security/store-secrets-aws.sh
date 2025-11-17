#!/bin/bash
# Store BioMate Secrets in AWS Secrets Manager
# SOC 2 CC6.1 - Access Control
# HIPAA §164.308(a)(4)(ii)(B) - Access Authorization
# Version: 1.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "AWS Secrets Manager Upload Script"
echo "========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it with:"
    echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    echo "  unzip awscliv2.zip"
    echo "  sudo ./aws/install"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Install it with: sudo apt install jq"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Configure with: aws configure"
    exit 1
fi

# Get secrets file from argument
SECRETS_FILE="${1:-}"

if [[ -z "$SECRETS_FILE" ]]; then
    echo -e "${RED}Error: No secrets file provided${NC}"
    echo "Usage: $0 <secrets-file.json>"
    exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo -e "${RED}Error: Secrets file not found: $SECRETS_FILE${NC}"
    exit 1
fi

# Validate JSON
if ! jq empty "$SECRETS_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in secrets file${NC}"
    exit 1
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
SECRET_PREFIX="biomate/prod"
KMS_KEY="${KMS_KEY_ID:-alias/aws/secretsmanager}"

echo "Configuration:"
echo "  AWS Region: $AWS_REGION"
echo "  Secret Prefix: $SECRET_PREFIX"
echo "  KMS Key: $KMS_KEY"
echo ""

# Extract database endpoint from environment or prompt
DB_HOST="${DB_HOST:-}"
if [[ -z "$DB_HOST" ]]; then
    read -p "Enter RDS endpoint (or press Enter to set later): " DB_HOST
fi

REDIS_HOST="${REDIS_HOST:-}"
if [[ -z "$REDIS_HOST" ]]; then
    read -p "Enter Redis endpoint (or press Enter to set later): " REDIS_HOST
fi

# Function to create or update secret
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    local description=$3

    echo -n "  $secret_name... "

    # Check if secret exists
    if aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" &> /dev/null; then

        # Update existing secret
        aws secretsmanager update-secret \
            --secret-id "$secret_name" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" \
            --kms-key-id "$KMS_KEY" \
            --output text &> /dev/null

        echo -e "${YELLOW}updated${NC}"
    else
        # Create new secret
        aws secretsmanager create-secret \
            --name "$secret_name" \
            --description "$description" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" \
            --kms-key-id "$KMS_KEY" \
            --tags Key=Environment,Value=production Key=Application,Value=biomate \
            --output text &> /dev/null

        echo -e "${GREEN}created${NC}"
    fi
}

# Function to enable automatic rotation
enable_rotation() {
    local secret_name=$1
    local rotation_days=${2:-90}

    # Note: Automatic rotation requires a Lambda function
    # This is a placeholder for future implementation
    echo -n "  Setting rotation schedule for $secret_name... "
    echo -e "${YELLOW}manual rotation required${NC}"
}

echo -e "${BLUE}Uploading secrets to AWS Secrets Manager...${NC}"
echo ""

# 1. Application Secrets
echo "1. Application Secrets"
APP_SECRETS=$(jq -n \
    --arg jwt "$(jq -r '.jwt_secret' "$SECRETS_FILE")" \
    --arg session "$(jq -r '.session_secret' "$SECRETS_FILE")" \
    --arg encryption "$(jq -r '.encryption_key' "$SECRETS_FILE")" \
    --arg csrf "$(jq -r '.csrf_secret' "$SECRETS_FILE")" \
    --arg cookie "$(jq -r '.cookie_secret' "$SECRETS_FILE")" \
    --arg internal_api "$(jq -r '.internal_api_key' "$SECRETS_FILE")" \
    --arg webhook "$(jq -r '.webhook_secret' "$SECRETS_FILE")" \
    '{
        jwt_secret: $jwt,
        session_secret: $session,
        encryption_key: $encryption,
        csrf_secret: $csrf,
        cookie_secret: $cookie,
        internal_api_key: $internal_api,
        webhook_secret: $webhook
    }')

create_or_update_secret \
    "$SECRET_PREFIX/app-secrets" \
    "$APP_SECRETS" \
    "BioMate production application secrets"

# 2. Database Credentials
echo "2. Database Credentials"
DB_SECRETS=$(jq -n \
    --arg host "$DB_HOST" \
    --arg port "5432" \
    --arg database "biomate" \
    --arg username "biomate_app" \
    --arg password "$(jq -r '.database_password' "$SECRETS_FILE")" \
    '{
        host: $host,
        port: $port,
        database: $database,
        username: $username,
        password: $password,
        ssl: true
    }')

create_or_update_secret \
    "$SECRET_PREFIX/database" \
    "$DB_SECRETS" \
    "BioMate production database credentials"

# 3. Redis Credentials
echo "3. Redis Credentials"
REDIS_SECRETS=$(jq -n \
    --arg host "$REDIS_HOST" \
    --arg port "6379" \
    --arg password "$(jq -r '.redis_password' "$SECRETS_FILE")" \
    '{
        host: $host,
        port: $port,
        password: $password,
        tls: true
    }')

create_or_update_secret \
    "$SECRET_PREFIX/redis" \
    "$REDIS_SECRETS" \
    "BioMate production Redis credentials"

# 4. Backup Encryption Key
echo "4. Backup Encryption"
BACKUP_SECRETS=$(jq -n \
    --arg key "$(jq -r '.backup_encryption_key' "$SECRETS_FILE")" \
    '{
        encryption_key: $key
    }')

create_or_update_secret \
    "$SECRET_PREFIX/backup" \
    "$BACKUP_SECRETS" \
    "BioMate production backup encryption key"

echo ""
echo -e "${GREEN}✓ All secrets uploaded successfully${NC}"
echo ""

# Create IAM policy for secret access
echo "========================================="
echo "IAM Policy for Secret Access"
echo "========================================="
echo ""
echo "Add this policy to your EC2 instance role:"
echo ""

cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:*:secret:biomate/prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:us-west-2:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.us-west-2.amazonaws.com"
          ]
        }
      }
    }
  ]
}
EOF

echo ""
echo "========================================="
echo "Retrieving Secrets in Application"
echo "========================================="
echo ""
echo "Example code to retrieve secrets:"
echo ""

cat <<'EOF'
// Node.js example
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager({ region: 'us-west-2' });

async function getSecret(secretName) {
  const data = await secretsManager.getSecretValue({
    SecretId: secretName
  }).promise();

  return JSON.parse(data.SecretString);
}

// Usage
const appSecrets = await getSecret('biomate/prod/app-secrets');
const dbSecrets = await getSecret('biomate/prod/database');
const redisSecrets = await getSecret('biomate/prod/redis');

// Use in environment
process.env.JWT_SECRET = appSecrets.jwt_secret;
process.env.DB_PASSWORD = dbSecrets.password;
process.env.REDIS_PASSWORD = redisSecrets.password;
EOF

echo ""
echo "========================================="
echo "Secret Rotation"
echo "========================================="
echo ""
echo "IMPORTANT: Rotate secrets every 90 days (SOC 2, HIPAA requirement)"
echo ""
echo "To rotate secrets:"
echo "  1. Generate new secrets: ./generate-secrets.sh"
echo "  2. Upload to AWS: ./store-secrets-aws.sh <new-secrets.json>"
echo "  3. Update application: Restart services to load new secrets"
echo "  4. Verify: Test application connectivity"
echo ""
echo "Set a calendar reminder for: $(date -d '+90 days' '+%Y-%m-%d')"
echo ""

# Create rotation schedule file
ROTATION_SCHEDULE="/tmp/biomate-secret-rotation-schedule.txt"
cat > "$ROTATION_SCHEDULE" <<EOF
BioMate Secret Rotation Schedule
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Next Rotation Due: $(date -d '+90 days' '+%Y-%m-%d')

Secrets to Rotate:
- JWT Secret
- Session Secret
- Encryption Key
- CSRF Secret
- Cookie Secret
- Database Password
- Redis Password
- Backup Encryption Key
- Internal API Key
- Webhook Secret

Rotation Procedure:
1. Run: ./generate-secrets.sh
2. Run: ./store-secrets-aws.sh <secrets-file.json>
3. Restart: sudo systemctl restart biomate-frontend biomate-backend
4. Verify: curl https://biomate.ai/health
5. Test: Run security test suite

Compliance:
- SOC 2: CC6.1 requires periodic credential rotation
- HIPAA: §164.308(a)(5)(ii)(D) recommends regular password changes
EOF

echo "Rotation schedule saved to: $ROTATION_SCHEDULE"
echo ""

# Summary
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo -e "${GREEN}✓ Secrets stored in AWS Secrets Manager${NC}"
echo ""
echo "Secret ARNs:"
aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --filters Key=name,Values="$SECRET_PREFIX" \
    --query 'SecretList[*].[Name,ARN]' \
    --output table

echo ""
echo -e "${YELLOW}IMPORTANT NEXT STEPS:${NC}"
echo "1. Update EC2 instance IAM role with secret access policy"
echo "2. Update application code to retrieve secrets from AWS"
echo "3. Remove any secrets from .env files"
echo "4. Set up secret rotation reminder (90 days)"
echo "5. Test application with new secrets"
echo ""
echo -e "${RED}⚠️  DELETE the local secrets file:${NC}"
echo "  shred -u $SECRETS_FILE"
echo ""
echo -e "${GREEN}✓ Secret management setup complete!${NC}"
