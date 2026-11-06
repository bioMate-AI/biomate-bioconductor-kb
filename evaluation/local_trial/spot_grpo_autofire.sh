#!/bin/bash
# Capacity-gated auto-fire for STAGE-2 GRPO (decomposition RLVR, gold-free structural reward).
# Unattended: polls get-spot-placement-scores across us-east-1 + us-west-2 every POLL seconds and
# fires exactly ONE spot instance the moment an AZ we hold a subnet for clears the >=6 gate.
#
# WHY THIS EXISTS: the GRPO build is fully reconciled against trl-1.14.1 (GRPOConfig, PeftModel, and
# the on-box scorer-staging fix 76eb764cc are all in the live tarball, uploaded 2026-10-19 14:11), but
# spot capacity receded below the >=6 gate (best AZ = 4 at 14:xx). Rather than babysit, this watcher
# fires the validated path the instant capacity returns.
#
# HARD RULES honoured:
#   - SPOT ONLY. Never sets ONDEMAND=1. spot_launch.sh defaults to a one-time spot request.
#   - >=6 gate. Fires only when an AZ's placement score >= GATE (default 6).
#   - Review-before-spend already done (all 4 reward inputs + sft_gold start policy verified present;
#     decomp_reward --selftest CPU-validated end-to-end). Bounded spend: 1 g6e.xlarge spot, self-
#     terminating, MAX_STEPS cap ~2-4h, ~$2-5.
#   - Idempotent: exits without firing if the final adapter already exists, or a prior fire is recorded.
#
# Outcome expectation (honest, from docs/20261019_ONPREM_LLM_V3_SFT_MEASURED_AND_GRPO_READY.md §3c):
#   LOW-EV. Deliverable = the RLVR pipeline runs end-to-end; decomposition_real score expected NEAR-FLOOR
#   (base/v3 ~ 0.016/0.087). A near-floor adapter is the likely, honest result.
#
#   bash spot_grpo_autofire.sh            # foreground (or nohup ... & for unattended)
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
GATE=${GATE:-6}
POLL=${POLL:-300}
DEADLINE_HOURS=${DEADLINE_HOURS:-24}
TYPES=(g6e.xlarge g6.2xlarge g5.2xlarge g5.4xlarge)
RESULT="$S3/models_20260919/med/grpo_grpo_decomp_adapter/adapter_config.json"
STATE=/tmp/spot_grpo_autofire.fired
LOG=${LOG:-/tmp/spot_grpo_autofire.log}
exec > >(tee -a "$LOG") 2>&1

# AZ-id -> "region subnet ami sg" for the AZs we actually hold a subnet in.
azrow() { case "$1" in
  use1-az4) echo "us-east-1 subnet-056f0aba4ab4f7ec2 ami-07ab2d4b1490816c3 sg-09a2408a8b8ca874b" ;;
  usw2-az3) echo "us-west-2 subnet-0254e4c3634b41bfc ami-04f7da1c787a89267 sg-0de9af2d4437a8c90" ;;
  usw2-az1) echo "us-west-2 subnet-03b277a7a08d388c1 ami-04f7da1c787a89267 sg-0de9af2d4437a8c90" ;;
  usw2-az4) echo "us-west-2 subnet-0b35a6e2c1cf02dc2 ami-04f7da1c787a89267 sg-0de9af2d4437a8c90" ;;
  usw2-az2) echo "us-west-2 subnet-09e4dce46682a6c60 ami-04f7da1c787a89267 sg-0de9af2d4437a8c90" ;;
  *) return 1 ;;
esac }

scores() { # region -> "azId score" lines, only AZs we hold a subnet in
  aws ec2 get-spot-placement-scores --region "$1" \
    --instance-types "${TYPES[@]}" --target-capacity 1 --single-availability-zone \
    --region-names "$1" --query 'SpotPlacementScores[].[AvailabilityZoneId,Score]' \
    --output text 2>/dev/null | while read -r az sc; do azrow "$az" >/dev/null 2>&1 && echo "$az $sc"; done
}

