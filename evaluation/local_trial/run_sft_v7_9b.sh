#!/bin/bash
# SFT v6 (v5 + clean-recipe enrichment) on the base -> sft_v7_adapter. Then eval vs sft_v5 on generative tasks.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=med STAGE=sft ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export TAG=${TAG:-_v7} SFT_DATA=${SFT_DATA:-multitask_sft_v7.jsonl}
export SFT_OVERRIDE=1000 SEQ_OVERRIDE=2048 BS_OVERRIDE=1 GA_OVERRIDE=32 FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g5.2xlarge g6e.xlarge g6.2xlarge g5.4xlarge)
RESULT="$S3/models_20260919/med/sft${TAG}_adapter/adapter_config.json"; aws s3 rm "${RESULT%/*}/" --recursive --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { lbl=spot; [ "$1" = 1 ] && lbl=od; echo "LAUNCHED $lbl-$T -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
# spot-reclaim is NOT fatal: spot_train.sh mirrors ckpts to S3 and is resume-aware, so relaunch and let it resume.
DEADLINE=$(( $(date +%s) + 3*3600 ))   # overall 3h budget across relaunches
for attempt in $(seq 1 12); do
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (no on-demand, policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "SFT_9B${TAG} attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== sft_v7_adapter READY ==="; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunching to resume from S3 ckpt">&2; break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
