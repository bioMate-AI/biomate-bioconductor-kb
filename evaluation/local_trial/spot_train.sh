#!/bin/bash
# Spot-instance-resilient training wrapper. Survives spot reclamation:
#  - RESUME: on (re)start, pulls the latest checkpoint for this stage/model from S3 and resumes.
#  - SYNC:   a background loop mirrors local checkpoints -> S3 every 120s (so a reclaim loses <=120s).
#  - INTERRUPT: a watcher polls the spot instance-action metadata; on the 2-min notice it does a final
#    checkpoint sync before the instance dies.
# Designed to be the spot instance's user-data entrypoint OR re-run after a restart — it is idempotent.
#
#   MODEL_SIZE=small STAGE=midtrain bash spot_train.sh
#   MODEL_SIZE=small STAGE=sft      bash spot_train.sh
set -uo pipefail
SIZE=${MODEL_SIZE:-large}; STAGE=${STAGE:-midtrain}
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
CKPT_S3="$S3/spot_ckpt/$SIZE/$STAGE"
OUT="$SCRATCH/out/$SIZE/$STAGE"; mkdir -p "$OUT"
case "$SIZE" in
  small) BASE="$SCRATCH/models/base_small"; MID=400; SFT=400; SEQ=2048; R=16 ;;
  large) BASE="$SCRATCH/models/base_large"; MID=800; SFT=600; SEQ=2048; R=32 ;;
esac

echo "[spot] pull any existing checkpoints for $SIZE/$STAGE from S3 (resume)…"
aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""
LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1)
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[spot] resuming from $LAST"

# background: mirror checkpoints to S3 every 120s (bounded data loss on reclaim)
( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "checkpoint-*" --quiet; sleep 120; done ) &
SYNC_PID=$!
# background: spot interruption watcher -> final sync on the 2-min notice
( while true; do
    if curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action; then
      echo "[spot] interruption notice — final checkpoint sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break
    fi; sleep 5; done ) &
WATCH_PID=$!
trap 'kill $SYNC_PID $WATCH_PID 2>/dev/null; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet' EXIT

echo "[spot] STAGE=$STAGE SIZE=$SIZE start"
if [ "$STAGE" = "midtrain" ]; then
  python3 "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
     --out "$OUT" --max-steps $MID --seq-len $SEQ --lora-r $R $RESUME \
     ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
elif [ "$STAGE" = "sft" ]; then
  python3 "$HERE/train_qlora_pilot.py" --base "${BASE_DOMAIN:-$BASE}" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT" --max-steps $SFT --seq-len $SEQ --lora-r $R $RESUME
else echo "STAGE must be midtrain|sft"; exit 1; fi

echo "[spot] $STAGE done — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_$(date +%Y%m%d 2>/dev/null || echo 20260919)/$SIZE/${STAGE}_adapter/" --recursive --quiet
echo "SPOT_${STAGE}_DONE size=$SIZE"
