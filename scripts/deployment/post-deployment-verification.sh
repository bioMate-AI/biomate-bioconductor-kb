#!/bin/bash
# Post-Deployment Verification Script
# Run immediately after deploying to production
# Verifies all systems are operational
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

DOMAIN="${DOMAIN:-biomate.ai}"
REPORT_FILE="post-deployment-verification-$(date +%Y%m%d_%H%M%S).txt"

passed=0
failed=0
total=0

echo "========================================="
echo "Post-Deployment Verification"
echo "========================================="
echo "Domain: $DOMAIN"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Logging
log() {
    echo "$1" | tee -a "$REPORT_FILE"
}

# Test function
test_check() {
    local name=$1
    local command=$2
    local critical=${3:-false}

    total=$((total + 1))
    echo -n "  [$total] $name... "

    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        log "[PASS] $name"
        passed=$((passed + 1))
        return 0
    else
        if [[ "$critical" == "true" ]]; then
            echo -e "${RED}✗ CRITICAL${NC}"
            log "[FAIL] $name - CRITICAL"
        else
            echo -e "${YELLOW}⚠ WARNING${NC}"
            log "[WARN] $name"
        fi
        failed=$((failed + 1))
        return 1
    fi
}

# ==================================
# 1. Network and DNS
# ==================================

echo -e "${BLUE}1. Network and DNS${NC}"
log "1. NETWORK AND DNS"
log "=================="

# DNS resolution
test_check "DNS resolution for $DOMAIN" "dig +short $DOMAIN @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'" true

test_check "DNS resolution for www.$DOMAIN" "dig +short www.$DOMAIN @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'" true

# Basic connectivity
test_check "HTTPS port 443 accessible" "timeout 5 bash -c '</dev/tcp/$DOMAIN/443'" true

test_check "HTTP port 80 accessible" "timeout 5 bash -c '</dev/tcp/$DOMAIN/80'"

echo ""
log ""

# ==================================
# 2. SSL/TLS Configuration
# ==================================

echo -e "${BLUE}2. SSL/TLS Configuration${NC}"
log "2. SSL/TLS"
log "=========="

# HTTPS connection
test_check "HTTPS connection successful" "curl -sf --max-time 10 https://$DOMAIN > /dev/null" true

# TLS version
test_check "TLS 1.3 supported" "openssl s_client -connect $DOMAIN:443 -tls1_3 -servername $DOMAIN </dev/null 2>&1 | grep -q 'Protocol  : TLSv1.3'" true

# Certificate validity
test_check "SSL certificate valid" "openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>&1 | openssl x509 -noout -checkend 0" true

# OCSP stapling
test_check "OCSP stapling enabled" "openssl s_client -connect $DOMAIN:443 -servername $DOMAIN -status </dev/null 2>&1 | grep -q 'OCSP Response Status: successful'"

echo ""
log ""

# ==================================
# 3. HTTP to HTTPS Redirect
# ==================================

echo -e "${BLUE}3. HTTP to HTTPS Redirect${NC}"
log "3. REDIRECTS"
log "============"

