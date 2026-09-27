#!/bin/bash
# Resume-safe SPOT driver for ONE SFT version (STAGE=sft) on the v4 corpus. Relaunch across AZ/type;
# on-demand fallback after 2 dry spot cycles (short ~30min run).
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=small; TAG=${TAG:-_v4}
DONE="$S3/models_20260919/$SIZE/sft${TAG}_adapter/adapter_model.safetensors"
export MODEL_SIZE=$SIZE STAGE=sft TAG=$TAG ENTRY=spot_train.sh \
  SEQ_OVERRIDE=2048 R_OVERRIDE=16 BS_OVERRIDE=8 GA_OVERRIDE=4 FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6e.xlarge g6e.2xlarge g6.4xlarge g5.4xlarge)
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  OUT=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1)
  IID=$(echo "$OUT"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
for attempt in 1 2 3 4; do
  aws s3 ls "$DONE" >/dev/null 2>&1 && { echo "SFT$TAG DONE"; exit 0; }
  IID=""; for c in 1 2; do IID=$(launch 0) && break; echo "no spot (cyc $c) wait 90s">&2; sleep 90; done
  [ -z "$IID" ] && { echo "spot dry -> on-demand">&2; IID=$(launch 1); }
  [ -z "$IID" ] && { echo "GAVE UP"; exit 3; }
  while true; do
    aws s3 ls "$DONE" >/dev/null 2>&1 && { echo "SFT$TAG DONE (box $IID)"; exit 0; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "box died ($ST) — relaunch"; sleep 15; break; }
    sleep 60
  done
done; echo "EXHAUSTED"; exit 4
