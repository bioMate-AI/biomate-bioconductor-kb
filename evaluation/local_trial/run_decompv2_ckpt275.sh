#!/bin/bash
# Driver for the ckpt-275 gap-closer eval. ONE fresh spot box, ckpt-275 only, decomposition_v2
# greedy + verifier re-ranker, incremental upload. FAST-FAIL: boot.log within BOOT_GRACE or
# terminate+retry a different AZ/type; stall>STALL_MAX -> terminate; hard WORKER_MAX_SECONDS cap;
# self-terminate on completion (no leak).
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
REGION=us-west-2
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_decompv2.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_decompv2_ckpt275_entry.sh BOOTSTRAP=spot_harness_bootstrap.sh
export TAG=${TAG:-_decompv2cl} FORCE_NGPU=1
export WORKER_MAX_SECONDS=${WORKER_MAX_SECONDS:-5400}   # 90 min hard cap (well above the ~35-45 min need)
BOOT_GRACE=${BOOT_GRACE:-420}; STALL_MAX=${STALL_MAX:-1500}
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6.4xlarge g5.4xlarge g6e.xlarge g6.8xlarge g5.8xlarge g6e.2xlarge)
BOOT="$S3/spot_logs/med/sft${TAG}/boot.log"

term(){ [ -n "${1:-}" ] && aws ec2 terminate-instances --region $REGION --instance-ids "$1" >/dev/null 2>&1 && echo "terminated $1">&2; }
done_marker(){ aws s3 cp "$BOOT" - 2>/dev/null | grep -q "DECOMPV2_CKPT275_DONE"; }
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=0 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }

aws s3 rm "$BOOT" --quiet 2>/dev/null || true
DEADLINE=$(( $(date +%s) + 3*3600 ))
for attempt in $(seq 1 10); do
  [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE — stop (spot/boot failures)"; exit 4; }
  IID=""; for c in $(seq 1 6); do IID=$(launch) && break; sleep 60; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE across all AZ/type"; sleep 120; continue; }
  echo "CKPT275-EVAL attempt=$attempt instance=$IID (boot ${BOOT_GRACE}s stall ${STALL_MAX}s cap ${WORKER_MAX_SECONDS}s)"
  t0=$(date +%s); lastsize=-1; lastgrow=$(date +%s); booted=0
  while :; do
    now=$(date +%s)
    done_marker && { echo "=== CKPT275 EVAL DONE ==="; aws s3 cp "$BOOT" - 2>/dev/null | grep "out=" | tail -1; echo "INSTANCE=$IID"; exit 0; }
    size=$(aws s3 ls "$BOOT" 2>/dev/null | awk '{print $3}' | tail -1)
    if [ -n "$size" ]; then booted=1; [ "$size" != "$lastsize" ] && { lastsize="$size"; lastgrow=$now; }; fi
    if [ "$booted" = 0 ] && [ $((now-t0)) -ge $BOOT_GRACE ]; then echo "FAST-FAIL: no boot.log in ${BOOT_GRACE}s">&2; term "$IID"; break; fi
    if [ "$booted" = 1 ] && [ $((now-lastgrow)) -ge $STALL_MAX ]; then echo "STALL: boot.log static ${STALL_MAX}s">&2; term "$IID"; break; fi
    ST=$(aws ec2 describe-instances --region $REGION --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then
      done_marker && { echo "=== CKPT275 EVAL DONE (post-terminate) ==="; echo "INSTANCE=$IID"; exit 0; }
      echo "instance ended ($ST) no DONE — retry">&2; break; fi
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE mid-attempt"; term "$IID"; exit 4; }
    sleep 30
  done
done
echo "EXHAUSTED relaunches"; exit 4
