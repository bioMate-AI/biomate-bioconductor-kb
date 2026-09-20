#!/bin/bash
# Evaluate a trained model on the GPU box: load base 4-bit + SFT adapter (direct, no vLLM) and run the
# out-of-catalog removal eval vs the 0.54 baseline. Streams log to S3; uploads result; self-terminates.
#   MODEL_SIZE=small bash spot_eval.sh   (as the instance entrypoint)
set -uo pipefail
SIZE=${MODEL_SIZE:-small}; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export EVAL_DIR="$SCRATCH/evaldata"; mkdir -p "$EVAL_DIR" "$SCRATCH/models"
case "$SIZE" in
  small) HF=Qwen/Qwen3-4B    ;;
  large) HF=Qwen/Qwen3.8-27B ;;
esac
BASE="$SCRATCH/models/base_$SIZE"; ADAPTER="$SCRATCH/models/adapter_$SIZE"
LOGS3="$S3/spot_logs/$SIZE/eval"

echo "[eval] pull base + adapter + removal dataset"
[ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/$SIZE/sft_adapter/" "$ADAPTER/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/removal_eval.jsonl" "$EVAL_DIR/removal_eval.jsonl" --quiet
( while true; do aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet 2>/dev/null; sleep 30; done ) &

echo "[eval] run removal eval (direct load, base 4bit + adapter)"
python3 "$HERE/eval_removal.py" --direct --base "$BASE" --adapter "$ADAPTER" --model "qwen-$SIZE-sft" --limit 80 \
  --out "$EVAL_DIR/removal_eval_${SIZE}.json"
aws s3 cp "$EVAL_DIR/removal_eval_${SIZE}.json" "$S3/eval/removal_eval_${SIZE}_trained.json" --quiet
aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet
echo "SPOT_EVAL_DONE size=$SIZE"
