#!/bin/bash
# launch_preflight.sh — launch ONE self-terminating SPOT CPU instance to run the avb6 FEP
# control-edge full-complex grompp preflight inside gromacs-cuda:2024-cu12.
#
# The in-session agent cannot run `aws ec2 run-instances` (harness auto-deny). Run this yourself:
#     bash research/guangzhou_all_atom/fep/launch_preflight.sh
# (from the repo root, or via `! bash .../launch_preflight.sh` in Claude Code).
#
# Bounded + safe: SPOT only (one-time), terminate-on-shutdown, 50 GB gp3, 90-min hard self-terminate,
# IAM profile ec2-ecr-builder-profile (ECR pull + S3 nextflow bucket). NOT the GPU FEP submit — grompp only.
# Results (STAGE_x:OK/FAIL markers) land in: s3://.../preflight-1792465588/out/preflight_stdout.txt
set -euo pipefail

REGION=us-west-2
PFX="s3://biomate-nextflow-work/cyclic_peptide/fep/preflight-1792465588"   # inputs already staged here
AMI=ami-0803a33fd43db1fbf          # AL2023 x86_64 (us-west-2)
SUBNET=subnet-0254e4c3634b41bfc    # default VPC, us-west-2c
SG=sg-0de9af2d4437a8c90            # default SG (no inbound needed; all egress + S3/ECR)
PROFILE=ec2-ecr-builder-profile    # ecsInstanceRole: ECR pull + GalaxyNextflowS3Access + SSM

UD=$(mktemp)
cat > "$UD" <<EOF
#!/bin/bash
exec > /var/log/pf.log 2>&1
set -x
shutdown -h +90
PFX="$PFX"
dnf install -y docker awscli >/dev/null 2>&1
systemctl enable --now docker
sleep 5
IMG=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gromacs-cuda:2024-cu12
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
docker pull \$IMG
mkdir -p /tmp/work
aws s3 cp \$PFX/in /tmp/work/in --recursive --region $REGION
aws s3 cp \$PFX/preflight_in_container.sh /tmp/work/preflight_in_container.sh --region $REGION
docker run --rm -v /tmp/work:/work -e S3LOG=\$PFX/out/logs.tgz -e AWS_DEFAULT_REGION=$REGION \$IMG bash /work/preflight_in_container.sh > /tmp/work/preflight_stdout.txt 2>&1
aws s3 cp /tmp/work/preflight_stdout.txt \$PFX/out/preflight_stdout.txt --region $REGION
aws s3 cp /var/log/pf.log \$PFX/out/bootstrap.log --region $REGION
echo DONE > /tmp/DONE; aws s3 cp /tmp/DONE \$PFX/out/DONE --region $REGION
shutdown -h now
EOF

IID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type c6i.2xlarge \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
  --instance-initiated-shutdown-behavior terminate \
  --iam-instance-profile Name=$PROFILE \
  --subnet-id $SUBNET \
  --security-group-ids $SG \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --metadata-options '{"HttpTokens":"required","HttpPutResponseHopLimit":2,"HttpEndpoint":"enabled"}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=avb6-fep-preflight},{Key=purpose,Value=fep-grompp-preflight-cpu},{Key=autoterminate,Value=90min}]' \
  --user-data "file://$UD" \
  --query 'Instances[0].InstanceId' --output text)
rm -f "$UD"

echo "LAUNCHED instance: $IID  (spot c6i.2xlarge, self-terminates <=90 min)"
echo "Monitor results (~10-20 min after boot):"
echo "  aws s3 cp $PFX/out/preflight_stdout.txt - --region $REGION   # STAGE_x:OK/FAIL markers"
echo "  aws s3 ls $PFX/out/ --region $REGION                          # DONE sentinel when finished"
echo "Confirm terminated:"
echo "  aws ec2 describe-instances --instance-ids $IID --region $REGION --query 'Reservations[].Instances[].State.Name' --output text"
