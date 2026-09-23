#!/bin/bash
# Self-healing scorecard runner: cycle spot instance-type x AZ until a box launches, poll for the
# result, and RELAUNCH if the box dies (spot reclaim / crash-poweroff) before staging it.
# Any 24GB+ GPU runs the 4B eval. Usage: TAG=_v3 bash run_scorecard.sh
set -uo pipefail
cd "$(dirname "$0")"
TAG=${TAG:-_v3}; SIZE=${MODEL_SIZE:-small}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
RESULT="$S3/eval/scorecard_${SIZE}${TAG}.json"
export MODEL_SIZE=$SIZE STAGE=sft TAG=$TAG ENTRY=spot_eval_corpus.sh
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)  # 2a 2b 2d 2c
# widened pool: any 24GB+ GPU runs the 4B eval — more types = better spot capacity odds
TYPES=(g6e.xlarge g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6e.2xlarge g6.4xlarge g5.4xlarge)
aws s3 rm "$RESULT" --quiet 2>/dev/null   # never read a stale scorecard

launch() {  # $1=ONDEMAND(0/1); echoes instance-id on success
  for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
    OUT=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1)
    IID=$(echo "$OUT" | grep -oE "i-[0-9a-f]{8,}" | head -1)
    [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID" >&2; echo "$IID"; return 0; }
  done; done
  return 1
}

for attempt in 1 2 3 4 5; do
  IID=""
  # 2 spot cycles first (spot-always discipline); then on-demand fallback for this short eval
  for c in 1 2; do IID=$(launch 0) && break; echo "no spot capacity anywhere (cycle $c), wait 60s" >&2; sleep 60; done
  if [ -z "$IID" ]; then echo "spot dry after 2 cycles -> ON-DEMAND fallback (short ~15min eval)" >&2; IID=$(launch 1); fi
  [ -z "$IID" ] && { echo "GAVE UP: no capacity (spot or on-demand)"; exit 3; }
  # poll ~40 min for result; bail early to relaunch if the box dies first
  for i in $(seq 1 80); do
    if aws s3 ls "$RESULT" >/dev/null 2>&1; then
      echo "=== SCORECARD $TAG READY (attempt $attempt) ==="; aws s3 cp "$RESULT" - 2>/dev/null; exit 0
    fi
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then
      echo "box $IID died (state=$ST) before result — relaunching (attempt $((attempt+1)))"; break
    fi
    sleep 30
  done
done
echo "TIMEOUT/EXHAUSTED after 5 attempts"; exit 4
