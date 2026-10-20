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
AMI=ami-0803a33fd43db1fbf
SUBNET=subnet-0254e4c3634b41bfc
SG=sg-0de9af2d4437a8c90
PROFILE=ec2-ecr-builder-profile
SETUP_LOCAL="$(cd "$(dirname "$0")" && pwd)/preflight/build_fep_setup.sh"

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
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=avb6-fep-build},{Key=purpose,Value=fep-input-build-cpu},{Key=autoterminate,Value=90min}]' \
  --user-data "file://$UD" \
  --query 'Instances[0].InstanceId' --output text)
rm -f "$UD"

echo "LAUNCHED instance: $IID  (spot c6i.2xlarge, self-terminates <=90 min)"
echo "Poll (~15-30 min; conda gromacs + pmx build + both legs):"
echo "  aws s3 cp $DEST/fepbuild_stdout.txt - --region $REGION    # STAGE_*:OK/FAIL markers"
echo "  aws s3 ls $DEST/in/ --region $REGION                       # FEP_INPUTS_READY sentinel = success"
echo "Confirm terminated:"
echo "  aws ec2 describe-instances --instance-ids $IID --region $REGION --query 'Reservations[].Instances[].State.Name' --output text"
echo "Then the agent runs: python3 cyclic_llm/fep_batch.py --submit --run-id=avb6-fep-ctrl-build1"
