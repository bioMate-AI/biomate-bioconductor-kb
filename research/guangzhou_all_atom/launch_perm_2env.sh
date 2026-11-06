#!/bin/bash
# Launch the (bug-fixed) 2-environment permeability job on a CPU SPOT instance.
# Fixes vs the 2026-09-18 run that produced no result: per-item SIGALRM timeout (hung AM1-BCC),
# per-iteration budget check (was gated behind i%25, so stalls evaded it and the hard deadline
# killed the box before ML), and row checkpointing to S3. Spot per launch-infra memory (CPU jobs too).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04678417fc39d7171            # Ubuntu 24.04 noble amd64 (no awscli apt pkg -> UserData self-installs v2)
TYPE=${TYPE:-c6i.8xlarge}
SUBNET=subnet-09e4dce46682a6c60; SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
RUNID=perm-2env-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/perm_2env.sh" "$S3RUN/code/perm_2env.sh" --only-show-errors
echo "uploaded code -> $S3RUN/code/perm_2env.sh"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/p2e-boot.log 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq unzip curl
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip
cd /tmp && unzip -q -o a.zip && ./aws/install
mkdir -p /opt/p2e
/usr/local/bin/aws s3 cp $S3RUN/code/perm_2env.sh /opt/p2e/perm_2env.sh --region us-west-2
chmod +x /opt/p2e/perm_2env.sh
OUT_S3=$S3RUN NSUB=200 bash /opt/p2e/perm_2env.sh
EOF
)

IID=$(aws ec2 run-instances \
  --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
  --subnet-id "$SUBNET" --security-group-ids "$SG" \
  --iam-instance-profile Name=AutoimmuneCorpusProfile \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
  --instance-initiated-shutdown-behavior terminate \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]' \
  --user-data "$UD" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "RUNID=$RUNID"
echo "INSTANCE=$IID"
echo "result -> $S3RUN/status/perm_2env.json (poll $S3RUN/status/status.json)"
