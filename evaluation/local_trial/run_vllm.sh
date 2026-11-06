#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
RESULT="$S3/eval/objective_vllm_base_vs_sft.json"
export MODEL_SIZE=small STAGE=vllmobj TAG=_vllm ENTRY=eval_vllm.sh BOOTSTRAP=gpu_bootstrap.sh
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6e.xlarge g5.4xlarge g6.4xlarge g5.2xlarge g6.2xlarge)
aws s3 rm "$RESULT" --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  OUT=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$OUT"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2 3; do IID=$(launch 0) && break; sleep 90; done; [ -z "$IID" ] && IID=$(launch 1)
[ -z "$IID" ] && { echo GAVEUP; exit 3; }
for i in $(seq 1 90); do aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== VLLM OBJ (base vs sft) ==="; aws s3 cp "$RESULT" -; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "died $ST"; exit 4; }; sleep 30; done
echo TIMEOUT; exit 4
