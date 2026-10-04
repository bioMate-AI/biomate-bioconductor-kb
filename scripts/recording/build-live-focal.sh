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

# t3-completed-withheld: T3's own run (c40459b2) has findings WITHHELD (outputs
# unreadable) — the honesty teaching point — so it cannot reuse the flagship's
# populated-findings completed.png. Crop T3's tracked full-panel r8 to the right
# After-run panel: Completed badge + tabs + RUN ORIGINAL + the amber withheld
# message + the manifest-provenance line (drops the chat column and empty space).
R8="$ROOT/reference/claude_design/tutorials/assets/r8-completed-chat-and-panel.png"
if [ -f "$R8" ]; then
  ffmpeg -y -loglevel error -i "$R8" -filter_complex "crop=1680:690:1200:190" "$DST/t3-completed-withheld.png"
fi

# T0 getting-started focal stills come from the live cold-start capture
# (capture-live-t0-focal.cjs → recording/video/live-t0-focal/*.png). They are
# already element-clipped at 3x, so just copy them into place.
T0SRC="$ROOT/recording/video/live-t0-focal"
for f in t0-composer t0-lane; do
  [ -f "$T0SRC/$f.png" ] && cp "$T0SRC/$f.png" "$DST/$f.png"
done

# T1 Design & Generate focal stills from capture-live-t1-focal.cjs (one small-
# molecule generate on an aspirin seed; already element-clipped at 3x).
T1SRC="$ROOT/recording/video/live-t1-focal"
for f in t1-form t1-results t1-pareto t1-rejection; do
  [ -f "$T1SRC/$f.png" ] && cp "$T1SRC/$f.png" "$DST/$f.png"
done

# T2 Models & closed-loop focal stills from capture-live-t2-focal.cjs (read-only
# navigation of /models tabs; already element-clipped at 3x).
T2SRC="$ROOT/recording/video/live-t2-focal"
for f in t2-registry t2-model-object t2-run t2-rounds; do
  [ -f "$T2SRC/$f.png" ] && cp "$T2SRC/$f.png" "$DST/$f.png"
done

# T4 Bringing-your-own-data focal stills from capture-live-t4-focal.cjs (uploads a
# demo CSV; element-clipped at 3x).
T4SRC="$ROOT/recording/video/live-t4-focal"
for f in t4-data-hub t4-dataset-object t4-quality; do
  [ -f "$T4SRC/$f.png" ] && cp "$T4SRC/$f.png" "$DST/$f.png"
done

echo "built focal stills:"
for f in prerun running completed outputs record t3-completed-withheld; do
  [ -f "$DST/$f.png" ] || continue
  printf '  %-22s ' "$f.png"; ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$DST/$f.png"
done
