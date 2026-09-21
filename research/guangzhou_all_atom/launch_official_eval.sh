#!/bin/bash
# GPU-spot launcher for official_eval.sh — the APPLES-TO-APPLES PepGLAD eval: PepGLAD's own generate.py +
# cal_metrics.py on the LNR test set with our BASE LDM checkpoint, comparable to the paper's Table 1/3
# (DockQ/RMSD/Diversity/Consistency/AAR; Success/dG needs PyRosetta, skipped). Clone of launch_closure_ph.sh.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267    # DL Base GPU AMI (drivers + awscli)
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
# BASE (non-cyclic) LDM checkpoint from the pepglad-eval run -> comparable to PepGLAD's general PepBench table.
CKPT_S3=${CKPT_S3:-s3://$BUCKET/cyclic_peptide/runs/pepglad-eval-20260914T154450Z/training/ldm/version_0/checkpoint/provided.ckpt}
N_SAMPLES=${N_SAMPLES:-10}; MAX_RUNTIME=${MAX_RUNTIME:-3h}
RUNID=official-eval-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/official_eval.sh" "$S3RUN/code/official_eval.sh" --only-show-errors
echo "uploaded official_eval.sh; CKPT_S3=$CKPT_S3 N_SAMPLES=$N_SAMPLES"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/eval-boot.log 2>&1
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/official_eval.sh /opt/guangzhou-peptide/code/official_eval.sh --region us-west-2 && break; sleep 10; done
# patch_training_integrity.py already lives in the canonical code/ dir from prior runs.
aws s3 cp s3://$BUCKET/cyclic_peptide/code/patch_training_integrity.py /opt/guangzhou-peptide/code/patch_training_integrity.py --region us-west-2
OUT_S3=$S3RUN CKPT_S3=$CKPT_S3 N_SAMPLES=$N_SAMPLES MAX_RUNTIME=$MAX_RUNTIME bash /opt/guangzhou-peptide/code/official_eval.sh
EOF
)

declare -a COMBO=(
  "g5.2xlarge subnet-03b277a7a08d388c1"
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-09e4dce46682a6c60"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  "g6.2xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0254e4c3634b41bfc"
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
echo "official metrics -> $S3RUN/status/official_metrics.txt  (poll $S3RUN/status/status.json)"
