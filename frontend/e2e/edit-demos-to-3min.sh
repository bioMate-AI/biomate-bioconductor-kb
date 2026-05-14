#!/usr/bin/env bash
# Edit raw 5-7 min Tier 0 demo recordings down to ~3:00 final cuts.
#
# Strategy:
#   - Each raw .webm is segmented into "tip + brief context" keep-windows
#     and "long quiet AWS wait" trim-windows.
#   - We use the demo's *.png screenshots' mtimes as the timeline anchors
#     (Playwright writes one screenshot per narrative beat).
#   - Final cut keeps ~14-16s around each screenshot (covers the tip,
#     the page state change, and a brief follow-on); drops the rest.
#
# Usage:
#   ./e2e/edit-demos-to-3min.sh             # all 5 demos
#   ./e2e/edit-demos-to-3min.sh T01         # one
#
# Output: e2e/demo-videos-3min/demo-T0N-*-3min.webm

set -uo pipefail
cd "$(dirname "$0")/.."

INPUT_DIR="e2e/demo-videos"
OUTPUT_DIR="e2e/demo-videos-3min"
SCREENSHOT_DIR="e2e/screenshots"
mkdir -p "$OUTPUT_DIR"

# How many seconds to keep around each anchor screenshot.
# 11 screenshots × 18s ≈ 200s minus overlap → ~3:00 final cut.
# Override per-demo via KEEP_SECONDS_PER_ANCHOR env var if needed.
KEEP_SECONDS_PER_ANCHOR="${KEEP_SECONDS_PER_ANCHOR:-22}"

ARG_DEMOS=("$@")
if [[ ${#ARG_DEMOS[@]} -eq 0 ]]; then
  ARG_DEMOS=(T01 T02 T03 T04 T05)
fi

# Resolve demo slug → full filename (e.g. T01 → demo-T01-bispecific-format)
demo_slug() {
  case "$1" in
    T01) echo "demo-T01-bispecific-format" ;;
    T02) echo "demo-T02-in-vivo-cart" ;;
    T03) echo "demo-T03-verve-base-edit" ;;
    T04) echo "demo-T04-glp1-bakeoff" ;;
    T05) echo "demo-T05-modality-triage" ;;
    *)   echo "" ;;
  esac
}

for ID in "${ARG_DEMOS[@]}"; do
  SLUG=$(demo_slug "$ID")
  if [[ -z "$SLUG" ]]; then
    echo "Unknown demo ID: $ID"; continue
  fi

  RAW="$INPUT_DIR/$SLUG.webm"
  if [[ ! -f "$RAW" ]]; then
    echo "Missing raw video: $RAW (record it first via run-demos.sh $ID)"; continue
  fi

  SHOT_PATH="$SCREENSHOT_DIR/$SLUG"
  if [[ ! -d "$SHOT_PATH" ]]; then
    echo "Missing screenshot dir: $SHOT_PATH"; continue
  fi

  # Get total duration
  TOTAL=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW" 2>/dev/null)
  echo "── $SLUG  raw=${TOTAL}s ──"

  # Read screenshot mtimes (sorted by name 00, 01, 02, …) and convert to
  # offsets from the start of the raw recording. Playwright video starts
  # at process spawn ~= the first screenshot's mtime minus ~3s (setup time).
  # Use the first screenshot as time 0.
  mapfile -t SHOTS < <(ls "$SHOT_PATH"/*.png 2>/dev/null | sort)
  if [[ ${#SHOTS[@]} -eq 0 ]]; then
    echo "  no screenshots; skipping"; continue
  fi
  T0=$(stat -c %Y "${SHOTS[0]}")

  # Build a list of keep-windows centered on each screenshot mtime.
  KEEP_FILTERS=()
  PREV_END=0
  for shot in "${SHOTS[@]}"; do
    TS=$(stat -c %Y "$shot")
    OFFSET=$((TS - T0))
    START=$((OFFSET - 4))
    END=$((OFFSET + KEEP_SECONDS_PER_ANCHOR - 4))
    [[ $START -lt $PREV_END ]] && START=$PREV_END
    [[ $START -lt 0 ]] && START=0
    KEEP_FILTERS+=("$START:$END")
    PREV_END=$END
  done

  # Build ffmpeg select filter (per-frame keep based on PTS)
  SELECT_EXPR=""
  for window in "${KEEP_FILTERS[@]}"; do
    S="${window%:*}"; E="${window##*:}"
    if [[ -n "$SELECT_EXPR" ]]; then SELECT_EXPR+="+"; fi
    SELECT_EXPR+="between(t,$S,$E)"
  done

  OUT="$OUTPUT_DIR/${SLUG}-3min.webm"
  echo "  filter: select='${SELECT_EXPR}' (output: $OUT)"

  # Single ffmpeg pass: keep only the windows, re-encode for clean concat
  ffmpeg -y -i "$RAW" \
    -vf "select='${SELECT_EXPR}',setpts=N/FRAME_RATE/TB" \
    -an \
    -c:v libvpx-vp9 -crf 28 -b:v 0 -row-mt 1 \
    "$OUT" 2>&1 | tail -3

  FINAL_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" 2>/dev/null)
  echo "  → final ${FINAL_DUR}s (target ~180s)"
done

echo ""
echo "Edited videos in $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/" 2>/dev/null
