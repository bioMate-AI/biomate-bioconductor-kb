#!/bin/bash
# Launch ONE spot job for workstream K. All compute runs on EC2, never on the laptop.
# usage: launch_job.sh NAME "python3 script.py args..." [PIP_PACKAGES] [INSTANCE_TYPE] [WALL_MINUTES]
# Stages ./ (this directory: *.py *.txt *.json *.md) to s3://.../allatom/k/<run-id>/code, boots a spot instance
# (ecsInstanceRole, SG sg-0de9af2d4437a8c90, 40 GB gp3 on /dev/xvda, tags project=cyclic-selector,Name=allatom-k-<NAME>),
# runs the command, uploads /w/out to <prefix>/out, writes done.flag, shuts down (terminate-on-shutdown). One writer per prefix.
set -u
NAME="$1"; CMD="$2"; PIPS="${3:-}"; ITYPE="${4:-c6i.large}"; WALL="${5:-90}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RID="k_${NAME}_$(date +%Y%m%d_%H%M%S)"
P="s3://biomate-nextflow-work/cyclic_peptide/allatom/k/${RID}"
STAGE="${TMPDIR:-/tmp}/${RID}_stage"; mkdir -p "$STAGE"
cp "$HERE"/*.py "$HERE"/*.txt "$STAGE"/ 2>/dev/null; cp "$HERE"/*.json "$STAGE"/ 2>/dev/null
# the directory above (allatom_paper/) is needed by the loader tests: stage contracts and harness too
cp "$HERE"/../contracts.py "$HERE"/../pmo_harness.py "$STAGE"/ 2>/dev/null
[ -f "$HERE"/../track_e/source_groups.json ] && cp "$HERE"/../track_e/source_groups.json "$STAGE"/
[ -f "$HERE"/../track_e/source_groups_v2.json ] && cp "$HERE"/../track_e/source_groups_v2.json "$STAGE"/
for F in ${EXTRA_FILES:-}; do cp "$F" "$STAGE"/; done
aws s3 cp "$STAGE" "$P/code/" --recursive --only-show-errors --cli-read-timeout 60 --cli-connect-timeout 10 || { echo "code upload failed"; exit 2; }
UD="$STAGE/userdata.sh"
cat > "$UD" <<EOF
#!/bin/bash
P=$P
shutdown -h +$WALL
mkdir -p /w/code /w/out; cd /w
exec >/w/boot.log 2>&1
( while true; do aws s3 cp /w/boot.log \$P/logs/boot.log --only-show-errors; [ -f /w/job.log ] && aws s3 cp /w/job.log \$P/logs/job.log --only-show-errors; sleep 20; done ) &
aws s3 cp \$P/code/ /w/code --recursive --only-show-errors
if [ -n "$PIPS" ]; then dnf install -y python3.11 python3.11-pip gcc >/dev/null 2>&1; python3.11 -m pip install -q $PIPS; fi
cd /w/code
export OUT=/w/out
if [ -n "$PIPS" ]; then CMD11=\$(echo "$CMD" | sed 's/^python3 /python3.11 /'); else CMD11="$CMD"; fi
eval "\$CMD11" > /w/job.log 2>&1; rc=\$?
echo "rc=\$rc" >> /w/job.log
aws s3 cp /w/out \$P/out --recursive --only-show-errors
echo \$rc > /w/done.flag; aws s3 cp /w/done.flag \$P/done.flag --only-show-errors
aws s3 cp /w/job.log \$P/logs/job.log --only-show-errors
shutdown -h now
EOF
for T in $ITYPE c6i.large c5.large m6i.large; do
  for SUB in subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1 subnet-09e4dce46682a6c60 subnet-0254e4c3634b41bfc; do
    IID=$(aws ec2 run-instances --image-id ami-0829b74b2a8c619b7 --instance-type "$T" --subnet-id "$SUB" \
      --security-group-ids sg-0de9af2d4437a8c90 --iam-instance-profile Name=ecsInstanceRole \
      --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]' \
      --user-data "file://$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=allatom-k-$NAME},{Key=project,Value=cyclic-selector}]" \
      --query 'Instances[0].InstanceId' --output text --cli-read-timeout 60 --cli-connect-timeout 10 2>/dev/null) && [ -n "$IID" ] && {
        echo "RUN_ID=$RID"; echo "INSTANCE=$IID TYPE=$T SUBNET=$SUB"; echo "PREFIX=$P"
        echo "$(date -u +%FT%TZ) $RID $IID $T" >> "$HERE/cost_log_k.txt"; exit 0; }
  done
done
echo "NO CAPACITY"; exit 1
