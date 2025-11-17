#!/bin/bash

################################################################################
# BioMate AI - Production Setup Guide
################################################################################
#
# This script guides you through the production setup process step-by-step.
# It performs read-only checks and provides clear instructions for each step.
#
# Usage: ./setup-production.sh
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
ADMIN_EMAIL="yaoyun.zhang@biomate.ai"
AWS_REGION="us-east-1"
DOMAIN="biomate.ai"

echo "========================================"
echo "BioMate AI - Production Setup"
echo "========================================"
echo ""
echo "Administrator: $ADMIN_EMAIL"
echo "AWS Region: $AWS_REGION"
echo "Domain: $DOMAIN"
echo ""

################################################################################
# Step 1: Environment Check
################################################################################

echo "========================================"
echo "Step 1: Environment Check"
echo "========================================"
echo ""

check_command() {
    local cmd=$1
    local name=$2
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $name installed"
        return 0
    else
        echo -e "${RED}✗${NC} $name not found"
        return 1
    fi
}

CHECKS_PASSED=0
CHECKS_FAILED=0

# Check required commands
if check_command "node" "Node.js"; then
    NODE_VERSION=$(node --version)
    echo "  Version: $NODE_VERSION"
    ((CHECKS_PASSED++))
else
    echo "  Install: https://nodejs.org/"
    ((CHECKS_FAILED++))
fi

if check_command "python3" "Python 3"; then
    PYTHON_VERSION=$(python3 --version)
    echo "  Version: $PYTHON_VERSION"
    ((CHECKS_PASSED++))
else
    echo "  Install: sudo apt-get install python3"
    ((CHECKS_FAILED++))
fi

if check_command "aws" "AWS CLI"; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1)
    echo "  Version: $AWS_VERSION"
    ((CHECKS_PASSED++))
else
    echo "  Install: https://aws.amazon.com/cli/"
    ((CHECKS_FAILED++))
fi

if check_command "git" "Git"; then
    GIT_VERSION=$(git --version)
    echo "  Version: $GIT_VERSION"
    ((CHECKS_PASSED++))
else
    echo "  Install: sudo apt-get install git"
    ((CHECKS_FAILED++))
fi

if check_command "jq" "jq"; then
    JQ_VERSION=$(jq --version)
    echo "  Version: $JQ_VERSION"
    ((CHECKS_PASSED++))
else
    echo "  Install: sudo apt-get install jq"
    ((CHECKS_FAILED++))
fi

echo ""
echo "Environment checks: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo ""

if [[ $CHECKS_FAILED -gt 0 ]]; then
    echo -e "${YELLOW}⚠${NC} Please install missing dependencies before continuing"
    echo ""
fi

################################################################################
# Step 2: AWS Configuration Check
################################################################################

echo "========================================"
echo "Step 2: AWS Configuration Check"
echo "========================================"
echo ""

if aws sts get-caller-identity &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
    echo -e "${GREEN}✓${NC} AWS CLI configured"
    echo "  Account: $AWS_ACCOUNT"
    echo "  User: $AWS_USER"
    echo "  Region: $AWS_REGION"
else
    echo -e "${RED}✗${NC} AWS CLI not configured"
    echo ""
    echo "Configure with:"
    echo "  aws configure"
    echo ""
    exit 1
fi

echo ""

################################################################################
# Step 3: Infrastructure Status
################################################################################

echo "========================================"
echo "Step 3: Current Infrastructure Status"
echo "========================================"
echo ""

echo "Checking RDS instances..."
RDS_COUNT=$(aws rds describe-db-instances --region "$AWS_REGION" --query 'length(DBInstances)' --output text 2>/dev/null || echo "0")
if [[ "$RDS_COUNT" == "0" ]]; then
    echo -e "${YELLOW}⚠${NC} No RDS instances found"
else
    echo -e "${GREEN}✓${NC} Found $RDS_COUNT RDS instance(s)"
    aws rds describe-db-instances --region "$AWS_REGION" \
        --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,MultiAZ:MultiAZ,Encrypted:StorageEncrypted}' \
        --output table
fi

echo ""
echo "Checking ElastiCache clusters..."
REDIS_COUNT=$(aws elasticache describe-cache-clusters --region "$AWS_REGION" --query 'length(CacheClusters)' --output text 2>/dev/null || echo "0")
if [[ "$REDIS_COUNT" == "0" ]]; then
    echo -e "${YELLOW}⚠${NC} No ElastiCache clusters found"
else
    echo -e "${GREEN}✓${NC} Found $REDIS_COUNT ElastiCache cluster(s)"
