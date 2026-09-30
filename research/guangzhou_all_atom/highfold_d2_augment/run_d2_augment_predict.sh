#!/bin/bash
# =====================================================================================================
# run_d2_augment_predict.sh — spot-GPU launcher for D2 (2ii): PREDICT bound cyclic-peptide–receptor complexes
# with Boltz (cyclic:true) to AUGMENT the thin experimental D2 data for the 2c target-conditioned generator.
# TRAIN-ONLY, provenance-tagged, confidence-gated. NO experimental/eval data is produced here.
#
# Mirrors run_m2c_ldm_finetune.sh's proven cyclic_peptide spot pattern (SAME discipline, verbatim conventions):
#   * SPOT ONLY (one-time, terminate-on-interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across the known-good subnet combos (COMBO_OVERRIDE for cross-region)
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + systemd dead-man's-switch (MAX_RUNTIME)
#   * heartbeat + OUTPUT STREAMING to S3 every 60s; resume-aware (predictions_manifest.jsonl skips done job_ids)
#   * runs on its OWN spot instance (Lane D) — must NOT contend with Lane M training GPUs (plan's no-contention rule)
#
# PIPELINE ON THE INSTANCE:
#   1. install Boltz (pip install boltz[cuda]; MIT; auto-downloads open weights on first predict)
#   2. d2_augment_prep.py    : BindingDB cyclic-peptide + UniProt-target pairs -> jobs_canonical.jsonl (+defers)
#   3. d2_augment_predict.py : per job -> Boltz YAML (cyclic:true) -> predict -> confidence-gate (iptm/plddt)
#   4. d2_augment_integrate.py : gate-passing complexes -> PepGLAD pdbs/+index (train-only, <tool>_predicted)
#   -> streams to s3://.../cyclic_peptide/datasets/bound_cyclic_pred_v1/ ready for m2c_process_complexes.py
#
# It launches ONE spot GPU instance and nothing else.
# Poll:   aws s3 cp $S3RUN/status/status.json -
# Manif:  aws s3 cp $S3RUN/pred/predictions_manifest.jsonl -
# Result: aws s3 cp $S3RUN/pred/predict_summary.json -
# Corpus: aws s3 ls $S3RUN/bound_cyclic_pred_v1/ --recursive
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}      # DL Base OSS Nvidia GPU AMI (Ubuntu 22.04); region-specific => OVERRIDE
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# --- inputs (env-overridable) ------------------------------------------------------------------------
# BindingDB peptide subset (the ONLY real cyclic-peptide + target pairing source; CycPeptMPDB has no target col)
BINDINGDB_S3=${BINDINGDB_S3:-s3://$BUCKET/cyclic_peptide/datasets/bindingdb_peptide/202609/bindingdb_peptide_subset.csv}
# where to publish the predicted, PepGLAD-format, train-only corpus
OUT_CORPUS_S3=${OUT_CORPUS_S3:-s3://$BUCKET/cyclic_peptide/datasets/bound_cyclic_pred_v1}

# knobs
TOOL=${TOOL:-Boltz1}                    # Boltz1|Boltz2 (both `boltz predict`); HighFold-MeD is a separate follow-up
MAX_REC_LEN=${MAX_REC_LEN:-800}         # receptor residue cap for A10G 24GB (plan's memory note)
MIN_PEP_LEN=${MIN_PEP_LEN:-5}
MAX_PEP_LEN=${MAX_PEP_LEN:-20}
MIN_IPTM=${MIN_IPTM:-0.6}               # interface confidence gate (plan: keep only high-iptm/plddt)
MIN_PLDDT=${MIN_PLDDT:-0.7}
PRED_LIMIT=${PRED_LIMIT:-500}           # cap #predictions this run (0=all ~few-thousand; scope the first batch)
PER_JOB_TIMEOUT=${PER_JOB_TIMEOUT:-1800}
USE_MSA_SERVER=${USE_MSA_SERVER:-0}     # 1 => --use_msa_server (needs egress to ColabFold MSA); default single-seq
MAX_RUNTIME=${MAX_RUNTIME:-12h}

RUNID=d2-augment-predict-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)            # research/guangzhou_all_atom (for runtime/PepGLAD)

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
for f in d2_augment_prep.py d2_augment_predict.py d2_augment_integrate.py; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $HERE/$f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
# PepGLAD runtime is needed ONLY by the integrate step (its list_blocks_to_pdb / pdb_to_list_blocks converters).
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$REPO/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  d2_augment_prep.py d2_augment_predict.py d2_augment_integrate.py pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  BINDINGDB_S3=$BINDINGDB_S3"
echo "  OUT_CORPUS_S3=$OUT_CORPUS_S3"
echo "  TOOL=$TOOL MIN_IPTM=$MIN_IPTM MIN_PLDDT=$MIN_PLDDT PRED_LIMIT=$PRED_LIMIT MAX_REC_LEN=$MAX_REC_LEN"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "$TMP/driver.sh" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-d2augment
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -d "$ROOT/data/jobs" ] && aws s3 sync "$ROOT/data/jobs" "$OUT_S3/jobs/" --only-show-errors || true
  [ -d "$ROOT/data/pred" ] && aws s3 sync "$ROOT/data/pred" "$OUT_S3/pred/" --exclude "_boltz/*" --only-show-errors || true
  [ -d "$ROOT/data/bound_cyclic_pred_v1" ] && aws s3 sync "$ROOT/data/bound_cyclic_pred_v1" "$OUT_S3/bound_cyclic_pred_v1/" --only-show-errors || true
}
finish() {
  rc=$?; trap - EXIT
  [ "$rc" -ne 0 ] && stage failed || true
  sync_all
  # publish the final corpus to the stable location for m2c (only if we produced one)
  [ -f "$ROOT/data/bound_cyclic_pred_v1/index.txt" ] && aws s3 sync "$ROOT/data/bound_cyclic_pred_v1" "$OUT_CORPUS_S3/" --only-show-errors || true
  shutdown -h now
  exit "$rc"
}
trap finish EXIT

