#!/bin/bash
# Per-task scorecard on the family-disjoint corpus_eval_big for a trained SFT adapter (TAG picks which).
set -uo pipefail
SIZE=${MODEL_SIZE:-small}; TAG=${TAG:-_v3}; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export EVAL_DIR="$SCRATCH/data"; mkdir -p "$EVAL_DIR" "$SCRATCH/models"
HF=Qwen/Qwen3-4B; BASE="$SCRATCH/models/base"; AD="$SCRATCH/models/ad$TAG"
LOGDST="$S3/spot_logs/$SIZE/evalcorpus$TAG/eval.log"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
# guarantee the FULL log (incl. any crash traceback) lands before the box powers off
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
[ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/$SIZE/sft${TAG}_adapter/" "$AD/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/corpus_eval_big.jsonl" "$EVAL_DIR/corpus_eval.jsonl" --quiet   # eval_corpus reads this name
export EVAL_DTYPE=${EVAL_DTYPE:-bf16} GEN_BATCH=${GEN_BATCH:-24}   # bf16+merged LoRA: ~3-5x faster than bnb-4bit, fits 24GB
python3 "$HERE/eval_corpus.py" --base "$BASE" --adapter "$AD" --model "qwen-$SIZE-sft$TAG" --out "$EVAL_DIR/scorecard$TAG.json"
aws s3 cp "$EVAL_DIR/scorecard$TAG.json" "$S3/eval/scorecard_$SIZE$TAG.json" --quiet
echo "SCORECARD_DONE $TAG"
