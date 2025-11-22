#!/bin/bash
#
# Setup Cron Job for Daily Auto-Update
#
# This script installs a cron job to run daily_update.sh at 2 AM every day
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAILY_SCRIPT="$SCRIPT_DIR/daily_update.sh"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "Daily Auto-Update Cron Setup"
echo "=================================================="
echo ""

# Check if daily_update.sh exists and is executable
if [ ! -x "$DAILY_SCRIPT" ]; then
    echo "ERROR: $DAILY_SCRIPT not found or not executable"
    exit 1
fi

echo "✓ Found daily update script: $DAILY_SCRIPT"
echo ""

# Check if GITHUB_TOKEN is available
if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -f "$BASE_DIR/.env" ]; then
        echo "✓ Found .env file: $BASE_DIR/.env"
    else
        echo "WARNING: GITHUB_TOKEN not set and .env file not found"
        echo "Please create $BASE_DIR/.env with GITHUB_TOKEN=your_token"
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "✓ GITHUB_TOKEN is set in environment"
fi
echo ""

# Create cron entry
CRON_TIME="0 2 * * *"  # 2 AM daily
CRON_CMD="$DAILY_SCRIPT"
CRON_ENTRY="$CRON_TIME $CRON_CMD"

echo "Cron entry to be added:"
echo "  $CRON_ENTRY"
echo ""

# Check if cron entry already exists
if crontab -l 2>/dev/null | grep -q "$DAILY_SCRIPT"; then
    echo "ℹ️  Cron entry already exists for daily_update.sh"
    echo ""
    echo "Current cron jobs:"
    crontab -l | grep -v "^#" || echo "  (none)"
    echo ""
    read -p "Replace existing entry? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping cron installation"
        exit 0
    fi

    # Remove existing entry
    crontab -l | grep -v "$DAILY_SCRIPT" | crontab -
    echo "✓ Removed old cron entry"
fi

# Add new cron entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo "✓ Cron job installed successfully"
echo ""

# Display current cron jobs
echo "Current cron jobs:"
crontab -l | grep -v "^#" || echo "  (none)"
echo ""

echo "=================================================="
echo "Setup Complete!"
echo "=================================================="
echo ""
echo "The daily update will run at 2 AM every day."
echo ""
echo "To manually test the script, run:"
echo "  $DAILY_SCRIPT"
echo ""
echo "To view logs:"
echo "  ls -lh $BASE_DIR/logs/daily/"
echo ""
echo "To remove the cron job:"
echo "  crontab -e"
echo "  # Then delete the line containing: $DAILY_SCRIPT"
echo ""
