#!/bin/bash
# FAIR mid-train test: task-aware corpus (KG-reasoning+tool-QA+db) on L40S, real coverage (~64%), then SFT(v5).
# Compares base_domain_v2mid+SFT(v5) vs sft_v5-alone -> does task-aware mid-train help? (vs the failed L4/raw-LM run)
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=small STAGE=full TAG=_v2mid ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export MIX_LITERATURE=1 FETCH_REPLAY=1 REPLAY_FRAC=0.25   # MIX_LITERATURE -> pulls the prebuilt task-aware v2mid mix
export SFT_DATA=multitask_sft_v5.jsonl
export MID_OVERRIDE=300 SFT_OVERRIDE=500 SEQ_OVERRIDE=1024 BS_OVERRIDE=2 GA_OVERRIDE=8 FORCE_NGPU=1  # fast early usefulness check
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g5.2xlarge g5.4xlarge g6e.xlarge g6.2xlarge g5.8xlarge g4dn.2xlarge)  # SPOT across many types/AZs
BASE_MARK="$S3/models_20260919/small/base_domain_v2mid/config.json"
FINAL_MARK="$S3/models_20260919/small/full_v2mid_adapter/"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in $(seq 1 10); do IID=$(launch 0) && break; echo "spot cycle $c failed, retrying (NO on-demand)">&2; sleep 120; done
[ -z "$IID" ] && { echo "SPOT UNAVAILABLE after retries — NOT falling back to on-demand (policy)"; exit 3; }
echo "MIDTRAIN_V2 instance=$IID"
for i in $(seq 1 400); do
  aws s3 ls "$BASE_MARK" >/dev/null 2>&1 && { echo "=== base_domain_v2mid READY (mid-train done; SFT next) ==="; break; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID died state=$ST before base"; exit 4; }; sleep 45; done
for i in $(seq 1 240); do aws s3 ls "$FINAL_MARK" >/dev/null 2>&1 && { echo "=== full_v2mid (mid+SFT) DONE ==="; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID ended state=$ST"; break; }; sleep 45; done
echo "DONE-or-timeout instance=$IID"