# Test redirect
HTTP_RESPONSE=$(curl -sI --max-time 10 http://$DOMAIN | head -1)
HTTP_LOCATION=$(curl -sI --max-time 10 http://$DOMAIN | grep -i '^location:' | sed 's/location: //i' | tr -d '\r')

if echo "$HTTP_RESPONSE" | grep -qE '301|302|307|308'; then
    if echo "$HTTP_LOCATION" | grep -q "^https://"; then
        echo -e "  ✓ ${GREEN}HTTP redirects to HTTPS${NC}"
        log "[PASS] HTTP → HTTPS redirect working"
        passed=$((passed + 1))
        total=$((total + 1))
    else
        echo -e "  ✗ ${RED}HTTP redirect not to HTTPS${NC}"
        log "[FAIL] HTTP redirect location: $HTTP_LOCATION"
        failed=$((failed + 1))
        total=$((total + 1))
    fi
else
    echo -e "  ✗ ${RED}No HTTP redirect detected${NC}"
    log "[FAIL] No HTTP redirect"
    failed=$((failed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# 4. Security Headers
# ==================================

echo -e "${BLUE}4. Security Headers${NC}"
log "4. SECURITY HEADERS"
log "==================="

# Get headers
HEADERS=$(curl -sI --max-time 10 https://$DOMAIN)

# HSTS
if echo "$HEADERS" | grep -qi "strict-transport-security:.*max-age"; then
    HSTS_VALUE=$(echo "$HEADERS" | grep -i "strict-transport-security:" | sed 's/.*: //' | tr -d '\r')
    echo -e "  ✓ ${GREEN}HSTS header present${NC}: $HSTS_VALUE"
    log "[PASS] HSTS: $HSTS_VALUE"
    passed=$((passed + 1))
    total=$((total + 1))

    # Check for includeSubDomains and preload
    if echo "$HSTS_VALUE" | grep -q "includeSubDomains"; then
        echo -e "    ✓ includes subdomains"
        log "  [PASS] HSTS includes subdomains"
    fi
    if echo "$HSTS_VALUE" | grep -q "preload"; then
        echo -e "    ✓ preload enabled"
        log "  [PASS] HSTS preload enabled"
    fi
else
    echo -e "  ✗ ${RED}HSTS header missing${NC}"
    log "[FAIL] HSTS header missing"
    failed=$((failed + 1))
    total=$((total + 1))
fi

# X-Frame-Options
test_check "X-Frame-Options header present" "echo '$HEADERS' | grep -qi 'x-frame-options:'" true

# X-Content-Type-Options
test_check "X-Content-Type-Options header present" "echo '$HEADERS' | grep -qi 'x-content-type-options:'" true

# Content-Security-Policy
test_check "Content-Security-Policy header present" "echo '$HEADERS' | grep -qi 'content-security-policy:'"

# Remove 'Server' header
if echo "$HEADERS" | grep -qi "^server:"; then
    echo -e "  ⚠ ${YELLOW}Server header exposed${NC}: $(echo "$HEADERS" | grep -i '^server:' | sed 's/.*: //' | tr -d '\r')"
    log "[WARN] Server header exposed"
else
    echo -e "  ✓ ${GREEN}Server header hidden${NC}"
    log "[PASS] Server header hidden"
    passed=$((passed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# 5. Application Endpoints
# ==================================

echo -e "${BLUE}5. Application Endpoints${NC}"
log "5. ENDPOINTS"
log "============"

# Health endpoint
test_check "Health endpoint responds" "curl -sf --max-time 10 https://$DOMAIN/health" true

HEALTH_RESPONSE=$(curl -sf --max-time 10 https://$DOMAIN/health || echo "")
if [[ -n "$HEALTH_RESPONSE" ]]; then
    log "  Health response: $HEALTH_RESPONSE"
fi

# Homepage
test_check "Homepage loads (200 OK)" "curl -sf --max-time 10 https://$DOMAIN -o /dev/null -w '%{http_code}' | grep -q 200" true

# API health
test_check "API health endpoint responds" "curl -sf --max-time 10 https://$DOMAIN/api/health"

# 404 handling
test_check "404 error handling works" "curl -sf --max-time 10 https://$DOMAIN/nonexistent-page-12345 -o /dev/null -w '%{http_code}' | grep -q 404"

echo ""
log ""

# ==================================
# 6. Rate Limiting
# ==================================

echo -e "${BLUE}6. Rate Limiting${NC}"
log "6. RATE LIMITING"
log "================"

echo "  Testing rate limiting (may take a moment)..."

# Send rapid requests
RATE_LIMIT_TRIGGERED=false
for i in {1..110}; do
    RESPONSE_CODE=$(curl -sf --max-time 2 https://$DOMAIN/api/health -o /dev/null -w '%{http_code}' 2>/dev/null || echo "000")
    if [[ "$RESPONSE_CODE" == "429" ]]; then
        RATE_LIMIT_TRIGGERED=true
        break
    fi
done

if [[ "$RATE_LIMIT_TRIGGERED" == "true" ]]; then
    echo -e "  ✓ ${GREEN}Rate limiting working (429 returned)${NC}"
    log "[PASS] Rate limiting functional"
    passed=$((passed + 1))
    total=$((total + 1))
else
    echo -e "  ⚠ ${YELLOW}Rate limiting not triggered (may need higher threshold)${NC}"
    log "[WARN] Rate limiting not detected in 110 requests"
    failed=$((failed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# 7. Services Status
# ==================================

echo -e "${BLUE}7. System Services${NC}"
log "7. SERVICES"
log "==========="

# Systemd services
test_check "Frontend service running" "systemctl is-active biomate-frontend" true

test_check "Backend service running" "systemctl is-active biomate-backend" true

test_check "Nginx service running" "systemctl is-active nginx" true

# Check for service errors
FRONTEND_ERRORS=$(systemctl status biomate-frontend --no-pager | grep -i error | wc -l || echo 0)
if [[ $FRONTEND_ERRORS -eq 0 ]]; then
    echo -e "  ✓ ${GREEN}No frontend service errors${NC}"
    log "[PASS] No frontend errors"
    passed=$((passed + 1))
    total=$((total + 1))
else
    echo -e "  ⚠ ${YELLOW}Frontend has $FRONTEND_ERRORS errors${NC}"
    log "[WARN] Frontend has $FRONTEND_ERRORS errors"
    failed=$((failed + 1))
    total=$((total + 1))
fi

BACKEND_ERRORS=$(systemctl status biomate-backend --no-pager | grep -i error | wc -l || echo 0)
if [[ $BACKEND_ERRORS -eq 0 ]]; then
    echo -e "  ✓ ${GREEN}No backend service errors${NC}"
    log "[PASS] No backend errors"
    passed=$((passed + 1))
    total=$((total + 1))
else
    echo -e "  ⚠ ${YELLOW}Backend has $BACKEND_ERRORS errors${NC}"
    log "[WARN] Backend has $BACKEND_ERRORS errors"
    failed=$((failed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# 8. Database Connectivity
# ==================================

echo -e "${BLUE}8. Database${NC}"
log "8. DATABASE"
log "==========="

# Test from application (via health endpoint if available)
if curl -sf --max-time 10 https://$DOMAIN/api/health 2>&1 | grep -qi "database.*ok"; then
    echo -e "  ✓ ${GREEN}Database connection healthy${NC}"
    log "[PASS] Database connection healthy"
    passed=$((passed + 1))
    total=$((total + 1))
else
    # If API doesn't provide database status, test directly
    DB_HOST=$(grep "^DB_HOST=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
    DB_USER=$(grep "^DB_USER=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")

    if [[ -n "$DB_HOST" ]] && [[ -n "$DB_USER" ]]; then
        if PGPASSWORD=$(grep "^DB_PASSWORD=" /home/biomate/biomate/.env.production 2>/dev/null | cut -d= -f2 | tr -d '"') timeout 5 psql -h "$DB_HOST" -U "$DB_USER" -d biomate -c "SELECT 1" &> /dev/null; then
            echo -e "  ✓ ${GREEN}Database connection successful${NC}"
            log "[PASS] Database connection successful"
            passed=$((passed + 1))
            total=$((total + 1))
        else
            echo -e "  ✗ ${RED}Database connection failed${NC}"
            log "[FAIL] Database connection failed - CRITICAL"
            failed=$((failed + 1))
            total=$((total + 1))
        fi
    else
        echo -e "  ⚠ ${YELLOW}Cannot test database connection (credentials not found)${NC}"
        log "[WARN] Database credentials not found"
        failed=$((failed + 1))
        total=$((total + 1))
    fi
fi

echo ""
log ""

# ==================================
# 9. Monitoring & Logging
# ==================================

echo -e "${BLUE}9. Monitoring${NC}"
log "9. MONITORING"
log "============="

# Check CloudWatch logs
if aws logs describe-log-groups --log-group-name-prefix /biomate/production --region us-west-2 --query 'length(logGroups)' --output text 2>/dev/null | grep -q '[1-9]'; then
    echo -e "  ✓ ${GREEN}CloudWatch log groups configured${NC}"
    log "[PASS] CloudWatch log groups exist"
    passed=$((passed + 1))
    total=$((total + 1))

    # Check for recent log entries
    RECENT_LOGS=$(aws logs describe-log-streams \
        --log-group-name /biomate/production/backend/access \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --region us-west-2 \
        --query 'logStreams[0].lastEventTimestamp' \
        --output text 2>/dev/null || echo "0")

    if [[ "$RECENT_LOGS" != "0" ]] && [[ "$RECENT_LOGS" != "None" ]]; then
        NOW=$(date +%s)000
        AGE=$(( ($NOW - $RECENT_LOGS) / 60000 ))  # minutes

        if [[ $AGE -lt 60 ]]; then
            echo -e "    ✓ Recent logs ($AGE minutes ago)"
            log "  [PASS] Recent logs: $AGE minutes ago"
        else
            echo -e "    ⚠ Last log $AGE minutes ago"
            log "  [WARN] Last log: $AGE minutes ago"
        fi
    fi
else
    echo -e "  ⚠ ${YELLOW}CloudWatch log groups not found${NC}"
    log "[WARN] CloudWatch log groups not configured"
    failed=$((failed + 1))
    total=$((total + 1))
fi

# Check for CloudWatch alarms
ALARM_COUNT=$(aws cloudwatch describe-alarms --alarm-name-prefix biomate- --region us-west-2 --query 'length(MetricAlarms)' --output text 2>/dev/null || echo "0")

if [[ $ALARM_COUNT -gt 0 ]]; then
    echo -e "  ✓ ${GREEN}CloudWatch alarms configured ($ALARM_COUNT alarms)${NC}"
    log "[PASS] CloudWatch alarms: $ALARM_COUNT"
    passed=$((passed + 1))
    total=$((total + 1))

    # Check alarm states
    ALARM_STATES=$(aws cloudwatch describe-alarms --alarm-name-prefix biomate- --region us-west-2 --query 'MetricAlarms[*].[AlarmName,StateValue]' --output text 2>/dev/null)
    ALARM_COUNT=$(echo "$ALARM_STATES" | grep "ALARM" | wc -l || echo 0)

    if [[ $ALARM_COUNT -gt 0 ]]; then
        echo -e "    ${RED}⚠ $ALARM_COUNT alarms in ALARM state${NC}"
        log "  [WARN] $ALARM_COUNT alarms triggered"
        echo "$ALARM_STATES" | grep "ALARM" | while read line; do
            echo -e "      - $line"
            log "    $line"
        done
    else
        echo -e "    ✓ All alarms OK"
        log "  [PASS] All alarms OK"
    fi
else
    echo -e "  ⚠ ${YELLOW}No CloudWatch alarms configured${NC}"
    log "[WARN] No CloudWatch alarms"
    failed=$((failed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# 10. Performance
# ==================================

echo -e "${BLUE}10. Performance${NC}"
log "10. PERFORMANCE"
log "==============="

# Measure response time
echo "  Measuring response time (10 samples)..."

TOTAL_TIME=0
SUCCESSFUL_REQUESTS=0

for i in {1..10}; do
    RESPONSE_TIME=$(curl -sf --max-time 10 -o /dev/null -w '%{time_total}' https://$DOMAIN/health 2>/dev/null || echo "0")

    if [[ "$RESPONSE_TIME" != "0" ]]; then
        TOTAL_TIME=$(echo "$TOTAL_TIME + $RESPONSE_TIME" | bc)
        SUCCESSFUL_REQUESTS=$((SUCCESSFUL_REQUESTS + 1))
    fi

    sleep 0.5
done

if [[ $SUCCESSFUL_REQUESTS -gt 0 ]]; then
    AVG_TIME=$(echo "scale=3; $TOTAL_TIME / $SUCCESSFUL_REQUESTS" | bc)
    AVG_TIME_MS=$(echo "$AVG_TIME * 1000" | bc | cut -d. -f1)

    echo -e "  Average response time: ${AVG_TIME}s (${AVG_TIME_MS}ms)"
    log "  Average response time: ${AVG_TIME_MS}ms"

    if [[ $AVG_TIME_MS -lt 500 ]]; then
        echo -e "  ✓ ${GREEN}Response time within target (<500ms)${NC}"
        log "[PASS] Response time: ${AVG_TIME_MS}ms (target: <500ms)"
        passed=$((passed + 1))
        total=$((total + 1))
    elif [[ $AVG_TIME_MS -lt 1000 ]]; then
        echo -e "  ⚠ ${YELLOW}Response time above target but acceptable${NC}"
        log "[WARN] Response time: ${AVG_TIME_MS}ms (target: <500ms)"
        failed=$((failed + 1))
        total=$((total + 1))
    else
        echo -e "  ✗ ${RED}Response time too slow${NC}"
        log "[FAIL] Response time: ${AVG_TIME_MS}ms (target: <500ms)"
        failed=$((failed + 1))
        total=$((total + 1))
    fi
else
    echo -e "  ✗ ${RED}Could not measure response time${NC}"
    log "[FAIL] Response time measurement failed"
    failed=$((failed + 1))
    total=$((total + 1))
fi

echo ""
log ""

# ==================================
# Summary
# ==================================

PASS_RATE=$((passed * 100 / total))

echo "========================================="
echo "POST-DEPLOYMENT VERIFICATION SUMMARY"
echo "========================================="
echo ""
echo "Total Checks: $total"
echo -e "Passed:       ${GREEN}$passed${NC}"
echo -e "Failed:       ${RED}$failed${NC}"
echo ""
echo "Pass Rate:    $PASS_RATE%"
echo ""

log ""
log "SUMMARY"
log "======="
log "Total: $total, Passed: $passed, Failed: $failed"
log "Pass Rate: $PASS_RATE%"
log ""

# Recommendations
if [[ $failed -gt 0 ]]; then
    echo "Failed Checks:"
    grep "\[FAIL\]" "$REPORT_FILE" | while read line; do
        echo "  - $line"
    done
    echo ""
fi

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✓ DEPLOYMENT VERIFIED${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "All critical checks passed. System is operational."
    echo ""
    echo "Next steps:"
    echo "  1. Monitor CloudWatch dashboards"
    echo "  2. Review application logs"
    echo "  3. Test user workflows"
    echo "  4. Monitor error rates"
    echo ""

    log "RESULT: SUCCESS"
    exit 0
elif [[ $PASS_RATE -ge 80 ]]; then
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}⚠ DEPLOYMENT PARTIAL${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "Most checks passed, but $failed issues detected."
    echo "Review failed checks and fix if critical."
    echo ""

    log "RESULT: PARTIAL"
    exit 1
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}✗ DEPLOYMENT VERIFICATION FAILED${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "Multiple critical issues detected."
    echo "System may not be fully operational."
    echo ""
    echo "RECOMMENDED ACTIONS:"
    echo "  1. Review failed checks in $REPORT_FILE"
    echo "  2. Check service logs: journalctl -u biomate-frontend -n 100"
    echo "  3. Check nginx logs: tail -100 /var/log/nginx/biomate-error.log"
    echo "  4. Consider rollback if issues are severe"
    echo ""

    log "RESULT: FAILURE"
    exit 2
fi
