#!/bin/bash
# Build the ENTIRE PubMed literature corpus on a many-vCPU box, upload to S3, poll for completion.
# Uses the proven DL AMI on GPU types first (guaranteed boot), then CPU types; spot first, on-demand
# fallback after 2 dry cycles (short one-time build blocking the mid-train).
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
RESULT="$S3/midtrain_corpus/literature_corpus.jsonl"
export MODEL_SIZE=small STAGE=litbuild TAG=_lit ENTRY=build_literature.sh BOOTSTRAP=noop_bootstrap.sh
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.8xlarge g6.4xlarge g5.8xlarge g5.4xlarge g6.12xlarge)   # many-vCPU, proven DL AMI boot
aws s3 rm "$RESULT" --quiet 2>/dev/null   # fresh build

launch() {  # $1=ONDEMAND; echoes iid
  for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
    OUT=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1)
    IID=$(echo "$OUT" | grep -oE "i-[0-9a-f]{8,}" | head -1)
    [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID" >&2; echo "$IID"; return 0; }
  done; done; return 1
}

for attempt in 1 2 3 4; do
  IID=""
  for c in 1 2; do IID=$(launch 0) && break; echo "no spot capacity (cycle $c), wait 90s" >&2; sleep 90; done
  [ -z "$IID" ] && { echo "spot dry -> ON-DEMAND fallback" >&2; IID=$(launch 1); }
  [ -z "$IID" ] && { echo "GAVE UP: no capacity"; exit 3; }
  for i in $(seq 1 120); do   # ~60 min
    if aws s3 ls "$RESULT" >/dev/null 2>&1; then
      echo "=== LITERATURE CORPUS READY ==="; aws s3 ls "$RESULT" --human-readable; exit 0
    fi
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then echo "box $IID died (state=$ST) before result — relaunch"; break; fi
    sleep 30
  done
done
echo "TIMEOUT/EXHAUSTED"; exit 4
