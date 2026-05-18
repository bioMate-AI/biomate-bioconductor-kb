#!/bin/bash
# Memory Integration Testing Script
# Runs E2E tests for cross-session memory and episode tracking

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║        Memory Integration E2E Testing Suite                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "[1/6] Checking prerequisites..."

# Check if backend is running
if ! pgrep -f "gunicorn.*8081" > /dev/null; then
    echo -e "${YELLOW}⚠ Backend not running${NC}"
    echo "   Please start backend: cd backend && bash start_backend.sh"
    echo "   Or run in another terminal: cd backend && bash start_backend.sh &"
    echo ""
    read -p "   Start backend now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd backend
        bash start_backend.sh &
        BACKEND_PID=$!
        echo "   Waiting for backend to start..."
        sleep 10
        cd ..
    else
        echo -e "${RED}✗ Cannot run tests without backend${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Backend running${NC}"
fi

# Check if frontend is running
if ! lsof -ti:5000 > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Frontend not running${NC}"
    echo "   Please start frontend: cd frontend && npm run dev"
    echo "   Or run in another terminal: cd frontend && npm run dev &"
    echo ""
    read -p "   Start frontend now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd frontend
        npm run dev &
        FRONTEND_PID=$!
        echo "   Waiting for frontend to start..."
        sleep 15
        cd ..
    else
        echo -e "${RED}✗ Cannot run tests without frontend${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Frontend running${NC}"
fi

# Check if Playwright is installed
if [ ! -d "frontend/node_modules/@playwright" ]; then
    echo -e "${YELLOW}⚠ Playwright not installed${NC}"
    cd frontend
    npm install
    npx playwright install
    cd ..
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Run tests
cd frontend

echo "[2/6] Running MM-0: API Preflight (30 seconds)"
echo "      Tests: Memory API endpoints + database connectivity"
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-0" --reporter=list || echo -e "${YELLOW}⚠ MM-0 had failures${NC}"
echo ""

echo "[3/6] Running MM-1: Session Initialization (5 minutes)"
echo "      Tests: User/project context loading"
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-1" --reporter=list || echo -e "${YELLOW}⚠ MM-1 had failures${NC}"
echo ""

echo "[4/6] Running MM-2: Episode Recording (5 minutes)"
echo "      Tests: Episode creation after workflow suggestion"
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-2" --reporter=list || echo -e "${YELLOW}⚠ MM-2 had failures${NC}"
echo ""

echo "[5/6] Running MM-3: Episode Outcome Tracking (10 minutes)"
echo "      Tests: Workflow completion → episode outcome recorded"
echo "      WARNING: This test runs an actual workflow"
read -p "      Run MM-3? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    npm run test:e2e -- memory-integration.e2e.ts --grep "MM-3" --reporter=list || echo -e "${YELLOW}⚠ MM-3 had failures${NC}"
else
    echo -e "${YELLOW}⊘ MM-3 skipped${NC}"
fi
echo ""

echo "[6/6] Running MM-4: Cross-Session Reference (15 minutes)"
echo "      Tests: Day 1 workflow → Day 2 'use same workflow'"
echo "      WARNING: This test runs across two sessions"
read -p "      Run MM-4? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    npm run test:e2e -- memory-integration.e2e.ts --grep "MM-4" --reporter=list || echo -e "${YELLOW}⚠ MM-4 had failures${NC}"
else
    echo -e "${YELLOW}⊘ MM-4 skipped${NC}"
fi
echo ""

# Results
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                      Testing Complete                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Audit files: frontend/e2e/screenshots/memory-integration/audit_*.json"
echo "Screenshots: frontend/e2e/screenshots/memory-integration/*.png"
echo ""
echo "To view results:"
echo "  cat frontend/e2e/screenshots/memory-integration/audit_*.json | jq '.[] | {testId, finalStatus, passed: [.assertions[] | select(.passed)] | length, total: [.assertions[]] | length}'"
echo ""

# Cleanup
if [ ! -z "$BACKEND_PID" ]; then
    echo "Stopping backend (PID $BACKEND_PID)..."
    kill $BACKEND_PID 2>/dev/null || true
fi

if [ ! -z "$FRONTEND_PID" ]; then
    echo "Stopping frontend (PID $FRONTEND_PID)..."
    kill $FRONTEND_PID 2>/dev/null || true
fi
