#!/bin/bash
# v3 POC: oversample BoltzGen for ONE target (more designs than the default 8) on a GPU SPOT instance,
# looping instance-type x AZ because GPU spot capacity is tight. Downstream: score the larger pool by
# binding x permeability-headroom (perm_redesign_v1.py) and check whether the permeability-aware Pareto
# finds good binders with far more headroom than BoltzGen's default top-ranked.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267    # DL Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) 20260918 — has drivers + awscli
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
TARGET_ONLY=${TARGET_ONLY:-1yf4}; NUM_DESIGNS=${NUM_DESIGNS:-32}; BUDGET=${BUDGET:-2}
RUNID=fep-hydration-poc-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/fep_hydration_poc.sh" "$S3RUN/code/fep_hydration_poc.sh" --only-show-errors
echo "uploaded code -> $S3RUN/code/ (TARGET_ONLY=$TARGET_ONLY NUM_DESIGNS=$NUM_DESIGNS)"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/bg-boot.log 2>&1
mkdir -p /opt/fep
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/fep_hydration_poc.sh /opt/fep/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/fep/run.sh
OUT_S3=$S3RUN bash /opt/fep/run.sh
EOF
)

# subnets per AZ (same VPC as SG)
declare -a COMBO=(
  "g5.2xlarge subnet-03b277a7a08d388c1"   # 2b (cheapest g5 seen)
  "g5.2xlarge subnet-0254e4c3634b41bfc"   # 2c
  "g5.2xlarge subnet-09e4dce46682a6c60"   # 2a
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"   # 2d
  "g6.2xlarge subnet-0254e4c3634b41bfc"   # 2c
  "g6.4xlarge subnet-0254e4c3634b41bfc"   # 2c
)
IID=""
for c in "${COMBO[@]}"; do
  set -- $c; TYPE=$1; SUBNET=$2
  echo "trying $TYPE in $SUBNET ..."
  IID=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
    --subnet-id "$SUBNET" --security-group-ids "$SG" \
    --iam-instance-profile Name=AutoimmuneCorpusProfile \
    --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
    --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "designs+metrics -> $S3RUN/  (poll $S3RUN/status/status.json)"
