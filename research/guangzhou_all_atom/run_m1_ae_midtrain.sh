#!/bin/bash
# =====================================================================================================
# run_m1_ae_midtrain.sh — spot-GPU launcher for the M1 geometry-AE mid-train (Option B), warm-started
# from the epoch-221 linear/protein AE. Multi-hour TRAINING (unlike M0's inference-only afternoon).
#
# Mirrors run_m0_frozen_probe.sh's proven cyclic_peptide spot pattern:
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across the known-good subnet combos
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + a systemd dead-man's-switch that
#     shuts the box down after MAX_RUNTIME even if the driver hangs
#   * heartbeat + CHECKPOINT STREAMING to S3 (added for training): every 60s the status dir AND the
#     ckpts dir are synced to S3, so a spot interruption keeps all checkpoints written so far. On boot
#     the driver RESUMES the dataset build if the mmap already exists in S3 (skips the CPU re-embed).
#
# Pipeline on the instance:  fetch code+data -> prep_cremp_dataset.py (CPU) -> m1_train_ae.py (GPU)
#                            -> m1_eval.py (GPU) -> stream everything to S3.
#
# It launches ONE spot GPU instance and nothing else.
# Poll:   aws s3 cp $S3RUN/status/status.json -
# Ckpts:  aws s3 ls $S3RUN/ckpts/ --recursive
# Result: aws s3 cp $S3RUN/m1_eval_result.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=knowledge-datasets-1759951976   # S3 bucket lives in us-west-2; cross-region reads work (small transfer cost)
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04); region-specific => OVERRIDE per region
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key (region-specific); set KEY="" to omit (instance is autonomous)

