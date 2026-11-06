#!/bin/bash
# Launch the v2 N-methyl MM-GBSA build SMOKE on a small CPU SPOT instance (one peptide, build test).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04678417fc39d7171            # Ubuntu 24.04 noble amd64
TYPE=${TYPE:-c6i.2xlarge}
SUBNET=subnet-09e4dce46682a6c60; SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
RUNID=nmethyl-smoke-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/peptide_nmethyl_smoke.sh" "$S3RUN/code/peptide_nmethyl_smoke.sh" --only-show-errors
echo "uploaded code -> $S3RUN/code/"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/nm-boot.log 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq unzip curl
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip
cd /tmp && unzip -q -o a.zip && ./aws/install
mkdir -p /opt/nm
/usr/local/bin/aws s3 cp $S3RUN/code/peptide_nmethyl_smoke.sh /opt/nm/run.sh --region us-west-2
chmod +x /opt/nm/run.sh
OUT_S3=$S3RUN bash /opt/nm/run.sh
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

echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "result -> $S3RUN/status/nmethyl_smoke.json (poll $S3RUN/status/status.json)"
