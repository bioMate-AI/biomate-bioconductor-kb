#!/bin/bash
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/small/diag/eval.log"; mkdir -p "$SCRATCH/models" "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/small/sft_v4_adapter/" "$SCRATCH/d/AD/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/corpus_eval_big.jsonl" "$SCRATCH/d/ce.jsonl" --quiet
python3 "$HERE/eval_diag.py" --base "$BASE" --adapter "$SCRATCH/d/AD" --evalfile "$SCRATCH/d/ce.jsonl" --per 2
echo "DIAG_COMPLETE"
