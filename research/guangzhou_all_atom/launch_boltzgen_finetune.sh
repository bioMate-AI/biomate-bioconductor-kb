#!/bin/bash
# launch_boltzgen_finetune.sh — Path-A BoltzGen cyclic fine-tune pipeline (SMOKE-gated).
# MODE=introspect : install boltzgen, download targets.zip/mols/ckpt, run boltzgen_introspect.py
#                   to PIN the Record/Manifest/config construction. (cheap; no training)
# MODE=smoke      : run --batch on a small subset + main.py max_steps=10 (added after introspect pins the API).
# Spot-first, self-terminating (shutdown=terminate + dead-man's-switch), streams to S3. ONE GPU instance.
set -Eeuo pipefail
REGION=${REGION:-us-west-2}; export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04) us-west-2 (CUDA drivers + awscli)
SG=${SG:-sg-011121fdf81073ec8}; KEY=${KEY:-biomate-trial-resume-20260912}
MODE=${MODE:-introspect}
MAX_RUNTIME=${MAX_RUNTIME:-1h}
RUNID=bgen-ft-${MODE}-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# ship our scripts
aws s3 cp "$HERE/boltzgen_introspect.py" "$S3RUN/code/boltzgen_introspect.py" --only-show-errors
aws s3 cp "$HERE/boltzgen_cyclic_convert.py" "$S3RUN/code/boltzgen_cyclic_convert.py" --only-show-errors
echo "shipped code -> $S3RUN/code/ (MODE=$MODE)"

cat > "/tmp/bgenft_driver.$$" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/bgenft; mkdir -p "$ROOT/status" "$ROOT/code"; cd "$ROOT"
exec > >(tee -a "$ROOT/status/boot.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed || stage done_rc0; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit "$rc"; }
trap finish EXIT
(while sleep 60; do aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; done) &

stage installing
for a in 1 2 3 4 5; do aws s3 cp "$OUT_S3/code/boltzgen_introspect.py" "$ROOT/code/" --only-show-errors && aws s3 cp "$OUT_S3/code/boltzgen_cyclic_convert.py" "$ROOT/code/" --only-show-errors && break; sleep 8; done
# conda base python has pip; install boltzgen from source (editable) + hf hub
git clone --depth 1 https://github.com/HannesStark/boltzgen "$ROOT/boltzgen" 2>&1 | tail -3
cd "$ROOT/boltzgen"
python -m pip install -q -e ".[dev]" 2>&1 | tail -8 || { echo "FATAL: boltzgen install failed"; exit 1; }
python -m pip install -q "huggingface_hub[cli]" pyyaml 2>&1 | tail -2
python -c "import boltzgen, torch; print('boltzgen ok; cuda', torch.cuda.is_available())"

stage fetching_data
mkdir -p "$ROOT/dl"; cd "$ROOT/dl"
# CCD mols (required by parse_mmcif)
huggingface-cli download boltzgen/inference-data mols.zip --repo-type dataset --local-dir . 2>&1 | tail -2 || true
[ -f mols.zip ] && { mkdir -p mols && unzip -q -o mols.zip -d mols && echo "mols: $(ls mols | wc -l) files"; } || echo "WARN: mols.zip not fetched"
# shipped training targets (to introspect Record/Manifest construction) + fold ckpt + small ckpt
huggingface-cli download boltzgen/boltzgen1_train targets.zip --repo-type dataset --local-dir . 2>&1 | tail -2 || true
[ -f targets.zip ] && { mkdir -p shipped && unzip -q -o targets.zip -d shipped && echo "shipped targets: $(find shipped -maxdepth 3 -name manifest.json | head -1)"; } || echo "WARN: targets.zip not fetched"

stage "running_${MODE}"
CFG="$ROOT/boltzgen/src/boltzgen/resources/config/train/boltzgen_small.yaml"
SHIPPED_TARGETS=$(dirname "$(find "$ROOT/dl/shipped" -maxdepth 4 -name manifest.json 2>/dev/null | head -1)")
echo "SHIPPED_TARGETS=$SHIPPED_TARGETS  CFG=$CFG"
if [ "$MODE" = "introspect" ]; then
  python "$ROOT/code/boltzgen_introspect.py" "${SHIPPED_TARGETS:-$ROOT/dl/shipped}" "$CFG" 2>&1 | tee "$ROOT/status/introspect.txt"
  aws s3 cp "$ROOT/status/introspect.txt" "$OUT_S3/status/introspect.txt" --only-show-errors || true
fi
stage complete
echo "=== $MODE DONE -> $OUT_S3/status/ ==="
DRIVER
aws s3 cp "/tmp/bgenft_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors; rm -f "/tmp/bgenft_driver.$$"

UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=bgenft-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +75 &
exec > /var/log/bgenft-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/bgenft/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/bgenft/driver.sh && break; sleep 10; done
chmod +x /opt/bgenft/driver.sh
OUT_S3=$S3RUN MODE=$MODE bash /opt/bgenft/driver.sh
EOF
)

declare -a COMBO=(
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g5.2xlarge subnet-09e4dce46682a6c60"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2" "g5.2xlarge subnet-03b277a7a08d388c1"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
)
[ -n "${COMBO_OVERRIDE:-}" ] && mapfile -t COMBO <<< "$COMBO_OVERRIDE"
try(){ local mode=$1 c T S opt; for c in "${COMBO[@]}"; do set -- $c; T=$1; S=$2
  [ "$mode" = spot ] && opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}') || opt=()
  IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$T" ${KEY:+--key-name $KEY} \
    --subnet-id "$S" --security-group-ids "$SG" --iam-instance-profile Name=AutoimmuneCorpusProfile \
    "${opt[@]}" --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
    --user-data "$UD" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $T $S -> $IID"; return 0; }
  echo "  no capacity ($T $S)"; done; return 1; }
IID=""; try spot || { echo "spot exhausted -> on-demand"; try ondemand; } || true
[ -z "$IID" ] && { echo "FATAL: no GPU capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll: aws s3 cp $S3RUN/status/status.json -"
echo "introspect: aws s3 cp $S3RUN/status/introspect.txt -"
