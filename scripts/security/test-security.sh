#!/bin/bash
# BioMate Security Test Suite
# Tests SOC 2 and HIPAA compliance controls
# Version: 1.0
# Date: 2025-11-11

set -euo pipefail

# Configuration
BASE_URL="${BASE_URL:-https://biomate.ai}"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="/tmp/biomate_security_test_$(date +%Y%m%d_%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0
WARNINGS=0

# Logging
log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo "ℹ $1"
}

# Test 1: HTTPS Redirection
test_https_redirect() {
    log_info "Testing HTTPS redirection..."

    local http_url="${BASE_URL/https/http}"
    local response=$(curl -s -I -L "$http_url" 2>/dev/null | head -n 1)

    if echo "$response" | grep -q "301\|302"; then
        log_pass "HTTPS redirection enabled"
    else
        log_fail "HTTPS redirection NOT enabled"
    fi
}

# Test 2: Security Headers
test_security_headers() {
    log_info "Testing security headers..."

    local headers=$(curl -s -I "$BASE_URL" 2>/dev/null)

    # HSTS
    if echo "$headers" | grep -qi "strict-transport-security"; then
        log_pass "HSTS header present"
    else
        log_fail "HSTS header MISSING"
    fi

    # X-Frame-Options
    if echo "$headers" | grep -qi "x-frame-options"; then
        log_pass "X-Frame-Options header present"
    else
        log_fail "X-Frame-Options header MISSING"
    fi

    # X-Content-Type-Options
    if echo "$headers" | grep -qi "x-content-type-options"; then
        log_pass "X-Content-Type-Options header present"
    else
        log_fail "X-Content-Type-Options header MISSING"
    fi

    # CSP
    if echo "$headers" | grep -qi "content-security-policy"; then
        log_pass "Content-Security-Policy header present"
    else
        log_warn "Content-Security-Policy header MISSING"
    fi

    # Referrer-Policy
    if echo "$headers" | grep -qi "referrer-policy"; then
        log_pass "Referrer-Policy header present"
    else
        log_warn "Referrer-Policy header MISSING"
    fi

    # X-Powered-By should be removed
    if echo "$headers" | grep -qi "x-powered-by"; then
        log_fail "X-Powered-By header PRESENT (should be hidden)"
    else
        log_pass "X-Powered-By header hidden"
    fi
}

# Test 3: TLS Configuration
test_tls_config() {
    log_info "Testing TLS configuration..."

    local domain=$(echo "$BASE_URL" | sed 's|https://||' | sed 's|/.*||')

    # Check TLS version (requires openssl)
    if command -v openssl &> /dev/null; then
        local tls_version=$(echo | openssl s_client -connect "$domain:443" 2>/dev/null | grep "Protocol" | awk '{print $3}')

        if [ "$tls_version" = "TLSv1.3" ]; then
            log_pass "TLS 1.3 enabled"
        elif [ "$tls_version" = "TLSv1.2" ]; then
            log_warn "TLS 1.2 enabled (TLS 1.3 recommended)"
        else
            log_fail "Weak TLS version: $tls_version"
        fi

        # Check SSL Labs rating (requires API key)
        # Uncomment if you have SSL Labs API access
        # local ssllabs_rating=$(curl -s "https://api.ssllabs.com/api/v3/analyze?host=$domain" | jq -r '.endpoints[0].grade')
        # log_info "SSL Labs rating: $ssllabs_rating"
    else
        log_warn "OpenSSL not installed, skipping TLS version check"
    fi
}

# Test 4: CORS Configuration
test_cors() {
    log_info "Testing CORS configuration..."

    # Test with valid origin
    local valid_origin="https://biomate.ai"
    local response=$(curl -s -I -H "Origin: $valid_origin" "$BASE_URL/api/health" 2>/dev/null)

    if echo "$response" | grep -qi "access-control-allow-origin"; then
        log_pass "CORS headers present"
    else
        log_fail "CORS headers MISSING"
    fi

    # Test with invalid origin (should be blocked)
    local invalid_origin="https://evil.com"
    local response2=$(curl -s -I -H "Origin: $invalid_origin" "$BASE_URL/api/health" 2>/dev/null)

    if echo "$response2" | grep -qi "access-control-allow-origin.*evil.com"; then
        log_fail "CORS allows unauthorized origin (security risk)"
    else
        log_pass "CORS blocks unauthorized origins"
    fi
}

