#!/bin/bash
# GPU-spot launcher for the closure A/B smoke WITH the new MacroGuide 'ph' arm.
# Runs generate_validation.py in 3 modes (default | cyclic | ph) on the SAME calibrated LDM checkpoint
# and compares closure_rate. Clone of launch_boltzgen_oversample.sh (spot, AZ-fallback, self-terminate).
# The scientific question: does persistent-homology (MacroGuide) guidance beat the hand-rolled head-to-tail
# 'cyclic' term at equal cost? (NOT "does it reach 99%": the incumbent is not a 1% baseline.)
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267    # DL Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) — drivers + awscli
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
# Base LDM checkpoint from the pepglad-eval run; closure_smoke.sh re-runs setup_latent_guidance.py to calibrate it.
CKPT_S3=${CKPT_S3:-s3://$BUCKET/cyclic_peptide/runs/pepglad-eval-20260914T154450Z/training/ldm/version_0/checkpoint/provided.ckpt}
LIMIT=${LIMIT:-20}; ATTEMPTS=${ATTEMPTS:-4}; MAX_RUNTIME=${MAX_RUNTIME:-2h}
RUNID=closure-ph-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# Canonical code dir (closure_smoke.sh fetches these at runtime). Additive/backward-compatible.
aws s3 cp "$HERE/generate_validation.py"  "s3://$BUCKET/cyclic_peptide/code/generate_validation.py"  --only-show-errors
aws s3 cp "$HERE/ph_closure_guidance.py"  "s3://$BUCKET/cyclic_peptide/code/ph_closure_guidance.py"  --only-show-errors
aws s3 cp "$HERE/patch_training_integrity.py" "s3://$BUCKET/cyclic_peptide/code/patch_training_integrity.py" --only-show-errors || true
# Run-specific copy of the driver script.
aws s3 cp "$HERE/closure_smoke.sh" "$S3RUN/code/closure_smoke.sh" --only-show-errors
echo "uploaded code; CKPT_S3=$CKPT_S3 LIMIT=$LIMIT ATTEMPTS=$ATTEMPTS"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/closure-boot.log 2>&1
mkdir -p /opt/closure-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/closure_smoke.sh /opt/closure-run/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/closure-run/run.sh
OUT_S3=$S3RUN CKPT_S3=$CKPT_S3 LIMIT=$LIMIT ATTEMPTS=$ATTEMPTS MAX_RUNTIME=$MAX_RUNTIME bash /opt/closure-run/run.sh
EOF
)

declare -a COMBO=(
  "g5.2xlarge subnet-03b277a7a08d388c1"   # 2b
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
echo "summaries -> $S3RUN/status/summary_{default,cyclic,ph}.json  (poll $S3RUN/status/status.json)"
