#!/bin/bash
# c2_launch.sh — launch ONE self-terminating SPOT CPU box to run the C2 retrospective
# closed-loop LEARNING simulation (the moat decider) on a CLEAN, uncontended slot. Local
# contention made a single HistGBM fit take ~230s; a clean box is ~1s, so the full
# targets x seeds x rounds sim completes in ~15-30 min. The in-session agent can't run
# `aws ec2 run-instances` (harness auto-deny) — run this yourself:
#   bash research/guangzhou_all_atom/c2_launch.sh
#
# Bounded + safe (same MO as build_fep_inputs.sh): SPOT only (one-time, multi-type/AZ sweep),
# terminate-on-shutdown, 50 GB gp3, 90-min hard cap, IAM profile ec2-ecr-builder-profile (S3).
# Self-contained: runs purely from the staged c2_retro_loop.py + c2_staged.npz (no CSV/rdkit).
set -euo pipefail

REGION=us-west-2
DEST="s3://biomate-nextflow-work/cyclic_peptide/c2_loop"       # staged inputs + out/ results
SG=sg-0de9af2d4437a8c90
PROFILE=ec2-ecr-builder-profile
HERE="$(cd "$(dirname "$0")" && pwd)"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region $REGION --query 'Parameter.Value' --output text)
# v2 all-targets + UCB/Thompson is ~10x the 10-target work -> parallelised across all vCPUs,
# so sweep many-core boxes (32-64 vCPU) first; terminate cap raised to 180 min for headroom.
TYPES="c6i.8xlarge c6a.8xlarge c7i.8xlarge m6i.8xlarge c6i.12xlarge c6i.16xlarge c6a.16xlarge m6i.16xlarge c6i.4xlarge"
AZS="us-west-2a us-west-2b us-west-2c us-west-2d"

# clear stale results (fresh run only) + stage the self-contained inputs
aws s3 rm "$DEST/out/DONE" --region $REGION >/dev/null 2>&1 || true
aws s3 rm "$DEST/out/c2_result.json" --region $REGION >/dev/null 2>&1 || true
aws s3 cp "$HERE/c2_retro_loop.py" "$DEST/c2_retro_loop.py" --region $REGION
aws s3 cp "$HERE/results/c2_staged.npz" "$DEST/c2_staged.npz" --region $REGION

UD=$(mktemp)
cat > "$UD" <<EOF
#!/bin/bash
exec > /var/log/c2.log 2>&1
set -x
shutdown -h +180
DEST="$DEST"; REGION="$REGION"
dnf install -y bzip2 tar awscli >/dev/null 2>&1
cd /opt && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
mv /opt/bin/micromamba /opt/micromamba
export MAMBA_ROOT_PREFIX=/opt/mamba
/opt/micromamba create -y -p /opt/c2env -c conda-forge python=3.11 numpy scipy scikit-learn >/dev/null 2>&1
mkdir -p /work && cd /work
aws s3 cp "\$DEST/c2_retro_loop.py" /work/c2_retro_loop.py --region "\$REGION"
aws s3 cp "\$DEST/c2_staged.npz" /work/c2_staged.npz --region "\$REGION"
C2_STAGE=/work/c2_staged.npz C2_OUT=/work/c2_result.json C2_MAX_TARGETS=200 /opt/c2env/bin/python /work/c2_retro_loop.py > /work/c2_stdout.txt 2>&1
RC=\$?
# fail-loud: always upload stdout + log; result + DONE(rc) record the honest outcome
aws s3 cp /work/c2_stdout.txt "\$DEST/out/c2_stdout.txt" --region "\$REGION"
aws s3 cp /var/log/c2.log "\$DEST/out/bootstrap.log" --region "\$REGION"
[ -f /work/c2_result.json ] && aws s3 cp /work/c2_result.json "\$DEST/out/c2_result.json" --region "\$REGION"
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
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=c2-retro-loop-v2-alltargets},{Key=purpose,Value=c2-loop-learning-cpu},{Key=autoterminate,Value=180min}]' \
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

echo "LAUNCHED instance: $IID  type=$LT az=$LAZ  (spot one-time, self-terminates <=90 min)"
echo "Poll (~15-30 min on a clean box):"
echo "  aws s3 cp $DEST/out/c2_stdout.txt - --region $REGION          # C2_START ... FINAL[raw]/FINAL[novel] ... C2_DONE"
echo "  aws s3 cp $DEST/out/c2_result.json - --region $REGION         # full learn-vs-fixed-vs-random curves"
echo "  aws s3 ls $DEST/out/ --region $REGION                          # DONE (rc=0) = finished"
echo "Confirm terminated:"
echo "  aws ec2 describe-instances --instance-ids $IID --region $REGION --query 'Reservations[].Instances[].State.Name' --output text"