fire() { # azId -> launch one spot instance via the validated path
  local az="$1"; read -r REGION SUBNET AMI SG <<<"$(azrow "$az")"
  echo "[$(date -u +%FT%TZ)] FIRING GRPO on $REGION/$az subnet=$SUBNET ami=$AMI sg=$SG (score>=$GATE)"
  OPENAI_API_KEY=${OPENAI_API_KEY:-unused} \
  REGION="$REGION" AMI="$AMI" SUBNET="$SUBNET" SG="$SG" INSTANCE_TYPE=g6e.xlarge \
  MODEL_SIZE=med STAGE=grpo ENTRY=spot_grpo_decomp_entry.sh BOOTSTRAP=today_bootstrap.sh \
  TAG=_grpo_decomp FORCE_NGPU=1 \
  REPO_TARBALL_S3="$S3/code/evaluation_local_trial_grpo_decomp.tgz" \
  MAX_STEPS=400 SAVE_STEPS=25 NUMGEN=8 BETA=0.04 TEMP=0.9 LR=1e-6 BS=2 GA=8 \
  W_NODE=0.30 W_EDGE=0.40 W_STRUCT=0.30 EVAL_HOOK=0 \
  SFT_ADAPTER_S3="$S3/models_20260919/med/sft_gold_adapter" \
  DATA_S3="$S3/sft/decomp_depgraph.jsonl" \
  DB_S3="$S3/eval/harness_payload/galaxy_ai_tools.db" \
  bash spot_launch.sh
}

echo "[$(date -u +%FT%TZ)] autofire start: gate>=$GATE poll=${POLL}s deadline=${DEADLINE_HOURS}h"
# precondition: start policy must exist (same guard the launcher enforces)
aws s3 ls "$S3/models_20260919/med/sft_gold_adapter/adapter_config.json" >/dev/null 2>&1 \
  || { echo "ABORT: sft_gold start policy missing"; exit 2; }

END=$(( $(date +%s) + DEADLINE_HOURS*3600 ))
while :; do
  if aws s3 ls "$RESULT" >/dev/null 2>&1; then echo "[$(date -u +%FT%TZ)] adapter already present — nothing to do"; exit 0; fi
  if [ -f "$STATE" ]; then echo "[$(date -u +%FT%TZ)] prior fire recorded ($(cat "$STATE")) — exiting watcher"; exit 0; fi
  BEST_AZ=""; BEST=-1
  while read -r az sc; do [ -n "${sc:-}" ] && [ "$sc" -gt "$BEST" ] 2>/dev/null && { BEST=$sc; BEST_AZ=$az; }; done < <( { scores us-east-1; scores us-west-2; } )
  echo "[$(date -u +%FT%TZ)] best eligible AZ=$BEST_AZ score=$BEST (gate>=$GATE)"
  if [ -n "$BEST_AZ" ] && [ "$BEST" -ge "$GATE" ] 2>/dev/null; then
    OUT=$(fire "$BEST_AZ"); echo "$OUT"
    IID=$(echo "$OUT" | grep -oE "i-[0-9a-f]{8,}" | head -1)
    if [ -n "$IID" ]; then
      echo "$(date -u +%FT%TZ) $BEST_AZ $IID" > "$STATE"
      echo "[$(date -u +%FT%TZ)] FIRED $IID on $BEST_AZ — watcher done. Grade when adapter lands:"
      echo "  ADAPTER_TAG=_grpo_decomp bash evaluation/local_trial/run_eval_sftv3real.sh  # decomposition_real headline"
      exit 0
    fi
    echo "[$(date -u +%FT%TZ)] launch returned no instance id (spot refused) — will retry next poll"
  fi
  [ $(date +%s) -ge $END ] && { echo "[$(date -u +%FT%TZ)] DEADLINE reached, no capacity >=$GATE — exiting without firing"; exit 3; }
  sleep "$POLL"
done
