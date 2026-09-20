#!/bin/bash
# Spot-resilient trainer for ONE model size. Self-sufficient: downloads base model, pulls data,
# resumes from S3 checkpoints, mirrors checkpoints to S3, handles the spot interruption notice.
# SFT-first path (mid-train optional): STAGE=sft trains the SFT adapter directly on the base.
#   MODEL_SIZE=small STAGE=sft bash spot_train.sh
set -uo pipefail
SIZE=${MODEL_SIZE:-small}; STAGE=${STAGE:-sft}
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
CKPT_S3="$S3/spot_ckpt/$SIZE/$STAGE"; LOG_S3="$S3/spot_logs/$SIZE/$STAGE"
OUT="$SCRATCH/out/$SIZE/$STAGE"; mkdir -p "$OUT" "$SCRATCH/data" "$SCRATCH/models"
case "$SIZE" in
  small) HF=Qwen/Qwen3-4B    ; SFT=500; MID=400; SEQ=2048; R=16 ;;
  large) HF=Qwen/Qwen3.8-27B ; SFT=700; MID=800; SEQ=2048; R=32 ;;
  *) echo "MODEL_SIZE must be small|large"; exit 1 ;;
esac
SEQ=${SEQ_OVERRIDE:-$SEQ}; R=${R_OVERRIDE:-$R}; MID=${MID_OVERRIDE:-$MID}   # overrides to fit GPU / set corpus coverage
BASE="$SCRATCH/models/base_$SIZE"

# stream this log to S3 every 30s so progress/errors are observable without SSH
( while true; do aws s3 cp /var/log/spot_train.log "$LOG_S3/train.log" --quiet 2>/dev/null; sleep 30; done ) &
LOGPID=$!

echo "[spot] $(date) size=$SIZE stage=$STAGE — pull data + base"
aws s3 cp "$S3/sft/multitask_sft_enriched.jsonl" "$SCRATCH/data/sft_enriched.jsonl" --quiet
[ "$STAGE" != sft ] && aws s3 cp "$S3/midtrain_corpus/midtrain_all.jsonl" "$SCRATCH/data/midtrain_all.jsonl" --quiet
if [ ! -d "$BASE" ]; then
  echo "[spot] downloading base $HF"
  python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"
fi

echo "[spot] resume check"; aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""; LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1)
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[spot] resuming from $LAST"

( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "checkpoint-*" --quiet; sleep 120; done ) & SYNCPID=$!
( while true; do curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action \
    && { echo "[spot] interruption notice — final sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break; }; sleep 5; done ) & WATCHPID=$!
trap 'kill $SYNCPID $WATCHPID $LOGPID 2>/dev/null; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; aws s3 cp /var/log/spot_train.log "$LOG_S3/train.log" --quiet' EXIT

echo "[spot] START training stage=$STAGE (MID=$MID SFT=$SFT SEQ=$SEQ R=$R)"
if [ "$STAGE" = midtrain ]; then
  python3 "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
     --out "$OUT" --max-steps $MID --seq-len $SEQ --lora-r $R $RESUME ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
elif [ "$STAGE" = full ]; then
  # committee-v3 fix: domain-adaptive mid-training FIRST, merge, then SFT — all on one box
  python3 "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
     --out "$OUT/midtrain" --max-steps $MID --seq-len $SEQ --lora-r $R ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
  python3 "$HERE/merge_lora.py" --base "$BASE" --adapter "$OUT/midtrain" --out "$OUT/base_domain"
  python3 "$HERE/train_qlora_pilot.py" --base "$OUT/base_domain" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT/sft" --max-steps $SFT --seq-len $SEQ --lora-r $R
  OUT="$OUT/sft"   # so the upload below grabs the SFT adapter
else
  python3 "$HERE/train_qlora_pilot.py" --base "${BASE_DOMAIN:-$BASE}" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT" --max-steps $SFT --seq-len $SEQ --lora-r $R $RESUME
fi
RC=$?
echo "[spot] training exit=$RC — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_20260919/$SIZE/${STAGE}_adapter/" --recursive --quiet
echo "SPOT_${STAGE}_DONE size=$SIZE rc=$RC"
