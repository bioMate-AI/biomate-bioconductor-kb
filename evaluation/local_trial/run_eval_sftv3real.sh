#!/bin/bash
# Launch the SFT-V3-REAL eval box: base vs base+sftv3real-SFT over:
#   (A) decomposition_real (HEADLINE, out-of-generator)  (B) decomposition_v2 (comparison)
#   (C) regression guard: param_prefill (must_not_fill!), cross_domain_routing, litqa2, findings,
#       task_decomposition (old coarse). One box, both arms, greedy. Each score uploaded as it computes.
# SPOT only, self-terminate, bounded (WORKER_MAX_SECONDS). FAST-FAIL: boot.log on S3 within BOOT_GRACE
# or terminate+retry a different AZ/type; boot.log static STALL_MAX -> terminate+retry.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
REGION=us-west-2
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_sftv3real.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_harness_sftv3real_entry.sh BOOTSTRAP=spot_harness_bootstrap.sh
export TAG=${TAG:-_sftv3realeval} FORCE_NGPU=1
export WORKER_MAX_SECONDS=${WORKER_MAX_SECONDS:-10800}   # 3h hard cap (incremental upload makes a cap non-fatal)
BOOT_GRACE=${BOOT_GRACE:-420}
STALL_MAX=${STALL_MAX:-1200}
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6.4xlarge g5.4xlarge g6e.xlarge g6.8xlarge g5.8xlarge g6e.2xlarge)
BOOT="$S3/spot_logs/med/sft${TAG}/boot.log"

# Stage the v3 adapter (LoRA files only; the shim uses the BASE tokenizer). Prefer the final 550-step
# adapter; fall back to the latest intermediate checkpoint if the final upload didn't land.
echo "=== stage sftv3real adapter -> eval_staging/sft_sftv3real ==="
SRC="$S3/models_20260919/med/sft_sftv3real_adapter"
if ! aws s3 ls "$SRC/adapter_config.json" >/dev/null 2>&1; then
  CK=$(aws s3 ls "$S3/spot_ckpt/med/sft_sftv3real/" | grep -oE "checkpoint-[0-9]+" | sort -t- -k2 -n | tail -1)
  [ -n "$CK" ] && SRC="$S3/spot_ckpt/med/sft_sftv3real/$CK" && echo "  final adapter absent -> using $CK"
fi
echo "  SRC=$SRC"
for f in adapter_config.json adapter_model.safetensors; do
  aws s3 cp "$SRC/$f" "$S3/eval_staging/sft_sftv3real/$f" --quiet && echo "  staged $f" || { echo "  MISSING $f — ABORT (no adapter to eval)"; exit 2; }
done

term(){ [ -n "${1:-}" ] && aws ec2 terminate-instances --region $REGION --instance-ids "$1" >/dev/null 2>&1 && echo "terminated $1">&2; }
done_marker(){ aws s3 cp "$BOOT" - 2>/dev/null | grep -q "SPOT_HARNESS_SFTV3REAL_EVAL_DONE"; }

launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=0 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }

DEADLINE=$(( $(date +%s) + 4*3600 ))
aws s3 rm "$BOOT" --quiet 2>/dev/null || true   # fresh slate so we don't read a stale DONE
for attempt in $(seq 1 10); do
  [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE — stop"; exit 4; }
  IID=""; for c in $(seq 1 6); do IID=$(launch) && break; sleep 60; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE across all AZ/type"; sleep 120; continue; }
  echo "EVAL attempt=$attempt instance=$IID (boot ${BOOT_GRACE}s, stall ${STALL_MAX}s, cap ${WORKER_MAX_SECONDS}s)"
  t0=$(date +%s); lastsize=-1; lastgrow=$(date +%s); booted=0
  while :; do
    now=$(date +%s)
    done_marker && { echo "=== EVAL DONE ==="; aws s3 cp "$BOOT" - 2>/dev/null | grep "out=" | tail -1; echo "INSTANCE=$IID"; exit 0; }
    size=$(aws s3 ls "$BOOT" 2>/dev/null | awk '{print $3}' | tail -1)
    if [ -n "$size" ]; then booted=1; [ "$size" != "$lastsize" ] && { lastsize="$size"; lastgrow=$now; }; fi
    if [ "$booted" = 0 ] && [ $((now - t0)) -ge $BOOT_GRACE ]; then
      echo "FAST-FAIL: no boot.log in ${BOOT_GRACE}s — terminate + retry">&2; term "$IID"; break; fi
    if [ "$booted" = 1 ] && [ $((now - lastgrow)) -ge $STALL_MAX ]; then
      echo "STALL: boot.log static ${STALL_MAX}s — terminate + retry">&2; term "$IID"; break; fi
    ST=$(aws ec2 describe-instances --region $REGION --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then
      done_marker && { echo "=== EVAL DONE (post-terminate) ==="; echo "INSTANCE=$IID"; exit 0; }
      echo "instance ended ($ST) with no DONE marker — retry">&2; break; fi
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE mid-attempt — terminate"; term "$IID"; exit 4; }
    sleep 30
  done
done
echo "EXHAUSTED eval relaunches"; exit 4
