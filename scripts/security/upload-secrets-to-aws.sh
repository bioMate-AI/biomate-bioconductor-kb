#!/bin/bash

################################################################################
# Upload Secrets to AWS Secrets Manager
################################################################################

set -eo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
KMS_KEY_ID="${1:-alias/biomate-production}"

echo "========================================"
echo "Uploading Secrets to AWS Secrets Manager"
echo "========================================"
echo ""
echo "Region: $AWS_REGION"
echo "KMS Key: $KMS_KEY_ID"
echo ""

if [[ ! -f "secrets-aws.json" ]]; then
    echo "✗ secrets-aws.json not found"
    echo "Run: ./scripts/security/generate-secrets.sh first"
    exit 1
fi

create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    local description=$3

    echo "Processing: $secret_name"

    if aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" &> /dev/null; then

        echo "  Updating existing secret..."
        aws secretsmanager update-secret \
            --secret-id "$secret_name" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" \
            --kms-key-id "$KMS_KEY_ID" > /dev/null

        echo "  ✓ Updated: $secret_name"
    else
        echo "  Creating new secret..."
        aws secretsmanager create-secret \
            --name "$secret_name" \
            --description "$description" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" \
            --kms-key-id "$KMS_KEY_ID" \
            --tags Key=Environment,Value=production Key=Project,Value=biomate > /dev/null

        echo "  ✓ Created: $secret_name"
    fi
}

# Extract sections from JSON
APP_SECRETS=$(cat secrets-aws.json | jq -c '.["app-secrets"]')
DB_SECRETS=$(cat secrets-aws.json | jq -c '.database')
REDIS_SECRETS=$(cat secrets-aws.json | jq -c '.redis')
BACKUP_SECRETS=$(cat secrets-aws.json | jq -c '.backup')

# Upload secrets
create_or_update_secret \
    "biomate/production/app-secrets" \
    "$APP_SECRETS" \
    "BioMate production application secrets"

create_or_update_secret \
    "biomate/production/database" \
    "$DB_SECRETS" \
    "BioMate production database credentials"

create_or_update_secret \
    "biomate/production/redis" \
    "$REDIS_SECRETS" \
    "BioMate production Redis credentials"

create_or_update_secret \
    "biomate/production/backup" \
    "$BACKUP_SECRETS" \
    "BioMate production backup encryption keys"

echo ""
echo "========================================"
echo "Secrets Upload Complete"
echo "========================================"
echo ""
echo "✓ 4 secret groups uploaded to AWS Secrets Manager"
echo ""
echo "Secrets:"
echo "  - biomate/production/app-secrets"
echo "  - biomate/production/database"
echo "  - biomate/production/redis"
echo "  - biomate/production/backup"
echo ""
echo "To retrieve secrets in your application:"
echo '  aws secretsmanager get-secret-value --secret-id biomate/production/app-secrets --region us-east-1'
echo ""
echo "Secrets are encrypted with KMS key: $KMS_KEY_ID"
echo ""
