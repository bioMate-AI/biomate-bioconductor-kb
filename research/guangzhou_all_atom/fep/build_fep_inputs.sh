#!/bin/bash
# build_fep_inputs.sh — launch ONE self-terminating SPOT CPU box to BUILD the avb6 FEP control-edge
# inputs OFFLINE (gromacs+pmx; no GPU, no mdrun). The in-session agent can't run `aws ec2 run-instances`
# (harness auto-deny), so run this yourself:  bash research/guangzhou_all_atom/fep/build_fep_inputs.sh
#
# Bounded + safe (identical to launch_preflight.sh): SPOT only (one-time), terminate-on-shutdown,
# 50 GB gp3, 90-min hard self-terminate, IAM profile ec2-ecr-builder-profile (S3). CONTROL EDGE ONLY.
# On success it writes the sentinel  <DEST>/in/FEP_INPUTS_READY ; then the agent runs fep_batch.py --submit.
set -euo pipefail

REGION=us-west-2
SRC="s3://biomate-nextflow-work/cyclic_peptide/fep/preflight-1792465588/in"      # precursor PDBs + itp + mdp
DEST="s3://biomate-nextflow-work/cyclic_peptide/fep/avb6-fep-ctrl-build1"        # FEP inputs out (run_id=avb6-fep-ctrl-build1)
SG=sg-0de9af2d4437a8c90
PROFILE=ec2-ecr-builder-profile
SETUP_LOCAL="$(cd "$(dirname "$0")" && pwd)/preflight/build_fep_setup.sh"
# resolve the AL2023 x86_64 AMI live via SSM (never a stale hard-coded id)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region $REGION --query 'Parameter.Value' --output text)
# interchangeable small CPU types (x86_64, ~2xlarge; 4xlarge as last resort) and all us-west-2 AZs
TYPES="c6i.2xlarge c6a.2xlarge c5.2xlarge m6i.2xlarge m5.2xlarge c7i.2xlarge c6i.4xlarge m6i.4xlarge"
AZS="us-west-2a us-west-2b us-west-2c us-west-2d"

# stage the setup script so the box can pull it (same pattern as the preflight script in S3)
aws s3 cp "$SETUP_LOCAL" "$DEST/build_fep_setup.sh" --region $REGION

UD=$(mktemp)
cat > "$UD" <<EOF
#!/bin/bash
exec > /var/log/fepbuild.log 2>&1
set -x
shutdown -h +90
SRC="$SRC"; DEST="$DEST"; REGION="$REGION"
dnf install -y bzip2 tar awscli >/dev/null 2>&1
# micromamba (single static binary) -> /opt/micromamba
cd /opt && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
mv /opt/bin/micromamba /opt/micromamba
export MAMBA_ROOT_PREFIX=/opt/mamba
# setuptools+wheel explicitly in the env so pmx's --no-build-isolation build has its toolchain.
/opt/micromamba create -y -p /opt/fepenv -c conda-forge gromacs python=3.10 pip setuptools wheel numpy matplotlib c-compiler make git >/dev/null 2>&1
eval "\$(/opt/micromamba shell hook -s bash)"
micromamba activate /opt/fepenv
# pmx is installed as a MARKED STAGE inside build_fep_setup.sh (--no-build-isolation) so a failure shows a marker, not a bare exit.
mkdir -p /work && cd /work
aws s3 cp "\$DEST/build_fep_setup.sh" /work/build_fep_setup.sh --region "\$REGION"
SRC="\$SRC" DEST="\$DEST" REGION="\$REGION" bash /work/build_fep_setup.sh > /work/fepbuild_stdout.txt 2>&1
aws s3 cp /work/fepbuild_stdout.txt "\$DEST/fepbuild_stdout.txt" --region "\$REGION"
aws s3 cp /var/log/fepbuild.log "\$DEST/bootstrap.log" --region "\$REGION"
echo DONE > /tmp/DONE; aws s3 cp /tmp/DONE "\$DEST/DONE" --region "\$REGION"
shutdown -h now
EOF

# SPOT-ONLY resilient launch: iterate (type, AZ) until one has spot capacity. NEVER on-demand.
IID=""; LT=""; LAZ=""
set +e
for ty in $TYPES; do
  for az in $AZS; do
    sn=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true Name=availability-zone,Values=$az \
          --region $REGION --query 'Subnets[0].SubnetId' --output text 2>/dev/null)
    [ -z "$sn" ] || [ "$sn" = "None" ] && continue    # no default subnet in this AZ -> skip
    echo "trying spot $ty in $az (subnet $sn) ..."
    OUT=$(aws ec2 run-instances \
      --region $REGION --image-id $AMI --instance-type $ty \
      --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
      --instance-initiated-shutdown-behavior terminate \
      --iam-instance-profile Name=$PROFILE \
      --subnet-id $sn --security-group-ids $SG \
      --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
      --metadata-options '{"HttpTokens":"required","HttpPutResponseHopLimit":2,"HttpEndpoint":"enabled"}' \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=avb6-fep-build},{Key=purpose,Value=fep-input-build-cpu},{Key=autoterminate,Value=90min}]' \
      --user-data "file://$UD" \
      --query 'Instances[0].InstanceId' --output text 2>&1)
    if [ $? -eq 0 ] && [ "${OUT#i-}" != "$OUT" ]; then IID=$OUT; LT=$ty; LAZ=$az; break 2; fi
    if echo "$OUT" | grep -qiE 'InsufficientInstanceCapacity|insufficient capacity|capacity-not-available|SpotMaxPriceTooLow|Unsupported|not supported in your requested Availability Zone'; then
      echo "  no capacity for $ty/$az -> next"; continue
    fi
    echo "FATAL non-capacity error on $ty/$az:"; echo "$OUT"; rm -f "$UD"; exit 2   # don't loop past real errors (auth, quota, bad AMI)
  done
done
set -e
rm -f "$UD"
if [ -z "$IID" ]; then
  echo "NO SPOT CAPACITY across us-west-2 (all types x AZs exhausted) right now — retry later."
  echo "NEVER falling back to on-demand."; exit 1
fi

echo "LAUNCHED instance: $IID  type=$LT az=$LAZ  (spot one-time, self-terminates <=90 min)"
echo "Poll (~15-30 min; conda gromacs + pmx build + both legs):"
echo "  aws s3 cp $DEST/fepbuild_stdout.txt - --region $REGION    # STAGE_*:OK/FAIL markers"
echo "  aws s3 ls $DEST/in/ --region $REGION                       # FEP_INPUTS_READY sentinel = success"
echo "Confirm terminated:"
echo "  aws ec2 describe-instances --instance-ids $IID --region $REGION --query 'Reservations[].Instances[].State.Name' --output text"
echo "Then the agent runs: python3 cyclic_llm/fep_batch.py --submit --run-id=avb6-fep-ctrl-build1"
