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
aws s3 cp "$S3/eval/removal_eval.jsonl" "$EVAL_DIR/removal_eval.jsonl" --quiet
( while true; do aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet 2>/dev/null; sleep 30; done ) &

# CKPTS = comma list of checkpoint subdirs to compare (e.g. "checkpoint-250,checkpoint-500"); default = final adapter
for CK in $(echo "${CKPTS:-final}" | tr ',' ' '); do
  if [ "$CK" = final ]; then SRC="$S3/models_20260919/$SIZE/sft_adapter"; TAG=final; else SRC="$S3/models_20260919/$SIZE/sft_adapter/$CK"; TAG=$CK; fi
  rm -rf "$ADAPTER"; aws s3 cp "$SRC/" "$ADAPTER/" --recursive --exclude "checkpoint-*/*" --quiet
  echo "[eval] === checkpoint $TAG ==="
  python3 "$HERE/eval_removal.py" --direct --base "$BASE" --adapter "$ADAPTER" --model "qwen-$SIZE-$TAG" --limit 80 \
    --out "$EVAL_DIR/removal_${SIZE}_${TAG}.json"
  aws s3 cp "$EVAL_DIR/removal_${SIZE}_${TAG}.json" "$S3/eval/removal_${SIZE}_${TAG}.json" --quiet
done
aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet
echo "SPOT_EVAL_DONE size=$SIZE"
