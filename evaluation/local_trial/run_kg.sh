#!/bin/bash
# Build the verbalized FULL-KG corpus (PrimeKG + MAP-KG) on a box, upload to S3, poll for completion.
# stdlib-only (noop bootstrap); spot first, on-demand fallback after 2 dry cycles (short one-time build).
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
RESULT="$S3/midtrain_corpus/kg_corpus.jsonl"
export MODEL_SIZE=small STAGE=kgbuild TAG=_kg ENTRY=build_kg.sh BOOTSTRAP=noop_bootstrap.sh
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.4xlarge g5.4xlarge g6.2xlarge g5.2xlarge g6.8xlarge)
aws s3 rm "$RESULT" --quiet 2>/dev/null

launch() {
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
  for i in $(seq 1 100); do
    if aws s3 ls "$RESULT" >/dev/null 2>&1; then echo "=== KG CORPUS READY ==="; aws s3 ls "$RESULT" --human-readable; exit 0; fi
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then echo "box $IID died (state=$ST) — relaunch"; break; fi
    sleep 30
  done
done
echo "TIMEOUT/EXHAUSTED"; exit 4
