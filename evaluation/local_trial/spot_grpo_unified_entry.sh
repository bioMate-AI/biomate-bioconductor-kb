#!/usr/bin/env bash
# On-box entry for the UNIFIED STAGE-2 GRPO. Starts from sft_gold_adapter (collected-gold SFT = the
# start policy + KL reference) and RL-tunes it against the UNIFIED verifiable reward
# (decision_reward.decision_reward — dispatches decision/routing/param/autofix scorers; pure stdlib,
# no verifier DB). Spot-resilient: resumes from S3 checkpoints, mirrors every 120s, handles the
# interruption notice, self-uploads the final adapter. Same pinned venv as decomp GRPO
# (trl==1.14.1 ships GRPOTrainer). Faithful port of spot_grpo_decomp_entry.sh.
set -euo pipefail
source /opt/biomate-cpt-venv/bin/activate
export PYTHONUNBUFFERED=1 PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
HERE=$(cd "$(dirname "$0")" && pwd)
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=med; TAG=${TAG:-_grpo_unified}
HF=${HF_OVERRIDE:-Qwen/Qwen3.5-9B}; HF_REV=${HF_REVISION:-c202236235762e1c871ad0ccb60c8ee5ba337b9a}
OUT="$SCRATCH/out/$SIZE/grpo"; CKPT_S3="$S3/spot_ckpt/$SIZE/grpo$TAG"; LOG_S3="$S3/spot_logs/$SIZE/grpo$TAG"
TRAIN_LOG=${TRAIN_LOG:-/var/log/spot_grpo.log}
mkdir -p "$OUT" "$SCRATCH/models/base_$SIZE" "$SCRATCH/sft_gold" "$SCRATCH/data"
exec > >(tee -a "$TRAIN_LOG") 2>&1

# knobs (all overridable from the launcher env)
MAX_STEPS=${MAX_STEPS:-400}; SAVE_STEPS=${SAVE_STEPS:-25}; NUMGEN=${NUMGEN:-8}
BETA=${BETA:-0.04}; TEMP=${TEMP:-0.9}; LR=${LR:-1e-6}; BS=${BS:-2}; GA=${GA:-8}
# start policy (= KL reference) + unified corpus, staged on S3 by the launcher
SFT_ADAPTER_S3=${SFT_ADAPTER_S3:-$S3/models_20260919/med/sft_gold_adapter}
DATA_S3=${DATA_S3:-$S3/sft/unified_grpo_corpus.jsonl}

( while true; do aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet 2>/dev/null; sleep 30; done ) & LOGPID=$!
echo "[grpo] $(date) pulling base + sft_gold adapter + unified corpus"
[ -f "$SCRATCH/models/base_$SIZE/config.json" ] || \
  PYTHONNOUSERSITE=1 python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', revision='$HF_REV', local_dir='$SCRATCH/models/base_$SIZE')"
aws s3 cp "$SFT_ADAPTER_S3/" "$SCRATCH/sft_gold/" --recursive --quiet || { echo SFT_ADAPTER_FAIL; exit 11; }
aws s3 cp "$DATA_S3" "$SCRATCH/data/unified_grpo_corpus.jsonl" --quiet || { echo DATA_FAIL; exit 12; }

echo "[grpo] resume check"; aws s3 sync "$CKPT_S3/" "$OUT/" --quiet || true
RESUME=""; LAST=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1) || LAST=""
[ -n "$LAST" ] && RESUME="--resume $LAST" && echo "[grpo] resuming from $LAST"

( while true; do aws s3 sync "$OUT/" "$CKPT_S3/" --exclude "*" --include "*checkpoint-*" --quiet; sleep 120; done ) & SYNCPID=$!
( while true; do curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q action \
    && { echo "[grpo] interruption notice — final sync"; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet; break; }; sleep 5; done ) & WATCHPID=$!
trap 'rc=$?; trap - EXIT; kill $SYNCPID $WATCHPID $LOGPID 2>/dev/null || true; aws s3 sync "$OUT/" "$CKPT_S3/" --quiet || true; aws s3 cp "$TRAIN_LOG" "$LOG_S3/train.log" --quiet || true; exit "$rc"' EXIT

echo "[grpo] START UNIFIED GRPO (steps=$MAX_STEPS numgen=$NUMGEN beta=$BETA temp=$TEMP lr=$LR reward=decision_reward(unified) EVAL_HOOK=${EVAL_HOOK:-0})"
python3 "$HERE/train_grpo_unified.py" \
  --base "$SCRATCH/models/base_$SIZE" --adapter "$SCRATCH/sft_gold" \
  --data "$SCRATCH/data/unified_grpo_corpus.jsonl" \
  --out "$OUT" --max-steps "$MAX_STEPS" --save-steps "$SAVE_STEPS" --num-generations "$NUMGEN" \
  --beta "$BETA" --temperature "$TEMP" --lr "$LR" --batch-size "$BS" --grad-accum "$GA" $RESUME
RC=$?
echo "[grpo] training exit=$RC — upload final adapter"
aws s3 cp "$OUT/" "$S3/models_20260919/$SIZE/grpo${TAG}_adapter/" --recursive --quiet
echo "SPOT_GRPO${TAG}_DONE size=$SIZE rc=$RC"
