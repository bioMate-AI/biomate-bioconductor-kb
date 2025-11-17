#!/bin/bash
# Test SSL/TLS Configuration for BioMate AI
# Verifies security best practices and compliance
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="${1:-biomate.ai}"
PORT="${2:-443}"

passed_tests=0
failed_tests=0
total_tests=0

echo "========================================="
echo "SSL/TLS Configuration Test"
echo "========================================="
echo "Domain: $DOMAIN"
echo "Port: $PORT"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Function to run test
run_test() {
    local test_name=$1
    local test_command=$2
    local expected=$3

    total_tests=$((total_tests + 1))

    echo -n "[$total_tests] $test_name... "

    if eval "$test_command" &> /dev/null; then
        if [[ "$expected" == "pass" ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_tests=$((passed_tests + 1))
        else
            echo -e "${RED}✗ FAIL${NC} (unexpected pass)"
            failed_tests=$((failed_tests + 1))
        fi
    else
        if [[ "$expected" == "fail" ]]; then
            echo -e "${GREEN}✓ PASS${NC} (expected failure)"
            passed_tests=$((passed_tests + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            failed_tests=$((failed_tests + 1))
        fi
    fi
}

# Function to check header
check_header() {
    local header=$1
    local expected_value=$2

    curl -sI "https://$DOMAIN" | grep -i "^$header:" | grep -q "$expected_value"
}

echo "========================================="
echo "1. Certificate Validity"
echo "========================================="

# Test 1: Certificate is valid
run_test "Certificate is valid" \
    "openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null 2>/dev/null | openssl x509 -noout -checkend 0" \
    "pass"

# Test 2: Certificate matches domain
run_test "Certificate matches domain" \
    "openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null 2>/dev/null | openssl x509 -noout -text | grep -q 'CN=$DOMAIN'" \
    "pass"

# Test 3: Certificate has valid chain
run_test "Certificate chain is complete" \
    "openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null 2>/dev/null | grep -q 'Verify return code: 0'" \
    "pass"

echo ""
echo "========================================="
echo "2. TLS Protocol Support"
echo "========================================="

# Test 4: TLS 1.3 is supported
run_test "TLS 1.3 is supported" \
    "openssl s_client -connect $DOMAIN:$PORT -tls1_3 -servername $DOMAIN </dev/null 2>/dev/null | grep -q 'Protocol  : TLSv1.3'" \
    "pass"

# Test 5: TLS 1.2 is rejected
run_test "TLS 1.2 is rejected" \
    "timeout 5 openssl s_client -connect $DOMAIN:$PORT -tls1_2 -servername $DOMAIN </dev/null 2>&1" \
    "fail"

# Test 6: TLS 1.1 is rejected
run_test "TLS 1.1 is rejected" \
    "timeout 5 openssl s_client -connect $DOMAIN:$PORT -tls1_1 -servername $DOMAIN </dev/null 2>&1" \
    "fail"

# Test 7: TLS 1.0 is rejected
run_test "TLS 1.0 is rejected" \
    "timeout 5 openssl s_client -connect $DOMAIN:$PORT -tls1 -servername $DOMAIN </dev/null 2>&1" \
    "fail"

# Test 8: SSLv3 is rejected
run_test "SSLv3 is rejected" \
    "timeout 5 openssl s_client -connect $DOMAIN:$PORT -ssl3 -servername $DOMAIN </dev/null 2>&1" \
    "fail"

echo ""
echo "========================================="
echo "3. Security Headers"
echo "========================================="

# Test 9: HSTS header present
run_test "HSTS header present" \
    "check_header 'strict-transport-security' 'max-age'" \
    "pass"

# Test 10: HSTS includes subdomains
run_test "HSTS includes subdomains" \
    "check_header 'strict-transport-security' 'includeSubDomains'" \
    "pass"

# Test 11: HSTS includes preload
run_test "HSTS includes preload" \
    "check_header 'strict-transport-security' 'preload'" \
    "pass"

# Test 12: X-Frame-Options present
run_test "X-Frame-Options present" \
    "check_header 'x-frame-options' 'DENY'" \
    "pass"

# Test 13: X-Content-Type-Options present
run_test "X-Content-Type-Options present" \
    "check_header 'x-content-type-options' 'nosniff'" \
    "pass"

# Test 14: Content-Security-Policy present
run_test "Content-Security-Policy present" \
    "curl -sI https://$DOMAIN | grep -qi 'content-security-policy:'" \
    "pass"

echo ""
echo "========================================="
echo "4. Certificate Details"
echo "========================================="

# Get certificate details
CERT_INFO=$(openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null 2>/dev/null | openssl x509 -noout -text)

# Test 15: Key size >= 2048 bits
KEY_SIZE=$(echo "$CERT_INFO" | grep "Public-Key:" | grep -oP '\d+')
if [[ $KEY_SIZE -ge 2048 ]]; then
    echo -e "[$((total_tests + 1))] Key size >= 2048 bits... ${GREEN}✓ PASS${NC} ($KEY_SIZE bits)"
    passed_tests=$((passed_tests + 1))
else
    echo -e "[$((total_tests + 1))] Key size >= 2048 bits... ${RED}✗ FAIL${NC} ($KEY_SIZE bits)"
    failed_tests=$((failed_tests + 1))
fi
total_tests=$((total_tests + 1))

# Test 16: Certificate issuer is Let's Encrypt
run_test "Certificate is from Let's Encrypt" \
    "echo '$CERT_INFO' | grep -q \"Let's Encrypt\"" \
    "pass"

# Test 17: Certificate has SAN (Subject Alternative Names)
run_test "Certificate has SAN extension" \
    "echo '$CERT_INFO' | grep -q 'Subject Alternative Name'" \
    "pass"

echo ""
echo "========================================="
echo "5. OCSP Stapling"
echo "========================================="

# Test 18: OCSP stapling is enabled
run_test "OCSP stapling is enabled" \
    "openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN -status </dev/null 2>&1 | grep -q 'OCSP Response Status: successful'" \
    "pass"

echo ""
echo "========================================="
echo "6. HTTP to HTTPS Redirect"
echo "========================================="

# Test 19: HTTP redirects to HTTPS
run_test "HTTP redirects to HTTPS" \
    "curl -sI http://$DOMAIN | grep -q '301\|302\|307\|308'" \
    "pass"

# Test 20: Redirect location is HTTPS
run_test "Redirect location is HTTPS" \
    "curl -sI http://$DOMAIN | grep -i location | grep -q 'https://'" \
    "pass"

echo ""
echo "========================================="
echo "7. Cipher Suites"
echo "========================================="

# Get supported cipher suites
CIPHERS=$(openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN -tls1_3 </dev/null 2>/dev/null | grep "Cipher")

echo "Supported ciphers:"
echo "$CIPHERS"
echo ""

# Test 21: Uses strong cipher suite
run_test "Uses strong cipher suite" \
    "echo '$CIPHERS' | grep -qE 'TLS_AES_256_GCM_SHA384|TLS_AES_128_GCM_SHA256|TLS_CHACHA20_POLY1305_SHA256'" \
    "pass"

echo ""
echo "========================================="
echo "8. Certificate Expiry"
echo "========================================="

# Get expiry date
EXPIRY_DATE=$(openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

echo "Certificate expires: $EXPIRY_DATE"
echo "Days until expiry: $DAYS_UNTIL_EXPIRY"
echo ""

# Test 22: Certificate doesn't expire soon (>30 days)
total_tests=$((total_tests + 1))
if [[ $DAYS_UNTIL_EXPIRY -gt 30 ]]; then
    echo -e "[$total_tests] Certificate doesn't expire soon... ${GREEN}✓ PASS${NC}"
    passed_tests=$((passed_tests + 1))
elif [[ $DAYS_UNTIL_EXPIRY -gt 7 ]]; then
    echo -e "[$total_tests] Certificate doesn't expire soon... ${YELLOW}⚠ WARNING${NC} (expires in $DAYS_UNTIL_EXPIRY days)"
    passed_tests=$((passed_tests + 1))
else
    echo -e "[$total_tests] Certificate doesn't expire soon... ${RED}✗ FAIL${NC} (expires in $DAYS_UNTIL_EXPIRY days)"
    failed_tests=$((failed_tests + 1))
fi

echo ""
echo "========================================="
echo "9. Performance"
echo "========================================="

# Test 23: Handshake completes quickly
START_TIME=$(date +%s%N)
openssl s_client -connect $DOMAIN:$PORT -servername $DOMAIN </dev/null &>/dev/null
END_TIME=$(date +%s%N)
HANDSHAKE_MS=$(( ($END_TIME - $START_TIME) / 1000000 ))

total_tests=$((total_tests + 1))
echo "Handshake time: ${HANDSHAKE_MS}ms"
if [[ $HANDSHAKE_MS -lt 1000 ]]; then
    echo -e "[$total_tests] Handshake completes quickly... ${GREEN}✓ PASS${NC}"
    passed_tests=$((passed_tests + 1))
elif [[ $HANDSHAKE_MS -lt 2000 ]]; then
    echo -e "[$total_tests] Handshake completes quickly... ${YELLOW}⚠ WARNING${NC} (slow)"
    passed_tests=$((passed_tests + 1))
else
    echo -e "[$total_tests] Handshake completes quickly... ${RED}✗ FAIL${NC} (too slow)"
    failed_tests=$((failed_tests + 1))
fi

echo ""
echo "========================================="
echo "10. External Validation"
echo "========================================="

echo "For comprehensive testing, use:"
echo "  - SSL Labs: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
echo "  - Mozilla Observatory: https://observatory.mozilla.org/analyze/$DOMAIN"
echo "  - SecurityHeaders.com: https://securityheaders.com/?q=$DOMAIN"
echo ""
echo "Expected SSL Labs grade: A+"

echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo ""
echo "Total tests: $total_tests"
echo -e "Passed: ${GREEN}$passed_tests${NC}"
echo -e "Failed: ${RED}$failed_tests${NC}"
echo ""

PASS_PERCENTAGE=$((passed_tests * 100 / total_tests))

if [[ $failed_tests -eq 0 ]]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}ALL TESTS PASSED ($PASS_PERCENTAGE%)${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "✅ SSL/TLS configuration meets security best practices"
    echo "✅ HIPAA §164.312(e)(2)(ii) compliant (encryption in transit)"
    echo "✅ SOC 2 CC6.7 compliant (transmission security)"
    echo ""
    exit 0
elif [[ $failed_tests -le 2 ]]; then
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}TESTS MOSTLY PASSED ($PASS_PERCENTAGE%)${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "⚠️  Minor issues detected. Review failed tests above."
    echo ""
    exit 1
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}TESTS FAILED ($PASS_PERCENTAGE%)${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "❌ SSL/TLS configuration has significant issues"
    echo "❌ Review failed tests and fix before production deployment"
    echo ""
    exit 2
fi
