#!/usr/bin/env bash
# On-box entry for Arm-A DPO. Starts from the clean SFT policy (sft_sftclean adapter, loaded base+
# adapter — the KL reference is the adapter-disabled model, so DPO improves over the SFT policy) and
# trains on the committee-VALIDATED preference pairs (dpo_pairs_validated.jsonl). Spot-resilient:
# resumes from S3 checkpoints, mirrors every 120s, handles interruption, self-uploads the adapter.
# Mirror of spot_grpo_unified_entry.sh; trl==1.14.1 ships DPOTrainer.
set -euo pipefail
source /opt/biomate-cpt-venv/bin/activate
export PYTHONUNBUFFERED=1 PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
HERE=$(cd "$(dirname "$0")" && pwd)
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=med; TAG=${TAG:-_dpo_clean}
HF=${HF_OVERRIDE:-Qwen/Qwen3.5-9B}; HF_REV=${HF_REVISION:-c202236235762e1c871ad0ccb60c8ee5ba337b9a}
OUT="$SCRATCH/out/$SIZE/dpo"; CKPT_S3="$S3/spot_ckpt/$SIZE/dpo$TAG"; LOG_S3="$S3/spot_logs/$SIZE/dpo$TAG"
TRAIN_LOG=${TRAIN_LOG:-/var/log/spot_dpo.log}
mkdir -p "$OUT" "$SCRATCH/models/base_$SIZE" "$SCRATCH/sft_start" "$SCRATCH/data"
exec > >(tee -a "$TRAIN_LOG") 2>&1

DPO_EPOCHS=${DPO_EPOCHS:-2}
# start policy (sft_sftclean = the KL reference) + validated pairs, staged on S3 by the launcher
SFT_ADAPTER_S3=${SFT_ADAPTER_S3:-$S3/models_20260919/med/sft_sftclean_adapter}
DATA_S3=${DATA_S3:-$S3/sft/dpo_pairs_validated.jsonl}

( while true; do aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet 2>/dev/null; sleep 30; done ) & LOGPID=$!
echo "[dpo] $(date) pulling base + sft_sftclean adapter + validated pairs"
[ -f "$SCRATCH/models/base_$SIZE/config.json" ] || \
  PYTHONNOUSERSITE=1 python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', revision='$HF_REV', local_dir='$SCRATCH/models/base_$SIZE')"
aws s3 cp "$SFT_ADAPTER_S3/" "$SCRATCH/sft_start/" --recursive --quiet || { echo SFT_ADAPTER_FAIL; exit 11; }
aws s3 cp "$DATA_S3" "$SCRATCH/data/dpo_pairs_validated.jsonl" --quiet || { echo DATA_FAIL; exit 12; }

echo "[dpo] resume check"; aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""; LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || LAST=""
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[dpo] resuming from $LAST"

( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "*checkpoint-*" --quiet; sleep 120; done ) & SYNCPID=$!
( while true; do curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action \
    && { echo "[dpo] interruption notice — final sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break; }; sleep 5; done ) & WATCHPID=$!
trap 'rc=$?; trap - EXIT; kill $SYNCPID $WATCHPID $LOGPID 2>/dev/null || true; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet || true; aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet || true; exit "$rc"' EXIT

echo "[dpo] START DPO (epochs=$DPO_EPOCHS start=sft_sftclean pairs=$(wc -l < "$SCRATCH/data/dpo_pairs_validated.jsonl"))"
DPO_EPOCHS=$DPO_EPOCHS python3 "$HERE/train_dpo_grounded.py" --phase train \
  --model "$SCRATCH/models/base_$SIZE" --adapter "$SCRATCH/sft_start" \
  --pairs-out "$SCRATCH/data/dpo_pairs_validated.jsonl" --out "$OUT" $RESUME
RC=$?
echo "[dpo] training exit=$RC — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_20260919/$SIZE/dpo${TAG}_adapter/" --recursive --quiet
echo "SPOT_DPO${TAG}_DONE size=$SIZE rc=$RC"
