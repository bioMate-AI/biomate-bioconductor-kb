#!/bin/bash
# GPU-spot launcher for run_pepglad_ec2.sh (PepGLAD training). Mirrors the proven code.tar.gz UserData
# template (results/pepglad-initial-*/user_data.sh). Default here = a BOUNDED FULL-BATCH PROBE:
# resolves (a) does UBOUND_PER_BATCH=60000 OOM on 24GB, (b) per-epoch wall-time at full batch,
# (c) does partial full-batch training lift DockQ — so the real convergence run can be sized.
# Override env to scale up once the probe answers those.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267    # DL Base GPU AMI
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912
# Training knobs (env-overridable). PROBE defaults: full batch, few epochs, 4h cap.
LDM_ONLY=${LDM_ONLY:-1}                        # AE already converged (epoch 13) -> train ONLY the LDM (full-batch retrain)
UBOUND_PER_BATCH=${UBOUND_PER_BATCH:-60000}   # full batch (upstream default); 30000 was the half-batch that under-trained
LDM_MAX_EPOCH=${LDM_MAX_EPOCH:-80}            # LDM convergence target (half-batch reached ~79); monitor early for OOM at 60000
RESUME_TRAINING_S3=${RESUME_TRAINING_S3:-s3://$BUCKET/cyclic_peptide/runs/pepglad-long-20260913T222203Z}  # source of trained AE
MAX_RUNTIME=${MAX_RUNTIME:-6h}
RUNID=pepglad-fullbatch-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle (proven pattern) ---
TMP=$(mktemp -d)
for f in run_pepglad_ec2.sh collect_pepbench.py configure_pepglad.py configure_warm_start.py \
         patch_training_integrity.py generate_validation.py pepbench_zenodo.json; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/code.tar.gz" -C "$TMP" run_pepglad_ec2.sh collect_pepbench.py configure_pepglad.py \
  configure_warm_start.py patch_training_integrity.py generate_validation.py pepbench_zenodo.json
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA); LDM_ONLY=$LDM_ONLY UBOUND=$UBOUND_PER_BATCH LDM=$LDM_MAX_EPOCH RESUME=$RESUME_TRAINING_S3"

UD=$(cat <<EOF | base64
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
trap 'shutdown -h now' ERR
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/code.tar.gz /opt/guangzhou-peptide/code.tar.gz && break; sleep 10; done
echo '$SHA  /opt/guangzhou-peptide/code.tar.gz' | sha256sum -c -
tar xzf /opt/guangzhou-peptide/code.tar.gz -C /opt/guangzhou-peptide/code
export OUT_S3=$S3RUN RESUME_TRAINING_S3=$RESUME_TRAINING_S3
export LDM_ONLY=$LDM_ONLY UBOUND_PER_BATCH=$UBOUND_PER_BATCH LDM_MAX_EPOCH=$LDM_MAX_EPOCH MAX_RUNTIME=$MAX_RUNTIME
bash /opt/guangzhou-peptide/code/run_pepglad_ec2.sh
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
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "training -> $S3RUN/  (poll $S3RUN/status/status.json; checkpoints stream to $S3RUN/training/)"
