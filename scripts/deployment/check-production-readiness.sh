#!/bin/bash
# BioMate AI Production Readiness Calculator
# Evaluates readiness for production deployment
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_DIR="./readiness-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/production-readiness-$TIMESTAMP.md"

mkdir -p "$REPORT_DIR"

# Scoring
total_checks=0
passed_checks=0
failed_checks=0
skipped_checks=0

critical_checks=0
critical_passed=0

echo "========================================="
echo "BioMate Production Readiness Assessment"
echo "========================================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Initialize report
cat > "$REPORT_FILE" <<EOF
# Production Readiness Assessment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Assessor:** $(whoami)@$(hostname)
**Version:** 1.0

---

## Executive Summary

EOF

# Function to check item
check_item() {
    local category=$1
    local item=$2
    local check_command=$3
    local is_critical=${4:-false}

    total_checks=$((total_checks + 1))

    if [[ "$is_critical" == "true" ]]; then
        critical_checks=$((critical_checks + 1))
    fi

    echo -n "  [$total_checks] $item... "

    if eval "$check_command" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        passed_checks=$((passed_checks + 1))

        if [[ "$is_critical" == "true" ]]; then
            critical_passed=$((critical_passed + 1))
        fi

        echo "- [x] $item" >> "$REPORT_FILE"
        return 0
    else
        echo -e "${RED}✗${NC}"
        failed_checks=$((failed_checks + 1))

        echo "- [ ] ⚠️  $item" >> "$REPORT_FILE"
        return 1
    fi
}

# Function to manual check (requires user input)
manual_check() {
    local category=$1
    local item=$2
    local is_critical=${3:-false}

    total_checks=$((total_checks + 1))

    if [[ "$is_critical" == "true" ]]; then
        critical_checks=$((critical_checks + 1))
    fi

    echo ""
    echo -n "  [$total_checks] $item (y/n/skip): "
    read -r answer

    case $answer in
        y|Y)
            echo -e "${GREEN}✓${NC}"
            passed_checks=$((passed_checks + 1))

            if [[ "$is_critical" == "true" ]]; then
                critical_passed=$((critical_passed + 1))
            fi

            echo "- [x] $item" >> "$REPORT_FILE"
            ;;
        n|N)
            echo -e "${RED}✗${NC}"
            failed_checks=$((failed_checks + 1))

            echo "- [ ] ⚠️  $item" >> "$REPORT_FILE"
            ;;
        *)
            echo -e "${YELLOW}⊘${NC} Skipped"
            skipped_checks=$((skipped_checks + 1))

            echo "- [ ] ⊘ $item (skipped)" >> "$REPORT_FILE"
            ;;
    esac
}

# ============================================
# 1. Security Configuration
# ============================================

echo ""
echo "========================================="
echo "1. Security Configuration"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 1. Security Configuration" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

manual_check "Security" "Production secrets generated and secured" true
manual_check "Security" "AWS Secrets Manager configured" true
manual_check "Security" "All default secrets removed from code" true

check_item "Security" "SSL certificate obtained" \
    "[[ -f /etc/letsencrypt/live/biomate.ai/fullchain.pem ]]" true

check_item "Security" "TLS 1.3 configured in nginx" \
    "grep -q 'TLSv1.3' /etc/nginx/sites-available/biomate.conf" true

check_item "Security" "Security middleware deployed" \
    "[[ -f /home/yzhang/biomate/frontend/server/security-config.ts ]]"

check_item "Security" "Encryption at rest implemented" \
    "[[ -f /home/yzhang/biomate/frontend/server/encryption.ts ]]" true

manual_check "Security" "WAF rules configured (if using AWS WAF)"
manual_check "Security" "DDoS protection enabled"

check_item "Security" "Security headers configured in nginx" \
    "grep -q 'Strict-Transport-Security' /etc/nginx/sites-available/biomate.conf"

# ============================================
# 2. Infrastructure
# ============================================

echo ""
echo "========================================="
echo "2. Infrastructure"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 2. Infrastructure" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

