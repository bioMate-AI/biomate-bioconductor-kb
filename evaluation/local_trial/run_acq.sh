#!/bin/bash
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
ACQ_RESULT="${ACQ_RESULT:-${ACQ_RESULT_KEY##*/}}"   # keep bound under set -u when only ACQ_RESULT_KEY is given
export MODEL_SIZE=small STAGE=${ACQ_STAGE:-acq} TAG=${ACQ_TAG:-_acq} ENTRY=$ACQ_ENTRY BOOTSTRAP=noop_bootstrap.sh PMC_MAXTOK=${PMC_MAXTOK:-}
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(c5.2xlarge c5.4xlarge m5.2xlarge g6.2xlarge)
# ACQ_RESULT_KEY = full key under the S3 root (for results outside midtrain_corpus/, e.g. sft/)
RESULT="${ACQ_RESULT_KEY:+$S3/$ACQ_RESULT_KEY}"; RESULT="${RESULT:-$S3/midtrain_corpus/$ACQ_RESULT}"; aws s3 rm "$RESULT" --quiet 2>/dev/null
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2; do IID=$(launch 0) && break; sleep 60; done; [ -z "$IID" ] && IID=$(launch 1); [ -z "$IID" ] && { echo GAVEUP; exit 3; }
for i in $(seq 1 200); do aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== $ACQ_RESULT READY ==="; aws s3 ls "$RESULT" --human-readable; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "died $ST"; exit 4; }; sleep 45; done
echo TIMEOUT; exit 4
