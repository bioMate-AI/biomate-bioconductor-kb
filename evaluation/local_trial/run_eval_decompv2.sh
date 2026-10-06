#!/bin/bash
# Launch the DECOMP-V2 eval box: base vs base+decomp-v2-SFT over the RealBio regression guard
# (routing/param_prefill/litqa2/findings_probe + old task_decomposition) AND the honest held-out
# decomposition_v2 benchmark (node/edge-F1 + per-class). One box runs BOTH arms. SPOT only,
# cycle AZ/type, self-terminate. Reuses spot_harness_decompv2_entry.sh + spot_harness_bootstrap.sh.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_decompv2.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_harness_decompv2_entry.sh BOOTSTRAP=spot_harness_bootstrap.sh
export TAG=${TAG:-_decompv2eval} FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.2xlarge g5.2xlarge g6e.xlarge g5.4xlarge)   # 9B bf16 inference: 24GB+
LOGP="$S3/spot_logs/med/sft${TAG}"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 5*3600 ))
for attempt in $(seq 1 12); do
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (spot-only policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 120; continue; }
  echo "EVAL_DECOMPV2 attempt=$attempt instance=$IID"
  while :; do
    # eval done marker: boot.log contains the entry's completion line
    aws s3 cp "$LOGP/boot.log" - 2>/dev/null | grep -q "SPOT_HARNESS_DECOMPV2_EVAL_DONE" && { echo "=== EVAL DONE ==="; echo "INSTANCE=$IID"; aws s3 cp "$LOGP/boot.log" - 2>/dev/null | grep "out=" | tail -1; exit 0; }
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt ended ($ST) — checking for DONE marker then relaunch">&2;
       aws s3 cp "$LOGP/boot.log" - 2>/dev/null | grep -q "SPOT_HARNESS_DECOMPV2_EVAL_DONE" && { echo "=== EVAL DONE (post-terminate) ==="; exit 0; }
       break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
