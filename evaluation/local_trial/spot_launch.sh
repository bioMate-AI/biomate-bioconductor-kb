#!/bin/bash
# Launch a PERSISTENT spot request for one training stage. Persistent + spot_train's resume-from-S3 =
# self-healing: if the instance is reclaimed, AWS re-launches it and spot_train resumes from the last
# S3 checkpoint. Set the region/AMI/subnet/key/profile for your account before running.
#
#   MODEL_SIZE=small STAGE=midtrain bash spot_launch.sh
set -euo pipefail
: "${MODEL_SIZE:?set small|large}"; : "${STAGE:?set midtrain|sft}"
REGION=${REGION:-us-west-2}
PROFILE_NAME=${PROFILE_NAME:-AutoimmuneCorpusProfile}     # S3 read/write instance profile
AMI=${AMI:?set AMI to the Deep Learning Base GPU AMI id in your region}
KEY=${KEY:?set your EC2 key pair name}
SUBNET=${SUBNET:?set a subnet id}; SG=${SG:?set a security group id}
# spot for 80GB A100/H100 is scarce -> for large, prefer a capacity-flexible type or fall back to on-demand
INSTANCE_TYPE=${INSTANCE_TYPE:-$( [ "$MODEL_SIZE" = small ] && echo g6e.xlarge || echo g6e.12xlarge )}
REPO_TARBALL_S3=${REPO_TARBALL_S3:-s3://biomate-models-399683337364/biomate-core-local-trial/code/evaluation_local_trial.tgz}

# user-data: bootstrap deps+data, then run the resume-aware spot trainer for this stage
USERDATA=$(cat <<EOF | base64
#!/bin/bash
set -e
export SCRATCH=/opt/dlami/nvme MODEL_SIZE=$MODEL_SIZE STAGE=$STAGE
mkdir -p \$SCRATCH/code && cd \$SCRATCH/code
aws s3 cp $REPO_TARBALL_S3 code.tgz && tar xzf code.tgz
bash gpu_bootstrap.sh
bash spot_train.sh >> /var/log/spot_train.log 2>&1
EOF
)

echo "Requesting PERSISTENT spot: $INSTANCE_TYPE ($MODEL_SIZE/$STAGE) in $REGION"
aws ec2 request-spot-instances --region "$REGION" \
  --instance-count 1 --type persistent \
  --instance-interruption-behavior stop \
  --launch-specification "$(cat <<JSON
{
  "ImageId": "$AMI",
  "InstanceType": "$INSTANCE_TYPE",
  "KeyName": "$KEY",
  "SubnetId": "$SUBNET",
  "SecurityGroupIds": ["$SG"],
  "IamInstanceProfile": {"Name": "$PROFILE_NAME"},
  "BlockDeviceMappings": [{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":300,"VolumeType":"gp3"}}],
  "UserData": "$USERDATA"
}
JSON
)"
echo "Requested. Checkpoints stream to .../spot_ckpt/$MODEL_SIZE/$STAGE ; final adapter to .../models_*/$MODEL_SIZE/."
echo "On reclaim, AWS relaunches and spot_train.sh resumes from the last S3 checkpoint. Cancel with:"
echo "  aws ec2 cancel-spot-instance-requests --region $REGION --spot-instance-request-ids <id>  (then terminate the instance)"
