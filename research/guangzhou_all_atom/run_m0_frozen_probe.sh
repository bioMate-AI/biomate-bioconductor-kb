#!/bin/bash
# =====================================================================================================
# run_m0_frozen_probe.sh — spot-GPU launcher for the M0 Tier-0 frozen-encoder linear-probe transfer
# matrix (m0_frozen_probe.py). ONE GPU afternoon, NO diffusion training.
#
# Mirrors the proven cyclic_peptide spot pattern (launch_closure_ph.sh / launch_pepglad_train.sh):
#   * SPOT ONLY (one-time, terminate on interruption), us-west-2, IAM AutoimmuneCorpusProfile
#   * AZ/instance-type fallback across the known-good subnet combos
#   * self-terminate: instance-initiated-shutdown-behavior=terminate + a systemd dead-man's-switch
#     that shuts the box down after MAX_RUNTIME even if the driver script hangs
#   * results stream to S3 (status heartbeat + the final m0_result.json)
#
# It does NOT launch anything itself beyond one spot instance; there is no GPU training, only inference.
# Poll:  aws s3 cp $S3RUN/status/status.json -   ;  final:  aws s3 cp $S3RUN/m0_result.json -
# =====================================================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267        # DL Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) — drivers + awscli
SG=sg-011121fdf81073ec8; KEY=biomate-trial-resume-20260912

# --- inputs (env-overridable) ------------------------------------------------------------------------
LDM_CKPT_S3=${LDM_CKPT_S3:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
CREMP_S3=${CREMP_S3:-s3://$BUCKET/cyclic_peptide/datasets/cremp_partial}
PEPBDB_S3=${PEPBDB_S3:-s3://$BUCKET/cyclic_peptide/datasets/pepbdb}   # optional experimental subset
SMALLMOL_CKPT_S3=${SMALLMOL_CKPT_S3:-}                                # OPTIONAL arm (iii); empty => skipped
N_TEST_MOLS=${N_TEST_MOLS:-300}
N_EXP=${N_EXP:-60}
MAX_RUNTIME=${MAX_RUNTIME:-4h}

RUNID=m0-frozen-probe-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- build + upload the code bundle (the probe + the partition helper it reuses) ---------------------
TMP=$(mktemp -d)
for f in m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
# vendored PepGLAD runtime (models/data/utils/evaluation) — the probe imports it, don't reinvent.
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" m0_frozen_probe.py cycpeptmpdb_to_pepglad.py noncanonical_vocab.py pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  LDM_CKPT_S3=$LDM_CKPT_S3"
echo "  CREMP_S3=$CREMP_S3  N_TEST_MOLS=$N_TEST_MOLS"
echo "  SMALLMOL_CKPT_S3=${SMALLMOL_CKPT_S3:-<none -> arm (iii) skipped>}"

# --- driver script that runs ON the instance (uploaded, fetched at boot) -----------------------------
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
  [ -f "$ROOT/m0_result.json" ] && aws s3 cp "$ROOT/m0_result.json" "$OUT_S3/m0_result.json" --only-show-errors || true
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

# periodic heartbeat + best-effort spot-interruption capture
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
# networkx is REQUIRED (cycpeptmpdb_to_pepglad._identify_residue uses VF2 subgraph isomorphism);
# it is NOT in the training image's install list, so add it here explicitly.
pip install 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' \
            'tqdm==4.67.1' 'networkx==3.2.1' 'boto3>=1.36,<2'
pip freeze > "$ROOT/status/environment.txt"
python -c 'import torch,torch_scatter,rdkit,networkx,Bio; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_data
aws s3 cp "$LDM_CKPT_S3" "$ROOT/data/epoch221.ckpt" --only-show-errors
mkdir -p "$ROOT/data/cremp"
aws s3 cp "$CREMP_S3/summary.csv"            "$ROOT/data/cremp/summary.csv" --only-show-errors
aws s3 cp "$CREMP_S3/sdf_and_json.tar.bz2"   "$ROOT/data/cremp/sdf_and_json.tar.bz2" --only-show-errors
PEPBDB_ARG=""
if [ -n "${PEPBDB_S3:-}" ]; then
  mkdir -p "$ROOT/data/pepbdb"
  aws s3 sync "$PEPBDB_S3" "$ROOT/data/pepbdb" --only-show-errors || true
  # unpack any tarballs pepbdb ships as (best-effort; probe is optional on this data)
  find "$ROOT/data/pepbdb" -name '*.tar.gz' -exec tar xzf {} -C "$ROOT/data/pepbdb" \; 2>/dev/null || true
  PEPBDB_ARG="--pepbdb-dir $ROOT/data/pepbdb"
fi
SMALLMOL_ARG=""
if [ -n "${SMALLMOL_CKPT_S3:-}" ]; then
  aws s3 cp "$SMALLMOL_CKPT_S3" "$ROOT/data/smallmol.ckpt" --only-show-errors
  SMALLMOL_ARG="--smallmol-ckpt $ROOT/data/smallmol.ckpt"
fi

stage running_probe
cd "$ROOT/code"
# m0_frozen_probe.py expects ./runtime/PepGLAD relative to itself — it is ($ROOT/code/runtime/PepGLAD).
python m0_frozen_probe.py \
  --ldm-ckpt   "$ROOT/data/epoch221.ckpt" \
  --cremp-dir  "$ROOT/data/cremp" \
  $PEPBDB_ARG $SMALLMOL_ARG \
  --n-test-mols "$N_TEST_MOLS" --n-exp "$N_EXP" \
  --gpu 0 --out "$ROOT/m0_result.json"
cp "$ROOT/m0_result.json" "$ROOT/status/m0_result.json" 2>/dev/null || true
stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
# DEAD-MAN'S-SWITCH (must be the first thing that runs): guarantee the box dies even if everything below
# hangs, before any download or venv work. Redundant with instance-initiated-shutdown-behavior=terminate.
systemd-run --unit=m0-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +240 &
exec > /var/log/m0-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN LDM_CKPT_S3=$LDM_CKPT_S3 CREMP_S3=$CREMP_S3 PEPBDB_S3=${PEPBDB_S3:-} \
  SMALLMOL_CKPT_S3=${SMALLMOL_CKPT_S3:-} N_TEST_MOLS=$N_TEST_MOLS N_EXP=$N_EXP MAX_RUNTIME=$MAX_RUNTIME \
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
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]' \
    --user-data "$UD" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
    --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $TYPE $SUBNET -> $IID"; break; }
  echo "  no capacity ($TYPE $SUBNET), trying next"
done
[ -z "$IID" ] && { echo "FATAL: no GPU spot capacity across all combos"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:   aws s3 cp $S3RUN/status/status.json -"
echo "result: aws s3 cp $S3RUN/m0_result.json -"
