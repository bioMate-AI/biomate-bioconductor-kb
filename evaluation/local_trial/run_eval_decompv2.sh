#!/bin/bash
# Launch the DECOMP-V2 eval box: base vs base+decomp-v2-SFT(ckpt-275) over the RealBio regression
# guard (routing/param/litqa2/findings + old coarse task_decomposition) AND the honest held-out
# decomposition_v2 benchmark (node/edge-F1 per-class) AND the no-train verifier re-ranker on REAL
# sampled candidates (SFT arm). One box, both arms. SPOT only, self-terminate.
#
# FAST-FAIL GUARD (a prior box hung 86 min with no S3 output): the box MUST write boot.log to S3
# within BOOT_GRACE; if not -> terminate + retry a different AZ/type. If boot.log stops growing for
# STALL_MAX -> terminate + retry. Hard cap via WORKER_MAX_SECONDS. Never let a box sit silent.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
REGION=us-west-2
export OPENAI_API_KEY=${OPENAI_API_KEY:-unused}
export REPO_TARBALL_S3="$S3/code/evaluation_local_trial_decompv2.tgz"
export MODEL_SIZE=med STAGE=sft ENTRY=spot_harness_decompv2_entry.sh BOOTSTRAP=spot_harness_bootstrap.sh
export TAG=${TAG:-_decompv2eval} FORCE_NGPU=1
export WORKER_MAX_SECONDS=${WORKER_MAX_SECONDS:-7200}   # hard 2h cap on the whole eval worker
BOOT_GRACE=${BOOT_GRACE:-420}      # 7 min to first boot.log
STALL_MAX=${STALL_MAX:-1200}       # 20 min with no boot.log growth -> dead
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6.xlarge g5.xlarge g6.2xlarge g5.2xlarge g6.4xlarge g5.4xlarge g6e.xlarge g6.8xlarge g5.8xlarge g6e.2xlarge)
BOOT="$S3/spot_logs/med/sft${TAG}/boot.log"

echo "=== stage ckpt-275 adapter -> eval_staging/sft_decompv2 (adapter + tokenizer only) ==="
for f in adapter_config.json adapter_model.safetensors chat_template.jinja tokenizer.json tokenizer_config.json; do
  aws s3 cp "$S3/spot_ckpt/med/sft_decompv2/checkpoint-275/$f" "$S3/eval_staging/sft_decompv2/$f" --quiet \
    && echo "  staged $f" || echo "  MISSING $f"
done

term(){ [ -n "${1:-}" ] && aws ec2 terminate-instances --region $REGION --instance-ids "$1" >/dev/null 2>&1 && echo "terminated $1">&2; }
done_marker(){ aws s3 cp "$BOOT" - 2>/dev/null | grep -q "SPOT_HARNESS_DECOMPV2_EVAL_DONE"; }

launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=0 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED spot-$T/$S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }

DEADLINE=$(( $(date +%s) + 4*3600 ))
# fresh boot.log slate so we don't read a stale DONE/old content as this run's
aws s3 rm "$BOOT" --quiet 2>/dev/null || true
for attempt in $(seq 1 10); do
  [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE — stop (spot capacity/boot failures)"; exit 4; }
  IID=""; for c in $(seq 1 6); do IID=$(launch) && break; sleep 60; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE across all AZ/type (spot-only policy)"; sleep 120; continue; }
  echo "EVAL attempt=$attempt instance=$IID (boot grace ${BOOT_GRACE}s, stall ${STALL_MAX}s, cap ${WORKER_MAX_SECONDS}s)"
  t0=$(date +%s); lastsize=-1; lastgrow=$(date +%s); booted=0
  while :; do
    now=$(date +%s)
    done_marker && { echo "=== EVAL DONE ==="; aws s3 cp "$BOOT" - 2>/dev/null | grep "out=" | tail -1; echo "INSTANCE=$IID"; exit 0; }
    size=$(aws s3 ls "$BOOT" 2>/dev/null | awk '{print $3}' | tail -1)
    if [ -n "$size" ]; then
      booted=1
      if [ "$size" != "$lastsize" ]; then lastsize="$size"; lastgrow=$now; fi
    fi
    # fast-fail: no boot.log at all within grace
    if [ "$booted" = 0 ] && [ $((now - t0)) -ge $BOOT_GRACE ]; then
      echo "FAST-FAIL: no boot.log in ${BOOT_GRACE}s — terminate + retry different AZ/type">&2; term "$IID"; break; fi
    # stall: boot.log stopped growing for too long (and not done)
    if [ "$booted" = 1 ] && [ $((now - lastgrow)) -ge $STALL_MAX ]; then
      echo "STALL: boot.log static ${STALL_MAX}s — terminate + retry">&2; term "$IID"; break; fi
    # instance ended on its own: success iff DONE marker present (self-terminate after eval)
    ST=$(aws ec2 describe-instances --region $REGION --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then
      done_marker && { echo "=== EVAL DONE (post-terminate) ==="; echo "INSTANCE=$IID"; exit 0; }
      echo "instance ended ($ST) with no DONE marker — retry">&2; break; fi
    [ $(date +%s) -ge $DEADLINE ] && { echo "DEADLINE mid-attempt — terminate + stop"; term "$IID"; exit 4; }
    sleep 30
  done
done
echo "EXHAUSTED eval relaunches"; exit 4
