#!/bin/bash
# BioMate Security Status Monitor
# Continuous monitoring of security posture
# Version: 1.0
# Date: 2025-11-11

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS_FILE="/var/log/biomate/security-status.json"
ALERT_THRESHOLD=70  # Alert if security score < 70%

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Check result
check() {
    local name="$1"
    local command="$2"
    local critical="${3:-false}"

    ((TOTAL_CHECKS++))

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        ((PASSED_CHECKS++))
        return 0
    else
        if [ "$critical" = "true" ]; then
            echo -e "${RED}✗ [CRITICAL]${NC} $name"
        else
            echo -e "${YELLOW}⚠${NC} $name"
        fi
        ((FAILED_CHECKS++))
        return 1
    fi
}

echo "========================================="
echo "BioMate Security Status Monitor"
echo "========================================="
echo "Date: $(date)"
echo ""

# 1. Check environment variables
echo "=== Environment Configuration ==="

check "ENCRYPTION_KEY set" \
    "[ -n \"\${ENCRYPTION_KEY:-}\" ]" \
    true

check "JWT_SECRET set" \
    "[ -n \"\${JWT_SECRET:-}\" ]" \
    true

check "DATABASE_URL uses SSL" \
    "echo \"\${DATABASE_URL:-}\" | grep -q 'sslmode=require'" \
    true

check "Production secrets not using defaults" \
    "! echo \"\${JWT_SECRET:-}\" | grep -q 'your-secret-key-change-in-production'" \
    true

echo ""

# 2. Check file permissions
echo "=== File Permissions ==="

check ".env file not world-readable" \
    "[ ! -e \"$PROJECT_ROOT/.env\" ] || [ \$(stat -c '%a' \"$PROJECT_ROOT/.env\" 2>/dev/null || stat -f '%A' \"$PROJECT_ROOT/.env\") -le 600 ]" \
    true

check "Sensitive config files protected" \
    "[ ! -e \"$PROJECT_ROOT/backend/config/galaxy.yml\" ] || [ \$(stat -c '%a' \"$PROJECT_ROOT/backend/config/galaxy.yml\" 2>/dev/null || stat -f '%A' \"$PROJECT_ROOT/backend/config/galaxy.yml\") -le 640 ]" \
    false

echo ""

# 3. Check dependencies
echo "=== Dependencies & Vulnerabilities ==="

if [ -f "$PROJECT_ROOT/frontend/package.json" ]; then
    check "No critical npm vulnerabilities" \
        "cd \"$PROJECT_ROOT/frontend\" && npm audit --audit-level=critical --json 2>/dev/null | jq -e '.metadata.vulnerabilities.critical == 0'" \
        true

    check "Security packages installed" \
        "cd \"$PROJECT_ROOT/frontend\" && npm list helmet cors csrf-sync > /dev/null 2>&1" \
        true
fi

echo ""

# 4. Check SSL/TLS certificates
echo "=== SSL/TLS Status ==="

if command -v openssl &> /dev/null; then
    check "SSL certificate valid" \
        "echo | openssl s_client -connect biomate.ai:443 -servername biomate.ai 2>/dev/null | openssl x509 -noout -checkend 2592000" \
        true

    check "SSL certificate not self-signed" \
        "! echo | openssl s_client -connect biomate.ai:443 -servername biomate.ai 2>/dev/null | grep -q 'self signed'" \
        false
else
    echo -e "${YELLOW}⚠${NC} OpenSSL not installed, skipping certificate checks"
fi

echo ""

# 5. Check database security
echo "=== Database Security ==="

if [ -n "${DATABASE_URL:-}" ]; then
    check "Database connection encrypted" \
        "echo \"\$DATABASE_URL\" | grep -q 'sslmode=require\\|sslmode=verify-full'" \
        true

    # Check database is accessible
    if command -v psql &> /dev/null; then
        check "Database accessible" \
            "psql \"\$DATABASE_URL\" -c 'SELECT 1;' > /dev/null 2>&1" \
            true
    fi
fi

echo ""

# 6. Check backup status
echo "=== Backup Status ==="

