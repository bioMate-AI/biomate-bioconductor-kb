#!/bin/bash
# Launch the property-conditioned cyclic-peptide SMILES LLM (MVP) on AWS spot (self-terminating).
# MODE=smoke : ~2000-row subset, ~300 steps, 50 samples (fast sanity: loss down + valid SMILES).
# MODE=full  : full CycPeptMPDB + binding_affinity_v1 cyclic, ~3000 steps, 200 samples + conditioning eval.
set -Eeuo pipefail
REGION=${REGION:-us-west-2}; export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}   # DL Base OSS Nvidia GPU AMI (CUDA drivers + awscli)
SG=${SG:-sg-011121fdf81073ec8}; KEY=${KEY:-biomate-trial-resume-20260912}
MODE=${MODE:-smoke}; MAX_RUNTIME=${MAX_RUNTIME:-3h}
RUNID=cyclic-llm-${MODE}-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)
aws s3 cp "$HERE/train_cyclic_llm.py" "$S3RUN/code/train_cyclic_llm.py" --only-show-errors
echo "shipped -> $S3RUN/code/ (MODE=$MODE)"

cat > "/tmp/cllm_driver.$$" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 PYTHONUNBUFFERED=1
ROOT=/opt/cllm; mkdir -p "$ROOT/status" "$ROOT/dl"; cd "$ROOT"
exec > >(tee -a "$ROOT/status/boot.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed || stage complete; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit "$rc"; }
trap finish EXIT
(while sleep 60; do aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; done) &

stage installing
source /opt/miniconda/etc/profile.d/conda.sh 2>/dev/null || { curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh && bash /tmp/mc.sh -b -p /opt/miniconda && source /opt/miniconda/etc/profile.d/conda.sh; }
conda create -y -n cllm python=3.11 >/dev/null 2>&1; conda activate cllm
pip install -q torch numpy pandas scikit-learn rdkit 2>&1 | tail -2
python -c "import torch,rdkit,sklearn,pandas;print('env ok cuda',torch.cuda.is_available(),torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu')"

stage fetching_data
aws s3 cp "s3://BUCKETPH/cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv" "$ROOT/dl/cyc.csv" --only-show-errors
aws s3 cp "s3://BUCKETPH/cyclic_peptide/datasets/binding_affinity_v1/binding_affinity_v1.csv" "$ROOT/dl/bind.csv" --only-show-errors
aws s3 cp "$OUT_S3/code/train_cyclic_llm.py" "$ROOT/train_cyclic_llm.py" --only-show-errors
if [ "$MODE" = "smoke" ]; then
  head -2000 "$ROOT/dl/cyc.csv" > "$ROOT/dl/cyc_s.csv"; head -2000 "$ROOT/dl/bind.csv" > "$ROOT/dl/bind_s.csv"
  CYC="$ROOT/dl/cyc_s.csv"; BIND="$ROOT/dl/bind_s.csv"; STEPS=300; NS=50
else
  CYC="$ROOT/dl/cyc.csv"; BIND="$ROOT/dl/bind.csv"; STEPS=${STEPS:-3000}; NS=200
fi

stage build_data
python "$ROOT/train_cyclic_llm.py" build-data --cyc "$CYC" --bind "$BIND" --out "$ROOT/data.jsonl" 2>&1 | tee "$ROOT/status/build.log"
aws s3 cp "$ROOT/status/build.log" "$OUT_S3/status/build.log" --only-show-errors || true

stage training
python "$ROOT/train_cyclic_llm.py" train --data "$ROOT/data.jsonl" --out-ckpt "$ROOT/cyclic_llm.pt" --max-steps "$STEPS" 2>&1 | tee "$ROOT/status/train.log"
aws s3 cp "$ROOT/status/train.log" "$OUT_S3/status/train.log" --only-show-errors || true

stage evaluating
python "$ROOT/train_cyclic_llm.py" eval --ckpt "$ROOT/cyclic_llm.pt" --data "$ROOT/data.jsonl" --n-sample "$NS" --out "$ROOT/status/eval.json" 2>&1 | tee "$ROOT/status/eval.log"
aws s3 cp "$ROOT/status/eval.json" "$OUT_S3/status/eval.json" --only-show-errors || true
aws s3 cp "$ROOT/status/eval.log" "$OUT_S3/status/eval.log" --only-show-errors || true

stage uploading_ckpt
aws s3 cp "$ROOT/cyclic_llm.pt" "$OUT_S3/ckpt/cyclic_llm.pt" --only-show-errors && echo "CKPT -> $OUT_S3/ckpt/cyclic_llm.pt"
echo "=== CLLM $MODE DONE ==="
DRIVER
sed -i.bak "s/BUCKETPH/$BUCKET/g" "/tmp/cllm_driver.$$" && rm -f "/tmp/cllm_driver.$$.bak"
aws s3 cp "/tmp/cllm_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors; rm -f "/tmp/cllm_driver.$$"

UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=cllm-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +180 &
exec > /var/log/cllm-boot.log 2>&1
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/cllm
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/cllm/driver.sh && break; sleep 10; done
chmod +x /opt/cllm/driver.sh
OUT_S3=$S3RUN MODE=$MODE STEPS=${STEPS:-} bash /opt/cllm/driver.sh
EOF
)
declare -a COMBO=(
  "g5.xlarge subnet-0254e4c3634b41bfc" "g5.xlarge subnet-09e4dce46682a6c60" "g6.xlarge subnet-0b35a6e2c1cf02dc2"
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g4dn.xlarge subnet-0254e4c3634b41bfc" "g4dn.xlarge subnet-03b277a7a08d388c1"
)
[ -n "${COMBO_OVERRIDE:-}" ] && mapfile -t COMBO <<< "$COMBO_OVERRIDE"
try(){ local mode=$1 c T S opt; for c in "${COMBO[@]}"; do set -- $c; T=$1; S=$2
  [ "$mode" = spot ] && opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}') || opt=()
  IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$T" ${KEY:+--key-name $KEY} \
    --subnet-id "$S" --security-group-ids "$SG" --iam-instance-profile Name=AutoimmuneCorpusProfile \
    "${opt[@]}" --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]' \
    --user-data "$UD" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $T $S -> $IID"; return 0; }
  echo "  no capacity ($T $S)"; done; return 1; }
IID=""; try spot || { echo "spot exhausted -> on-demand"; try ondemand; } || true
[ -z "$IID" ] && { echo "FATAL: no GPU capacity"; exit 1; }
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll: aws s3 cp $S3RUN/status/status.json -"
echo "eval: aws s3 cp $S3RUN/status/eval.json -"
