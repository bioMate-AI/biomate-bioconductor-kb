#!/bin/bash
# ============================================================
# record-tutorial.sh — End-to-end tutorial video recorder
#
# Usage:
#   bash scripts/recording/record-tutorial.sh <demo-id> [voice] [lang]
#
#   <demo-id>  one of:
#       website-quickstart, cryosparc-main, outputs-findings,
#       ra-cryo, ra-afterrun, ra-drugscreen, ind
#   [voice]    Gemini TTS voice (default: Aoede)
#   [lang]     en | zh  (default: en)
#                 en  → English audio, no subtitles
#                 zh  → English audio + Chinese subtitles burned in
#
# Examples:
#   bash scripts/recording/record-tutorial.sh ra-cryo
#   bash scripts/recording/record-tutorial.sh ind Aoede zh
# ============================================================

set -euo pipefail

DEMO="${1:?Usage: record-tutorial.sh <demo-id> [voice] [lang]}"
VOICE="${2:-Aoede}"
LANG_MODE="${3:-en}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Map demo IDs → narration .md (EN audio path) and ZH narration (for subs)
declare -A NARRATION_EN=(
  [website-quickstart]="reference/claude_design/biomate/website-quickstart-narration.md"
  [cryosparc-main]="reference/claude_design/biomate/cryosparc-narration.md"
  [outputs-findings]="reference/claude_design/biomate/outputs-findings-narration.md"
  [outputs-findings-report]="reference/claude_design/biomate/outputs-findings-narration.md"
  [ra-cryo]="reference/claude_design/research_agents/narration/ra-cryo.en.short.md"
  [ra-afterrun]="reference/claude_design/research_agents/narration/ra-afterrun.en.short.md"
  [ra-drugscreen]="reference/claude_design/research_agents/narration/ra-drugscreen.en.short.md"
  [ind]="reference/claude_design/research_agents/narration/ind.en.short.md"
  [website-quickstart-v2]="reference/claude_design/biomate/website-quickstart-v2.en.short.md"
)
declare -A NARRATION_ZH=(
  [ra-cryo]="reference/claude_design/research_agents/narration/ra-cryo.zh.subs.md"
  [ra-afterrun]="reference/claude_design/research_agents/narration/ra-afterrun.zh.subs.md"
  [ra-drugscreen]="reference/claude_design/research_agents/narration/ra-drugscreen.zh.subs.md"
  [ind]="reference/claude_design/research_agents/narration/ind.zh.subs.md"
  [website-quickstart-v2]="reference/claude_design/biomate/website-quickstart-v2.zh.subs.md"
)

NARRATION="${NARRATION_EN[$DEMO]:-}"
if [[ -z "$NARRATION" ]]; then
  echo "ERROR: Unknown demo '$DEMO'. Known demos: ${!NARRATION_EN[*]}"
  exit 1
fi

SUFFIX=""
ZH_NARRATION=""
if [[ "$LANG_MODE" == "zh" ]]; then
  ZH_NARRATION="${NARRATION_ZH[$DEMO]:-}"
  if [[ -z "$ZH_NARRATION" ]]; then
    echo "ERROR: no ZH narration for '$DEMO'"
    exit 1
  fi
  SUFFIX="-zh"
fi

AUDIO_DIR="$REPO_ROOT/recording/audio/$DEMO"
VIDEO_DIR="$REPO_ROOT/recording/video"
OUTPUT_DIR="$REPO_ROOT/recording/output"
RAW_VIDEO="$VIDEO_DIR/${DEMO}-raw.webm"
OUTPUT="$OUTPUT_DIR/${DEMO}${SUFFIX}-tutorial.mp4"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Step 0: install ffmpeg if needed ─────────────────────────
log "Checking ffmpeg..."
if ! which ffmpeg &>/dev/null; then
  log "Installing ffmpeg..."
  sudo apt-get install -y ffmpeg
fi
ffmpeg -version 2>/dev/null | head -1

# ── Step 1: ensure static server on :7779 ────────────────────
if ! curl -sf -o /dev/null "http://localhost:7779/biomate/Workflow%20Panel%20Redesign.html"; then
  log "Starting static server on :7779..."
  ( cd "$REPO_ROOT/reference/claude_design" && python3 -m http.server 7779 ) \
    > "$REPO_ROOT/recording/static7779.log" 2>&1 &
  sleep 1.5
fi

# ── Step 2: generate TTS audio (EN — always) ────────────────
# Pick TTS backend: TTS_BACKEND=edge|gemini|gtts  (default edge; free, high-quality, no quota)
TTS_BACKEND="${TTS_BACKEND:-edge}"
if [[ -s "$AUDIO_DIR/timing.json" ]] && [[ -s "$AUDIO_DIR/step-001.wav" ]] && [[ "${SKIP_TTS:-0}" == "1" || "${REUSE_AUDIO:-0}" == "1" ]]; then
  log "Reusing existing audio in $AUDIO_DIR (REUSE_AUDIO=1)"
  case "true" in true) ;; esac
