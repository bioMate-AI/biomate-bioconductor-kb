#!/bin/bash
# LAUNCHER (prepped 2026-10-22; GPU run GATED on explicit go) for the UNIFIED STAGE-2 GRPO on the
# on-prem 9B. RL-tunes the collected-gold SFT adapter (sft_gold_adapter) against the UNIFIED
# verifiable reward (decision_reward.decision_reward, which dispatches decision + routing +
# param + autofix scorers) over the 12,275-row unified corpus. Spot-only, cycle AZ/type,
# resume-safe (ckpts mirror to S3), self-terminating. trl==1.14.1 ships GRPOTrainer.
#
# PRECONDITION (VERIFIED present 2026-10-22): the start-policy adapter exists at
#   $S3/models_20260919/med/sft_gold_adapter/adapter_config.json   (routing+decomp node-F1 0.36->0.73)
# GRPO starts from it and KL-anchors to it. The refusal guard below enforces this.
#
# ONE REMAINING GPU-ENV GLUE (write+test ON the spot box — trl-version-specific, do NOT guess here):
#   spot_grpo_unified_entry.sh  = cp of spot_grpo_decomp_entry.sh, DATA_S3 -> unified corpus,
#     SFT_ADAPTER_S3 -> sft_gold_adapter, and it invokes train_grpo_unified.py.
#   train_grpo_unified.py       = cp of train_grpo_decomp.py with 'import decomp_reward as R' ->
#     'import decision_reward as R'; reward_funcs=[R.decision_reward] (already TRL-shaped, reads the
#     gold/scorer/labels columns — no weights); dataset=unified_grpo_corpus.jsonl; drop W_NODE/EDGE/
#     STRUCT; eval hook scores decomposition_real + decision_eval via their scorers.
# Reward + data are PROVEN offline (decision_reward.py --selftest: 12,275/12,275 oracle>anti-oracle).
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_grpo_unified.tgz"
export MODEL_SIZE=med STAGE=grpo ENTRY=spot_grpo_unified_entry.sh BOOTSTRAP=today_bootstrap.sh
export TAG=${TAG:-_grpo_unified} FORCE_NGPU=1
# GRPO knobs forwarded to the entry (see spot_grpo_unified_entry.sh)
export MAX_STEPS=${MAX_STEPS:-400} SAVE_STEPS=${SAVE_STEPS:-25} NUMGEN=${NUMGEN:-8}
export BETA=${BETA:-0.04} TEMP=${TEMP:-0.9} LR=${LR:-1e-6} BS=${BS:-2} GA=${GA:-8}
export W_NODE=${W_NODE:-0.30} W_EDGE=${W_EDGE:-0.40} W_STRUCT=${W_STRUCT:-0.30} EVAL_HOOK=${EVAL_HOOK:-1}
export SFT_ADAPTER_S3=${SFT_ADAPTER_S3:-$S3/models_20260919/med/sft_gold_adapter}
export DATA_S3=${DATA_S3:-$S3/sft/unified_grpo_corpus.jsonl}
export DB_S3=${DB_S3:-$S3/eval/harness_payload/galaxy_ai_tools.db}

# guard: refuse to launch until the start policy exists (fail loud, don't train from the base)
if ! aws s3 ls "$SFT_ADAPTER_S3/adapter_config.json" >/dev/null 2>&1; then
  echo "REFUSING TO LAUNCH: start-policy adapter not found at $SFT_ADAPTER_S3 — check sft_gold_adapter path."; exit 2; fi

SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.2xlarge g5.2xlarge g6e.xlarge g5.4xlarge)   # 9B QLoRA 4-bit + GRPO rollouts: 24GB+ only
RESULT="$S3/models_20260919/med/grpo${TAG}_adapter/adapter_config.json"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 8*3600 ))
for attempt in $(seq 1 12); do
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (spot-only policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "GRPO_9B${TAG} attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== grpo${TAG}_adapter READY ==="; echo "INSTANCE=$IID"; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunch to resume from S3 ckpt">&2; break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
