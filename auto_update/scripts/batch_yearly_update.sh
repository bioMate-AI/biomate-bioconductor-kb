#!/bin/bash
#
# Batch Yearly Update Script for 2025 Full Data Load
# Processes data in monthly chunks to avoid GitHub API rate limits
#
# Usage: ./batch_yearly_update.sh [start_month] [end_month]
#   Example: ./batch_yearly_update.sh 1 11  (January to November 2025)
#

set -e  # Exit on error

# Configuration
export ANTHROPIC_API_KEY='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'
export GITHUB_TOKEN="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"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SCRIPT="$SCRIPT_DIR/run_pipeline.py"
LOG_DIR="$SCRIPT_DIR/../logs/batch_update"
DATA_DIR="$SCRIPT_DIR/../data"

# Parameters
MIN_STARS=75
START_MONTH=${1:-1}   # Default: January
END_MONTH=${2:-11}    # Default: November (current month)

# Create log directory
mkdir -p "$LOG_DIR"

echo "============================================================"
echo "Batch Yearly Update for 2025"
echo "============================================================"
echo "Processing months: $START_MONTH to $END_MONTH"
echo "Minimum stars: $MIN_STARS"
echo "Log directory: $LOG_DIR"
echo "============================================================"
echo ""

# Calculate days_back for each month (from today: 2025-11-21)
# November 2025: 0-30 days back
# October 2025: 31-61 days back
# September 2025: 62-91 days back
# etc.

# Month configurations: (month_name, days_back_start, days_back_end)
declare -A MONTHS
MONTHS[1]="January:294:324"    # Jan 1-31 (324-294 days ago)
MONTHS[2]="February:265:293"   # Feb 1-28 (293-265 days ago)
MONTHS[3]="March:234:264"      # Mar 1-31 (264-234 days ago)
MONTHS[4]="April:204:233"      # Apr 1-30 (233-204 days ago)
MONTHS[5]="May:173:203"        # May 1-31 (203-173 days ago)
MONTHS[6]="June:143:172"       # Jun 1-30 (172-143 days ago)
MONTHS[7]="July:112:142"       # Jul 1-31 (142-112 days ago)
MONTHS[8]="August:81:111"      # Aug 1-31 (111-81 days ago)
MONTHS[9]="September:51:80"    # Sep 1-30 (80-51 days ago)
MONTHS[10]="October:21:50"     # Oct 1-31 (50-21 days ago)
MONTHS[11]="November:0:20"     # Nov 1-21 (20-0 days ago)

# Summary tracking
TOTAL_DETECTED=0
TOTAL_INTEGRATED=0
TOTAL_FAILED=0
declare -a BATCH_RESULTS

# Process each month
for month in $(seq $START_MONTH $END_MONTH); do
    if [ -z "${MONTHS[$month]}" ]; then
        echo "⚠️  Skipping invalid month: $month"
        continue
    fi

    # Parse month configuration
    IFS=':' read -r month_name days_start days_end <<< "${MONTHS[$month]}"
    days_range=$((days_end - days_start + 1))

    echo ""
    echo "============================================================"
    echo "Processing: $month_name 2025"
    echo "Date range: ~$(date -d "$days_end days ago" +%Y-%m-%d) to $(date -d "$days_start days ago" +%Y-%m-%d)"
    echo "Days back: $days_end (using full month for simplicity: ~30 days)"
    echo "============================================================"

    # Use middle of the range for days_back calculation
    # For practical purposes, we'll use 30-day windows centered on each month
    days_back=$((324 - month * 30))

    # Log file for this batch
    batch_log="$LOG_DIR/batch_${month}_${month_name}_$(date +%Y%m%d_%H%M%S).log"

    echo "Starting batch $month/$END_MONTH..."
    echo "Log file: $batch_log"
    echo ""

    # Run pipeline for this month (no limit - process all tools found)
    if python3 "$PIPELINE_SCRIPT" \
        --mode full \
        --days 30 \
        --min-stars $MIN_STARS \
        2>&1 | tee "$batch_log"; then

        # Parse results from log
        detected=$(grep "Tools detected:" "$batch_log" | awk '{print $3}' || echo "0")
        integrated=$(grep "Tools integrated:" "$batch_log" | awk '{print $3}' || echo "0")
        failed=$(grep "Tests failed:" "$batch_log" | awk '{print $3}' || echo "0")

        TOTAL_DETECTED=$((TOTAL_DETECTED + detected))
        TOTAL_INTEGRATED=$((TOTAL_INTEGRATED + integrated))
        TOTAL_FAILED=$((TOTAL_FAILED + failed))

        BATCH_RESULTS+=("✅ $month_name: $detected detected, $integrated integrated, $failed failed")

        echo ""
        echo "✅ Completed $month_name batch"
        echo "   Detected: $detected | Integrated: $integrated | Failed: $failed"
    else
        echo ""
        echo "❌ Failed to process $month_name batch"
        BATCH_RESULTS+=("❌ $month_name: FAILED")
    fi

    # Brief pause between batches to respect rate limits
    echo ""
    echo "Waiting 10 seconds before next batch..."
    sleep 10
done

# Final summary
echo ""
echo "============================================================"
echo "Batch Update Complete!"
echo "============================================================"
echo "Total tools detected: $TOTAL_DETECTED"
echo "Total tools integrated: $TOTAL_INTEGRATED"
echo "Total tests failed: $TOTAL_FAILED"
echo ""
echo "Results by month:"
for result in "${BATCH_RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "All logs saved to: $LOG_DIR"
echo "============================================================"

# Save summary to file
summary_file="$LOG_DIR/BATCH_SUMMARY_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "Batch Yearly Update Summary - $(date)"
    echo "======================================"
    echo ""
    echo "Total tools detected: $TOTAL_DETECTED"
    echo "Total tools integrated: $TOTAL_INTEGRATED"
    echo "Total tests failed: $TOTAL_FAILED"
    echo ""
    echo "Results by month:"
    for result in "${BATCH_RESULTS[@]}"; do
        echo "  $result"
    done
} > "$summary_file"

echo "Summary saved to: $summary_file"
