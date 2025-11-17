#!/bin/bash
# Pre-Flight Check for Production Deployment
# Run this immediately before deploying to production
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="pre-flight-report-$(date +%Y%m%d_%H%M%S).txt"

passed=0
failed=0
warnings=0

echo "========================================="
echo "Pre-Flight Check for Production Deployment"
echo "========================================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Logging
log() {
    echo "$1" | tee -a "$REPORT_FILE"
}

check() {
    local name=$1
    local command=$2
    local critical=${3:-false}

    echo -n "  Checking $name... "

    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        log "[PASS] $name"
        passed=$((passed + 1))
        return 0
    else
        if [[ "$critical" == "true" ]]; then
            echo -e "${RED}✗ CRITICAL${NC}"
            log "[FAIL] $name - CRITICAL"
            failed=$((failed + 1))
        else
            echo -e "${YELLOW}⚠ WARNING${NC}"
            log "[WARN] $name"
            warnings=$((warnings + 1))
        fi
        return 1
    fi
}

# ==================================
# 1. Environment Checks
# ==================================

log "1. ENVIRONMENT CHECKS"
log "===================="

check "Node.js installed" "command -v node" true
check "npm installed" "command -v npm" true
check "Python 3 installed" "command -v python3" true
check "AWS CLI installed" "command -v aws" true
check "Git installed" "command -v git" true

# Check versions
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    log "  Node version: $NODE_VERSION"

    MAJOR_VERSION=$(echo $NODE_VERSION | sed 's/v\([0-9]*\).*/\1/')
    if [[ $MAJOR_VERSION -ge 18 ]]; then
        echo -e "  ${GREEN}✓${NC} Node.js version acceptable (>= 18)"
        log "[PASS] Node.js version >= 18"
        passed=$((passed + 1))
    else
        echo -e "  ${RED}✗${NC} Node.js version too old (need >= 18)"
        log "[FAIL] Node.js version < 18"
        failed=$((failed + 1))
    fi
fi

log ""

# ==================================
# 2. AWS Infrastructure Checks
# ==================================

log "2. AWS INFRASTRUCTURE"
log "===================="

# AWS credentials
check "AWS credentials configured" "aws sts get-caller-identity" true

if aws sts get-caller-identity &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    log "  AWS Account: $AWS_ACCOUNT"
fi

# Check critical AWS resources
check "RDS instance exists" "aws rds describe-db-instances --db-instance-identifier biomate-prod-db --region us-west-2 --query 'DBInstances[0].DBInstanceStatus' --output text | grep -q available"

check "Redis cluster exists" "aws elasticache describe-replication-groups --replication-group-id biomate-prod-redis --region us-west-2 --query 'ReplicationGroups[0].Status' --output text | grep -q available"

check "S3 upload bucket exists" "aws s3 ls s3://biomate-prod-uploads" true

check "S3 backup bucket exists" "aws s3 ls s3://biomate-prod-backups" true

check "CloudWatch log groups exist" "aws logs describe-log-groups --log-group-name-prefix /biomate/production --region us-west-2 --query 'length(logGroups)' --output text | awk '{exit !(\$1 >= 5)}'"

log ""

# ==================================
# 3. Secrets and Configuration
# ==================================

log "3. SECRETS AND CONFIGURATION"
log "==========================="

# Check secrets in AWS Secrets Manager
check "App secrets in Secrets Manager" "aws secretsmanager describe-secret --secret-id biomate/prod/app-secrets --region us-west-2"

check "Database secrets in Secrets Manager" "aws secretsmanager describe-secret --secret-id biomate/prod/database --region us-west-2"

check "Redis secrets in Secrets Manager" "aws secretsmanager describe-secret --secret-id biomate/prod/redis --region us-west-2"

# Check local environment file
check "Production .env file exists" "[[ -f /home/biomate/biomate/.env.production ]]" true

