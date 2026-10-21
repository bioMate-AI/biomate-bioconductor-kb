#!/bin/bash
# c4_launch.sh — launch ONE self-terminating SPOT CPU box to run the C4-forward EXPLICIT
# conformer-ENSEMBLE permeability benchmark at FULL SCALE (all ~8,466 CycPeptMPDB rows, so it is
# apples-to-apples with the full-set ECFP 0.237 / proxy 0.301 baselines — no subset-CI caveat).
# The per-molecule ETKDGv3 ensemble generation is the only bottleneck and is parallelised across
# all vCPUs (1 embed thread/worker), so the full set finishes in ~15-25 min on a many-core box.
# The in-session agent can't run `aws ec2 run-instances` (harness auto-deny) — run this yourself:
#   bash research/guangzhou_all_atom/c4_launch.sh
#
# Bounded + safe (same MO as c2_launch.sh): SPOT only (one-time, multi-type/AZ sweep),
# terminate-on-shutdown, 50 GB gp3, 180-min hard cap, IAM profile ec2-ecr-builder-profile (S3).
# Self-contained: runs from the staged c4_ensemble_permeability.py + CycPeptMPDB CSV (clean
# micromamba python=3.11 numpy/scipy/scikit-learn/rdkit — no repo checkout on the box).
set -euo pipefail

REGION=us-west-2
DEST="s3://biomate-nextflow-work/cyclic_peptide/c4_ensemble"    # staged inputs + out/ results
SG=sg-0de9af2d4437a8c90
PROFILE=ec2-ecr-builder-profile
HERE="$(cd "$(dirname "$0")" && pwd)"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region $REGION --query 'Parameter.Value' --output text)
# conformer gen is CPU-bound & embarrassingly parallel across mols → many-core boxes first
TYPES="c6i.8xlarge c6a.8xlarge c7i.8xlarge m6i.8xlarge c6i.12xlarge c6i.16xlarge c6a.16xlarge m6i.16xlarge c6i.4xlarge"
AZS="us-west-2a us-west-2b us-west-2c us-west-2d"

# clear stale results (fresh run only) + stage the self-contained inputs
aws s3 rm "$DEST/out/DONE" --region $REGION >/dev/null 2>&1 || true
aws s3 rm "$DEST/out/c4_result.json" --region $REGION >/dev/null 2>&1 || true
aws s3 cp "$HERE/c4_ensemble_permeability.py" "$DEST/c4_ensemble_permeability.py" --region $REGION
aws s3 cp "$HERE/data/raw/CycPeptMPDB_Peptide_All.csv" "$DEST/CycPeptMPDB_Peptide_All.csv" --region $REGION

UD=$(mktemp)
cat > "$UD" <<EOF
#!/bin/bash
exec > /var/log/c4.log 2>&1
set -x
shutdown -h +180
DEST="$DEST"; REGION="$REGION"
dnf install -y bzip2 tar awscli >/dev/null 2>&1
cd /opt && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
mv /opt/bin/micromamba /opt/micromamba
export MAMBA_ROOT_PREFIX=/opt/mamba
/opt/micromamba create -y -p /opt/c4env -c conda-forge python=3.11 numpy scipy scikit-learn rdkit >/dev/null 2>&1
mkdir -p /work && cd /work
aws s3 cp "\$DEST/c4_ensemble_permeability.py" /work/c4_ensemble_permeability.py --region "\$REGION"
aws s3 cp "\$DEST/CycPeptMPDB_Peptide_All.csv" /work/CycPeptMPDB_Peptide_All.csv --region "\$REGION"
C4_CSV=/work/CycPeptMPDB_Peptide_All.csv C4_OUT=/work/c4_result.json C4_NMAX=9000 \
  /opt/c4env/bin/python /work/c4_ensemble_permeability.py > /work/c4_stdout.txt 2>&1
RC=\$?
# fail-loud: always upload stdout + log; result + DONE(rc) record the honest outcome
aws s3 cp /work/c4_stdout.txt "\$DEST/out/c4_stdout.txt" --region "\$REGION"
aws s3 cp /var/log/c4.log "\$DEST/out/bootstrap.log" --region "\$REGION"
[ -f /work/c4_result.json ] && aws s3 cp /work/c4_result.json "\$DEST/out/c4_result.json" --region "\$REGION"
echo "rc=\$RC" > /tmp/DONE; aws s3 cp /tmp/DONE "\$DEST/out/DONE" --region "\$REGION"
shutdown -h now
EOF

IID=""; LT=""; LAZ=""
set +e
for ty in $TYPES; do
  for az in $AZS; do
    sn=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true Name=availability-zone,Values=$az \
          --region $REGION --query 'Subnets[0].SubnetId' --output text 2>/dev/null)
    [ -z "$sn" ] || [ "$sn" = "None" ] && continue
    echo "trying spot $ty in $az (subnet $sn) ..."
    OUT=$(aws ec2 run-instances \
      --region $REGION --image-id $AMI --instance-type $ty \
      --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
      --instance-initiated-shutdown-behavior terminate \
      --iam-instance-profile Name=$PROFILE \
      --subnet-id $sn --security-group-ids $SG \
      --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
      --metadata-options '{"HttpTokens":"required","HttpPutResponseHopLimit":2,"HttpEndpoint":"enabled"}' \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=c4-ensemble-permeability},{Key=purpose,Value=c4-ensemble-cpu},{Key=autoterminate,Value=180min}]' \
      --user-data "file://$UD" \
      --query 'Instances[0].InstanceId' --output text 2>&1)
    if [ $? -eq 0 ] && [ "${OUT#i-}" != "$OUT" ]; then IID=$OUT; LT=$ty; LAZ=$az; break 2; fi
    if echo "$OUT" | grep -qiE 'InsufficientInstanceCapacity|insufficient capacity|capacity-not-available|SpotMaxPriceTooLow|Unsupported|not supported in your requested Availability Zone'; then
      echo "  no capacity for $ty/$az -> next"; continue
    fi
    echo "FATAL non-capacity error on $ty/$az:"; echo "$OUT"; rm -f "$UD"; exit 2
  done
done
set -e
rm -f "$UD"
if [ -z "$IID" ]; then
  echo "NO SPOT CAPACITY across us-west-2 right now — retry later. NEVER on-demand."; exit 1
fi

echo "LAUNCHED instance: $IID  type=$LT az=$LAZ  (spot one-time, self-terminates <=180 min)"
echo "Poll (~15-25 min on a many-core box):"
echo "  aws s3 cp $DEST/out/c4_stdout.txt - --region $REGION          # per-100 progress ... R2 table ... WROTE"
echo "  aws s3 cp $DEST/out/c4_result.json - --region $REGION         # full ECFP/proxy/ensemble R2/MAE/Spearman"
echo "  aws s3 ls $DEST/out/ --region $REGION                          # DONE (rc=0) = finished"
echo "Confirm terminated:"
echo "  aws ec2 describe-instances --instance-ids $IID --region $REGION --query 'Reservations[].Instances[].State.Name' --output text"
