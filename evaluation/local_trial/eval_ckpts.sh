#!/bin/bash
# Box entry: per-checkpoint eval -> learning curve. SFT mode = gold routing; midtrain mode = knowledge NLL.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=${MODEL_SIZE:-small}; TAG=${TAG:-_v4}; MODE=${CKMODE:-sft}; STG=${CKPT_STAGE:-sft}
LOGDST="$S3/spot_logs/$SIZE/ckpteval$TAG/eval.log"; mkdir -p "$SCRATCH/ck" "$SCRATCH/models"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
HF=Qwen/Qwen3-4B; BASE="$SCRATCH/models/base"
[ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"
# pull checkpoints (flat for sft; nested midtrain/ for full stage)
SRC="$S3/spot_ckpt/$SIZE/$STG$TAG/"; [ "$MODE" = midtrain ] && SRC="$S3/spot_ckpt/$SIZE/full${TAG}/midtrain/"
aws s3 cp "$SRC" "$SCRATCH/ck/" --recursive --quiet
EXTRA=""
if [ "$MODE" = sft ]; then aws s3 cp "$S3/eval/gold_routing_eval.jsonl" "$SCRATCH/gr.jsonl" --quiet; EXTRA="--evalfile $SCRATCH/gr.jsonl";
else aws s3 cp "$S3/eval/midtrain_probe.jsonl" "$SCRATCH/probe.jsonl" --quiet; EXTRA="--probe $SCRATCH/probe.jsonl"; fi
python3 "$HERE/eval_checkpoints.py" --base "$BASE" --ckpt-root "$SCRATCH/ck" --mode "$MODE" $EXTRA --out "$SCRATCH/curve.json"
aws s3 cp "$SCRATCH/curve.json" "$S3/eval/ckpt_curve_$SIZE$TAG.json" --quiet
echo "CKPT_CURVE_DONE"
