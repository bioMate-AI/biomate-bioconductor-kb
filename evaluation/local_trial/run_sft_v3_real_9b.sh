#!/bin/bash
# Launch the SFT-V3-REAL retrain of the on-prem 9B: QLoRA SFT (r16/a32) on the clean base
# Qwen/Qwen3.5-9B @ c202236..., SFT_DATA = v2 mix + 219 REAL decomp rows + 854 param must_not_fill
# anchors folded in (sft_from_gold_v3_real_20261007.jsonl, 22,361 rows). EXACT prior recipe
# (spot_sft_gold_entry.sh -> spot_train.sh STAGE=sft -> train_qlora_pilot.py, assistant_only_loss).
# STOP EARLY at 550 steps (the plateau: gains realized ~550, must_not_fill penalty grows after).
# SAVE_STEPS=25 keeps intermediate checkpoints evaluable + S3-mirrored. TAG=_sftv3real so neither
# the prior sft_gold nor the sft_decompv2 adapter is touched. SPOT only, cycle AZ/type, resume-safe,
# the box self-terminates. Bounded worker (WORKER_MAX_SECONDS). Reuses today_bootstrap.sh (pinned venv).
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}   # spot_launch userdata expands it under set -u
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_sftv3real.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_sft_gold_entry.sh BOOTSTRAP=today_bootstrap.sh
export TAG=${TAG:-_sftv3real} SFT_DATA=${SFT_DATA:-sft_from_gold_v3_real_20261007.jsonl}
export SFT_OVERRIDE=${SFT_OVERRIDE:-550} SEQ_OVERRIDE=2048 BS_OVERRIDE=1 GA_OVERRIDE=16 FORCE_NGPU=1
export WORKER_MAX_SECONDS=${WORKER_MAX_SECONDS:-16200}   # 4.5h hard cap per box (550 steps ~2.6h + dl/boot)
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
# 9B QLoRA 4-bit fits any single 24GB+ GPU; broad pool maximizes spot availability in a crunch
TYPES=(g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6.4xlarge g5.4xlarge g6e.xlarge g6.8xlarge g5.8xlarge g6e.2xlarge)
RESULT="$S3/models_20260919/med/sft${TAG}_adapter/adapter_config.json"
LOG="$S3/spot_logs/med/sft${TAG}/boot.log"
REGION=us-west-2
term(){ [ -n "${1:-}" ] && aws ec2 terminate-instances --region $REGION --instance-ids "$1" >/dev/null 2>&1 && echo "terminated $1">&2; }
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+ondemand}${1:-spot}-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 6*3600 ))
BOOT_GRACE=${BOOT_GRACE:-420}   # fast-fail: boot.log on S3 within 7 min or kill+retry different AZ/type
for attempt in $(seq 1 12); do
  [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE"; exit 4; }
  IID=""; for c in $(seq 1 8); do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (spot-only policy)"; sleep 120; continue; }
  echo "SFT_9B${TAG} attempt=$attempt instance=$IID (boot grace ${BOOT_GRACE}s)"
  t0=$(date +%s); booted=0
  while :; do
    now=$(date +%s)
    aws s3 ls "$RESULT" >/dev/null 2>&1 && { echo "=== sft${TAG}_adapter READY ==="; echo "INSTANCE=$IID"; exit 0; }
    [ $now -ge $DEADLINE ] && { echo "DEADLINE"; term "$IID"; exit 4; }
    # fast-fail: no boot.log on S3 within grace -> dead box, terminate + retry a different AZ/type
    if [ "$booted" = 0 ]; then
      aws s3 ls "$LOG" >/dev/null 2>&1 && booted=1
      if [ "$booted" = 0 ] && [ $((now - t0)) -ge $BOOT_GRACE ]; then
        echo "FAST-FAIL: no boot.log in ${BOOT_GRACE}s — terminate + retry">&2; term "$IID"; break; fi
    fi
    ST=$(aws ec2 describe-instances --region $REGION --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed/ended ($ST) — relaunch resumes from S3 ckpt">&2; break; }
    sleep 45
  done
done
echo "EXHAUSTED relaunches"; exit 4
