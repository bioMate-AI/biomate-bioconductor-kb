#!/bin/bash
#
# Daily Tool Auto-Update Script
# Runs daily to discover and integrate new bioinformatics tools
#
# Author: BioMate Auto-Update System
# Created: 2025-11-07
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BASE_DIR/logs/daily"
BACKUP_DIR="$BASE_DIR/backups"
REPORT_DIR="$BASE_DIR/reports/daily"
DB_PATH="/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

# Create directories
mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$REPORT_DIR"

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/daily_run_${TIMESTAMP}.log"
SUMMARY_FILE="$REPORT_DIR/summary_${DATE}.json"

# Pipeline parameters
DAYS_BACK=1           # Look for tools updated in last 1 day
MIN_STARS=10          # Lower threshold for daily runs
LIMIT=0               # No limit (process all found tools)
ENABLE_TEST=0         # 0 = skip testing, 1 = enable

# GitHub token (from environment or config)
if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -f "$BASE_DIR/.env" ]; then
        source "$BASE_DIR/.env"
    fi
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_TOKEN not set" >&2
    exit 1
fi

# ============================================================
# Functions
# ============================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Backup database before running
backup_database() {
    log "Creating database backup..."
    local backup_file="$BACKUP_DIR/galaxy_ai_tools_${TIMESTAMP}.db"

    if [ -f "$DB_PATH" ]; then
        cp "$DB_PATH" "$backup_file"
        gzip "$backup_file"
        log "Backup created: ${backup_file}.gz"

        # Keep only last 7 days of backups
        find "$BACKUP_DIR" -name "*.db.gz" -mtime +7 -delete
        log "Cleaned old backups (>7 days)"
    else
        log_error "Database not found: $DB_PATH"
        return 1
    fi
}

# Get current statistics before run
get_stats_before() {
    log "Gathering pre-run statistics..."
    sqlite3 "$DB_PATH" <<EOF > /tmp/stats_before_${TIMESTAMP}.txt
SELECT
    COUNT(*) as total_tools,
    COUNT(CASE WHEN auto_discovered = 1 THEN 1 END) as auto_discovered,
    COUNT(CASE WHEN created_at >= date('now', '-1 day') THEN 1 END) as added_today
FROM tools;
EOF
    cat /tmp/stats_before_${TIMESTAMP}.txt | tee -a "$LOG_FILE"
}

# Get statistics after run
get_stats_after() {
    log "Gathering post-run statistics..."
    sqlite3 "$DB_PATH" <<EOF > /tmp/stats_after_${TIMESTAMP}.txt
SELECT
    COUNT(*) as total_tools,
    COUNT(CASE WHEN auto_discovered = 1 THEN 1 END) as auto_discovered,
    COUNT(CASE WHEN created_at >= date('now', '-1 day') THEN 1 END) as added_today
FROM tools;
EOF
    cat /tmp/stats_after_${TIMESTAMP}.txt | tee -a "$LOG_FILE"
}

# Run the pipeline
run_pipeline() {
    log "Starting daily pipeline run..."
    log "Parameters: days=$DAYS_BACK, min_stars=$MIN_STARS, limit=$LIMIT"

    cd "$SCRIPT_DIR"

    local test_flag=""
    if [ $ENABLE_TEST -eq 0 ]; then
        test_flag="--no-test"
    fi

    python3 run_pipeline.py \
        --mode full \
        --days "$DAYS_BACK" \
        --min-stars "$MIN_STARS" \
        --limit "$LIMIT" \
        $test_flag \
        2>&1 | tee -a "$LOG_FILE"

    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -eq 0 ]; then
        log "Pipeline completed successfully"
        return 0
    else
        log_error "Pipeline failed with exit code $exit_code"
        return $exit_code
    fi
}

