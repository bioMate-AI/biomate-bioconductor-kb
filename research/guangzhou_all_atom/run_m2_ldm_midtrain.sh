#!/bin/bash
# =====================================================================================================
# run_m2_ldm_midtrain.sh — spot-GPU launcher for M2 stage-2b: cyclic mid-train of the PepGLAD LATENT-
# DIFFUSION generator over the v1-AE latent, warm-started from the epoch-221 diffusion. Multi-hour TRAINING.
#
# Mirrors run_m1_ae_midtrain.sh's proven cyclic_peptide spot pattern:
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across the known-good subnet combos (COMBO_OVERRIDE for cross-region)
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + a systemd dead-man's-switch that
#     shuts the box down after MAX_RUNTIME even if the driver hangs
#   * heartbeat + CHECKPOINT STREAMING to S3 every 60s (spot-interruption keeps all ckpts written so far);
#     resume-aware dataset build (reuse the prebuilt CREMP mmap from S3, skip the CPU re-embed)
#
# WHAT'S DIFFERENT vs M1 (the generator, not the AE):
#   * TWO warm-start inputs: (a) the epoch-221 LDM (its DIFFUSION is warm-started; its AE is dropped),
#     and (b) the M1 v1 AE (epoch39_step3520.ckpt) which becomes the FROZEN autoencoder of the LDM.
#   * Entrypoint m2_train_ldm.py + config m2_ldm_midtrain.yaml + eval m2_eval.py (unconditional 2b panel).
#   * ubound 12000 + PYTORCH_CUDA_ALLOC_CONF=expandable_segments (set in m2_train_ldm.py) — same OOM fix.
#
# Pipeline on the instance:  fetch code+data -> prep_cremp_dataset.py (CPU, reuse M1 mmap if present) ->
#                            m2_train_ldm.py (GPU) -> m2_eval.py (GPU) -> stream everything to S3.
#
# It launches ONE spot GPU instance and nothing else.
# Poll:   aws s3 cp $S3RUN/status/status.json -
# Ckpts:  aws s3 ls $S3RUN/ckpts/ --recursive
# Result: aws s3 cp $S3RUN/m2_eval_result.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=knowledge-datasets-1759951976   # S3 bucket lives in us-west-2; cross-region reads work
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04); region-specific => OVERRIDE per region
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit (instance is autonomous)

