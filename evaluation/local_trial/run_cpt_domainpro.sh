#!/bin/bash
# Domain-pro CPT: STAGE=full = midtrain (CPT on the concept-dominant mix) -> merge -> SFT, on a
# Qwen3.5-9B base (med) by default. Pulls the prebuilt concept mix (midtrain_domain_concept.jsonl).
# Spot-only, relaunch-on-reclaim (resumes from S3 ckpts). SIZE=med (9B) | large (27B).
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SIZE=${SIZE:-med}
export MODEL_SIZE=$SIZE STAGE=full ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export TAG=${TAG:-_concept}
export MIX_LITERATURE=1                      # use the prebuilt concept mix (concepts-only; no KG/facts)
export FETCH_REPLAY=1 REPLAY_FRAC=${REPLAY_FRAC:-0.3}
export SEQ_OVERRIDE=2048 MID_OVERRIDE=${MID_OVERRIDE:-1500} SFT_OVERRIDE=${SFT_OVERRIDE:-1000}
export BS_OVERRIDE=${BS_OVERRIDE:-1} GA_OVERRIDE=${GA_OVERRIDE:-32} FORCE_NGPU=${FORCE_NGPU:-1}
export SFT_DATA=${SFT_DATA:-multitask_sft_enriched.jsonl}
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
# 9B fits 24GB (QLoRA); 27B needs 48GB (g6e/L40S). Prefer less-contended types first.
if [ "$SIZE" = large ]; then TYPES=(g6e.xlarge g5.12xlarge g5.4xlarge g6e.2xlarge); else TYPES=(g5.2xlarge g6e.xlarge g6.xlarge g5.xlarge g5.4xlarge g6.2xlarge g5.8xlarge); fi  # 24GB+ only (9B QLoRA; g4dn 16GB too small)
RESULT="$S3/models_20260919/$SIZE/base_domain${TAG}/config.json"   # CPT-merged model = the key artifact
FINAL="$S3/models_20260919/$SIZE/full${TAG}_adapter/adapter_config.json"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { lbl=spot; [ "$1" = 1 ] && lbl=od; echo "LAUNCHED $lbl-$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
DEADLINE=$(( $(date +%s) + 5*3600 ))   # full pipeline is long; 5h budget across relaunches
for attempt in $(seq 1 12); do
  IID=""; for c in 1 2 3; do IID=$(launch 0) && break; sleep 90; done
  [ -z "$IID" ] && { echo "SPOT UNAVAILABLE (policy)"; [ $(date +%s) -ge $DEADLINE ] && exit 3; sleep 150; continue; }
  echo "CPT_DOMAINPRO $SIZE$TAG attempt=$attempt instance=$IID"
  while :; do
    aws s3 ls "$FINAL" >/dev/null 2>&1 && { echo "=== full${TAG}_adapter READY (CPT+SFT done) ==="; exit 0; }
    aws s3 ls "$RESULT" >/dev/null 2>&1 && echo "[ckpt] base_domain${TAG} (CPT merged) persisted"
    [ $(date +%s) -ge $DEADLINE ] && { echo DEADLINE; exit 4; }
    ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
    [ "$ST" != running ] && [ "$ST" != pending ] && { echo "attempt=$attempt reclaimed ($ST) — relaunch (resume from S3 ckpt)">&2; break; }
    sleep 60
  done
done
echo EXHAUSTED; exit 4