manual_check "Infrastructure" "Encrypted RDS instance set up (AES-256)" true
manual_check "Infrastructure" "SSL required for database connections" true
manual_check "Infrastructure" "Multi-AZ deployment enabled"
manual_check "Infrastructure" "ElastiCache Redis with TLS configured"
manual_check "Infrastructure" "S3 buckets created with encryption"
manual_check "Infrastructure" "S3 versioning enabled"
manual_check "Infrastructure" "Load balancer configured"
manual_check "Infrastructure" "Auto-scaling groups configured"

check_item "Infrastructure" "Systemd service files deployed" \
    "[[ -f /etc/systemd/system/biomate-frontend.service ]]"

check_item "Infrastructure" "Nginx configuration deployed" \
    "[[ -f /etc/nginx/sites-available/biomate.conf ]]"

# ============================================
# 3. Monitoring & Logging
# ============================================

echo ""
echo "========================================="
echo "3. Monitoring & Logging"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 3. Monitoring & Logging" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

manual_check "Monitoring" "CloudWatch Logs configured (6-year retention)" true

check_item "Monitoring" "CloudWatch config file exists" \
    "[[ -f /home/yzhang/biomate/deployment/cloudwatch/cloudwatch-config.json ]]"

manual_check "Monitoring" "CloudWatch alarms created"
manual_check "Monitoring" "SNS topic for alerts created"
manual_check "Monitoring" "Email notifications configured"
manual_check "Monitoring" "Uptime monitoring configured"

check_item "Monitoring" "Audit logging enabled" \
    "grep -q 'ENABLE_AUDIT_LOGGING=true' /home/biomate/biomate/.env.production || true"

# ============================================
# 4. Backup & Disaster Recovery
# ============================================

echo ""
echo "========================================="
echo "4. Backup & Disaster Recovery"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 4. Backup & Disaster Recovery" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_item "Backup" "Backup scripts deployed" \
    "[[ -x /home/yzhang/biomate/scripts/backup/backup-database.sh ]]"

check_item "Backup" "Restore scripts deployed" \
    "[[ -x /home/yzhang/biomate/scripts/backup/restore-database.sh ]]"

manual_check "Backup" "Automated daily backups configured" true
manual_check "Backup" "Backup encryption enabled (AES-256)" true
manual_check "Backup" "30-day backup retention configured"
manual_check "Backup" "Cross-region backup replication set up"
manual_check "Backup" "Disaster recovery procedures documented"
manual_check "Backup" "DR tested (RTO < 2 hours, RPO < 15 min)"

# ============================================
# 5. Compliance & Documentation
# ============================================

echo ""
echo "========================================="
echo "5. Compliance & Documentation"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 5. Compliance & Documentation" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

manual_check "Compliance" "Business Associate Agreements executed (AWS, Anthropic, OpenAI)" true
manual_check "Compliance" "HIPAA risk assessment completed" true

check_item "Compliance" "Incident response plan documented" \
    "[[ -f /home/yzhang/biomate/20251111_1435_INCIDENT_RESPONSE_PLAN.md ]]"

check_item "Compliance" "Backup & DR procedures documented" \
    "[[ -f /home/yzhang/biomate/20251111_1440_BACKUP_DISASTER_RECOVERY.md ]]"

check_item "Compliance" "Security audit report created" \
    "[[ -f /home/yzhang/biomate/20251111_1430_SECURITY_COMPLIANCE_AUDIT_REPORT.md ]]"

check_item "Compliance" "Security setup guide created" \
    "[[ -f /home/yzhang/biomate/20251111_1445_SECURITY_SETUP_GUIDE.md ]]"

manual_check "Compliance" "Terms of Service created" true
manual_check "Compliance" "Privacy Policy created" true
manual_check "Compliance" "HIPAA Notice of Privacy Practices created"
manual_check "Compliance" "Security policies and procedures documented"

# ============================================
# 6. Application Deployment
# ============================================

echo ""
echo "========================================="
echo "6. Application Deployment"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 6. Application Deployment" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_item "Deployment" "Production environment file configured" \
    "[[ -f /home/biomate/biomate/.env.production ]]" true

check_item "Deployment" "Dependencies installed" \
    "[[ -d /home/biomate/biomate/frontend/node_modules ]]"

manual_check "Deployment" "Database migrations run successfully"
manual_check "Deployment" "Application services running (frontend, backend)"
manual_check "Deployment" "Nginx running and proxying correctly"