# --- inputs (env-overridable) ------------------------------------------------------------------------
# (a) epoch-221 LDM -> warm-start the DIFFUSION (its .autoencoder is dropped in m2_train_ldm.warm_start_diffusion)
WARM_LDM_S3=${WARM_LDM_S3:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
# (b) M1 v1 AE (production AE) -> becomes the FROZEN autoencoder of the LDM
V1_AE_S3=${V1_AE_S3:-s3://$BUCKET/cyclic_peptide/runs/m1-ae-midtrain-20260928T225554Z/ckpts/m1_ae_midtrain/version_0/checkpoint/epoch39_step3520.ckpt}
CREMP_S3=${CREMP_S3:-s3://$BUCKET/cyclic_peptide/datasets/cremp_partial}
# OPTIONAL: reuse the exact CREMP mmap the M1 run built (identical split) — skips the CPU re-embed entirely.
M1_DATASET_S3=${M1_DATASET_S3:-s3://$BUCKET/cyclic_peptide/runs/m1-ae-midtrain-20260928T225554Z/dataset}

# training knobs (passed to the config via overwrite_values / to prep as CLI)
MAX_CONFS_PER_MOL=${MAX_CONFS_PER_MOL:-8}
MAX_TRAIN_MOLS=${MAX_TRAIN_MOLS:-6000}   # match M1's embed budget; raise for full CREMP
MAX_VAL_MOLS=${MAX_VAL_MOLS:-400}
MAX_TEST_MOLS=${MAX_TEST_MOLS:-100}      # 2b eval samples N per mol -> keep test set modest (sampling is slow)
N_SAMPLES=${N_SAMPLES:-8}                # unconditional samples per length-slot (diversity/consistency need >=2)
MAX_EPOCH=${MAX_EPOCH:-60}
LR=${LR:-2.0e-5}
MAX_RUNTIME=${MAX_RUNTIME:-12h}          # LDM training + per-val-epoch sampling is slower than the AE; larger cap

RUNID=m2-ldm-midtrain-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
for f in prep_cremp_dataset.py m1_peptide_dataset.py m1_closure_ae.py m2_peptide_ldm.py m2_train_ldm.py \
         m2_eval.py m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py m2_ldm_midtrain.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  prep_cremp_dataset.py m1_peptide_dataset.py m1_closure_ae.py m2_peptide_ldm.py m2_train_ldm.py \
  m2_eval.py m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py m2_ldm_midtrain.yaml pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  WARM_LDM_S3=$WARM_LDM_S3"
echo "  V1_AE_S3=$V1_AE_S3"
echo "  CREMP_S3=$CREMP_S3  M1_DATASET_S3=$M1_DATASET_S3"
echo "  MAX_TRAIN_MOLS=$MAX_TRAIN_MOLS MAX_EPOCH=$MAX_EPOCH LR=$LR N_SAMPLES=$N_SAMPLES MAX_RUNTIME=$MAX_RUNTIME"

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
  [ -d "$ROOT/ckpts" ] && aws s3 sync "$ROOT/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true
  [ -f "$ROOT/m2_eval_result.json" ] && aws s3 cp "$ROOT/m2_eval_result.json" "$OUT_S3/m2_eval_result.json" --only-show-errors || true
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
# networkx REQUIRED (cycpeptmpdb_to_pepglad._identify_residue uses VF2); sympy REQUIRED (DynamicBatchWrapper);
# tensorboard REQUIRED (abs_trainer SummaryWriter). None are in the base image.
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
aws s3 cp "$WARM_LDM_S3" "$ROOT/data/epoch221.ckpt" --only-show-errors    # (a) diffusion warm-start
aws s3 cp "$V1_AE_S3"    "$ROOT/data/v1_ae.ckpt"    --only-show-errors     # (b) FROZEN autoencoder
mkdir -p "$ROOT/data/cremp"
aws s3 cp "$CREMP_S3/summary.csv"          "$ROOT/data/cremp/summary.csv" --only-show-errors
aws s3 cp "$CREMP_S3/sdf_and_json.tar.bz2" "$ROOT/data/cremp/sdf_and_json.tar.bz2" --only-show-errors

cd "$ROOT/code"

# ---- resume-aware dataset build: reuse the M1 mmap (identical split) from S3 if present ----
stage building_dataset
if aws s3 ls "$OUT_S3/dataset/train/index.txt" >/dev/null 2>&1; then
  echo "found prebuilt dataset in THIS run's S3 -> reusing (spot-resume)"
  mkdir -p "$ROOT/data/cremp_pepglad"
  aws s3 sync "$OUT_S3/dataset" "$ROOT/data/cremp_pepglad" --only-show-errors
elif [ -n "${M1_DATASET_S3:-}" ] && aws s3 ls "$M1_DATASET_S3/train/index.txt" >/dev/null 2>&1; then
  echo "reusing the M1 CREMP mmap (identical split, no re-embed): $M1_DATASET_S3"
  mkdir -p "$ROOT/data/cremp_pepglad"
  aws s3 sync "$M1_DATASET_S3" "$ROOT/data/cremp_pepglad" --only-show-errors
  aws s3 sync "$ROOT/data/cremp_pepglad" "$OUT_S3/dataset" --only-show-errors || true
else
  python prep_cremp_dataset.py \
    --cremp-dir "$ROOT/data/cremp" \
    --out-dir   "$ROOT/data/cremp_pepglad" \
    --max-confs-per-mol "$MAX_CONFS_PER_MOL" \
    --max-train-mols "$MAX_TRAIN_MOLS" --max-val-mols "$MAX_VAL_MOLS" --max-test-mols "$MAX_TEST_MOLS"
  aws s3 sync "$ROOT/data/cremp_pepglad" "$OUT_S3/dataset" --only-show-errors || true
fi

stage training
# overwrite_values wants --dotted.key=value opt-args (leading -- required; '.' nests; value cast to the
# YAML value's existing type). Every path below already exists in m2_ldm_midtrain.yaml.
python m2_train_ldm.py --gpus 0 --config m2_ldm_midtrain.yaml \
  --warm_start_ldm_ckpt="$ROOT/data/epoch221.ckpt" \
  --model.autoencoder_ckpt="$ROOT/data/v1_ae.ckpt" \
  --dataset.train.mmap_dir="$ROOT/data/cremp_pepglad/train" \
  --dataset.valid.mmap_dir="$ROOT/data/cremp_pepglad/valid" \
  --trainer.config.save_dir="$ROOT/ckpts/m2_ldm_midtrain" \
  --trainer.config.max_epoch="$MAX_EPOCH" \
  --trainer.config.optimizer.lr="$LR"
sync_all

stage evaluating
# best (lowest val-loss) checkpoint = first line of topk_map.txt.
BEST_CKPT=$(head -1 "$ROOT/ckpts/m2_ldm_midtrain"/version_*/checkpoint/topk_map.txt 2>/dev/null | sed 's/^[^:]*: //' || true)
if [ -z "$BEST_CKPT" ] || [ ! -f "$BEST_CKPT" ]; then
  BEST_CKPT=$(ls -t "$ROOT/ckpts/m2_ldm_midtrain"/version_*/checkpoint/epoch*.ckpt 2>/dev/null | head -1 || true)
fi
echo "eval checkpoint: $BEST_CKPT"
if [ -n "$BEST_CKPT" ]; then
  python m2_eval.py \
    --m2-ckpt "$BEST_CKPT" \
    --cremp-dir "$ROOT/data/cremp" \
    --n-test-mols "$MAX_TEST_MOLS" --n-samples "$N_SAMPLES" --gpu 0 --out "$ROOT/m2_eval_result.json"
  cp "$ROOT/m2_eval_result.json" "$ROOT/status/m2_eval_result.json" 2>/dev/null || true
else
  echo '{"status":"error","error":"no checkpoint produced"}' > "$ROOT/m2_eval_result.json"
fi
stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
# DEAD-MAN'S-SWITCH (first thing to run): guarantee the box dies even if everything below hangs.
systemd-run --unit=m2-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +720 &
exec > /var/log/m2-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN WARM_LDM_S3=$WARM_LDM_S3 V1_AE_S3=$V1_AE_S3 CREMP_S3=$CREMP_S3 M1_DATASET_S3=$M1_DATASET_S3 \
  MAX_CONFS_PER_MOL=$MAX_CONFS_PER_MOL MAX_TRAIN_MOLS=$MAX_TRAIN_MOLS MAX_VAL_MOLS=$MAX_VAL_MOLS \
  MAX_TEST_MOLS=$MAX_TEST_MOLS N_SAMPLES=$N_SAMPLES MAX_EPOCH=$MAX_EPOCH LR=$LR MAX_RUNTIME=$MAX_RUNTIME \
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
  # broadened net (the LDM diffusion is small — a T4/L4 is plenty; add cheaper/older families across AZs)
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
echo "result: aws s3 cp $S3RUN/m2_eval_result.json -"
