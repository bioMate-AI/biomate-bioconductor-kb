#!/bin/bash
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=small STAGE=evaldpo TAG=_evaldpo ENTRY=build_eval_dpo.sh BOOTSTRAP=gpu_bootstrap.sh
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.2xlarge g5.2xlarge g6e.xlarge g5.xlarge)
RESULT="$S3/eval/eval_dpo_full.json"; aws s3 rm "$RESULT" --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2; do IID=$(launch 0) && break; sleep 60; done; [ -z "$IID" ] && IID=$(launch 1); [ -z "$IID" ] && { echo GAVEUP; exit 3; }
echo "EVALVLLM instance=$IID"
for i in $(seq 1 120); do aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== EVAL DPO ==="; aws s3 cp "$RESULT" -; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "died $ST"; exit 4; }; sleep 45; done
echo TIMEOUT; exit 4
