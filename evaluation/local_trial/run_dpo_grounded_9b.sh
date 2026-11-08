#!/bin/bash
# LAUNCHER for Arm-A DPO on the on-prem 9B. Starts from the clean SFT policy (sft_sftclean adapter)
# and DPO-trains on the committee-VALIDATED preference pairs (dpo_pairs_validated.jsonl, 6,424).
# DPO improves over the SFT policy (KL ref = adapter-disabled model). Spot-only, cycle AZ/type,
# resume-safe (ckpts mirror to S3), self-terminating. trl==1.14.1 ships DPOTrainer.
#
# PRECONDITION: the start-policy adapter must exist (sft_sftclean = the clean-data SFT). Refusal
# guard below enforces it. Pairs are committee-validated (validate_dpo_negatives.py, 52% keep).
#   TAG=_dpo_clean bash run_dpo_grounded_9b.sh
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_dpo.tgz"
export MODEL_SIZE=med STAGE=dpo ENTRY=spot_dpo_entry.sh BOOTSTRAP=today_bootstrap.sh
export TAG=${TAG:-_dpo_clean} FORCE_NGPU=1
export DPO_EPOCHS=${DPO_EPOCHS:-2}
export SFT_ADAPTER_S3=${SFT_ADAPTER_S3:-$S3/models_20260919/med/sft_sftclean_adapter}
export DATA_S3=${DATA_S3:-$S3/sft/dpo_pairs_validated.jsonl}
if ! aws s3 ls "$SFT_ADAPTER_S3/adapter_config.json" >/dev/null 2>&1; then
  echo "REFUSING TO LAUNCH: start-policy adapter not found at $SFT_ADAPTER_S3 — run the clean SFT first."; exit 2; fi
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.2xlarge g5.2xlarge g6e.xlarge g5.4xlarge)
RESULT="$S3/models_20260919/med/dpo${TAG}_adapter/adapter_config.json"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 8*3600 ))
for attempt in $(seq 1 12); do
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (spot-only policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "DPO_9B${TAG} attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== dpo${TAG}_adapter READY ==="; echo "INSTANCE=$IID"; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunch to resume from S3 ckpt">&2; break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
