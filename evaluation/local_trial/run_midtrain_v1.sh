#!/bin/bash
# Launch the v1 mid-train (STAGE=full: midtrain->merge->persist base_domain->SFT). Spot-first over
# GPU types x AZs; on-demand fallback. Polls S3 for the persisted strong base. Tracks the instance id.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=small STAGE=full TAG=_v1strong ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export MID_OVERRIDE=2000 SFT_OVERRIDE=400 SEQ_OVERRIDE=2048 BS_OVERRIDE=2 GA_OVERRIDE=16 FORCE_NGPU=1
export MIX_LITERATURE=1 LIT_KEEP_EVERY=8 STRUCT_REPEAT=6 MIX_KG=1 KG_REPEAT=1 MIX_DEDUP=1
export PMC_FILE=pmc_fulltext_corpus_v1small.jsonl PMC_REPEAT=3 TOOLDOC_REPEAT=3 DBCAT_REPEAT=1
export FETCH_REPLAY=1 REPLAY_FRAC=0.25
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6e.xlarge g6.2xlarge g5.2xlarge g5.xlarge)
BASE_MARK="$S3/models_20260919/small/base_domain_v1strong/config.json"
FINAL_MARK="$S3/models_20260919/small/full_v1strong_adapter/"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2 3; do IID=$(launch 0) && break; echo "spot cycle $c failed, retry">&2; sleep 90; done
[ -z "$IID" ] && { echo "spot exhausted -> on-demand">&2; IID=$(launch 1); }
[ -z "$IID" ] && { echo GAVEUP; exit 3; }
echo "MIDTRAIN_V1 instance=$IID"
for i in $(seq 1 480); do   # up to ~6h
  if aws s3 ls "$BASE_MARK" >/dev/null 2>&1; then echo "=== STRONG BASE base_domain_v1strong READY (instance $IID still doing SFT) ==="; break; fi
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID died state=$ST before base persisted"; exit 4; }
  sleep 45
done
# wait for SFT final adapter too (so we have an evaluatable model)
for i in $(seq 1 240); do aws s3 ls "$FINAL_MARK" >/dev/null 2>&1 && { echo "=== FULL v1 (base+SFT) DONE ==="; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID ended state=$ST"; break; }; sleep 45; done
echo "DONE-or-timeout instance=$IID"
