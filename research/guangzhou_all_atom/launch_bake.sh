#!/bin/bash
# launch_bake.sh — build the pre-baked cyclic-peptide AMI. On-demand GPU, big EBS, NO auto-terminate
# (we snapshot this instance into an AMI once bake_cyclic_image.sh signals READY, then terminate it).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04) us-west-2
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
RUNID=bake-cyclic-$(date -u +%Y%m%dT%H%M%SZ)
BAKE_S3=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)
aws s3 cp "$HERE/bake_cyclic_image.sh" "$BAKE_S3/code/bake_cyclic_image.sh" --only-show-errors
echo "uploaded bake script -> $BAKE_S3/code/"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/bake-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/bake
for i in 1 2 3 4 5; do aws s3 cp $BAKE_S3/code/bake_cyclic_image.sh /opt/bake/bake.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/bake/bake.sh
BAKE_S3=$BAKE_S3 bash /opt/bake/bake.sh
EOF
)
# on-demand (no market-options), NO shutdown-behavior (must stay up to snapshot), 200GB for the stacks
declare -a COMBO=("g4dn.xlarge subnet-03b277a7a08d388c1" "g4dn.xlarge subnet-0254e4c3634b41bfc" "g4dn.xlarge subnet-09e4dce46682a6c60" "g4dn.xlarge subnet-0b35a6e2c1cf02dc2" "g5.2xlarge subnet-0254e4c3634b41bfc" "g6.2xlarge subnet-0b35a6e2c1cf02dc2")
IID=""
for c in "${COMBO[@]}"; do
  set -- $c; TYPE=$1; SUBNET=$2
  echo "trying $TYPE in $SUBNET ..."
  IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
    --subnet-id "$SUBNET" --security-group-ids "$SG" --iam-instance-profile Name=AutoimmuneCorpusProfile \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "NOTE: does NOT auto-terminate. When status=READY -> create-image, then terminate."
echo "poll: aws s3 cp $BAKE_S3/status/status.json -"