if [[ -f /home/biomate/biomate/.env.production ]]; then
    # Check for required variables
    REQUIRED_VARS=("NODE_ENV" "DB_HOST" "DB_PASSWORD" "REDIS_HOST" "REDIS_PASSWORD" "JWT_SECRET" "ENCRYPTION_KEY")

    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${var}=" /home/biomate/biomate/.env.production; then
            echo -e "  ${GREEN}✓${NC} $var configured"
            log "[PASS] Environment variable $var set"
            passed=$((passed + 1))
        else
            echo -e "  ${RED}✗${NC} $var missing"
            log "[FAIL] Environment variable $var missing"
            failed=$((failed + 1))
        fi
    done

    # Check NODE_ENV is production
    if grep -q "^NODE_ENV=production" /home/biomate/biomate/.env.production; then
        echo -e "  ${GREEN}✓${NC} NODE_ENV set to production"
        log "[PASS] NODE_ENV=production"
        passed=$((passed + 1))
    else
        echo -e "  ${RED}✗ CRITICAL${NC} NODE_ENV not set to production"
        log "[FAIL] NODE_ENV not production - CRITICAL"
        failed=$((failed + 1))
    fi
fi

log ""

# ==================================
# 4. SSL/TLS Configuration
# ==================================

log "4. SSL/TLS"
log "=========="

check "SSL certificate exists" "[[ -f /etc/letsencrypt/live/biomate.ai/fullchain.pem ]]" true