# Generate daily summary report
generate_summary() {
    log "Generating daily summary report..."

    python3 - <<EOF | tee "$SUMMARY_FILE"
import sqlite3
import json
from datetime import datetime, timedelta

db_path = "$DB_PATH"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# Tools added today
cursor.execute("""
    SELECT COUNT(*) as count
    FROM tools
    WHERE DATE(created_at) = DATE('now')
    AND auto_discovered = 1
""")
tools_added_today = cursor.fetchone()['count']

# Citations added
cursor.execute("""
    SELECT COUNT(*) as count
    FROM tools
    WHERE DATE(created_at) = DATE('now')
    AND auto_discovered = 1
    AND citations IS NOT NULL
    AND citations != '[]'
""")
tools_with_citations = cursor.fetchone()['count']

# Duplicates detected (skipped)
# Note: We'd need to track this in the pipeline logs

# Average quality score
cursor.execute("""
    SELECT AVG(quality_score) as avg_quality
    FROM tools
    WHERE DATE(created_at) = DATE('now')
    AND auto_discovered = 1
""")
avg_quality = cursor.fetchone()['avg_quality'] or 0

# Category distribution
cursor.execute("""
    SELECT category, COUNT(*) as count
    FROM tools
    WHERE DATE(created_at) = DATE('now')
    AND auto_discovered = 1
    GROUP BY category
    ORDER BY count DESC
    LIMIT 10
""")
categories = [dict(row) for row in cursor.fetchall()]

summary = {
    "date": "$DATE",
    "timestamp": "$TIMESTAMP",
    "tools_added": tools_added_today,
    "tools_with_citations": tools_with_citations,
    "citation_rate": round(tools_with_citations / tools_added_today * 100, 1) if tools_added_today > 0 else 0,
    "avg_quality_score": round(avg_quality, 3),
    "categories": categories,
    "log_file": "$LOG_FILE",
    "backup_file": "$BACKUP_DIR/galaxy_ai_tools_${TIMESTAMP}.db.gz"
}

print(json.dumps(summary, indent=2))
conn.close()
EOF

    log "Summary report saved: $SUMMARY_FILE"
}

# Send notification (email or Slack)
send_notification() {
    local status=$1
    local summary_file=$2

    log "Sending notification (status: $status)..."

    # TODO: Implement email/Slack notification
    # For now, just log
    if [ "$status" = "success" ]; then
        log "✅ Daily update completed successfully"
        if [ -f "$summary_file" ]; then
            cat "$summary_file" | tee -a "$LOG_FILE"
        fi
    else
        log_error "❌ Daily update failed - check logs: $LOG_FILE"
    fi
}

# Cleanup old logs and reports
cleanup_old_files() {
    log "Cleaning up old files..."

    # Keep logs for 30 days
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete

    # Keep reports for 90 days
    find "$REPORT_DIR" -name "*.json" -mtime +90 -delete

    # Keep backups for 7 days (already done in backup_database)

    log "Cleanup completed"
}

# ============================================================
# Main Execution
# ============================================================

main() {
    log "=================================================="
    log "Daily Tool Auto-Update - Starting"
    log "=================================================="
    log "Date: $DATE"
    log "Timestamp: $TIMESTAMP"
    log "Database: $DB_PATH"
    log ""

    # Step 1: Backup database
    if ! backup_database; then
        log_error "Database backup failed - aborting"
        send_notification "failure" ""
        exit 1
    fi

    # Step 2: Get statistics before
    get_stats_before

    # Step 3: Run pipeline
    local pipeline_status=0
    if ! run_pipeline; then
        pipeline_status=1
    fi

    # Step 4: Get statistics after
    get_stats_after

    # Step 5: Generate summary
    generate_summary

    # Step 6: Cleanup old files
    cleanup_old_files

    # Step 7: Send notification
    if [ $pipeline_status -eq 0 ]; then
        send_notification "success" "$SUMMARY_FILE"
        log "=================================================="
        log "Daily Tool Auto-Update - Completed Successfully"
        log "=================================================="
        exit 0
    else
        send_notification "failure" "$SUMMARY_FILE"
        log "=================================================="
        log "Daily Tool Auto-Update - Completed with Errors"
        log "=================================================="
        exit 1
    fi
}

# Run main function
main "$@"
