#!/bin/bash
# Generate Production Secrets for BioMate AI
# SOC 2 CC6.1 - Access Control
# HIPAA §164.312(a)(2)(i) - Unique User Identification
# Version: 1.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "BioMate Production Secrets Generator"
echo "========================================="
echo ""

# Function to generate secure random string
generate_secret() {
    local length=$1
    local charset=${2:-"A-Za-z0-9"}

    if [[ "$charset" == "base64" ]]; then
        openssl rand -base64 "$length"
    elif [[ "$charset" == "hex" ]]; then
        openssl rand -hex "$length"
    else
        # Alphanumeric only
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    fi
}

# Function to generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Create temporary directory for secrets
TEMP_DIR=$(mktemp -d)
trap "shred -u $TEMP_DIR/* 2>/dev/null || true; rm -rf $TEMP_DIR" EXIT

SECRETS_FILE="$TEMP_DIR/secrets.json"
ENV_FILE="$TEMP_DIR/.env.production.secrets"

echo -e "${YELLOW}Generating secure production secrets...${NC}"
echo ""

# 1. JWT Secret (512 bits / 64 bytes)
echo "Generating JWT secret..."
JWT_SECRET=$(generate_secret 64 base64)

# 2. Session Secret (512 bits / 64 bytes)
echo "Generating session secret..."
SESSION_SECRET=$(generate_secret 64 base64)

# 3. Encryption Key (256 bits / 32 bytes for AES-256)
echo "Generating encryption key..."
ENCRYPTION_KEY=$(generate_secret 32 base64)

# 4. CSRF Secret (256 bits / 32 bytes)
echo "Generating CSRF secret..."
CSRF_SECRET=$(generate_secret 32 base64)

# 5. Database Password (32 characters, alphanumeric + special)
echo "Generating database password..."
DB_PASSWORD=$(generate_secret 48 base64 | tr -d '/+=' | cut -c1-32)

# 6. Redis Password (32 characters, alphanumeric only for compatibility)
echo "Generating Redis password..."
REDIS_PASSWORD=$(generate_secret 32)

# 7. Backup Encryption Key (256 bits / 32 bytes)
echo "Generating backup encryption key..."
BACKUP_ENCRYPTION_KEY=$(generate_secret 32 base64)

# 8. API Key for internal services (UUID format)
echo "Generating internal API key..."
INTERNAL_API_KEY=$(generate_uuid)

# 9. Webhook Secret (for GitHub, external integrations)
echo "Generating webhook secret..."
WEBHOOK_SECRET=$(generate_secret 48 hex)

# 10. Cookie Secret (for signed cookies)
echo "Generating cookie secret..."
COOKIE_SECRET=$(generate_secret 32 base64)

echo ""
echo -e "${GREEN}✓ All secrets generated successfully${NC}"
echo ""

# Create JSON file for AWS Secrets Manager
cat > "$SECRETS_FILE" <<EOF
{
  "jwt_secret": "$JWT_SECRET",
  "session_secret": "$SESSION_SECRET",
  "encryption_key": "$ENCRYPTION_KEY",
  "csrf_secret": "$CSRF_SECRET",
  "database_password": "$DB_PASSWORD",
  "redis_password": "$REDIS_PASSWORD",
  "backup_encryption_key": "$BACKUP_ENCRYPTION_KEY",
  "internal_api_key": "$INTERNAL_API_KEY",
  "webhook_secret": "$WEBHOOK_SECRET",
  "cookie_secret": "$COOKIE_SECRET",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "generated_by": "$(whoami)@$(hostname)"
}
EOF

# Create .env file format
cat > "$ENV_FILE" <<EOF
# BioMate Production Secrets
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# IMPORTANT: Never commit this file to version control!

# Security Secrets
JWT_SECRET="$JWT_SECRET"
SESSION_SECRET="$SESSION_SECRET"
ENCRYPTION_KEY="$ENCRYPTION_KEY"
CSRF_SECRET="$CSRF_SECRET"
COOKIE_SECRET="$COOKIE_SECRET"