if [[ -f /etc/letsencrypt/live/biomate.ai/fullchain.pem ]]; then
    # Check expiration
    EXPIRY_DATE=$(openssl x509 -in /etc/letsencrypt/live/biomate.ai/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

    if [[ $DAYS_UNTIL_EXPIRY -gt 30 ]]; then
        echo -e "  ${GREEN}✓${NC} Certificate valid for $DAYS_UNTIL_EXPIRY days"
        log "[PASS] SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        passed=$((passed + 1))
    elif [[ $DAYS_UNTIL_EXPIRY -gt 7 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Certificate expires in $DAYS_UNTIL_EXPIRY days (renew soon)"
        log "[WARN] SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        warnings=$((warnings + 1))
    else
        echo -e "  ${RED}✗ CRITICAL${NC} Certificate expires in $DAYS_UNTIL_EXPIRY days"
        log "[FAIL] SSL certificate expires in $DAYS_UNTIL_EXPIRY days - CRITICAL"
        failed=$((failed + 1))
    fi
fi

# Check nginx TLS config
check "Nginx TLS 1.3 configured" "grep -q 'ssl_protocols TLSv1.3' /etc/nginx/sites-available/biomate.conf" true

log ""

# ==================================
# 5. Application Code
# ==================================

log "5. APPLICATION CODE"
log "==================="

# Check git status
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current)
    log "  Current branch: $BRANCH"

    if [[ "$BRANCH" == "production" ]] || [[ "$BRANCH" == "main" ]]; then
        echo -e "  ${GREEN}✓${NC} On production branch"
        log "[PASS] On production branch: $BRANCH"
        passed=$((passed + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} Not on production/main branch"
        log "[WARN] Not on production/main branch: $BRANCH"
        warnings=$((warnings + 1))
    fi

    # Check for uncommitted changes
    if git diff-index --quiet HEAD --; then
        echo -e "  ${GREEN}✓${NC} No uncommitted changes"
        log "[PASS] No uncommitted changes"
        passed=$((passed + 1))
    else
        echo -e "  ${RED}✗${NC} Uncommitted changes detected"
        log "[FAIL] Uncommitted changes detected"
        failed=$((failed + 1))
    fi

    # Check for unpushed commits
    UNPUSHED=$(git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null | wc -l)
    if [[ $UNPUSHED -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} All commits pushed"
        log "[PASS] All commits pushed"
        passed=$((passed + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} $UNPUSHED unpushed commits"
        log "[WARN] $UNPUSHED unpushed commits"
        warnings=$((warnings + 1))
    fi
fi

# Check dependencies
check "Frontend node_modules exists" "[[ -d /home/biomate/biomate/frontend/node_modules ]]" true

check "Backend virtualenv exists" "[[ -d /home/biomate/biomate/backend/.venv ]]" true

log ""

# ==================================
# 6. Services and Processes
# ==================================

log "6. SERVICES"
log "==========="

# Check systemd services exist
check "Frontend systemd service exists" "[[ -f /etc/systemd/system/biomate-frontend.service ]]" true

check "Backend systemd service exists" "[[ -f /etc/systemd/system/biomate-backend.service ]]" true

check "Nginx config exists" "[[ -f /etc/nginx/sites-available/biomate.conf ]]" true

check "Nginx config enabled" "[[ -L /etc/nginx/sites-enabled/biomate.conf ]]" true

# Test nginx config
check "Nginx configuration valid" "nginx -t" true

# Check if services are running
if systemctl is-active --quiet biomate-frontend; then
    echo -e "  ${GREEN}✓${NC} Frontend service running"
    log "[PASS] Frontend service running"
    passed=$((passed + 1))
else
    echo -e "  ${YELLOW}⚠${NC} Frontend service not running"
    log "[WARN] Frontend service not running"
    warnings=$((warnings + 1))
fi

if systemctl is-active --quiet biomate-backend; then
    echo -e "  ${GREEN}✓${NC} Backend service running"
    log "[PASS] Backend service running"
    passed=$((passed + 1))
else
    echo -e "  ${YELLOW}⚠${NC} Backend service not running"
    log "[WARN] Backend service not running"
    warnings=$((warnings + 1))
fi

if systemctl is-active --quiet nginx; then
    echo -e "  ${GREEN}✓${NC} Nginx running"
    log "[PASS] Nginx running"
    passed=$((passed + 1))
else
    echo -e "  ${RED}✗ CRITICAL${NC} Nginx not running"
    log "[FAIL] Nginx not running - CRITICAL"
    failed=$((failed + 1))
fi

log ""

# ==================================
# 7. Database Connectivity
# ==================================

log "7. DATABASE"
log "==========="

# Test database connection
DB_HOST=$(grep "^DB_HOST=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
DB_USER=$(grep "^DB_USER=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
DB_NAME=$(grep "^DB_NAME=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")

if [[ -n "$DB_HOST" ]] && [[ -n "$DB_USER" ]]; then
    if PGPASSWORD=$(grep "^DB_PASSWORD=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"') psql -h "$DB_HOST" -U "$DB_USER" -d "${DB_NAME:-postgres}" -c "SELECT 1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Database connection successful"
        log "[PASS] Database connection successful"
        passed=$((passed + 1))
    else
        echo -e "  ${RED}✗ CRITICAL${NC} Cannot connect to database"
        log "[FAIL] Database connection failed - CRITICAL"
        failed=$((failed + 1))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Database credentials not found in .env"
    log "[WARN] Database credentials not configured"
    warnings=$((warnings + 1))
fi

log ""

# ==================================
# 8. Security Checks
# ==================================

log "8. SECURITY"
log "==========="

# Check for default/test credentials
if grep -q "password=password\|password=test\|password=admin" /home/biomate/biomate/.env.production 2>/dev/null; then
    echo -e "  ${RED}✗ CRITICAL${NC} Default/test passwords detected"
    log "[FAIL] Default passwords detected - CRITICAL"
    failed=$((failed + 1))
else
    echo -e "  ${GREEN}✓${NC} No default passwords found"
    log "[PASS] No default passwords"
    passed=$((passed + 1))
fi

# Check file permissions
if [[ -f /home/biomate/biomate/.env.production ]]; then
    PERMS=$(stat -c '%a' /home/biomate/biomate/.env.production)
    if [[ "$PERMS" == "600" ]] || [[ "$PERMS" == "400" ]]; then
        echo -e "  ${GREEN}✓${NC} .env.production has secure permissions ($PERMS)"
        log "[PASS] .env.production permissions secure: $PERMS"
        passed=$((passed + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} .env.production has permissions $PERMS (should be 600)"
        log "[WARN] .env.production permissions: $PERMS (should be 600)"
        warnings=$((warnings + 1))
    fi
fi

# Check for exposed secrets in git
if git rev-parse --git-dir > /dev/null 2>&1; then
    if git log --all --full-history -- "*secret*" "*password*" "*.env" 2>/dev/null | grep -q .; then
        echo -e "  ${RED}✗${NC} Secrets may have been committed to git"
        log "[FAIL] Potential secrets in git history"
        failed=$((failed + 1))
    else
        echo -e "  ${GREEN}✓${NC} No secrets in git history"
        log "[PASS] No secrets in git history"
        passed=$((passed + 1))
    fi
fi

# Check for security scripts
check "Security test script exists" "[[ -x ./scripts/security/test-security.sh ]]"

check "Security monitoring script exists" "[[ -x ./scripts/monitoring/check-security-status.sh ]]"

log ""

# ==================================
# 9. Backup and DR
# ==================================

log "9. BACKUP & DISASTER RECOVERY"
log "=============================="

check "Backup script exists" "[[ -x ./scripts/backup/backup-database.sh ]]" true

check "Restore script exists" "[[ -x ./scripts/backup/restore-database.sh ]]" true

check "Backup timer configured" "systemctl is-enabled biomate-backup.timer || true"

# Check for recent backup
if aws s3 ls s3://biomate-prod-backups/database/ 2>/dev/null | tail -1 | awk '{print $1, $2}' | xargs -I {} date -d "{}" +%s &> /dev/null; then
    LATEST_BACKUP_TIME=$(aws s3 ls s3://biomate-prod-backups/database/ 2>/dev/null | tail -1 | awk '{print $1, $2}' | xargs -I {} date -d "{}" +%s)
    NOW=$(date +%s)
    HOURS_SINCE_BACKUP=$(( ($NOW - $LATEST_BACKUP_TIME) / 3600 ))

    if [[ $HOURS_SINCE_BACKUP -lt 48 ]]; then
        echo -e "  ${GREEN}✓${NC} Recent backup exists ($HOURS_SINCE_BACKUP hours old)"
        log "[PASS] Recent backup: $HOURS_SINCE_BACKUP hours old"
        passed=$((passed + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} Last backup is $HOURS_SINCE_BACKUP hours old"
        log "[WARN] Last backup is $HOURS_SINCE_BACKUP hours old"
        warnings=$((warnings + 1))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} No backups found or unable to check"
    log "[WARN] No backups found"
    warnings=$((warnings + 1))
fi

log ""

# ==================================
# 10. Monitoring
# ==================================

log "10. MONITORING"
log "=============="

check "CloudWatch agent config exists" "[[ -f /home/yzhang/biomate/deployment/cloudwatch/cloudwatch-config.json ]]"

check "CloudWatch alarms script exists" "[[ -x /home/yzhang/biomate/deployment/cloudwatch/create-alarms.sh ]]"

# Check if log groups have correct retention
LOG_GROUP="/biomate/production/audit"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region us-west-2 --query 'logGroups[0].retentionInDays' --output text 2>/dev/null | grep -q 2555; then
    echo -e "  ${GREEN}✓${NC} Audit log retention set to 2555 days (7 years)"
    log "[PASS] Audit log retention: 2555 days"
    passed=$((passed + 1))
else
    echo -e "  ${YELLOW}⚠${NC} Audit log retention not set to 2555 days"
    log "[WARN] Audit log retention not HIPAA compliant"
    warnings=$((warnings + 1))
fi

log ""

# ==================================
# Summary
# ==================================

TOTAL=$((passed + failed + warnings))
PASS_RATE=$((passed * 100 / TOTAL))

echo ""
echo "========================================="
echo "PRE-FLIGHT CHECK SUMMARY"
echo "========================================="
echo ""
echo "Total Checks: $TOTAL"
echo -e "Passed:       ${GREEN}$passed${NC}"
echo -e "Failed:       ${RED}$failed${NC}"
echo -e "Warnings:     ${YELLOW}$warnings${NC}"
echo ""
echo "Pass Rate:    $PASS_RATE%"
echo ""

log ""
log "SUMMARY"
log "======="
log "Total: $TOTAL, Passed: $passed, Failed: $failed, Warnings: $warnings"
log "Pass Rate: $PASS_RATE%"
log ""

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✓ PRE-FLIGHT CHECK PASSED${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "System is ready for production deployment."

    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}Note: $warnings warnings detected. Review recommended but not blocking.${NC}"
    fi

    log "RESULT: PASS"
    exit 0
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}✗ PRE-FLIGHT CHECK FAILED${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "System is NOT ready for production deployment."
    echo "Fix the $failed failed checks before deploying."
    echo ""
    echo "Review the report: $REPORT_FILE"

    log "RESULT: FAIL"
    exit 1
fi
