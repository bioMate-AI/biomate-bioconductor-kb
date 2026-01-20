#!/bin/bash
# E2E Test Runner with Video Recording for BioMate
#
# This script runs end-to-end tests with video recording for audit purposes.
# Videos are saved to: frontend/e2e/videos/
# Screenshots are saved to: frontend/e2e/screenshots/
# Reports are saved to: frontend/e2e/reports/
#
# Usage:
#   ./scripts/run-e2e-with-video.sh              # Run all e2e tests
#   ./scripts/run-e2e-with-video.sh --headed     # Run with visible browser
#   ./scripts/run-e2e-with-video.sh --ui         # Run with Playwright UI
#   ./scripts/run-e2e-with-video.sh vcf          # Run only VCF viewer tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUDIT_DIR="$PROJECT_ROOT/docs/audit/${TIMESTAMP}_e2e_tests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "BioMate E2E Test Runner with Video Recording"
echo "=================================================="
echo "Timestamp: $TIMESTAMP"
echo "Audit Directory: $AUDIT_DIR"
echo "=================================================="
echo ""

# Create audit directory
mkdir -p "$AUDIT_DIR"

# Check if server is running
check_server() {
    echo -n "Checking if frontend server is running... "
    if curl -s -o /dev/null -w "" http://localhost:5000 2>/dev/null; then
        echo -e "${GREEN}Running${NC}"
        return 0
    else
        echo -e "${YELLOW}Not running${NC}"
        return 1
    fi
}

# Start the frontend server
start_server() {
    echo "Starting frontend server in background..."
    cd "$FRONTEND_DIR"
    npm run dev > "$AUDIT_DIR/server.log" 2>&1 &
    SERVER_PID=$!
    echo "Server PID: $SERVER_PID"

    # Wait for server to be ready
    echo -n "Waiting for server to start"
    for i in {1..30}; do
        if curl -s -o /dev/null -w "" http://localhost:5000 2>/dev/null; then
            echo -e " ${GREEN}Ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo -e " ${RED}Failed to start${NC}"
    kill $SERVER_PID 2>/dev/null || true
    return 1
}

# Stop server if we started it
stop_server() {
    if [ -n "$SERVER_PID" ]; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
    fi
}

# Run e2e tests
run_tests() {
    local test_args="$@"

    echo ""
    echo "Running E2E tests with video recording..."
    echo "Test arguments: $test_args"
    echo ""

    cd "$FRONTEND_DIR"

    # Run playwright tests
    if [ -z "$test_args" ]; then
        npx playwright test --reporter=html,json,list
    else
        npx playwright test $test_args --reporter=html,json,list
    fi

    return $?
}

# Copy results to audit directory
copy_results() {
    echo ""
    echo "Copying test results to audit directory..."

    # Copy videos
    if [ -d "$FRONTEND_DIR/e2e/test-results" ]; then
        cp -r "$FRONTEND_DIR/e2e/test-results" "$AUDIT_DIR/test-results"
    fi

    # Copy screenshots
    if [ -d "$FRONTEND_DIR/e2e/screenshots" ]; then
        cp -r "$FRONTEND_DIR/e2e/screenshots" "$AUDIT_DIR/screenshots"
    fi

    # Copy reports
    if [ -d "$FRONTEND_DIR/e2e/reports" ]; then
        cp -r "$FRONTEND_DIR/e2e/reports" "$AUDIT_DIR/reports"
    fi

    # Find and copy video files
    mkdir -p "$AUDIT_DIR/videos"
    find "$FRONTEND_DIR/e2e" -name "*.webm" -exec cp {} "$AUDIT_DIR/videos/" \; 2>/dev/null || true

    # Generate summary
    cat > "$AUDIT_DIR/E2E_TEST_SUMMARY.md" << EOF
# E2E Test Execution Summary

**Date:** $(date)
**Timestamp:** $TIMESTAMP

## Test Configuration
- Browser: Chromium
- Video Recording: Enabled
- Screenshot Mode: On failure
- Trace Collection: Enabled

## Output Locations
- Videos: $AUDIT_DIR/videos/
- Screenshots: $AUDIT_DIR/screenshots/
- Reports: $AUDIT_DIR/reports/
- Test Results: $AUDIT_DIR/test-results/

## Test Files Executed
$(ls -la "$FRONTEND_DIR/e2e"/*.ts 2>/dev/null | awk '{print "- " $NF}' || echo "- None found")

## How to View Results

### View HTML Report
\`\`\`bash
cd $FRONTEND_DIR && npm run e2e:report
\`\`\`

### Replay Test Trace
\`\`\`bash
npx playwright show-trace $AUDIT_DIR/test-results/*/trace.zip
\`\`\`

### View Videos
Videos are in WebM format and can be viewed with VLC or in a web browser.
EOF

    echo "Results copied to: $AUDIT_DIR"
}

# Main execution
main() {
    local test_args=""
    local started_server=false

    # Parse arguments
    for arg in "$@"; do
        test_args="$test_args $arg"
    done

    # Check/start server
    if ! check_server; then
        start_server
        started_server=true
    fi

    # Ensure cleanup on exit
    trap 'if [ "$started_server" = true ]; then stop_server; fi' EXIT

    # Run tests
    if run_tests $test_args; then
        echo -e "\n${GREEN}E2E tests completed successfully!${NC}"
        TEST_STATUS="PASSED"
    else
        echo -e "\n${RED}E2E tests failed!${NC}"
        TEST_STATUS="FAILED"
    fi

    # Copy results
    copy_results

    echo ""
    echo "=================================================="
    echo "E2E Test Run Complete"
    echo "Status: $TEST_STATUS"
    echo "Audit Directory: $AUDIT_DIR"
    echo "=================================================="
    echo ""
    echo "To view the HTML report:"
    echo "  cd $FRONTEND_DIR && npm run e2e:report"
    echo ""
    echo "To replay test traces:"
    echo "  npx playwright show-trace $AUDIT_DIR/test-results/*/trace.zip"
    echo ""
}

main "$@"