fi

echo ""
echo "Checking S3 buckets..."
S3_BIOMATE_COUNT=$(aws s3 ls 2>/dev/null | grep -i biomate | wc -l || echo "0")
if [[ "$S3_BIOMATE_COUNT" == "0" ]]; then
    echo -e "${YELLOW}⚠${NC} No BioMate S3 buckets found"
else
    echo -e "${GREEN}✓${NC} Found $S3_BIOMATE_COUNT BioMate S3 bucket(s)"
    aws s3 ls | grep -i biomate
fi

echo ""
echo "Checking Secrets Manager..."
SECRET_COUNT=$(aws secretsmanager list-secrets --region "$AWS_REGION" --query 'length(SecretList)' --output text 2>/dev/null || echo "0")
if [[ "$SECRET_COUNT" == "0" ]]; then
    echo -e "${YELLOW}⚠${NC} No secrets found in Secrets Manager"
else
    echo -e "${GREEN}✓${NC} Found $SECRET_COUNT secret(s)"
fi

echo ""

################################################################################
# Step 4: Security Status
################################################################################

echo "========================================"
echo "Step 4: Security Status"
echo "========================================"
echo ""

echo "Checking for local .env.production file..."
if [[ -f ".env.production" ]]; then
    echo -e "${GREEN}✓${NC} .env.production exists"
    echo "  Size: $(du -h .env.production | cut -f1)"
else
    echo -e "${YELLOW}⚠${NC} .env.production not found"
    echo "  Will need to generate production secrets"
fi

echo ""
echo "Checking for SSL certificates..."
if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    echo -e "${GREEN}✓${NC} SSL certificate found for $DOMAIN"
    CERT_EXPIRY=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
    echo "  Expires: $CERT_EXPIRY"
else
    echo -e "${YELLOW}⚠${NC} No SSL certificate found for $DOMAIN"
    echo "  Will need to run: sudo ./scripts/ssl/setup-ssl-cert.sh $DOMAIN $ADMIN_EMAIL"
fi

echo ""

################################################################################
# Step 5: Compliance Status
################################################################################

echo "========================================"
echo "Step 5: Compliance Status"
echo "========================================"
echo ""

echo "Checking for HIPAA assessment..."
HIPAA_ASSESSMENTS=$(find . -name "hipaa-assessment-*.json" -type f 2>/dev/null | wc -l)
if [[ "$HIPAA_ASSESSMENTS" == "0" ]]; then
    echo -e "${YELLOW}⚠${NC} No HIPAA assessments found"
    echo "  Run: ./scripts/compliance/hipaa-risk-assessment.sh"
