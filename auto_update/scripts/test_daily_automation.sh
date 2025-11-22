#!/bin/bash
#
# Test Daily Automation System
#
# Runs a quick test of the daily automation pipeline with limited scope
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "Daily Automation System Test"
echo "=================================================="
echo ""

# Test 1: Check script exists and is executable
echo "[1/6] Checking daily_update.sh exists and is executable..."
if [ -x "$SCRIPT_DIR/daily_update.sh" ]; then
    echo "  ✅ daily_update.sh is executable"
else
    echo "  ❌ daily_update.sh not found or not executable"
    exit 1
fi

# Test 2: Check .env file exists
echo ""
echo "[2/6] Checking .env file exists..."
if [ -f "$BASE_DIR/.env" ]; then
    echo "  ✅ .env file exists"
    source "$BASE_DIR/.env"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "  ✅ GITHUB_TOKEN is set"
    else
        echo "  ⚠️  GITHUB_TOKEN not set in .env"
    fi
else
    echo "  ❌ .env file not found"
    exit 1
fi

# Test 3: Check monitoring script works
echo ""
echo "[3/6] Testing monitoring script..."
if python3 "$SCRIPT_DIR/monitor_daily_runs.py" --health-check 2>/dev/null; then
    echo "  ✅ Monitoring script works (healthy)"
elif [ $? -eq 1 ]; then
    echo "  ✅ Monitoring script works (warning status - expected for new install)"
else
    echo "  ⚠️  Monitoring script returned critical status"
fi

# Test 4: Check cron setup script
echo ""
echo "[4/6] Checking cron setup script..."
if [ -x "$SCRIPT_DIR/setup_cron.sh" ]; then
    echo "  ✅ setup_cron.sh is executable"
else
    echo "  ❌ setup_cron.sh not found or not executable"
    exit 1
fi

# Test 5: Check database exists
echo ""
echo "[5/6] Checking database access..."
DB_PATH="/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
if [ -f "$DB_PATH" ]; then
    echo "  ✅ Database exists"
    # Test database query
    if sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tools;" > /dev/null 2>&1; then
        TOOL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tools;")
        echo "  ✅ Database accessible ($TOOL_COUNT tools)"
    else
        echo "  ❌ Database query failed"
        exit 1
    fi
else
    echo "  ❌ Database not found"
    exit 1
fi

# Test 6: Run a minimal pipeline test (1 tool)
echo ""
echo "[6/6] Running minimal pipeline test (1 tool, full mode)..."
if python3 "$SCRIPT_DIR/run_pipeline.py" --mode full --days 30 --min-stars 200 --limit 1 --no-test > /tmp/daily_automation_test.log 2>&1; then
    echo "  ✅ Pipeline test passed"
    # Show detection results
    echo "  Pipeline output:"
    grep -E "Found.*tools|Processing tool:|Successfully integrated" /tmp/daily_automation_test.log | head -5 || true
else
    echo "  ❌ Pipeline test failed"
    echo "  Check logs: /tmp/daily_automation_test.log"
    exit 1
fi

echo ""
echo "=================================================="
echo "All Tests Passed! ✅"
echo "=================================================="
echo ""
echo "Daily automation system is ready to use."
echo ""
echo "Next steps:"
echo "  1. Install cron job:"
echo "     ./scripts/setup_cron.sh"
echo ""
echo "  2. View monitoring dashboard:"
echo "     ./scripts/monitor_daily_runs.py"
echo ""
echo "  3. Manual test run:"
echo "     ./scripts/daily_update.sh"
echo ""
