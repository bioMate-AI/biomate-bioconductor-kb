#!/bin/bash
# Launch the v8 arms eval (base vs sft_v5 vs sft_v8). SIZE=small|med. Spot-only, relaunch-on-reclaim.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=${SIZE:-small}
export MODEL_SIZE=$SIZE STAGE=evalv8 TAG=_evalv8 ENTRY=build_eval_vllm_v8.sh BOOTSTRAP=gpu_bootstrap.sh SIZE
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.2xlarge g5.2xlarge g6e.xlarge g5.4xlarge)
RESULT="$S3/eval/eval_v8_alltasks_$SIZE.json"; aws s3 rm "$RESULT" --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { lbl=spot; [ "$1" = 1 ] && lbl=od; echo "LAUNCHED $lbl-$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 2*3600 ))
for attempt in $(seq 1 10); do
  IID=""; for c in 1 2 3; do IID=$(launch 0) && break; sleep 60; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "EVALV8_$SIZE attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== EVAL v8 ($SIZE) ==="; aws s3 cp "$RESULT" -; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo DEADLINE; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunch">&2; break; }
    sleep 40
  done
done
echo EXHAUSTED; exit 4