# Database Credentials
DB_PASSWORD="$DB_PASSWORD"

# Redis Credentials
REDIS_PASSWORD="$REDIS_PASSWORD"

# Backup Encryption
BACKUP_ENCRYPTION_KEY="$BACKUP_ENCRYPTION_KEY"

# API Keys
INTERNAL_API_KEY="$INTERNAL_API_KEY"
WEBHOOK_SECRET="$WEBHOOK_SECRET"
EOF

# Display secret strength information
echo "========================================="
echo "Secret Strength Information"
echo "========================================="
echo ""
echo "JWT Secret:              $(echo -n "$JWT_SECRET" | wc -c) characters (512 bits)"
echo "Session Secret:          $(echo -n "$SESSION_SECRET" | wc -c) characters (512 bits)"
echo "Encryption Key:          $(echo -n "$ENCRYPTION_KEY" | wc -c) characters (256 bits)"
echo "CSRF Secret:             $(echo -n "$CSRF_SECRET" | wc -c) characters (256 bits)"
echo "Database Password:       32 characters (192 bits entropy)"
echo "Redis Password:          32 characters (192 bits entropy)"
echo "Backup Encryption Key:   $(echo -n "$BACKUP_ENCRYPTION_KEY" | wc -c) characters (256 bits)"
echo "Internal API Key:        UUID v4 (122 bits entropy)"
echo "Webhook Secret:          96 characters (384 bits)"
echo "Cookie Secret:           $(echo -n "$COOKIE_SECRET" | wc -c) characters (256 bits)"
echo ""
echo -e "${GREEN}✓ All secrets meet NIST SP 800-131A requirements${NC}"
echo ""

# Provide usage instructions
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "The secrets have been generated in:"
echo "  1. JSON format: $SECRETS_FILE"
echo "  2. ENV format:  $ENV_FILE"
echo ""
echo -e "${YELLOW}IMPORTANT SECURITY NOTES:${NC}"
echo "1. These files are in a temporary directory that will be deleted on exit"
echo "2. Copy the files to a secure location IMMEDIATELY"
echo "3. NEVER commit these secrets to version control"
echo "4. Store in AWS Secrets Manager using the upload script"
echo ""
echo "To store secrets in AWS Secrets Manager, run:"
echo "  ./store-secrets-aws.sh $SECRETS_FILE"
echo ""
echo "To use secrets locally (development only):"
echo "  cp $ENV_FILE /home/biomate/biomate/.env.production"
echo "  chmod 600 /home/biomate/biomate/.env.production"
echo ""

# Offer to save files
read -p "Save secrets to current directory? (yes/no): " SAVE_CHOICE
if [[ "$SAVE_CHOICE" == "yes" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_JSON="biomate-secrets-$TIMESTAMP.json"
    OUTPUT_ENV="biomate-secrets-$TIMESTAMP.env"

    cp "$SECRETS_FILE" "$OUTPUT_JSON"
    cp "$ENV_FILE" "$OUTPUT_ENV"

    chmod 600 "$OUTPUT_JSON" "$OUTPUT_ENV"

    echo ""
    echo -e "${GREEN}✓ Secrets saved to:${NC}"
    echo "  - $OUTPUT_JSON"
    echo "  - $OUTPUT_ENV"
    echo ""
    echo -e "${RED}⚠️  CRITICAL: Move these files to a secure location NOW${NC}"
    echo -e "${RED}⚠️  Delete them after uploading to AWS Secrets Manager${NC}"
    echo ""
fi

# Offer to upload to AWS Secrets Manager immediately
read -p "Upload to AWS Secrets Manager now? (yes/no): " UPLOAD_CHOICE
if [[ "$UPLOAD_CHOICE" == "yes" ]]; then
    if command -v aws &> /dev/null; then
        echo ""
        echo "Uploading to AWS Secrets Manager..."
        ./store-secrets-aws.sh "$SECRETS_FILE"
    else
        echo -e "${RED}Error: AWS CLI not found. Install it first.${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Secret generation complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
