#!/bin/bash
# Claude Code Audit Wrapper
# Records terminal session and copies conversation transcripts for audit purposes
#
# Usage: ./claude-audit.sh [session_name]
#
# Example: ./claude-audit.sh bioinformatics_testing

set -e

SESSION_NAME="${1:-session}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUDIT_DIR="/home/yzhang/biomate/docs/audit/${TIMESTAMP}_${SESSION_NAME}"

mkdir -p "$AUDIT_DIR"

echo "=================================================="
echo "Claude Code Audit Session"
echo "=================================================="
echo "Session: $SESSION_NAME"
echo "Audit Directory: $AUDIT_DIR"
echo "=================================================="
echo ""
echo "Starting terminal recording..."
echo "Press Ctrl+D or type 'exit' to end the session."
echo ""

# Record terminal session with timing
script --timing="$AUDIT_DIR/timing.txt" "$AUDIT_DIR/terminal.txt" -c "claude"

echo ""
echo "Session ended. Processing transcripts..."

# Copy all recent JSONL transcripts (modified in last hour)
find /home/yzhang/.claude/projects/-home-yzhang-biomate/ \
    -name "*.jsonl" \
    -mmin -60 \
    -exec cp {} "$AUDIT_DIR/" \;

# Extract conversation logs
if [ -f /home/yzhang/biomate/scripts/extract-llm-calls.py ]; then
    for jsonl in "$AUDIT_DIR"/*.jsonl; do
        if [ -f "$jsonl" ]; then
            basename=$(basename "$jsonl" .jsonl)
            python3 /home/yzhang/biomate/scripts/extract-llm-calls.py \
                "$jsonl" \
                "$AUDIT_DIR/extracted_${basename}/"
        fi
    done
fi

# Generate summary
cat > "$AUDIT_DIR/AUDIT_SUMMARY.md" << EOF
# Audit Session Summary

**Session Name:** $SESSION_NAME
**Timestamp:** $TIMESTAMP
**Directory:** $AUDIT_DIR

## Contents

- \`terminal.txt\` - Full terminal session transcript
- \`timing.txt\` - Timing data for terminal replay
- \`*.jsonl\` - Raw Claude Code conversation logs
- \`extracted_*/\` - Formatted conversation extracts

## Replay Terminal Session

\`\`\`bash
scriptreplay "$AUDIT_DIR/timing.txt" "$AUDIT_DIR/terminal.txt"
\`\`\`

## File Inventory
$(ls -la "$AUDIT_DIR" | sed 's/^/    /')
EOF

echo ""
echo "=================================================="
echo "Audit session complete!"
echo "=================================================="
echo "Files saved to: $AUDIT_DIR"
echo ""
echo "To replay terminal session:"
echo "  scriptreplay $AUDIT_DIR/timing.txt $AUDIT_DIR/terminal.txt"
echo ""