else
    echo -e "${GREEN}✓${NC} Found $HIPAA_ASSESSMENTS HIPAA assessment(s)"
    LATEST_ASSESSMENT=$(find . -name "hipaa-assessment-*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2)
    echo "  Latest: $LATEST_ASSESSMENT"
fi

echo ""
echo "Checking for legal documents..."
LEGAL_DOCS=0
[[ -f "legal-templates/TERMS_OF_SERVICE_TEMPLATE.md" ]] && ((LEGAL_DOCS++))
[[ -f "legal-templates/PRIVACY_POLICY_TEMPLATE.md" ]] && ((LEGAL_DOCS++))
[[ -f "legal-templates/HIPAA_NOTICE_OF_PRIVACY_PRACTICES_TEMPLATE.md" ]] && ((LEGAL_DOCS++))

if [[ "$LEGAL_DOCS" == "3" ]]; then
    echo -e "${GREEN}✓${NC} All legal document templates present"
    echo "  ⚠ Templates require legal review before publication"
else
    echo -e "${RED}✗${NC} Missing legal document templates"
fi

echo ""

################################################################################
# Step 6: Next Steps
################################################################################

echo "========================================"
echo "Next Steps for Production Launch"
echo "========================================"
echo ""

STEP_NUM=1

# Infrastructure deployment
if [[ "$RDS_COUNT" == "0" ]] || [[ "$REDIS_COUNT" == "0" ]] || [[ "$S3_BIOMATE_COUNT" == "0" ]]; then
    echo "${STEP_NUM}. Deploy AWS Infrastructure"
    echo "   - Set up RDS PostgreSQL (Multi-AZ, encrypted)"
    echo "   - Set up ElastiCache Redis (Multi-AZ, TLS)"
    echo "   - Create S3 buckets (versioning, encryption)"
    echo "   - Configure CloudWatch (logs, metrics, alarms)"
    echo ""
    ((STEP_NUM++))
fi

# Secrets
if [[ "$SECRET_COUNT" == "0" ]]; then
    echo "${STEP_NUM}. Generate and Store Production Secrets"
    echo "   Run: ./scripts/security/generate-secrets.sh"
    echo "   Then: ./scripts/security/store-secrets-aws.sh"
    echo ""
    ((STEP_NUM++))
fi

# SSL
if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    echo "${STEP_NUM}. Set Up SSL Certificate"
    echo "   Run: sudo ./scripts/ssl/setup-ssl-cert.sh $DOMAIN $ADMIN_EMAIL"
    echo ""
    ((STEP_NUM++))
fi

# HIPAA assessment
if [[ "$HIPAA_ASSESSMENTS" == "0" ]]; then
    echo "${STEP_NUM}. Complete HIPAA Risk Assessment"
    echo "   Run: ./scripts/compliance/hipaa-risk-assessment.sh"
    echo ""
    ((STEP_NUM++))
fi

# Legal review
echo "${STEP_NUM}. Legal Document Review (REQUIRED)"
echo "   - Engage qualified legal counsel (\$2K-\$10K)"
echo "   - Review and customize legal-templates/"
echo "   - Publish to website after approval"
echo ""
((STEP_NUM++))

# BAAs
echo "${STEP_NUM}. Execute Business Associate Agreements"
echo "   Required vendors:"
echo "   - AWS (https://aws.amazon.com/compliance/hipaa-baa-request/)"
echo "   - Anthropic (contact: enterprise@anthropic.com)"
echo "   - OpenAI (contact: enterprise@openai.com)"
echo "   - Payment processor"
echo ""
((STEP_NUM++))

# Training
echo "${STEP_NUM}. HIPAA Training"
echo "   - All employees must complete HIPAA Privacy & Security training"
echo "   - Document completion with certificates"
echo "   - Retain records for 6+ years"
echo ""
((STEP_NUM++))

# Penetration testing
echo "${STEP_NUM}. Schedule Penetration Testing"
echo "   - Review guide: 20251111_1535_PENETRATION_TESTING_GUIDE.md"
echo "   - Budget: \$5K-\$50K depending on scope"
echo "   - Schedule 2-4 weeks before launch"
echo ""
((STEP_NUM++))

# Insurance
echo "${STEP_NUM}. Obtain Cyber Liability Insurance"
echo "   - Coverage: Data breach, business interruption, HIPAA violations"
echo "   - Annual cost: \$1K-\$7.5K"
echo ""
((STEP_NUM++))

# Final checks
echo "${STEP_NUM}. Final Production Readiness"
echo "   Run: ./scripts/deployment/launch-coordinator.sh"
echo "   - Guides through all 7 launch phases"
echo "   - Collects executive sign-offs"
echo "   - Creates launch artifacts"
echo ""

echo "========================================"
echo "Helpful Resources"
echo "========================================"
echo ""
echo "Documentation:"
echo "  - Secrets Management: 20251111_1525_SECRETS_MANAGEMENT_GUIDE.md"
echo "  - HIPAA Compliance: 20251111_1530_HIPAA_COMPLIANCE_GUIDE.md"
echo "  - Penetration Testing: 20251111_1535_PENETRATION_TESTING_GUIDE.md"
echo "  - Evidence Collection: 20251111_COMPLIANCE_EVIDENCE_GUIDE.md"
echo "  - Complete Summary: SESSION_SUMMARY_20251111_PRODUCTION_LAUNCH_COMPLETE.md"
echo ""
echo "Scripts:"
echo "  - Generate secrets: ./scripts/security/generate-secrets.sh"
echo "  - SSL setup: sudo ./scripts/ssl/setup-ssl-cert.sh"
echo "  - HIPAA assessment: ./scripts/compliance/hipaa-risk-assessment.sh"
echo "  - Evidence collection: ./scripts/compliance/collect-evidence.sh"
echo "  - Launch coordinator: ./scripts/deployment/launch-coordinator.sh"
echo ""

echo "========================================"
echo "Estimated Timeline to Launch: 4-5 weeks"
echo "========================================"
echo ""
echo "Week 1: Security foundation (secrets, SSL, assessments)"
echo "Week 2: Legal review and BAAs"
echo "Week 3: Infrastructure deployment and testing"
echo "Week 4: Final preparation and penetration testing"
echo "Week 5: Launch"
echo ""

echo "Configuration file: .biomate-config"
echo "Admin email: $ADMIN_EMAIL"
echo ""
echo "For questions: $ADMIN_EMAIL"
echo ""