# --- inputs (env-overridable) ------------------------------------------------------------------------
WARM_CKPT_S3=${WARM_CKPT_S3:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
CREMP_S3=${CREMP_S3:-s3://$BUCKET/cyclic_peptide/datasets/cremp_partial}
# training knobs (passed to the config via overwrite_values / to prep as CLI)
MAX_CONFS_PER_MOL=${MAX_CONFS_PER_MOL:-8}
MAX_TRAIN_MOLS=${MAX_TRAIN_MOLS:-6000}   # cap the CPU embed + keep an epoch reasonable; raise for full CREMP
MAX_VAL_MOLS=${MAX_VAL_MOLS:-400}
MAX_TEST_MOLS=${MAX_TEST_MOLS:-300}      # matches M0's 300 held-out for eval parity
MAX_EPOCH=${MAX_EPOCH:-40}
LR=${LR:-2.0e-5}
RING_CLOSURE_LOSS_WEIGHT=${RING_CLOSURE_LOSS_WEIGHT:-0.3}
MAX_RUNTIME=${MAX_RUNTIME:-10h}          # multi-hour training; dead-man's-switch cap

RUNID=m1-ae-midtrain-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
for f in prep_cremp_dataset.py m1_peptide_dataset.py m1_closure_ae.py m1_train_ae.py m1_eval.py \
         m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py m1_ae_midtrain.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  prep_cremp_dataset.py m1_peptide_dataset.py m1_closure_ae.py m1_train_ae.py m1_eval.py \
  m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py m1_ae_midtrain.yaml pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  WARM_CKPT_S3=$WARM_CKPT_S3"
echo "  CREMP_S3=$CREMP_S3  MAX_TRAIN_MOLS=$MAX_TRAIN_MOLS  MAX_CONFS_PER_MOL=$MAX_CONFS_PER_MOL"
echo "  MAX_EPOCH=$MAX_EPOCH LR=$LR RING_CLOSURE_LOSS_WEIGHT=$RING_CLOSURE_LOSS_WEIGHT MAX_RUNTIME=$MAX_RUNTIME"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "$TMP/driver.sh" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data" "$ROOT/ckpts"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  # stream checkpoints so a spot interruption keeps everything written so far
  [ -d "$ROOT/ckpts" ] && aws s3 sync "$ROOT/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true
  [ -f "$ROOT/m1_eval_result.json" ] && aws s3 cp "$ROOT/m1_eval_result.json" "$OUT_S3/m1_eval_result.json" --only-show-errors || true
  [ -f "$ROOT/data/cremp_pepglad/manifest.json" ] && aws s3 cp "$ROOT/data/cremp_pepglad/manifest.json" "$OUT_S3/dataset_manifest.json" --only-show-errors || true
}
finish() {
  rc=$?
  trap - EXIT
  [ "$rc" -ne 0 ] && stage failed || true
  sync_all
  shutdown -h now
  exit "$rc"
}
trap finish EXIT

# periodic heartbeat + checkpoint stream (every 60s) + best-effort spot-interruption capture
(while sleep 60; do sync_all; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json"; then
    stage spot_interruption; sync_all; break
  fi
done) >/dev/null 2>&1 &

stage installing
for attempt in 1 2 3 4 5 6; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; [ "$attempt" = 6 ] && exit 1; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install --disable-pip-version-check 'pip==25.0.1'
pip install 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
# networkx REQUIRED (cycpeptmpdb_to_pepglad._identify_residue uses VF2); sympy REQUIRED
# (DynamicBatchWrapper); tensorboard REQUIRED (abs_trainer SummaryWriter). None are in the base image.
pip install 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' \
            'tqdm==4.67.1' 'networkx==3.2.1' 'sympy==1.13.3' 'tensorboard==2.18.0' 'boto3>=1.36,<2'
pip freeze > "$ROOT/status/environment.txt"
python -c 'import torch,torch_scatter,rdkit,networkx,sympy,Bio,tensorboard; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_data
aws s3 cp "$WARM_CKPT_S3" "$ROOT/data/epoch221.ckpt" --only-show-errors
mkdir -p "$ROOT/data/cremp"
aws s3 cp "$CREMP_S3/summary.csv"          "$ROOT/data/cremp/summary.csv" --only-show-errors
aws s3 cp "$CREMP_S3/sdf_and_json.tar.bz2" "$ROOT/data/cremp/sdf_and_json.tar.bz2" --only-show-errors

cd "$ROOT/code"

# ---- resume-aware dataset build: reuse a prebuilt mmap from S3 if present (skips CPU re-embed) ----
stage building_dataset
if aws s3 ls "$OUT_S3/dataset/train/index.txt" >/dev/null 2>&1; then
  echo "found prebuilt dataset in S3 -> reusing (spot-resume)"
  mkdir -p "$ROOT/data/cremp_pepglad"
  aws s3 sync "$OUT_S3/dataset" "$ROOT/data/cremp_pepglad" --only-show-errors
else
  python prep_cremp_dataset.py \
    --cremp-dir "$ROOT/data/cremp" \
    --out-dir   "$ROOT/data/cremp_pepglad" \
    --max-confs-per-mol "$MAX_CONFS_PER_MOL" \
    --max-train-mols "$MAX_TRAIN_MOLS" --max-val-mols "$MAX_VAL_MOLS" --max-test-mols "$MAX_TEST_MOLS"
  # persist the built dataset so a later spot re-launch resumes without re-embedding
  aws s3 sync "$ROOT/data/cremp_pepglad" "$OUT_S3/dataset" --only-show-errors || true
fi

stage training
# overwrite_values consumes key=value opt-args; point the config at the fetched paths + the run knobs.
# overwrite_values wants --dotted.key=value opt-args (leading -- required; '.' nests; value cast to the
# YAML value's existing type). Every path below already exists in m1_ae_midtrain.yaml.
python m1_train_ae.py --gpus 0 --config m1_ae_midtrain.yaml \
  --warm_start_ckpt="$ROOT/data/epoch221.ckpt" \
  --dataset.train.mmap_dir="$ROOT/data/cremp_pepglad/train" \
  --dataset.valid.mmap_dir="$ROOT/data/cremp_pepglad/valid" \
  --trainer.config.save_dir="$ROOT/ckpts/m1_ae_midtrain" \
  --trainer.config.max_epoch="$MAX_EPOCH" \
  --trainer.config.optimizer.lr="$LR" \
  --model.ring_closure_loss_weight="$RING_CLOSURE_LOSS_WEIGHT"
sync_all

stage evaluating
# pick the best (lowest val-loss) checkpoint = last line's path in topk_map.txt is worst; first is best.
BEST_CKPT=$(head -1 "$ROOT/ckpts/m1_ae_midtrain"/version_*/checkpoint/topk_map.txt 2>/dev/null | sed 's/^[^:]*: //' || true)
if [ -z "$BEST_CKPT" ] || [ ! -f "$BEST_CKPT" ]; then
  BEST_CKPT=$(ls -t "$ROOT/ckpts/m1_ae_midtrain"/version_*/checkpoint/epoch*.ckpt 2>/dev/null | head -1 || true)
fi
echo "eval checkpoint: $BEST_CKPT"
if [ -n "$BEST_CKPT" ]; then
  python m1_eval.py \
    --m1-ckpt "$BEST_CKPT" \
    --baseline-ckpt "$ROOT/data/epoch221.ckpt" \
    --cremp-dir "$ROOT/data/cremp" \
    --n-test-mols "$MAX_TEST_MOLS" --gpu 0 --out "$ROOT/m1_eval_result.json"
  cp "$ROOT/m1_eval_result.json" "$ROOT/status/m1_eval_result.json" 2>/dev/null || true
else
  echo '{"status":"error","error":"no checkpoint produced"}' > "$ROOT/m1_eval_result.json"
fi
stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
# DEAD-MAN'S-SWITCH (first thing to run): guarantee the box dies even if everything below hangs.
systemd-run --unit=m1-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +600 &
exec > /var/log/m1-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN WARM_CKPT_S3=$WARM_CKPT_S3 CREMP_S3=$CREMP_S3 \
  MAX_CONFS_PER_MOL=$MAX_CONFS_PER_MOL MAX_TRAIN_MOLS=$MAX_TRAIN_MOLS MAX_VAL_MOLS=$MAX_VAL_MOLS \
  MAX_TEST_MOLS=$MAX_TEST_MOLS MAX_EPOCH=$MAX_EPOCH LR=$LR \
  RING_CLOSURE_LOSS_WEIGHT=$RING_CLOSURE_LOSS_WEIGHT MAX_RUNTIME=$MAX_RUNTIME \
  bash /opt/guangzhou-peptide/driver.sh
EOF
)

