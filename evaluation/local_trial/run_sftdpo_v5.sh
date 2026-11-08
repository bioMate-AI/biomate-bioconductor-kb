#!/bin/bash
# SFT(v5 clean+openbook+contrastive+paraphrase) -> merge -> DPO(hard-neg pairs) on the PLAIN base.
# Isolates data-quality lift (mid-train base comparison runs later). Spot-first GPU, resume-safe.
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
export MODEL_SIZE=small STAGE=sftdpo TAG=_v5 ENTRY=spot_train.sh BOOTSTRAP=gpu_bootstrap.sh
export SFT_DATA=multitask_sft_v5.jsonl DPO_PAIRS=routing_dpo_pairs_v2.jsonl
export SFT_OVERRIDE=1000 SEQ_OVERRIDE=2048 BS_OVERRIDE=2 GA_OVERRIDE=16 FORCE_NGPU=1
SUBS=(subnet-09e4dce46682a6c60 subnet-03b277a7a08d388c1 subnet-0b35a6e2c1cf02dc2 subnet-0254e4c3634b41bfc)
TYPES=(g6e.xlarge g6.2xlarge g5.2xlarge g5.xlarge)
DPO_MARK="$S3/models_20260919/small/dpo_v5_adapter/"
SFT_MARK="$S3/models_20260919/small/sft_v5_merged/config.json"
launch(){ for T in "${TYPES[@]}"; do for S in "${SUBS[@]}"; do
  O=$(ONDEMAND=$1 INSTANCE_TYPE=$T SUBNET=$S bash spot_launch.sh 2>&1); IID=$(echo "$O"|grep -oE "i-[0-9a-f]{8,}"|head -1)
  [ -n "$IID" ] && { echo "LAUNCHED ${1:+od-}$T @ $S -> $IID">&2; echo "$IID"; return 0; }
done; done; return 1; }
IID=""; for c in 1 2 3; do IID=$(launch 0) && break; echo "spot cycle $c failed">&2; sleep 90; done
[ -z "$IID" ] && { echo "spot exhausted -> on-demand">&2; IID=$(launch 1); }
[ -z "$IID" ] && { echo GAVEUP; exit 3; }
echo "SFTDPO_V5 instance=$IID"
for i in $(seq 1 400); do
  aws s3 ls "$SFT_MARK" >/dev/null 2>&1 && { echo "=== sft_v5_merged READY ($i) ==="; break; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID died state=$ST before SFT"; exit 4; }; sleep 45; done
for i in $(seq 1 200); do aws s3 ls "$DPO_MARK" >/dev/null 2>&1 && { echo "=== DPO v5 DONE ==="; exit 0; }
  ST=$(aws ec2 describe-instances --region us-west-2 --instance-ids "$IID" --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  [ "$ST" != running ] && [ "$ST" != pending ] && { echo "instance $IID ended state=$ST"; break; }; sleep 45; done
echo "DONE-or-timeout instance=$IID"
