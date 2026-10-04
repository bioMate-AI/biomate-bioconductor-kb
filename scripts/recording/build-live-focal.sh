#!/usr/bin/env bash
# Turn the high-DPI focal captures (from capture-live-admet-focal.cjs) into the five
# zoomed, large-font live-UI stills the flagship video embeds. Each still is cropped
# to the single element that makes its scene's point, so the product UI text is large
# and sharp in the slide instead of small in a full-panel view. Only the right-hand
# panel is ever in frame (the honest "exit 1" chat line on the left is never shown).
#
# Inputs : recording/video/live-admet-focal/*.png   (3x device-pixel element crops)
# Outputs: reference/claude_design/tutorials/assets/live/{prerun,running,completed,outputs,record}.png
#
# Run:  bash scripts/recording/build-live-focal.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/recording/video/live-admet-focal"
DST="$ROOT/reference/claude_design/tutorials/assets/live"
mkdir -p "$DST"

# pre-run: editable Smiles List + Admet Model Type (drop the partial 3rd row) stacked
# over the permissions row + Confirm & Run button — "everything editable before compute".
ffmpeg -y -loglevel error -i "$SRC/prerun-params.png" -i "$SRC/prerun-confirm.png" \
  -filter_complex "[0:v]crop=2457:430:0:0,pad=2457:468:0:0:white[a];[a][1:v]vstack=inputs=2" "$DST/prerun.png"

# running: the phase group — RUNNING phase card + the QC GATES list (CiPA/hERG thresholds).
cp "$SRC/running-0.png" "$DST/running.png"

# completed: the Completed badge + Findings Summary values (drop tab bars + explainer middle).
ffmpeg -y -loglevel error -i "$SRC/completed-combo.png" \
  -filter_complex "[0:v]crop=2457:155:0:0,pad=2457:185:0:0:white[t];[0:v]crop=2457:705:0:725[f];[t][f]vstack=inputs=2" "$DST/completed.png"

# outputs: the 6-file Outputs list (crop out the post-run feedback survey overlay on the right).
ffmpeg -y -loglevel error -i "$SRC/outputs-table.png" -filter_complex "crop=1170:672:0:0" "$DST/outputs.png"

# record: reproducibility fields (workflow, run id, status, timestamps) + Outputs + SHA-256
# (drop the Parameters/Input-bindings middle so the fields + checksum table read larger).
ffmpeg -y -loglevel error -i "$SRC/record-full.png" \
  -filter_complex "[0:v]crop=2379:500:0:0,pad=2379:530:0:0:white[t];[0:v]crop=2379:708:0:930[f];[t][f]vstack=inputs=2" "$DST/record.png"

echo "built focal stills:"
for f in prerun running completed outputs record; do
  printf '  %-12s ' "$f.png"; ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$DST/$f.png"
done