else
log "Generating EN TTS audio (voice: $VOICE, backend: $TTS_BACKEND)..."
case "$TTS_BACKEND" in
  edge)
    TTS_VOICE="${EDGE_VOICE:-en-US-AriaNeural}" python3 "$REPO_ROOT/scripts/recording/edge-tts-gen.py" \
      --narration "$REPO_ROOT/$NARRATION" \
      --out "$AUDIO_DIR"
    ;;
  gtts)
    python3 "$REPO_ROOT/scripts/recording/gtts-gen.py" \
      --narration "$REPO_ROOT/$NARRATION" \
      --out "$AUDIO_DIR"
    ;;
  *)
    TTS_VOICE="$VOICE" python3 "$REPO_ROOT/scripts/recording/gemini-tts.py" \
      --narration "$REPO_ROOT/$NARRATION" \
      --out "$AUDIO_DIR"
    ;;
esac
fi
log "Audio ready: $AUDIO_DIR"

# ── Step 3: record screen (skip if RAW already exists for this demo) ──
mkdir -p "$VIDEO_DIR"
TIMESTAMPS_PATH="$AUDIO_DIR/step_timestamps.json"
if [[ ! -s "$RAW_VIDEO" ]] || [[ ! -s "$TIMESTAMPS_PATH" ]]; then
  log "Recording screen (demo: $DEMO)..."
  if [[ "$DEMO" == "website-quickstart-v2" ]]; then
    python3 "$REPO_ROOT/scripts/recording/record-website-v2.py" \
      --timing "$AUDIO_DIR/timing.json" \
      --out "$RAW_VIDEO"
  else
    python3 "$REPO_ROOT/scripts/recording/playwright-record.py" \
      --demo "$DEMO" \
      --timing "$AUDIO_DIR/timing.json" \
      --out "$RAW_VIDEO" \
      --timestamps-out "$TIMESTAMPS_PATH"
  fi
else
  log "Reusing existing raw video: $RAW_VIDEO"
fi

# ── Step 4: optional — generate .srt for ZH subtitle burn ───
SRT_PATH=""
if [[ "$LANG_MODE" == "zh" ]]; then
  log "Building ZH .srt from $ZH_NARRATION using EN timing.json..."
  SRT_PATH="$AUDIO_DIR/${DEMO}.zh.srt"
  python3 "$REPO_ROOT/scripts/recording/build-zh-srt.py" \
    --zh-narration "$REPO_ROOT/$ZH_NARRATION" \
    --timing "$AUDIO_DIR/timing.json" \
    --out "$SRT_PATH"
fi

# ── Step 5: aligned merge (trim picker frames + place each WAV at its arrival time) ──
mkdir -p "$OUTPUT_DIR"
log "Aligned merge → $OUTPUT"

if [[ -s "$TIMESTAMPS_PATH" ]]; then
  EXTRA_ARGS=()
  if [[ -n "$SRT_PATH" ]]; then
    EXTRA_ARGS+=(--srt "$SRT_PATH")
  fi
  python3 "$REPO_ROOT/scripts/recording/merge-audio-aligned.py" \
    --raw-video "$RAW_VIDEO" \
    --audio-dir "$AUDIO_DIR" \
    --timestamps "$TIMESTAMPS_PATH" \
    --out "$OUTPUT" \
    "${EXTRA_ARGS[@]}"
else
  log "WARN: no step_timestamps.json; falling back to legacy concat merge"
  WATERMARK="drawtext=text='biomate.ai':fontfile=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc:fontcolor=white@0.85:fontsize=22:box=1:boxcolor=black@0.35:boxborderw=6:x=w-tw-24:y=h-th-24"
  if [[ -n "$SRT_PATH" ]]; then
    SRT_ESCAPED=$(echo "$SRT_PATH" | sed "s/:/\\\\:/g")
    ffmpeg -y -i "$RAW_VIDEO" -i "$AUDIO_DIR/full-narration.wav" \
      -vf "subtitles='${SRT_ESCAPED}':force_style='FontName=Noto Sans CJK SC,FontSize=14,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,BorderStyle=3,Outline=1,Shadow=0,Alignment=2,MarginV=50',${WATERMARK}" \
      -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest "$OUTPUT"
  else
    ffmpeg -y -i "$RAW_VIDEO" -i "$AUDIO_DIR/full-narration.wav" \
      -vf "${WATERMARK}" \
      -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest "$OUTPUT"
  fi
fi

DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT" 2>/dev/null | head -1)
log "Done: $OUTPUT  (duration ${DURATION%.*}s)"
du -sh "$OUTPUT"