declare -a COMBO=(
  "g5.xlarge subnet-0254e4c3634b41bfc"
  "g5.xlarge subnet-03b277a7a08d388c1"
  "g5.xlarge subnet-09e4dce46682a6c60"
  "g6.xlarge subnet-0b35a6e2c1cf02dc2"
  "g6.xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  # broadened net (M1 model is tiny — a T4 is plenty; add cheaper/older families across AZs)
  "g4dn.xlarge subnet-0254e4c3634b41bfc"
  "g4dn.xlarge subnet-03b277a7a08d388c1"
  "g4dn.xlarge subnet-09e4dce46682a6c60"
  "g4dn.xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-09e4dce46682a6c60"
)
# Region override: pass COMBO_OVERRIDE as newline-separated "TYPE SUBNET" pairs (for cross-region launches).
if [ -n "${COMBO_OVERRIDE:-}" ]; then
  mapfile -t COMBO <<< "$COMBO_OVERRIDE"
fi
IID=""
for c in "${COMBO[@]}"; do
  set -- $c; TYPE=$1; SUBNET=$2
  echo "trying $TYPE in $SUBNET ..."
  IID=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type "$TYPE" ${KEY:+--key-name $KEY} \
    --subnet-id "$SUBNET" --security-group-ids "$SG" \
    --iam-instance-profile Name=AutoimmuneCorpusProfile \
    --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
    --instance-initiated-shutdown-behavior terminate \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:   aws s3 cp $S3RUN/status/status.json -"
echo "ckpts:  aws s3 ls $S3RUN/ckpts/ --recursive"
echo "result: aws s3 cp $S3RUN/m1_eval_result.json -"
