#!/bin/bash
#
# Run full LLM-powered metadata extraction for all tools
#
# Usage:
#   ./run_full_extraction.sh [category] [workers]
#
# Examples:
#   ./run_full_extraction.sh                    # Process all tools with 5 workers
#   ./run_full_extraction.sh Proteomics        # Process only Proteomics
#   ./run_full_extraction.sh Proteomics 3      # Process Proteomics with 3 workers
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="$SCRIPT_DIR/../database/galaxy_ai_tools.db"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

CATEGORY="${1:-}"
WORKERS="${2:-5}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/extraction_${TIMESTAMP}.log"

# Check API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable not set"
    echo ""
    echo "Set it with:"
    echo "  export ANTHROPIC_API_KEY='your-api-key-here'"
    exit 1
fi

# Check database
if [ ! -f "$DB_PATH" ]; then
    echo "❌ Error: Database not found at $DB_PATH"
    exit 1
fi

echo "================================================================================"
echo "LLM-Powered Tool Metadata Extraction"
echo "================================================================================"
echo "Database: $DB_PATH"
echo "Workers: $WORKERS"
if [ -n "$CATEGORY" ]; then
    echo "Category: $CATEGORY"
else
    echo "Category: ALL"
fi
echo "Log file: $LOG_FILE"
echo ""

# Backup database
echo "📦 Creating database backup..."
BACKUP_PATH="${DB_PATH}.backup_${TIMESTAMP}"
cp "$DB_PATH" "$BACKUP_PATH"
echo "   Backup created: $BACKUP_PATH"
echo ""

# Build command
CMD="python3 $SCRIPT_DIR/batch_llm_extract.py --workers $WORKERS"
if [ -n "$CATEGORY" ]; then
    CMD="$CMD --category $CATEGORY"
fi

# Estimate time
if [ -n "$CATEGORY" ]; then
    TOOL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tools WHERE category = '$CATEGORY' AND (rawText IS NOT NULL AND rawText != '')")
else
    TOOL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tools WHERE (rawText IS NOT NULL AND rawText != '')")
fi

ESTIMATED_MINUTES=$((TOOL_COUNT / 35))  # ~35 tools/minute with 5 workers
ESTIMATED_HOURS=$((ESTIMATED_MINUTES / 60))
ESTIMATED_MINUTES_REMAINDER=$((ESTIMATED_MINUTES % 60))

echo "📊 Estimated processing:"
echo "   Tools to process: ~$TOOL_COUNT"
echo "   Estimated time: ${ESTIMATED_HOURS}h ${ESTIMATED_MINUTES_REMAINDER}m"
echo "   Estimated cost: \$$(echo "scale=2; $TOOL_COUNT * 0.006" | bc)"
echo ""

# Confirm
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting extraction..."
echo "   Press Ctrl+C to stop (progress will be saved)"
echo ""

# Run extraction
$CMD 2>&1 | tee "$LOG_FILE"

# Summary
echo ""
echo "================================================================================"
echo "✅ Extraction Complete"
echo "================================================================================"
echo "Log file: $LOG_FILE"
echo "Backup: $BACKUP_PATH"
echo ""

# Show statistics
echo "📊 Database Statistics:"
sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT
    category,
    COUNT(*) as total_tools,
    SUM(CASE WHEN json_extract(scientific_context, '$.data_type_compatibility') IS NOT NULL THEN 1 ELSE 0 END) as with_llm_context,
    ROUND(100.0 * SUM(CASE WHEN json_extract(scientific_context, '$.data_type_compatibility') IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) as coverage_pct
FROM tools
WHERE category IN ('Proteomics', 'Transcriptomics', 'Metabolomics', 'Genomics', 'RNA', 'Variant Analysis')
GROUP BY category
ORDER BY coverage_pct DESC;
EOF

echo ""
echo "✅ Done! Your tools now have comprehensive scientific metadata."
echo ""
echo "Next steps:"
echo "  1. Review examples: python3 /tmp/show_examples.py"
echo "  2. Query database: sqlite3 $DB_PATH"
echo "  3. Integrate with ACE: See reference/ACE_BIOMATE_INTEGRATION_PLAN_20251030.md"
