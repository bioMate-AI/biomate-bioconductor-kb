#!/bin/bash
# =====================================================================================================
# launch_d2_mine.sh — scale the EXPERIMENTAL bound-cyclic-complex corpus (the M2c bottleneck).
# Runs mine_bound_cyclic_complexes.py at scale on a CPU SPOT instance (no GPU): queries the RCSB
# candidate pool (<= --max-pep-len bound short peptides), coordinate-detects cyclization, and streams
# a provenance-tagged manifest (JSONL + PepGLAD index) to S3. This grows the ~235-entry bound_cyclic_v1
# toward the 1-2k target. Processing (m2c_process_complexes.py -> mmap) + M2c retrain are the GPU steps
# that consume this output afterward.
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + systemd dead-man's-switch
#   * heartbeat + manifest STREAMING to S3 every 60s (interruption-safe: partial manifest is kept)
# Poll:     aws s3 cp $S3RUN/status/status.json -
# Manifest: aws s3 cp $S3RUN/bound_cyclic_v2/bound_cyclic_manifest.jsonl -
# =====================================================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04678417fc39d7171            # Ubuntu 24.04 noble amd64 (same as the mmgbsa CPU launcher)
KEY=biomate-trial-resume-20260912
SG=sg-011121fdf81073ec8
MAX_PEP_LEN=${MAX_PEP_LEN:-16}
LIMIT=${LIMIT:-13000}                 # cap on coord downloads; ~12.4k candidates at <=16 res
ROWS=${ROWS:-16000}                   # RCSB page rows to enumerate
SLEEP=${SLEEP:-0.12}
MAX_RUNTIME=${MAX_RUNTIME:-6h}
RUNID=d2-mine-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

aws s3 cp "$HERE/mine_bound_cyclic_complexes.py" "$S3RUN/code/mine_bound_cyclic_complexes.py" --only-show-errors
echo "uploaded mine code -> $S3RUN/code/"

UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=mine-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +360 &
exec > /var/log/d2-mine-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/d2-mine; mkdir -p "\$ROOT/status" "\$ROOT/code"
stage(){ printf '{"stage":"%s","time":"%s"}\n' "\$1" "\$(date -u +%FT%TZ)" > "\$ROOT/status/status.json"; aws s3 sync "\$ROOT/status" "$S3RUN/status/" --only-show-errors || true; }
sync_all(){ aws s3 sync "\$ROOT/status" "$S3RUN/status/" --only-show-errors || true; [ -d "\$ROOT/out" ] && aws s3 sync "\$ROOT/out" "$S3RUN/bound_cyclic_v2/" --only-show-errors || true; }
trap 'rc=\$?; [ \$rc -ne 0 ] && stage failed; sync_all; shutdown -h now; exit \$rc' EXIT
for i in 1 2 3 4 5; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq unzip curl python3-venv python3-pip python3-dev build-essential
command -v aws >/dev/null 2>&1 || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install); }
python3 -m venv "\$ROOT/venv"; source "\$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
# biopython>=1.83 has cp312 wheels (1.80 compiles from source on Ubuntu 24.04/py3.12 -> needs the build deps above)
pip install -q 'gemmi>=0.6.6' 'biopython>=1.83' 'requests>=2.31' 'boto3>=1.36,<2'
aws s3 cp "$S3RUN/code/mine_bound_cyclic_complexes.py" "\$ROOT/code/mine.py" --only-show-errors
(while sleep 60; do sync_all; done) &
stage mining
python "\$ROOT/code/mine.py" --max-pep-len ${MAX_PEP_LEN} --limit ${LIMIT} --rows ${ROWS} --sleep ${SLEEP} --out-dir "\$ROOT/out" 2>&1 | tail -50
stage done
sync_all
EOF
)

# CPU spot with AZ/type fallback (mirror the GPU fallback ladder, CPU types)
declare -a COMBO=(
  "c6i.2xlarge subnet-09e4dce46682a6c60"
  "c6i.2xlarge subnet-0254e4c3634b41bfc"
  "c6i.4xlarge subnet-09e4dce46682a6c60"
  "c5.2xlarge subnet-0254e4c3634b41bfc"
  "c6a.2xlarge subnet-09e4dce46682a6c60"
  "m6i.2xlarge subnet-0254e4c3634b41bfc"
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
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), next"
done
[ -z "$IID" ] && { echo "FATAL: no CPU spot capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:     aws s3 cp $S3RUN/status/status.json -"
echo "manifest: aws s3 cp $S3RUN/bound_cyclic_v2/bound_cyclic_manifest.jsonl -"
