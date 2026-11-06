#!/bin/bash
# =====================================================================================================
# pdl1_m2c_run.sh — spot-GPU launcher for the ACT Round-1 DIVERSITY ARM: DE-NOVO cyclic-peptide GENERATION
# on the PD-L1 target (PDB 5O45) with the trained M2c target-conditioned latent-diffusion generator.
# Complements the BoltzGen pool (BoltzGen leads; M2c adds orthogonal chemotypes). No training — GENERATION
# on ONE target. Feeds the §3 re-rank (gate -> MM-GBSA -> permeability -> GP-Pareto).
#
# Mirrors run_m2c_ldm_finetune.sh's proven cyclic_peptide spot pattern:
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across known-good subnet combos (COMBO_OVERRIDE for cross-region)
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + systemd dead-man's-switch
#   * heartbeat + result STREAMING to S3 every 60s
#
# WHAT'S DIFFERENT vs run_m2c_ldm_finetune.sh:
#   * NO TRAIN. Steps: stage 5O45 as a generation target (pdl1_m2c_stage_target.py, CPU+network) ->
#     GENERATE (pdl1_m2c_generate.py drives stock generate.py) -> stream designs (jsonl + PDBs) to S3.
#   * loads the RELEASED M2c ckpt (default s3 path below) + the v1 AE is ALREADY inside the ckpt object
#     (trained with AE_MODE=v1) -> only m1_closure_ae must be importable to unpickle (bundled). No AE swap.
#   * SHORT + CHEAP: staging is minutes; generation is ~n_samples * n_variants reverse-diffusion samples.
#     No DockQ toolchain needed here (reference-free metrics only for an unseen target).
#
# It launches ONE spot GPU instance and nothing else.
# Poll:    aws s3 cp $S3RUN/status/status.json -
# Designs: aws s3 cp $S3RUN/pdl1_m2c_designs.jsonl -   (the §3 re-rank feed)
# Report:  aws s3 cp $S3RUN/pdl1_m2c_generate_report.json -
# PDBs:    aws s3 ls $S3RUN/gen/candidates/ --recursive
# Target:  aws s3 cp $S3RUN/target_manifest.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04); region-specific => OVERRIDE
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# --- inputs (env-overridable) ------------------------------------------------------------------------
# the RELEASED M2c ckpt (epoch39_step320; epoch-221 AE via AE_MODE=v1; DockQ 0.437 on the D2 test split)
M2C_CKPT_S3=${M2C_CKPT_S3:-s3://$BUCKET/cyclic_peptide/runs/m2c-ldm-finetune-20260930T153141Z/ckpts/m2c_ldm_finetune/version_0/checkpoint/epoch39_step320.ckpt}

# target + generation knobs
TARGET_PDB=${TARGET_PDB:-5o45}
REC_CHAIN=${REC_CHAIN:-A}                 # PD-L1 IgV domain
PEP_CHAIN=${PEP_CHAIN:-B}                 # native macrocyclic peptide-71 (pocket definer + length scaffold)
POCKET_TH=${POCKET_TH:-10.0}             # PepGLAD CB-CB pocket threshold (stock 10 A)
LENGTHS=${LENGTHS:-10,12,14,16}          # de-novo length band (clamped to <= native length 14)
N_SAMPLES=${N_SAMPLES:-150}             # designs per length variant (150 x ~4 = ~600 raw designs)
ENERGY=${ENERGY:-off}                    # off = no guidance (default, correct for a single unseen target); d2
                                         # = fit consec-dist over the D2 finetune-run TRAIN split first
D2_DATASET_S3=${D2_DATASET_S3:-s3://$BUCKET/cyclic_peptide/runs/m2c-ldm-finetune-20260930T153141Z/dataset}
MAX_RUNTIME=${MAX_RUNTIME:-5h}          # stage (network) + generate; generation is the only slow part

RUNID=pdl1-m2c-generate-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
# m1_closure_ae is required to UNPICKLE the M2c ckpt (its .autoencoder is the v1 AE class). The stock
# generate.py + setup_latent_guidance.py live in the PepGLAD runtime tarball. m1_peptide_dataset /
# m2_peptide_ldm register classes at import in the M2c training path but are NOT needed to LOAD+SAMPLE the
# ckpt (generate.py only needs models + m1_closure_ae) — omitted to keep the bundle minimal + import-clean.
for f in pdl1_m2c_stage_target.py pdl1_m2c_generate.py m1_closure_ae.py \
         pdl1_m2c_test_noenergy.yaml pdl1_m2c_test_codesign.yaml pdl1_m2c_setup_latent_guidance.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  pdl1_m2c_stage_target.py pdl1_m2c_generate.py m1_closure_ae.py \
  pdl1_m2c_test_noenergy.yaml pdl1_m2c_test_codesign.yaml pdl1_m2c_setup_latent_guidance.yaml \
  pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  M2C_CKPT_S3=$M2C_CKPT_S3"
echo "  TARGET=$TARGET_PDB rec=$REC_CHAIN pep=$PEP_CHAIN pocket_th=$POCKET_TH lengths=$LENGTHS"
echo "  N_SAMPLES=$N_SAMPLES ENERGY=$ENERGY MAX_RUNTIME=$MAX_RUNTIME"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "$TMP/driver.sh" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -f "$ROOT/out/pdl1_m2c_designs.jsonl" ] && aws s3 cp "$ROOT/out/pdl1_m2c_designs.jsonl" "$OUT_S3/pdl1_m2c_designs.jsonl" --only-show-errors || true
  [ -f "$ROOT/out/pdl1_m2c_generate_report.json" ] && aws s3 cp "$ROOT/out/pdl1_m2c_generate_report.json" "$OUT_S3/pdl1_m2c_generate_report.json" --only-show-errors || true
  [ -d "$ROOT/out/m2c_gen" ] && aws s3 sync "$ROOT/out/m2c_gen" "$OUT_S3/gen" --only-show-errors || true
  [ -f "$ROOT/data/pdl1_m2c_target/manifest.json" ] && aws s3 cp "$ROOT/data/pdl1_m2c_target/manifest.json" "$OUT_S3/target_manifest.json" --only-show-errors || true
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

# periodic heartbeat + result stream (every 60s) + best-effort spot-interruption capture
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
# same pinned stack as run_m2c_ldm_finetune.sh (proven to load the M2c ckpt + run stock generate.py).
pip install 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' \
            'tqdm==4.67.1' 'networkx==3.2.1' 'sympy==1.13.3' 'tensorboard==2.18.0' 'boto3>=1.36,<2'
pip freeze > "$ROOT/status/environment.txt"
python -c 'import torch,torch_scatter,rdkit,networkx,sympy,Bio,scipy; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_ckpt
aws s3 cp "$M2C_CKPT_S3" "$ROOT/data/m2c.ckpt" --only-show-errors
[ -s "$ROOT/data/m2c.ckpt" ] || { echo "FATAL: M2c ckpt empty/missing"; exit 1; }

cd "$ROOT/code"

# ---- 1. stage 5O45 as a GENERATION TARGET (CPU + RCSB fetch; no GPU) ----
stage staging_target
python pdl1_m2c_stage_target.py \
  --pdb "$TARGET_PDB" --rec-chain "$REC_CHAIN" --pep-chain "$PEP_CHAIN" \
  --out-dir "$ROOT/data/pdl1_m2c_target" --pocket-th "$POCKET_TH" --lengths "$LENGTHS"
aws s3 cp "$ROOT/data/pdl1_m2c_target/manifest.json" "$OUT_S3/target_manifest.json" --only-show-errors || true

# ---- (optional) --energy d2 : pull the D2 finetune-run TRAIN split so setup_latent_guidance can fit consec-dist
D2_GUID_ARGS=""
if [ "$ENERGY" = "d2" ]; then
  stage fetching_d2_guidance
  mkdir -p "$ROOT/data/bound_cyclic_pepglad"
  aws s3 sync "$D2_DATASET_S3" "$ROOT/data/bound_cyclic_pepglad" --only-show-errors
  D2_GUID_ARGS="--d2-guidance-mmap $ROOT/data/bound_cyclic_pepglad/processed --d2-guidance-index $ROOT/data/bound_cyclic_pepglad/processed/train_index.txt"
fi

# ---- 2. GENERATE (drives stock generate.py; ABS paths injected -> cwd-independent) ----
stage generating
python pdl1_m2c_generate.py \
  --m2c-ckpt "$ROOT/data/m2c.ckpt" \
  --target-dir "$ROOT/data/pdl1_m2c_target" \
  --n-samples "$N_SAMPLES" --gpu 0 --energy "$ENERGY" $D2_GUID_ARGS \
  --out "$ROOT/out"
cp "$ROOT/out/pdl1_m2c_generate_report.json" "$ROOT/status/pdl1_m2c_generate_report.json" 2>/dev/null || true

stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=pdl1m2c-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +300 &
exec > /var/log/pdl1-m2c-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN M2C_CKPT_S3=$M2C_CKPT_S3 TARGET_PDB=$TARGET_PDB REC_CHAIN=$REC_CHAIN PEP_CHAIN=$PEP_CHAIN \
  POCKET_TH=$POCKET_TH LENGTHS=$LENGTHS N_SAMPLES=$N_SAMPLES ENERGY=$ENERGY D2_DATASET_S3=$D2_DATASET_S3 \
  MAX_RUNTIME=$MAX_RUNTIME \
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
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":150,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:    aws s3 cp $S3RUN/status/status.json -"
echo "designs: aws s3 cp $S3RUN/pdl1_m2c_designs.jsonl -"
echo "report:  aws s3 cp $S3RUN/pdl1_m2c_generate_report.json -"
echo "pdbs:    aws s3 ls $S3RUN/gen/candidates/ --recursive"
echo "target:  aws s3 cp $S3RUN/target_manifest.json -"