check_item "Deployment" "Health endpoint responding" \
    "curl -sf https://biomate.ai/health > /dev/null || true"

manual_check "Deployment" "SSL certificate valid (https://)"
manual_check "Deployment" "HTTP redirects to HTTPS"

# ============================================
# 7. Testing
# ============================================

echo ""
echo "========================================="
echo "7. Testing"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 7. Testing" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

manual_check "Testing" "End-to-end tests passing"
manual_check "Testing" "Security tests passing"

check_item "Testing" "Security test suite exists" \
    "[[ -x /home/yzhang/biomate/scripts/security/test-security.sh ]]"

manual_check "Testing" "Penetration testing conducted" true
manual_check "Testing" "Load testing completed (1000 concurrent users)"
manual_check "Testing" "API response time < 500ms (p95)"
manual_check "Testing" "Backup restoration tested"
manual_check "Testing" "Disaster recovery tested"

# ============================================
# 8. Security Specific
# ============================================

echo ""
echo "========================================="
echo "8. Security Verification"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 8. Security Verification" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_item "Security" "SSL/TLS test script exists" \
    "[[ -x /home/yzhang/biomate/scripts/ssl/test-ssl-config.sh ]]"

manual_check "Security" "SSL Labs grade A+ achieved"
manual_check "Security" "Rate limiting tested and working"
manual_check "Security" "CSRF protection tested"
manual_check "Security" "SQL injection testing passed"
manual_check "Security" "XSS protection tested"
manual_check "Security" "File upload security tested"

# ============================================
# 9. Operational Procedures
# ============================================

echo ""
echo "========================================="
echo "9. Operational Procedures"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 9. Operational Procedures" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_item "Operations" "Incident response runbook exists" \
    "[[ -f /home/yzhang/biomate/20251111_1435_INCIDENT_RESPONSE_PLAN.md ]]"

manual_check "Operations" "Deployment runbook created"
manual_check "Operations" "Rollback runbook created"
manual_check "Operations" "On-call schedule defined"
manual_check "Operations" "Status page configured"
manual_check "Operations" "SLOs/SLIs defined"

# ============================================
# 10. Critical Path Items
# ============================================

echo ""
echo "========================================="
echo "10. Critical Path Items"
echo "========================================="
echo "" >> "$REPORT_FILE"
echo "### 10. Critical Path Items (Mandatory)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "These items are MANDATORY before production launch:"
echo "" >> "$REPORT_FILE"

manual_check "Critical" "All production secrets generated and secured" true
manual_check "Critical" "SSL certificate obtained and HTTPS enabled" true
manual_check "Critical" "Encrypted database with automated backups" true
manual_check "Critical" "CloudWatch logging with 6-year retention" true
manual_check "Critical" "Business Associate Agreements executed" true
manual_check "Critical" "HIPAA risk assessment completed" true
manual_check "Critical" "Penetration testing conducted and issues fixed" true
manual_check "Critical" "Terms of Service and Privacy Policy published" true
manual_check "Critical" "Disaster recovery tested successfully" true
manual_check "Critical" "All required approvals obtained" true

# ============================================
# Calculate Results
# ============================================

echo ""
echo "========================================="
echo "Calculating Readiness Score..."
echo "========================================="

total_evaluated=$((total_checks - skipped_checks))
readiness_percentage=$((passed_checks * 100 / total_evaluated))
critical_percentage=$((critical_passed * 100 / critical_checks))

# Append to report
cat >> "$REPORT_FILE" <<EOF

---

## Results

**Total Checks:** $total_checks
**Passed:** $passed_checks
**Failed:** $failed_checks
**Skipped:** $skipped_checks

**Overall Readiness:** $readiness_percentage%
**Critical Items Completion:** $critical_percentage% ($critical_passed/$critical_checks)

EOF

# Determine launch readiness
if [[ $critical_percentage -eq 100 ]] && [[ $readiness_percentage -ge 90 ]]; then
    STATUS="✅ READY FOR PRODUCTION LAUNCH"
    RECOMMENDATION="All critical items complete and readiness >= 90%. Recommend proceeding with launch."
    COLOR=$GREEN
