#!/bin/bash
# Evaluate a trained model on the GPU box: load base 4-bit + SFT adapter (direct, no vLLM) and run the
# out-of-catalog removal eval vs the 0.54 baseline. Streams log to S3; uploads result; self-terminates.
#   MODEL_SIZE=small STAGE=sft  bash spot_eval.sh   (eval the SFT-only adapter on the raw base)
#   MODEL_SIZE=small STAGE=full bash spot_eval.sh   (eval the midtrain->SFT adapter on base_domain)
set -uo pipefail
SIZE=${MODEL_SIZE:-small}; STAGE=${STAGE:-sft}; TAG=${TAG:-}; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export EVAL_DIR="$SCRATCH/evaldata"; mkdir -p "$EVAL_DIR" "$SCRATCH/models"
case "$SIZE" in
  small) HF=Qwen/Qwen3-4B    ;;
  large) HF=Qwen/Qwen3.8-27B ;;
esac
BASE="$SCRATCH/models/base_$SIZE"; ADAPTER="$SCRATCH/models/adapter_$SIZE"
ADIR="${STAGE}${TAG}_adapter"   # sft_adapter | full_adapter | full_mix_adapter — S3 folder for this variant's adapter
LOGS3="$S3/spot_logs/$SIZE/eval$TAG"

echo "[eval] pull base + adapter + removal dataset (stage=$STAGE)"
[ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"
aws s3 cp "$S3/eval/removal_eval.jsonl" "$EVAL_DIR/removal_eval.jsonl" --quiet
( while true; do aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet 2>/dev/null; sleep 30; done ) &

# STAGE=full: the adapter's true base is base_domain (raw base + merged mid-training), NOT the raw HF
# base. Pull base_domain (persisted by spot_train.sh's full stage) or the eval is meaningless.
EVALBASE="$BASE"
if [ "$STAGE" = full ]; then
  BD="$SCRATCH/models/base_domain${TAG}_$SIZE"
  [ -f "$BD/config.json" ] || aws s3 cp "$S3/models_20260919/$SIZE/base_domain$TAG/" "$BD/" --recursive --quiet
  if [ ! -f "$BD/config.json" ]; then
    echo "[eval] FATAL: base_domain$TAG missing at $S3/models_20260919/$SIZE/base_domain$TAG/ — re-run STAGE=full (TAG=$TAG) with the persistence patch before evaluating."; exit 3
  fi
  EVALBASE="$BD"
fi

# CKPTS = comma list of checkpoint subdirs to compare (e.g. "checkpoint-250,checkpoint-500"); default = final adapter
for CK in $(echo "${CKPTS:-final}" | tr ',' ' '); do
  if [ "$CK" = final ]; then SRC="$S3/models_20260919/$SIZE/$ADIR"; CKTAG=final; else SRC="$S3/models_20260919/$SIZE/$ADIR/$CK"; CKTAG=$CK; fi
  rm -rf "$ADAPTER"; aws s3 cp "$SRC/" "$ADAPTER/" --recursive --exclude "checkpoint-*/*" --quiet
  VLABEL="${STAGE}${TAG}-${CKTAG}"   # e.g. full-final | full_mix-final — keeps A/B results distinct
  echo "[eval] === $VLABEL (base=$(basename "$EVALBASE")) ==="
  python3 "$HERE/eval_removal.py" --direct --base "$EVALBASE" --adapter "$ADAPTER" --model "qwen-$SIZE-$VLABEL" --limit 80 \
    --out "$EVAL_DIR/removal_${SIZE}_${VLABEL}.json"
  aws s3 cp "$EVAL_DIR/removal_${SIZE}_${VLABEL}.json" "$S3/eval/removal_${SIZE}_${VLABEL}.json" --quiet
done
aws s3 cp /var/log/ud.log "$LOGS3/eval.log" --quiet
echo "SPOT_EVAL_DONE size=$SIZE stage=$STAGE$TAG"