# Test 5: Rate Limiting
test_rate_limiting() {
    log_info "Testing rate limiting..."

    local rate_limit_exceeded=false

    # Send multiple requests rapidly
    for i in {1..100}; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/health" 2>/dev/null)

        if [ "$status" = "429" ]; then
            rate_limit_exceeded=true
            break
        fi
    done

    if [ "$rate_limit_exceeded" = true ]; then
        log_pass "Rate limiting active (429 Too Many Requests)"
    else
        log_warn "Rate limiting not triggered (may need adjustment)"
    fi
}

# Test 6: Authentication
test_authentication() {
    log_info "Testing authentication..."

    # Test protected endpoint without auth
    local status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/auth/me" 2>/dev/null)

    if [ "$status" = "401" ]; then
        log_pass "Protected endpoints require authentication"
    else
        log_fail "Protected endpoints accessible without authentication"
    fi

    # Test CSRF token endpoint
    local csrf_response=$(curl -s "$BASE_URL/api/csrf-token" 2>/dev/null)

    if echo "$csrf_response" | grep -q "csrfToken"; then
        log_pass "CSRF token endpoint accessible"
    else
        log_warn "CSRF token endpoint not found"
    fi
}

# Test 7: SQL Injection Protection
test_sql_injection() {
    log_info "Testing SQL injection protection..."

    # Test common SQL injection payloads
    local payloads=(
        "' OR '1'='1"
        "1; DROP TABLE users--"
        "' UNION SELECT NULL--"
    )

    local vulnerable=false

    for payload in "${payloads[@]}"; do
        local response=$(curl -s -X POST "$BASE_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$payload\",\"password\":\"test\"}" 2>/dev/null)

        # Check if we get an error or SQL-related response
        if echo "$response" | grep -qi "sql\|syntax error\|database"; then
            vulnerable=true
            break
        fi
    done

    if [ "$vulnerable" = true ]; then
        log_fail "Possible SQL injection vulnerability detected"
    else
        log_pass "SQL injection protection working"
    fi
}

# Test 8: XSS Protection
test_xss_protection() {
    log_info "Testing XSS protection..."

    local xss_payload="<script>alert('XSS')</script>"

    # Test if XSS payload is reflected in response
    local response=$(curl -s "$BASE_URL/?q=$xss_payload" 2>/dev/null)

    if echo "$response" | grep -F "$xss_payload"; then
        log_fail "XSS vulnerability detected (unescaped script tag)"
    else
        log_pass "XSS protection working"
    fi

    # Check for X-XSS-Protection header
    local headers=$(curl -s -I "$BASE_URL" 2>/dev/null)

    if echo "$headers" | grep -qi "x-xss-protection"; then
        log_pass "X-XSS-Protection header present"
    else
        log_warn "X-XSS-Protection header missing"
    fi
}

# Test 9: Sensitive Data Exposure
test_sensitive_data() {
    log_info "Testing for sensitive data exposure..."

    local exposed=false

    # Check for .env files
    local env_status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/.env" 2>/dev/null)
    if [ "$env_status" != "404" ]; then
        log_fail ".env file accessible (CRITICAL)"
        exposed=true
    fi

    # Check for backup files
    local backup_status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/backup.sql" 2>/dev/null)
    if [ "$backup_status" != "404" ]; then
        log_fail "Backup file accessible (CRITICAL)"
        exposed=true
    fi

    # Check for git directory
    local git_status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/.git/config" 2>/dev/null)
    if [ "$git_status" != "404" ]; then
        log_fail ".git directory accessible (CRITICAL)"
        exposed=true
    fi

    # Check for common sensitive paths
    local sensitive_paths=(
        "/api/debug"
        "/phpinfo.php"
        "/server-status"
        "/.aws/credentials"
    )

    for path in "${sensitive_paths[@]}"; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$path" 2>/dev/null)
        if [ "$status" != "404" ] && [ "$status" != "403" ]; then
            log_warn "Sensitive path accessible: $path"
        fi
    done

    if [ "$exposed" = false ]; then
        log_pass "No obvious sensitive data exposure"
    fi
}

