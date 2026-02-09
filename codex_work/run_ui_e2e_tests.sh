#!/bin/bash
# UI E2E Test Runner for Workflow Marker Validation
# Created: 2026-02-09
# Purpose: Automate UI testing for Nextflow integration

set -e

echo "================================================"
echo "UI E2E Test Runner - Workflow Markers"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BACKEND_URL="${GALAXY_URL:-http://localhost:8081}"
FRONTEND_URL="${BIOMATE_URL:-http://localhost:5000}"
MAX_WAIT=60
POLL_INTERVAL=5

echo "Configuration:"
echo "  Backend:  $BACKEND_URL"
echo "  Frontend: $FRONTEND_URL"
echo ""

# Function to check service health
check_service() {
    local url=$1
    local name=$2
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$response" = "200" ]; then
        echo -e "${GREEN}✓${NC} $name is running (HTTP $response)"
        return 0
    else
        echo -e "${RED}✗${NC} $name is not running (HTTP $response)"
        return 1
    fi
}

# Function to wait for services
wait_for_services() {
    echo "Waiting for services to start..."
    local elapsed=0

    while [ $elapsed -lt $MAX_WAIT ]; do
        if check_service "$BACKEND_URL/api/version" "Backend" && \
           check_service "$FRONTEND_URL/" "Frontend"; then
            echo -e "${GREEN}✓${NC} All services ready!"
            return 0
        fi

        echo "  Waiting... ($elapsed/$MAX_WAIT seconds)"
        sleep $POLL_INTERVAL
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    echo -e "${RED}✗${NC} Services did not start in time"
    return 1
}

# Check if services are running
echo "Step 1: Service Health Check"
echo "----------------------------"
if ! wait_for_services; then
    echo ""
    echo -e "${YELLOW}Services not running. Please start them:${NC}"
    echo ""
    echo "Terminal 1 - Backend:"
    echo "  cd /home/yzhang/biomate/backend"
    echo "  ./start_galaxy_simple.sh"
    echo ""
    echo "Terminal 2 - Frontend:"
    echo "  cd /home/yzhang/biomate/frontend"
    echo "  export GALAXY_API_KEY=7341822cd19cddaa49139f6cccae8c76"
    echo "  export GALAXY_URL=http://localhost:8081"
    echo "  npm run dev"
    echo ""
    exit 1
fi

echo ""
echo "Step 2: Running Playwright Tests"
echo "--------------------------------"

cd /home/yzhang/biomate/frontend

# Run our specific workflow markers test
echo "Running workflow-markers-validation.spec.ts..."
if npm run e2e -- workflow-markers-validation.spec.ts --reporter=line; then
    echo -e "${GREEN}✓${NC} Workflow markers test passed"
else
    echo -e "${RED}✗${NC} Workflow markers test failed"
    echo ""
    echo "Check the test report for details"
fi

echo ""
echo "Step 3: Running Full E2E Test Suite"
echo "-----------------------------------"

# Run all E2E tests
if npm run e2e -- --reporter=html; then
    echo -e "${GREEN}✓${NC} Full E2E test suite passed"
else
    echo -e "${YELLOW}⚠${NC} Some E2E tests failed"
fi

echo ""
echo "Step 4: Generate Test Report"
echo "----------------------------"

# Show report location
REPORT_DIR="/home/yzhang/biomate/frontend/playwright-report"
if [ -d "$REPORT_DIR" ]; then
    echo -e "${GREEN}✓${NC} Test report generated: $REPORT_DIR/index.html"
    echo ""
    echo "To view report:"
    echo "  npm run e2e:report"
else
    echo -e "${YELLOW}⚠${NC} No test report found"
fi

echo ""
echo "================================================"
echo "Test Execution Complete"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Review test report"
echo "2. Fix any failing tests"
echo "3. Document results in codex_work/"
echo ""
