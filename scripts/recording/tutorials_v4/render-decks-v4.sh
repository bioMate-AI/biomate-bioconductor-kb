#!/bin/bash
# Disk-safe sequential renderer for v4 tutorial decks (_v4.js contract).
# record -> mux -> upload to Drive -> delete local, one deck at a time, with a
# free-space guard. NEVER parallel-render: two 1080p lanes fill the disk (ENOSPC),
# which then blocks every command. See README.md.
#
# Usage:
#   render-decks-v4.sh <tutorials_v3_root> <deck-list.tsv> <rclone_dest> [http_port]
# deck-list.tsv lines (tab-separated):
#   <deck-folder><TAB><deck-html-basename><TAB><narration-basename>
# Env: MIN_KB (free-space abort threshold, default 400000), TTS_RATE (default +8%),
#      FRONTEND_DIR (has node_modules/playwright; default <repo>/frontend).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$1"; LIST="$2"; DRIVE="$3"; PORT="${4:-8099}"
FE="${FRONTEND_DIR:-$(cd "$HERE/../../../frontend" && pwd)}"
MIN_KB="${MIN_KB:-400000}"; export TTS_RATE="${TTS_RATE:-+8%}"
TMP="$(mktemp -d)"; LOG="$TMP/render.log"; : > "$LOG"
echo "[v4] start $(date)  root=$ROOT dest=$DRIVE tmp=$TMP" | tee -a "$LOG"

( cd "$ROOT" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
SRV=$!; trap 'kill $SRV 2>/dev/null; rm -rf "$TMP"' EXIT; sleep 2
urlenc() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1"; }

while IFS=$'\t' read -r folder deck narr; do
  [ -z "$folder" ] && continue
  avail=$(df -k / | tail -1 | awk '{print $4}')
  if [ "$avail" -lt "$MIN_KB" ]; then echo "[v4] ABORT low disk (${avail}KB) before $folder" | tee -a "$LOG"; break; fi
  recdir="$TMP/$folder"; mkdir -p "$recdir"; rec="$recdir/rec.json"
  url="http://localhost:$PORT/$(urlenc "$folder/$deck")?rec=1"
  echo "[v4] RECORD $folder $(date +%H:%M:%S) (free ${avail}KB)" | tee -a "$LOG"
  ( cd "$FE" && node "$HERE/record-walkthrough-v4.mjs" "$url" "$recdir" ) > "$rec" 2>"$recdir/err"
  if ! python3 -c "import json;json.load(open('$rec'))" 2>/dev/null; then
    echo "[v4] !! RECORD FAIL $folder: $(tail -1 "$recdir/err")" | tee -a "$LOG"; rm -rf "$recdir"; continue; fi
  vid=$(python3 -c "import json;print(json.load(open('$rec'))['video'])")
  out="$TMP/$folder.zh.mp4"
  if python3 "$HERE/mux-walkthrough-v4.py" --rec "$rec" --narr "$ROOT/narration/$narr" --webm "$vid" --out "$out" --rate "$TTS_RATE" >>"$LOG" 2>&1; then
    mb=$(( $(stat -f%z "$out")/1000000 ))
    if [ "$mb" -lt 10 ]; then echo "[v4] !! TRUNCATED $folder ${mb}MB (NOT uploaded)" | tee -a "$LOG"; rm -f "$out"
    elif rclone moveto "$out" "$DRIVE/$folder.zh.mp4" --timeout 120s >>"$LOG" 2>&1; then echo "[v4] OK+UPLOADED $folder ${mb}MB" | tee -a "$LOG"
    else echo "[v4] !! UPLOAD FAIL $folder (kept $out)" | tee -a "$LOG"; fi
  else echo "[v4] !! MUX FAIL $folder" | tee -a "$LOG"; fi
  rm -f "$vid"; rm -rf "$recdir"
done < "$LIST"
echo "[v4] done $(date)" | tee -a "$LOG"
