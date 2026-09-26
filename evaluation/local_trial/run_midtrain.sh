#!/bin/bash
# Resume-safe SPOT driver for the large-scale 4B mid-train -> merge -> SFT (STAGE=full, TAG=_mid2).
# Spot-always: long job, S3-checkpointed + resume-safe, so interruption is harmless. Relaunch across
# AZ/type on death or capacity; stop when the final adapter lands. Do NOT switch to on-demand.
set -uo pipefail
cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=small; STAGE=full; TAG=${TAG:-_litkg}   # literature + KG + structured + replay
DONE="$S3/models_20260919/$SIZE/${STAGE}${TAG}_adapter/adapter_model.safetensors"
# large-scale mid-train on the DOMAIN mix = PubMed literature (stride-sampled ~2B tok) + structured
# (x8 upweight) + 25% general replay. MID=5000 (~325M tok seen, ~4-5h) vs old 400=wash.
export MODEL_SIZE=$SIZE STAGE=$STAGE TAG=$TAG ENTRY=spot_train.sh \
  MID_OVERRIDE=${MID_OVERRIDE:-5000} SEQ_OVERRIDE=2048 R_OVERRIDE=16 \
  BS_OVERRIDE=8 GA_OVERRIDE=4 FORCE_NGPU=1 \
  MIX_LITERATURE=1 LIT_KEEP_EVERY=${LIT_KEEP_EVERY:-5} STRUCT_REPEAT=${STRUCT_REPEAT:-8} \
  MIX_KG=${MIX_KG:-1} KG_REPEAT=${KG_REPEAT:-3} \
  FETCH_REPLAY=1 REPLAY_FRAC=${REPLAY_FRAC:-0.25}
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6e.xlarge g6e.2xlarge g6e.4xlarge g6e.12xlarge)   # all 48GB L40S (12xl=4x, FORCE_NGPU=1 uses one)

launch() {  # echoes instance-id on success
  for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
    OUT=$(INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1)
    IID=$(echo "$OUT" | grep -oE "i-[0-9a-f]{8,}" | head -1)
    [ -n "$IID" ] && { echo "LAUNCHED $T @ $S -> $IID" >&2; echo "$IID"; return 0; }
  done; done
  return 1
}

while true; do
  aws s3 ls "$DONE" >/dev/null 2>&1 && { echo "TRAINING DONE: full${TAG} adapter staged"; exit 0; }
  IID=""; for c in $(seq 1 8); do IID=$(launch) && break; echo "no spot capacity (cycle $c), wait 90s" >&2; sleep 90; done
  [ -z "$IID" ] && { echo "no spot capacity after 8 cycles; wait 300s, retry (spot-always)"; sleep 300; continue; }
  # babysit this box until the adapter lands (DONE) or the box dies (spot reclaim/crash) -> relaunch resumes from S3 ckpt
  while true; do
    aws s3 ls "$DONE" >/dev/null 2>&1 && { echo "TRAINING DONE (box $IID)"; exit 0; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    if [ "$ST" != running ] && [ "$ST" != pending ]; then
      echo "box $IID state=$ST — relaunching (resume from S3 checkpoint)"; sleep 15; break
    fi
    sleep 60
  done
done
