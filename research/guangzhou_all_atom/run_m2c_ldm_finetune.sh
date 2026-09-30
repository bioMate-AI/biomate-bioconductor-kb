#!/bin/bash
# =====================================================================================================
# run_m2c_ldm_finetune.sh — spot-GPU launcher for M2 stage-2c: TARGET-CONDITIONED fine-tune of the PepGLAD
# latent-diffusion generator on REAL bound cyclic-peptide COMPLEXES (D2), warm-started from epoch-221, over
# the FROZEN v1 AE. Multi-step: process D2 complexes -> fine-tune -> generate+score the official panel.
#
# Mirrors run_m2_ldm_midtrain.sh's proven cyclic_peptide spot pattern:
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across known-good subnet combos (COMBO_OVERRIDE for cross-region)
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + systemd dead-man's-switch
#   * heartbeat + CHECKPOINT STREAMING to S3 every 60s; resume-aware dataset build (reuse the prebuilt
#     D2 complex mmap from THIS run's S3 if a spot interruption restarted us)
#
# WHAT'S DIFFERENT vs the 2b midtrain launcher:
#   * DATA: instead of prep_cremp_dataset.py, it runs m2c_process_complexes.py to fetch+stage the 235 D2
#     bound complexes from RCSB and build the PepGLAD CoDesignDataset mmap (stock process.py) + a
#     leakage-aware seq-cluster split with a held-out TEST set.
#   * TRAIN: m2c_train_ldm.py (STOCK LDMPepDesign + CoDesignDataset, receptor present) + m2c_ldm_finetune.yaml.
#   * EVAL: m2c_eval.py drives the OFFICIAL setup_latent_guidance -> generate.py -> cal_metrics.py panel on
#     the held-out test split (DockQ + AAR + RMSD(CA) + Diversity + Consistency). dG is N/A (no pyrosetta).
#   * ENV: adds git + build-essential + gfortran so evaluation.dockq can git-clone+make bjornwallner/DockQ v1.0
#     on first import (globals.py:19-23). Without these DockQ is reported "unavailable" (never a silent 0).
#
# It launches ONE spot GPU instance and nothing else.
# Poll:   aws s3 cp $S3RUN/status/status.json -
# Ckpts:  aws s3 ls $S3RUN/ckpts/ --recursive
# Result: aws s3 cp $S3RUN/m2c_eval_result.json -
# Data:   aws s3 cp $S3RUN/dataset_manifest.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04); region-specific => OVERRIDE
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# --- inputs (env-overridable) ------------------------------------------------------------------------
# (a) epoch-221 LDM -> warm-start the DIFFUSION (its .autoencoder is dropped in warm_start_diffusion)
WARM_LDM_S3=${WARM_LDM_S3:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
# (b) M1 v1 AE (production AE) -> becomes the FROZEN autoencoder of the LDM
V1_AE_S3=${V1_AE_S3:-s3://$BUCKET/cyclic_peptide/runs/m1-ae-midtrain-20260928T225554Z/ckpts/m1_ae_midtrain/version_0/checkpoint/epoch39_step3520.ckpt}
# (c) D2 bound cyclic complexes (index.txt + manifest); processed into a mmap ON the instance
D2_S3=${D2_S3:-s3://$BUCKET/cyclic_peptide/datasets/bound_cyclic_v1}

# training / data knobs
POCKET_TH=${POCKET_TH:-10.0}
MIN_TEST=${MIN_TEST:-24}                 # floor for the held-out test set (of ~235 complexes)
VAL_FRAC=${VAL_FRAC:-0.1}
TEST_FRAC=${TEST_FRAC:-0.1}
ID_TH=${ID_TH:-0.6}                      # peptide-seq identity threshold for the leakage-aware split
MAX_EPOCH=${MAX_EPOCH:-40}
LR=${LR:-1.0e-5}
N_SAMPLES=${N_SAMPLES:-16}               # samples/target at eval (>=2 for diversity/consistency)
STRUCT_PASS=${STRUCT_PASS:-0}            # 1 = also run struct_only pass for DockQ>=/RMSD<= buckets
MAX_RUNTIME=${MAX_RUNTIME:-10h}          # process (network) + short fine-tune + eval

RUNID=m2c-ldm-finetune-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
# NOTE: m2c_train_ldm imports warm_start_diffusion from m2_train_ldm (validated reuse). m2_train_ldm imports
# m1_peptide_dataset + m2_peptide_ldm at MODULE level (they only REGISTER classes — harmless on the 2c stock
# path), so both must be bundled or the import fails. m1_closure_ae is required to unpickle the v1 AE.
for f in m2c_process_complexes.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
         m2_train_ldm.py m2c_train_ldm.py m2c_eval.py \
         m2c_ldm_finetune.yaml m2c_test_codesign.yaml m2c_setup_latent_guidance.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  m2c_process_complexes.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
  m2_train_ldm.py m2c_train_ldm.py m2c_eval.py \
  m2c_ldm_finetune.yaml m2c_test_codesign.yaml m2c_setup_latent_guidance.yaml pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  WARM_LDM_S3=$WARM_LDM_S3"
echo "  V1_AE_S3=$V1_AE_S3"
echo "  D2_S3=$D2_S3"
echo "  MIN_TEST=$MIN_TEST MAX_EPOCH=$MAX_EPOCH LR=$LR N_SAMPLES=$N_SAMPLES STRUCT_PASS=$STRUCT_PASS MAX_RUNTIME=$MAX_RUNTIME"

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
  [ -f "$ROOT/m2c_eval_result.json" ] && aws s3 cp "$ROOT/m2c_eval_result.json" "$OUT_S3/m2c_eval_result.json" --only-show-errors || true
  [ -f "$ROOT/data/bound_cyclic_pepglad/manifest.json" ] && aws s3 cp "$ROOT/data/bound_cyclic_pepglad/manifest.json" "$OUT_S3/dataset_manifest.json" --only-show-errors || true
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
# python-venv + DockQ v1.0 build toolchain (git already present; build-essential+gfortran for `make`).
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git build-essential gfortran
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install --disable-pip-version-check 'pip==25.0.1'
pip install 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
# gemmi speeds up cif->pdb staging (optional; biopython MMCIFParser is the fallback). networkx/sympy/tensorboard
# required (DynamicBatchWrapper/abs_trainer). scipy needed by evaluation.diversity.
pip install 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' \
            'tqdm==4.67.1' 'networkx==3.2.1' 'sympy==1.13.3' 'tensorboard==2.18.0' 'boto3>=1.36,<2' 'gemmi==0.6.7'
pip freeze > "$ROOT/status/environment.txt"
python -c 'import torch,torch_scatter,rdkit,networkx,sympy,Bio,scipy,tensorboard; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_data
aws s3 cp "$WARM_LDM_S3" "$ROOT/data/epoch221.ckpt" --only-show-errors    # (a) diffusion warm-start
aws s3 cp "$V1_AE_S3"    "$ROOT/data/v1_ae.ckpt"    --only-show-errors     # (b) FROZEN autoencoder
mkdir -p "$ROOT/data/bound_cyclic_v1"
aws s3 cp "$D2_S3/index.txt"                    "$ROOT/data/bound_cyclic_v1/index.txt" --only-show-errors
aws s3 cp "$D2_S3/bound_cyclic_manifest.jsonl" "$ROOT/data/bound_cyclic_v1/bound_cyclic_manifest.jsonl" --only-show-errors

cd "$ROOT/code"

# ---- AE_MODE=epoch221 : matched-latent DIAGNOSTIC. The v1 AE (M1 mid-train) shifted the latent away from
# what the epoch-221 diffusion knows -> warm-start mismatch. Swap in epoch-221's OWN .autoencoder so the
# frozen AE latent matches the warm-started diffusion (self-consistent). Default AE_MODE=v1 keeps the v1 AE.
if [ "${AE_MODE:-v1}" = "epoch221" ]; then
  python -c "import sys; sys.path.insert(0,'runtime/PepGLAD'); import torch, models; \
    ldm=torch.load('$ROOT/data/epoch221.ckpt', map_location='cpu', weights_only=False); \
    torch.save(ldm.autoencoder, '$ROOT/data/v1_ae.ckpt'); print('[AE_MODE=epoch221] frozen AE = epoch-221 .autoencoder (matched latent)')"
fi

# ---- resume-aware complex-mmap build: reuse THIS run's S3 dataset if a spot interruption restarted us ----
stage building_dataset
if aws s3 ls "$OUT_S3/dataset/processed/index.txt" >/dev/null 2>&1; then
  echo "found prebuilt D2 mmap in THIS run's S3 -> reusing (spot-resume)"
  mkdir -p "$ROOT/data/bound_cyclic_pepglad"
  aws s3 sync "$OUT_S3/dataset" "$ROOT/data/bound_cyclic_pepglad" --only-show-errors
else
  python m2c_process_complexes.py \
    --d2-dir  "$ROOT/data/bound_cyclic_v1" \
    --out-dir "$ROOT/data/bound_cyclic_pepglad" \
    --pocket-th "$POCKET_TH" --min-test "$MIN_TEST" \
    --val-frac "$VAL_FRAC" --test-frac "$TEST_FRAC" --id-th "$ID_TH"
  aws s3 sync "$ROOT/data/bound_cyclic_pepglad" "$OUT_S3/dataset" --only-show-errors || true
fi

stage training
# overwrite_values wants --dotted.key=value opt-args (leading -- required; '.' nests; value cast to the YAML
# value's existing type). Every path below already exists in m2c_ldm_finetune.yaml.
python m2c_train_ldm.py --gpus 0 --config m2c_ldm_finetune.yaml \
  --warm_start_ldm_ckpt="$ROOT/data/epoch221.ckpt" \
  --model.autoencoder_ckpt="$ROOT/data/v1_ae.ckpt" \
  --dataset.train.mmap_dir="$ROOT/data/bound_cyclic_pepglad/processed" \
  --dataset.train.specify_index="$ROOT/data/bound_cyclic_pepglad/processed/train_index.txt" \
  --dataset.valid.mmap_dir="$ROOT/data/bound_cyclic_pepglad/processed" \
  --dataset.valid.specify_index="$ROOT/data/bound_cyclic_pepglad/processed/valid_index.txt" \
  --trainer.config.save_dir="$ROOT/ckpts/m2c_ldm_finetune" \
  --trainer.config.max_epoch="$MAX_EPOCH" \
  --trainer.config.optimizer.lr="$LR"
sync_all

stage evaluating
# FIX (eval-path bug): m2c_eval runs the stock scripts with cwd=runtime/PepGLAD, but the guidance+test
# configs use relative './data/bound_cyclic_pepglad' paths -> they resolved to runtime/PepGLAD/data/... and
# FileNotFound'd (training worked only because it got ABSOLUTE mmap_dir via overwrite args). Make the config
# paths absolute so they resolve from any cwd.
sed -i "s|\./data/bound_cyclic_pepglad|$ROOT/data/bound_cyclic_pepglad|g" \
  m2c_setup_latent_guidance.yaml m2c_test_codesign.yaml m2c_ldm_finetune.yaml
# best (lowest val-loss) checkpoint = first line of topk_map.txt (format "<score>: <path>", best-first).
BEST_CKPT=$(head -1 "$ROOT/ckpts/m2c_ldm_finetune"/version_*/checkpoint/topk_map.txt 2>/dev/null | sed 's/^[^:]*: //' || true)
if [ -z "$BEST_CKPT" ] || [ ! -f "$BEST_CKPT" ]; then
  BEST_CKPT=$(ls -t "$ROOT/ckpts/m2c_ldm_finetune"/version_*/checkpoint/epoch*.ckpt 2>/dev/null | head -1 || true)
fi
echo "eval checkpoint: $BEST_CKPT"
if [ -n "$BEST_CKPT" ]; then
  STRUCT_FLAG=""; [ "$STRUCT_PASS" = "1" ] && STRUCT_FLAG="--struct-pass"
  python m2c_eval.py \
    --m2c-ckpt "$BEST_CKPT" \
    --data-dir "$ROOT/data/bound_cyclic_pepglad" \
    --test-config m2c_test_codesign.yaml \
    --guidance-config m2c_setup_latent_guidance.yaml \
    --n-samples "$N_SAMPLES" --gpu 0 $STRUCT_FLAG --out "$ROOT/m2c_eval_result.json"
  cp "$ROOT/m2c_eval_result.json" "$ROOT/status/m2c_eval_result.json" 2>/dev/null || true
  # also stream the generated pdbs + per-id eval report for inspection
  aws s3 sync "$ROOT/m2c_gen_codesign" "$OUT_S3/gen_codesign" --only-show-errors || true
else
  echo '{"status":"error","error":"no checkpoint produced"}' > "$ROOT/m2c_eval_result.json"
fi
stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=m2c-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +600 &
exec > /var/log/m2c-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN WARM_LDM_S3=$WARM_LDM_S3 V1_AE_S3=$V1_AE_S3 D2_S3=$D2_S3 \
  POCKET_TH=$POCKET_TH MIN_TEST=$MIN_TEST VAL_FRAC=$VAL_FRAC TEST_FRAC=$TEST_FRAC ID_TH=$ID_TH \
  MAX_EPOCH=$MAX_EPOCH LR=$LR N_SAMPLES=$N_SAMPLES STRUCT_PASS=$STRUCT_PASS MAX_RUNTIME=$MAX_RUNTIME \
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
  "g4dn.xlarge subnet-0254e4c3634b41bfc"
  "g4dn.xlarge subnet-03b277a7a08d388c1"
  "g4dn.xlarge subnet-09e4dce46682a6c60"
  "g4dn.xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-09e4dce46682a6c60"
)
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
echo "result: aws s3 cp $S3RUN/m2c_eval_result.json -"
echo "data:   aws s3 cp $S3RUN/dataset_manifest.json -"
