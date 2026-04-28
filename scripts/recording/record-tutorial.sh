#!/bin/bash
# ============================================================
# record-tutorial.sh — End-to-end tutorial video recorder
#
# Usage:
#   bash scripts/recording/record-tutorial.sh <demo-id> [voice]
#
# Examples:
#   bash scripts/recording/record-tutorial.sh website-quickstart
#   bash scripts/recording/record-tutorial.sh cryosparc-main Orbit
#   bash scripts/recording/record-tutorial.sh outputs-findings Charon
#
# Demo IDs and their narration files:
#   website-quickstart  → reference/claude_design/biomate/website-quickstart-narration.md
#   cryosparc-main      → reference/claude_design/biomate/cryosparc-narration.md
#   outputs-findings    → reference/claude_design/biomate/outputs-findings-narration.md
# ============================================================

set -euo pipefail

DEMO="${1:?Usage: record-tutorial.sh <demo-id> [voice]}"
VOICE="${2:-Aoede}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Map demo IDs to narration files
declare -A NARRATION_MAP=(
  [website-quickstart]="reference/claude_design/biomate/website-quickstart-narration.md"
  [cryosparc-main]="reference/claude_design/biomate/cryosparc-narration.md"
  [outputs-findings]="reference/claude_design/biomate/outputs-findings-narration.md"
  [outputs-findings-report]="reference/claude_design/biomate/outputs-findings-narration.md"
)

NARRATION="${NARRATION_MAP[$DEMO]:-}"
if [[ -z "$NARRATION" ]]; then
  echo "ERROR: Unknown demo '$DEMO'. Known demos: ${!NARRATION_MAP[*]}"
  exit 1
fi

AUDIO_DIR="$REPO_ROOT/recording/audio/$DEMO"
VIDEO_DIR="$REPO_ROOT/recording/video"
OUTPUT="$REPO_ROOT/recording/output/${DEMO}-tutorial.mp4"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Step 0: install ffmpeg if needed ─────────────────────────
log "Checking ffmpeg..."
if ! which ffmpeg &>/dev/null; then
  log "Installing ffmpeg..."
  sudo apt-get install -y ffmpeg
fi
ffmpeg -version 2>/dev/null | head -1

# ── Step 1: generate TTS audio ───────────────────────────────
log "Generating TTS audio (voice: $VOICE)..."
TTS_VOICE="$VOICE" python3 "$REPO_ROOT/scripts/recording/gemini-tts.py" \
  --narration "$REPO_ROOT/$NARRATION" \
  --out "$AUDIO_DIR"

log "Audio ready: $AUDIO_DIR"

# ── Step 2: record screen ─────────────────────────────────────
log "Recording screen (demo: $DEMO)..."
mkdir -p "$VIDEO_DIR"
python3 "$REPO_ROOT/scripts/recording/playwright-record.py" \
  --demo "$DEMO" \
  --timing "$AUDIO_DIR/timing.json" \
  --out "$VIDEO_DIR/${DEMO}-raw.webm"

log "Raw video: $VIDEO_DIR/${DEMO}-raw.webm"

# ── Step 3: merge audio + video ───────────────────────────────
log "Merging audio + video..."
mkdir -p "$REPO_ROOT/recording/output"
ffmpeg -y \
  -i "$VIDEO_DIR/${DEMO}-raw.webm" \
  -i "$AUDIO_DIR/full-narration.wav" \
  -c:v libx264 -preset fast -crf 18 \
  -c:a aac -b:a 192k \
  -shortest \
  "$OUTPUT"

log "Done: $OUTPUT"
echo ""
echo "  Video: $OUTPUT"
du -sh "$OUTPUT"