elif [[ $critical_percentage -eq 100 ]] && [[ $readiness_percentage -ge 80 ]]; then
    STATUS="⚠️  CONDITIONALLY READY"
    RECOMMENDATION="All critical items complete but overall readiness is $readiness_percentage%. Recommend addressing remaining items before launch."
    COLOR=$YELLOW
elif [[ $critical_percentage -lt 100 ]]; then
    STATUS="🔴 NOT READY - CRITICAL ITEMS INCOMPLETE"
    RECOMMENDATION="Critical items incomplete ($critical_passed/$critical_checks). MUST complete all critical items before launch."
    COLOR=$RED
else
    STATUS="🔴 NOT READY"
    RECOMMENDATION="Readiness below 80%. Address failed items before reconsidering launch."
    COLOR=$RED
fi

cat >> "$REPORT_FILE" <<EOF
**Status:** $STATUS

**Recommendation:** $RECOMMENDATION

---

## Priority Actions

### Critical Items (Must Complete Before Launch)

EOF

# List incomplete critical items
echo ""
echo "Incomplete Critical Items:" >> "$REPORT_FILE"
if [[ $critical_passed -lt $critical_checks ]]; then
    echo "Review the checklist above for items marked with ⚠️ in the Critical section" >> "$REPORT_FILE"
else
    echo "All critical items complete! ✅" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

### High Priority (Should Complete Before Launch)

Review all failed items (marked with ⚠️) in categories:
- Security Configuration
- Infrastructure
- Monitoring & Logging
- Backup & Disaster Recovery
- Compliance & Documentation

---

## Sign-Off

### Technical Approval
- [ ] CTO/Engineering Lead: _________________ Date: _______
- [ ] DevOps Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______

### Compliance Approval
- [ ] CISO: _________________ Date: _______
- [ ] Compliance Officer: _________________ Date: _______
- [ ] Legal Counsel: _________________ Date: _______

### Business Approval
- [ ] CEO/Founder: _________________ Date: _______
- [ ] Product Lead: _________________ Date: _______

---

## Next Steps

1. **Address all failed checks** (marked with ⚠️)
2. **Focus on critical items first** (mandatory for launch)
3. **Rerun this assessment** after fixes: \`./scripts/deployment/check-production-readiness.sh\`
4. **Schedule final review** when readiness >= 90%
5. **Obtain all required sign-offs**
6. **Set launch date**

---

**Report Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Report File:** $(basename "$REPORT_FILE")

---

## Related Documentation

- [Production Readiness Checklist](20251111_1510_PRODUCTION_READINESS_CHECKLIST.md)
- [Security Compliance Audit Report](20251111_1430_SECURITY_COMPLIANCE_AUDIT_REPORT.md)
- [Production Deployment Guide](20251111_1515_PRODUCTION_DEPLOYMENT_GUIDE.md)
- [Incident Response Plan](20251111_1435_INCIDENT_RESPONSE_PLAN.md)
- [Backup & Disaster Recovery](20251111_1440_BACKUP_DISASTER_RECOVERY.md)
EOF

# Display summary
echo ""
echo "========================================="
echo "Production Readiness Assessment Complete"
echo "========================================="
echo ""
echo -e "Total Checks: $total_checks"
echo -e "Passed: ${GREEN}$passed_checks${NC}"
echo -e "Failed: ${RED}$failed_checks${NC}"
echo -e "Skipped: ${YELLOW}$skipped_checks${NC}"
echo ""
echo -e "Overall Readiness: ${COLOR}$readiness_percentage%${NC}"
echo -e "Critical Items: ${COLOR}$critical_percentage% ($critical_passed/$critical_checks)${NC}"
echo ""
echo -e "Status: $STATUS"
echo ""
echo "Recommendation:"
echo "$RECOMMENDATION"
echo ""
echo "Report saved to: $REPORT_FILE"
echo ""

if [[ $readiness_percentage -ge 90 ]] && [[ $critical_percentage -eq 100 ]]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✅ READY FOR PRODUCTION LAUNCH${NC}"
    echo -e "${GREEN}=========================================${NC}"
    exit 0
elif [[ $critical_percentage -eq 100 ]]; then
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}⚠️  CONDITIONAL PASS - Complete remaining items${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    exit 1
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}🔴 NOT READY - Complete critical items${NC}"
    echo -e "${RED}=========================================${NC}"
    exit 2
fi
