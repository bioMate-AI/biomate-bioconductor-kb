#!/bin/bash
# Launch a spot GPU instance for one training stage (headless; logs + checkpoints stream to S3).
# Defaults are the discovered account params (us-west-2). 27B QLoRA (4-bit) fits on a single L40S 48GB,
# so both sizes run on the cheap g6e family (no expensive P-family). Reclaim-safe: spot_train resumes
# from S3, so re-running this after a reclaim continues from the last checkpoint.
#   MODEL_SIZE=small STAGE=sft bash spot_launch.sh
set -euo pipefail
: "${MODEL_SIZE:?small|large}"; STAGE=${STAGE:-sft}
REGION=${REGION:-us-west-2}
AMI=${AMI:-ami-04f7da1c787a89267}                         # DL Base GPU AMI (us-west-2)
PROFILE=${PROFILE:-biomate-core-trial-20260912}
SUBNET=${SUBNET:-subnet-0254e4c3634b41bfc}
SG=${SG:-sg-0de9af2d4437a8c90}
INSTANCE_TYPE=${INSTANCE_TYPE:-$( [ "$MODEL_SIZE" = small ] && echo g6e.xlarge || echo g6e.4xlarge )}
REPO_TARBALL_S3=${REPO_TARBALL_S3:-s3://biomate-models-399683337364/biomate-core-local-trial/20260912/code/evaluation_local_trial.tgz}

TAG=${TAG:-}   # namespaces logs/ckpts/outputs for A/B variants (e.g. _mix)
LOG_S3="s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_logs/$MODEL_SIZE/$STAGE$TAG"
USERDATA=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/ud.log 2>&1
set -x
export SCRATCH=/opt/dlami/nvme MODEL_SIZE=$MODEL_SIZE STAGE=$STAGE TAG=$TAG ENTRY=${ENTRY:-spot_train.sh} BOOTSTRAP=${BOOTSTRAP:-gpu_bootstrap.sh} SEQ_OVERRIDE=${SEQ_OVERRIDE:-} R_OVERRIDE=${R_OVERRIDE:-} MID_OVERRIDE=${MID_OVERRIDE:-} BS_OVERRIDE=${BS_OVERRIDE:-} GA_OVERRIDE=${GA_OVERRIDE:-} FORCE_NGPU=${FORCE_NGPU:-} CKPTS=${CKPTS:-} FETCH_REPLAY=${FETCH_REPLAY:-0} REPLAY_FRAC=${REPLAY_FRAC:-} REPLAY_DOCS=${REPLAY_DOCS:-} MIX_LITERATURE=${MIX_LITERATURE:-0} LIT_KEEP_EVERY=${LIT_KEEP_EVERY:-} STRUCT_REPEAT=${STRUCT_REPEAT:-} MIX_KG=${MIX_KG:-0} KG_REPEAT=${KG_REPEAT:-} LIT_START=${LIT_START:-} LIT_FILES=${LIT_FILES:-} LIT_WORKERS=${LIT_WORKERS:-} KGSFT_TARGET=${KGSFT_TARGET:-} CKMODE=${CKMODE:-} CKPT_STAGE=${CKPT_STAGE:-} OPENAI_API_KEY=$OPENAI_API_KEY GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
# stream the boot log to S3 from the START so bootstrap failures are visible (EBS is gone on terminate)
( while true; do aws s3 cp /var/log/ud.log $LOG_S3/boot.log --quiet 2>/dev/null; sleep 20; done ) &
mkdir -p \$SCRATCH/code && cd \$SCRATCH/code
for i in 1 2 3; do aws s3 cp $REPO_TARBALL_S3 code.tgz && break || sleep 10; done
tar xzf code.tgz
bash ${BOOTSTRAP:-gpu_bootstrap.sh}
bash ${ENTRY:-spot_train.sh}
aws s3 cp /var/log/ud.log $LOG_S3/boot.log --quiet
sleep 30
shutdown -h now
EOF
)

MARKET="--instance-market-options MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}"
[ "${ONDEMAND:-0}" = "1" ] && MARKET="" && echo "(on-demand mode)"
echo "Launching $INSTANCE_TYPE ${ONDEMAND:+on-demand}${ONDEMAND:-spot} for $MODEL_SIZE/$STAGE in $REGION"
IID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET" --security-group-ids "$SG" \
  --iam-instance-profile "Name=$PROFILE" \
  $MARKET \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=400,VolumeType=gp3}' \
  --instance-initiated-shutdown-behavior terminate \
  --user-data "$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=biomate-onprem-$MODEL_SIZE-$STAGE$TAG}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "INSTANCE=$IID  ($MODEL_SIZE/$STAGE)"
echo "logs:  s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_logs/$MODEL_SIZE/$STAGE/train.log"
echo "ckpts: s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_ckpt/$MODEL_SIZE/$STAGE/"
echo "final: s3://biomate-models-399683337364/biomate-core-local-trial/20260912/models_20260919/$MODEL_SIZE/"