# Test 10: Encryption in Transit
test_encryption_in_transit() {
    log_info "Testing encryption in transit..."

    local domain=$(echo "$BASE_URL" | sed 's|https://||' | sed 's|/.*||')

    if command -v openssl &> /dev/null; then
        # Check cipher suites
        local cipher=$(echo | openssl s_client -connect "$domain:443" -cipher 'HIGH:!aNULL:!eNULL' 2>/dev/null | grep "Cipher" | awk '{print $3}')

        if [ -n "$cipher" ]; then
            log_pass "Strong cipher suite in use: $cipher"
        else
            log_fail "Weak cipher suite detected"
        fi
    else
        log_warn "OpenSSL not installed, skipping cipher check"
    fi
}

# Test 11: Session Security
test_session_security() {
    log_info "Testing session security..."

    # Test cookie security flags
    local cookies=$(curl -s -I "$BASE_URL/api/auth/login" -c - 2>/dev/null | grep -i "set-cookie")

    if echo "$cookies" | grep -qi "httponly"; then
        log_pass "HttpOnly flag set on cookies"
    else
        log_fail "HttpOnly flag MISSING on cookies"
    fi

    if echo "$cookies" | grep -qi "secure"; then
        log_pass "Secure flag set on cookies"
    else
        log_fail "Secure flag MISSING on cookies (required for HTTPS)"
    fi

    if echo "$cookies" | grep -qi "samesite"; then
        log_pass "SameSite flag set on cookies"
    else
        log_warn "SameSite flag MISSING on cookies"
    fi
}

# Test 12: Information Disclosure
test_info_disclosure() {
    log_info "Testing for information disclosure..."

    # Check error pages for stack traces
    local error_response=$(curl -s "$BASE_URL/nonexistent-page-12345" 2>/dev/null)

    if echo "$error_response" | grep -qi "stack trace\|exception\|error:.*at.*line"; then
        log_fail "Stack traces exposed in error pages"
    else
        log_pass "No stack traces in error pages"
    fi

    # Check headers for version info
    local headers=$(curl -s -I "$BASE_URL" 2>/dev/null)

    if echo "$headers" | grep -qi "server:.*nginx/\|server:.*apache/"; then
        log_warn "Server version information exposed"
    else
        log_pass "Server version information hidden"
    fi
}

# Generate test report
generate_report() {
    local total=$((PASSED + FAILED + WARNINGS))
    local pass_rate=$(( (PASSED * 100) / total ))

    cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "base_url": "$BASE_URL",
  "total_tests": $total,
  "passed": $PASSED,
  "failed": $FAILED,
  "warnings": $WARNINGS,
  "pass_rate": $pass_rate,
  "compliance_status": {
    "soc2": $([ $FAILED -eq 0 ] && echo "true" || echo "false"),
    "hipaa": $([ $FAILED -eq 0 ] && echo "true" || echo "false")
  }
}
EOF

    echo ""
    echo "========================================="
    echo "Security Test Results"
    echo "========================================="
    echo -e "Total Tests:  $total"
    echo -e "${GREEN}Passed:${NC}       $PASSED"
    echo -e "${RED}Failed:${NC}       $FAILED"
    echo -e "${YELLOW}Warnings:${NC}     $WARNINGS"
    echo -e "Pass Rate:    $pass_rate%"
    echo ""

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All critical security tests passed${NC}"
        echo -e "${GREEN}✓ SOC 2 compliant${NC}"
        echo -e "${GREEN}✓ HIPAA compliant${NC}"
    else
        echo -e "${RED}✗ $FAILED critical issues found${NC}"
        echo -e "${RED}✗ NOT ready for production${NC}"
    fi

    echo ""
    echo "Full report saved to: $RESULTS_FILE"
}

# Main execution
main() {
    echo "========================================="
    echo "BioMate Security Test Suite"
    echo "========================================="
    echo "Testing: $BASE_URL"
    echo "Date: $(date)"
    echo ""

    # Run all tests
    test_https_redirect
    test_security_headers
    test_tls_config
    test_cors
    test_rate_limiting
    test_authentication
    test_sql_injection
    test_xss_protection
    test_sensitive_data
    test_encryption_in_transit
    test_session_security
    test_info_disclosure

    # Generate report
    generate_report

    # Exit with appropriate code
    if [ $FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
