#!/bin/bash
# Launch the DECOMP-V2 retrain of the on-prem 9B: QLoRA SFT (r16/a32) on the clean base
# Qwen/Qwen3.5-9B @ c202236..., SFT_DATA = prior gold mix + 4,300 depends_on decomp rows folded in.
# STOP EARLY at 650 steps (plateau finding: gains realized ~550, must_not_fill penalty grows after);
# SAVE_STEPS default 25 keeps intermediate checkpoints evaluable. TAG=_decompv2 so the prior
# sft_gold adapter is untouched. SPOT only, cycle AZ/type, resume-safe (ckpts mirror to S3), the
# box self-terminates. Reuses spot_sft_gold_entry.sh + today_bootstrap.sh (pinned train venv).
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}   # spot_launch userdata expands it under set -u
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_decompv2.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_sft_gold_entry.sh BOOTSTRAP=today_bootstrap.sh
export TAG=${TAG:-_decompv2} SFT_DATA=${SFT_DATA:-sft_from_gold_v2_decomp_20261006.jsonl}
export SFT_OVERRIDE=${SFT_OVERRIDE:-650} SEQ_OVERRIDE=2048 BS_OVERRIDE=1 GA_OVERRIDE=16 FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
# 9B QLoRA 4-bit fits any single 24GB+ GPU; broad pool maximizes spot availability in a crunch
TYPES=(g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6.4xlarge g5.4xlarge g6e.xlarge g6.8xlarge g5.8xlarge g6e.2xlarge)
RESULT="$S3/models_20260919/med/sft${TAG}_adapter/adapter_config.json"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 6*3600 ))
for attempt in $(seq 1 12); do
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (spot-only policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "SFT_9B${TAG} attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== sft${TAG}_adapter READY ==="; echo "INSTANCE=$IID"; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunch to resume from S3 ckpt">&2; break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
