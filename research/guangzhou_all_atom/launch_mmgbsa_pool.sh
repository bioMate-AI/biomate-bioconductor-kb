#!/bin/bash
# Launch peptide_mmgbsa_run.sh — MM-GBSA dG for ALL BoltzGen designs of ONE target (final_ranked CIFs).
# Self-contained runner (installs openmm/psfgen/parmed, fetches CHARMM36 toppar, GBn2 implicit-solvent
# MD on GPU, single-trajectory MM-GBSA). Spot by default; ONDEMAND=1 uses on-demand (capacity-crunch).
# Self-terminates (runner's 3h dead-man's-switch + shutdown-behavior=terminate).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04) us-west-2 (CUDA drivers)
SG=${SG:-sg-011121fdf81073ec8}; KEY=${KEY:-biomate-trial-resume-20260912}
TARGET=${TARGET:-5o45}
RUNNER=${RUNNER:-peptide_mmgbsa_run.sh}   # override: peptide_mmgbsa_pocket_run.sh for large/multi-chain receptors
DESIGNS_S3=${DESIGNS_S3:-s3://$BUCKET/cyclic_peptide/runs/boltzgen-oversample-5o45-20260930T172457Z/boltzgen_targets}
NS=${NS:-0.5}
RUNID=mmgbsa-pool-${TARGET}-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/$RUNNER" "$S3RUN/code/peptide_mmgbsa_run.sh" --only-show-errors
echo "uploaded runner -> $S3RUN/code/  (TARGET=$TARGET DESIGNS_S3=$DESIGNS_S3 NS=$NS)"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/mmg-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/mmg
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/peptide_mmgbsa_run.sh /opt/mmg/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/mmg/run.sh
OUT_S3=$S3RUN DESIGNS_S3=$DESIGNS_S3 TARGET=$TARGET NS=$NS bash /opt/mmg/run.sh
EOF
)

declare -a COMBO=(
  "g5.2xlarge subnet-03b277a7a08d388c1"
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-09e4dce46682a6c60"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  "g6.2xlarge subnet-0254e4c3634b41bfc"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
)
[ -n "${COMBO_OVERRIDE:-}" ] && mapfile -t COMBO <<< "$COMBO_OVERRIDE"
IID=""
for c in "${COMBO[@]}"; do
  set -- $c; TYPE=$1; SUBNET=$2
  echo "trying $TYPE in $SUBNET ..."
  IID=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type "$TYPE" ${KEY:+--key-name $KEY} \
    --subnet-id "$SUBNET" --security-group-ids "$SG" \
    --iam-instance-profile Name=AutoimmuneCorpusProfile \
    $([ -z "${ONDEMAND:-}" ] && echo "--instance-market-options {\"MarketType\":\"spot\",\"SpotOptions\":{\"SpotInstanceType\":\"one-time\",\"InstanceInterruptionBehavior\":\"terminate\"}}") \
    --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU capacity across all combos"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:    aws s3 cp $S3RUN/status/status.json -"
echo "results: aws s3 ls $S3RUN/ --recursive | grep -i mmgbsa"