# heartbeat + spot-interruption capture (same shape as run_m2c_ldm_finetune.sh)
(while sleep 60; do sync_all; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json"; then
    stage spot_interruption; sync_all; break
  fi
done) >/dev/null 2>&1 &

stage installing
for a in 1 2 3 4 5 6; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; [ "$a" = 6 ] && exit 1; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install --disable-pip-version-check 'pip==25.0.1'
# Boltz: MIT, pip-installable, auto-downloads its own OPEN weights on first predict (the key spot-friendly property).
# boltz[cuda] pulls a CUDA torch; rdkit gives d2_augment_prep exact macrocycle detection; gemmi/biopython for converters.
pip install 'boltz[cuda]' 'rdkit==2024.9.6' 'gemmi==0.6.7' 'biopython==1.80' 'boto3>=1.36,<2' 'numpy==1.26.4'
pip freeze > "$ROOT/status/environment.txt"
python -c "import torch, boltz; print('boltz import ok; cuda', torch.cuda.is_available())"

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD (integrate needs it)

stage fetching_data
aws s3 cp "$BINDINGDB_S3" "$ROOT/data/bindingdb_peptide_subset.csv" --only-show-errors
cd "$ROOT/code"

# ---- resume-aware: if this run's S3 already has predictions, pull them so predict skips done job_ids ----
mkdir -p "$ROOT/data/pred"
aws s3 sync "$OUT_S3/pred" "$ROOT/data/pred" --exclude "_boltz/*" --only-show-errors || true

stage prep
mkdir -p "$ROOT/data/jobs"
python d2_augment_prep.py \
  --bindingdb "$ROOT/data/bindingdb_peptide_subset.csv" \
  --out-dir "$ROOT/data/jobs" \
  --tool "$TOOL" --max-rec-len "$MAX_REC_LEN" \
  --min-pep-len "$MIN_PEP_LEN" --max-pep-len "$MAX_PEP_LEN"
# NOTE: prep is run WITHOUT --resolve-receptor (keeps it fast/offline-safe); predict resolves receptors itself.
sync_all

stage predicting
MSA_FLAG=""; [ "$USE_MSA_SERVER" = "1" ] && MSA_FLAG="--msa-server"
python d2_augment_predict.py \
  --jobs "$ROOT/data/jobs/jobs_canonical.jsonl" \
  --out-dir "$ROOT/data/pred" \
  --min-iptm "$MIN_IPTM" --min-plddt "$MIN_PLDDT" \
  --per-job-timeout "$PER_JOB_TIMEOUT" --limit "$PRED_LIMIT" \
  --resolve-missing-receptor $MSA_FLAG
sync_all

stage integrating
python d2_augment_integrate.py \
  --pred-dir "$ROOT/data/pred" \
  --out-dir "$ROOT/data/bound_cyclic_pred_v1"
sync_all

stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=d2aug-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +720 &
exec > /var/log/d2aug-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-d2augment/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-d2augment/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-d2augment/driver.sh
OUT_S3=$S3RUN BINDINGDB_S3=$BINDINGDB_S3 OUT_CORPUS_S3=$OUT_CORPUS_S3 \
  TOOL=$TOOL MAX_REC_LEN=$MAX_REC_LEN MIN_PEP_LEN=$MIN_PEP_LEN MAX_PEP_LEN=$MAX_PEP_LEN \
  MIN_IPTM=$MIN_IPTM MIN_PLDDT=$MIN_PLDDT PRED_LIMIT=$PRED_LIMIT PER_JOB_TIMEOUT=$PER_JOB_TIMEOUT \
  USE_MSA_SERVER=$USE_MSA_SERVER MAX_RUNTIME=$MAX_RUNTIME \
  bash /opt/guangzhou-d2augment/driver.sh
EOF
)

# A10G 24GB (g5) preferred for Boltz complex inference; g6 (L4) + g4dn (T4) fallbacks. Same combo table as m2c.
declare -a COMBO=(
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-03b277a7a08d388c1"
  "g5.2xlarge subnet-09e4dce46682a6c60"
  "g5.xlarge subnet-0254e4c3634b41bfc"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  "g6.2xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
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
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":250,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:   aws s3 cp $S3RUN/status/status.json -"
echo "manif:  aws s3 cp $S3RUN/pred/predictions_manifest.jsonl -"
echo "result: aws s3 cp $S3RUN/pred/predict_summary.json -"
echo "corpus: aws s3 ls $OUT_CORPUS_S3/ --recursive"
