#!/bin/bash
# SFT v6 (v5 + clean-recipe enrichment) on the base -> sft_v6_adapter. Then eval vs sft_v5 on generative tasks.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=small STAGE=sft TAG=_v6 ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export SFT_DATA=multitask_sft_v6.jsonl SFT_OVERRIDE=1000 SEQ_OVERRIDE=2048 BS_OVERRIDE=2 GA_OVERRIDE=16 FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g5.2xlarge g6e.xlarge g6.2xlarge g5.4xlarge)
RESULT="$S3/models_20260919/small/sft_v6_adapter/adapter_config.json"; aws s3 rm "${RESULT%/*}/" --recursive --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2; do IID=$(launch 0) && break; sleep 60; done; [ -z "$IID" ] && IID=$(launch 1); [ -z "$IID" ] && { echo GAVEUP; exit 3; }
echo "SFT_V6 instance=$IID"
for i in $(seq 1 160); do aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== sft_v6_adapter READY ==="; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "died $ST"; exit 4; }; sleep 45; done
echo TIMEOUT; exit 4
