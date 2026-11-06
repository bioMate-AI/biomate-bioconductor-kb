#!/bin/bash
# Eval PLAIN Qwen3-4B (no SFT, no adapter) on curated gold routing — the true zero-shot base baseline.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/small/baseeval/eval.log"; mkdir -p "$SCRATCH/models" "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/eval/gold_routing_eval.jsonl" "$SCRATCH/d/gr.jsonl" --quiet
export EVAL_DTYPE=bf16
python3 "$HERE/eval_gold.py" --base "$BASE" --adapter "" --model base_noSFT --evalfile "$SCRATCH/d/gr.jsonl" --out "$SCRATCH/base.json"
aws s3 cp "$SCRATCH/base.json" "$S3/eval/base_routing.json" --quiet
echo "BASE_EVAL_DONE"; cat "$SCRATCH/base.json"
