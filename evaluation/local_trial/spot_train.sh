#!/bin/bash
# Spot-resilient trainer for ONE model size. Self-sufficient: downloads base model, pulls data,
# resumes from S3 checkpoints, mirrors checkpoints to S3, handles the spot interruption notice.
# SFT-first path (mid-train optional): STAGE=sft trains the SFT adapter directly on the base.
#   MODEL_SIZE=small STAGE=sft bash spot_train.sh
set -uo pipefail
SIZE=${MODEL_SIZE:-small}; STAGE=${STAGE:-sft}; TAG=${TAG:-}   # TAG namespaces outputs for A/B variants (e.g. _mix)
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
CKPT_S3="$S3/spot_ckpt/$SIZE/$STAGE$TAG"; LOG_S3="$S3/spot_logs/$SIZE/$STAGE$TAG"
OUT="$SCRATCH/out/$SIZE/$STAGE"; mkdir -p "$OUT" "$SCRATCH/data" "$SCRATCH/models"
case "$SIZE" in
  small) HF=Qwen/Qwen3-4B    ; SFT=500; MID=400; SEQ=2048; R=16 ;;
  large) HF=Qwen/Qwen3.8-27B ; SFT=700; MID=800; SEQ=2048; R=32 ;;
  *) echo "MODEL_SIZE must be small|large"; exit 1 ;;
esac
SEQ=${SEQ_OVERRIDE:-$SEQ}; R=${R_OVERRIDE:-$R}; MID=${MID_OVERRIDE:-$MID}   # overrides to fit GPU / set corpus coverage
BS=${BS_OVERRIDE:-1}; GA=${GA_OVERRIDE:-16}   # per-device batch + grad-accum (raise BS to fill a big GPU)
NGPU=$(nvidia-smi -L 2>/dev/null | wc -l); [ "${NGPU:-0}" -ge 1 ] || NGPU=1
# multi-GPU -> torchrun data-parallel (each rank = full model on its own GPU); single GPU -> plain python
# FORCE_NGPU pins the launcher (e.g. =1 to use the proven single-process path even on a multi-GPU box).
[ -n "${FORCE_NGPU:-}" ] && NGPU=$FORCE_NGPU
# --tee/--redirects surface each rank's child traceback into the log (torchrun otherwise hides it: error_file N/A).
if [ "$NGPU" -gt 1 ]; then LAUNCH="torchrun --nproc_per_node=$NGPU --master_port=29500 --tee 3 --redirects 3"; else LAUNCH="python3"; fi
echo "[spot] GPUs=$NGPU launcher='$LAUNCH' per-device-batch=$BS grad-accum=$GA (effective batch=$((BS*GA*NGPU)))"
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

# FETCH_REPLAY=1 → build/reuse the general-replay corpus (FineWeb-Edu, ODC-BY) for the 25/75
# anti-forgetting mixture. Reused from S3 if already staged; else streamed here (disk box) + cached.
if [ "${FETCH_REPLAY:-0}" = 1 ] && [ "$STAGE" != sft ]; then
  REPLAY="$SCRATCH/data/general_replay.jsonl"
  [ -s "$REPLAY" ] || aws s3 cp "$S3/midtrain_corpus/general_replay.jsonl" "$REPLAY" --quiet 2>/dev/null || true
  if [ ! -s "$REPLAY" ]; then
    echo "[spot] streaming general-replay (FineWeb-Edu sample-10BT) -> $REPLAY"
    python3 - "$REPLAY" "${REPLAY_DOCS:-550000}" <<'PYEOF'
import sys, json
from datasets import load_dataset
out, cap = sys.argv[1], int(sys.argv[2])
ds = load_dataset("HuggingFaceFW/fineweb-edu", "sample-10BT", split="train", streaming=True)
n = 0
with open(out, "w") as f:
    for r in ds:
        t = r.get("text", "")
        if len(t) > 300:
            f.write(json.dumps({"text": t[:16000]}) + "\n"); n += 1
        if n >= cap: break
print("general_replay docs:", n)
PYEOF
    aws s3 cp "$REPLAY" "$S3/midtrain_corpus/general_replay.jsonl" --quiet
  fi
  export REPLAY REPLAY_FRAC=${REPLAY_FRAC:-0.75}
  echo "[spot] replay ready: $(wc -l < "$REPLAY") docs, frac=$REPLAY_FRAC"
fi

echo "[spot] resume check"; aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""; LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1)
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[spot] resuming from $LAST"

( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "*checkpoint-*" --quiet; sleep 120; done ) & SYNCPID=$!
( while true; do curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action \
    && { echo "[spot] interruption notice — final sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break; }; sleep 5; done ) & WATCHPID=$!
trap 'kill $SYNCPID $WATCHPID $LOGPID 2>/dev/null; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; aws s3 cp /var/log/spot_train.log "$LOG_S3/train.log" --quiet' EXIT

echo "[spot] START training stage=$STAGE (MID=$MID SFT=$SFT SEQ=$SEQ R=$R)"
if [ "$STAGE" = midtrain ]; then
  $LAUNCH "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
     --out "$OUT" --max-steps $MID --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $RESUME ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
elif [ "$STAGE" = full ]; then
  # committee-v3 fix: domain-adaptive mid-training FIRST, merge, then SFT — all on one box
  $LAUNCH "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
     --out "$OUT/midtrain" --max-steps $MID --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA ${REPLAY:+--replay "$REPLAY" --replay-frac ${REPLAY_FRAC:-0.5}}
  python3 "$HERE/merge_lora.py" --base "$BASE" --adapter "$OUT/midtrain" --out "$OUT/base_domain"   # merge = single process
  # PERSIST mid-training artifacts NOW — NVMe is wiped on spot terminate. full_adapter's base IS
  # base_domain (the merged domain-adapted base); without it the SFT adapter is orphaned + un-evaluable.
  aws s3 cp "$OUT/midtrain/" "$S3/models_20260919/$SIZE/midtrain_adapter$TAG/" --recursive --exclude "checkpoint-*/*" --quiet
  aws s3 cp "$OUT/base_domain/" "$S3/models_20260919/$SIZE/base_domain$TAG/" --recursive --quiet
  $LAUNCH "$HERE/train_qlora_pilot.py" --base "$OUT/base_domain" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT/sft" --max-steps $SFT --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA
  OUT="$OUT/sft"   # so the upload below grabs the SFT adapter
else
  $LAUNCH "$HERE/train_qlora_pilot.py" --base "${BASE_DOMAIN:-$BASE}" --data "$SCRATCH/data/sft_enriched.jsonl" \
     --out "$OUT" --max-steps $SFT --seq-len $SEQ --lora-r $R --batch-size $BS --grad-accum $GA $RESUME
fi
RC=$?
echo "[spot] training exit=$RC — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_20260919/$SIZE/${STAGE}${TAG}_adapter/" --recursive --quiet
echo "SPOT_${STAGE}${TAG}_DONE size=$SIZE rc=$RC"