if [ -n "${S3_BACKUP_BUCKET:-}" ]; then
    check "Recent backup exists (<24h)" \
        "aws s3 ls \"s3://\${S3_BACKUP_BUCKET}/daily/\$(date +%Y/%m/%d)/\" 2>/dev/null | grep -q '.sql.enc'" \
        true

    check "Backup bucket encrypted" \
        "aws s3api get-bucket-encryption --bucket \"\$S3_BACKUP_BUCKET\" 2>/dev/null | grep -q 'AES256'" \
        true
fi

echo ""

# 7. Check audit logging
echo "=== Audit Logging ==="

check "Audit log directory exists" \
    "[ -d \"/var/log/biomate\" ]" \
    true

check "Audit logs being written" \
    "[ -f \"/var/log/biomate/audit.log\" ] && [ \$(find \"/var/log/biomate/audit.log\" -mtime -1 | wc -l) -gt 0 ]" \
    false

echo ""

# 8. Check services status
echo "=== Services Status ==="

if command -v systemctl &> /dev/null; then
    check "Frontend service running" \
        "systemctl is-active --quiet biomate-frontend || pgrep -f 'node.*index.js'" \
        true

    check "Backend service running" \
        "systemctl is-active --quiet biomate-backend || pgrep -f 'gunicorn.*galaxy'" \
        true
fi

echo ""

# 9. Check monitoring
echo "=== Monitoring & Alerting ==="

check "CloudWatch agent installed" \
    "command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl" \
    false

check "Sentry DSN configured" \
    "[ -n \"\${SENTRY_DSN:-}\" ]" \
    false

echo ""

# 10. Check compliance
echo "=== Compliance Status ==="

check "HIPAA mode enabled" \
    "[ \"\${HIPAA_MODE:-false}\" = \"true\" ]" \
    true

check "PHI encryption enabled" \
    "[ \"\${ENCRYPT_PHI:-false}\" = \"true\" ]" \
    true

check "Audit log retention configured" \
    "[ \"\${AUDIT_LOG_RETENTION_DAYS:-0}\" -ge 2190 ]" \
    true

echo ""

# Calculate security score
SECURITY_SCORE=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))

# Generate status report
mkdir -p "$(dirname "$STATUS_FILE")"

cat > "$STATUS_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_checks": $TOTAL_CHECKS,
  "passed": $PASSED_CHECKS,
  "failed": $FAILED_CHECKS,
  "security_score": $SECURITY_SCORE,
  "status": "$([ $SECURITY_SCORE -ge 80 ] && echo "GOOD" || echo "NEEDS_ATTENTION")",
  "compliance": {
    "soc2_ready": $([ $SECURITY_SCORE -ge 85 ] && echo "true" || echo "false"),
    "hipaa_ready": $([ $SECURITY_SCORE -ge 85 ] && echo "true" || echo "false")
  }
}
EOF

# Display summary
echo "========================================="
echo "Security Status Summary"
echo "========================================="
echo "Total Checks:    $TOTAL_CHECKS"
echo -e "${GREEN}Passed:${NC}          $PASSED_CHECKS"
echo -e "${RED}Failed:${NC}          $FAILED_CHECKS"
echo "Security Score:  ${SECURITY_SCORE}%"
echo ""

if [ $SECURITY_SCORE -ge 90 ]; then
    echo -e "${GREEN}✓ Excellent security posture${NC}"
elif [ $SECURITY_SCORE -ge 80 ]; then
    echo -e "${GREEN}✓ Good security posture${NC}"
elif [ $SECURITY_SCORE -ge 70 ]; then
    echo -e "${YELLOW}⚠ Adequate but needs improvement${NC}"
else
    echo -e "${RED}✗ Poor security posture - immediate action required${NC}"
fi

echo ""
echo "Full status saved to: $STATUS_FILE"

# Send alert if score is too low
if [ $SECURITY_SCORE -lt $ALERT_THRESHOLD ]; then
    if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
        curl -X POST "$ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\": \"Security Alert: BioMate security score is ${SECURITY_SCORE}% (threshold: ${ALERT_THRESHOLD}%)\",
                \"severity\": \"high\",
                \"timestamp\": \"$(date -Iseconds)\",
                \"details\": \"$FAILED_CHECKS out of $TOTAL_CHECKS checks failed\"
            }" \
            > /dev/null 2>&1 || true
    fi
fi

# Exit with appropriate code
if [ $SECURITY_SCORE -ge $ALERT_THRESHOLD ]; then
    exit 0
else
    exit 1
fi
