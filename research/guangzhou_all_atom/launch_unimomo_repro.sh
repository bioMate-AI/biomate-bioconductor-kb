#!/bin/bash
# =============================================================================
# launch_unimomo_repro.sh
#
# Reproduce UniMoMo (ICML 2025, arXiv 2503.19300; github.com/kxz18/UniMoMo) peptide
# co-design DockQ on the PepBench / LNR split (93 test targets x 100 candidates/target).
# Reported headline in the paper: Codesign DockQ = 0.759. This run establishes that
# number as our day-1 base so we can then beat it.
#
# This is a LAUNCHER: it uploads an on-instance driver to S3 and starts an on-demand GPU
# instance (SPOT-first across known instance-type x AZ combos, ON-DEMAND fallback — authorized)
# that is self-terminating (instance-initiated-shutdown=terminate) + dead-man's-switch
# (systemd deadline timer) + streams all outputs to S3 every 120s. Durable, NOT local.
#
# Clean public AWS Deep Learning *Base* GPU AMI (drivers only) — UniMoMo gets its OWN deps
# built fresh from its env_cuda121.yaml via Miniforge (NOT our baked pepglad env).
#
# METRIC AGGREGATION (pinned from scripts/metrics/peptide.py @ f58f117, see repro doc):
#   DockQ headline = mean over the 93 LNR targets of ( max DockQ over the 100 candidates ).
#   i.e. ORACLE best-of-100 per target, then averaged across targets. (AAR same; RMSD = min
#   per target then MEDIAN across targets.) Any future "beat 0.759" claim MUST use this exact
#   split / budget (100) / aggregation (best-of-N max, mean over targets).
#
# dG/ddG (PyRosetta) is NOT reproduced here (orthogonal to DockQ and ~hours/96-cores expensive);
# upstream code falls back to dG=0 when PyRosetta is absent — DockQ/AAR/RMSD are unaffected and
# computed by upstream code UNCHANGED (evaluation/dockq.py -> DockQ==2.1.3).
#
# Usage:   bash research/guangzhou_all_atom/launch_unimomo_repro.sh
# Verify:  bash -n research/guangzhou_all_atom/launch_unimomo_repro.sh
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2

# --- fixed, verified facts (checked live before authoring) ---
BUCKET=knowledge-datasets-1759951976
AMI=ami-04f7da1c787a89267                      # Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) 20260918
SG=sg-011121fdf81073ec8
KEY=biomate-trial-resume-20260912
PROFILE=AutoimmuneCorpusProfile
UNIMOMO_REPO=https://github.com/kxz18/UniMoMo.git
UNIMOMO_COMMIT=f58f117d43975d45dc2521b34ae3066a095582f0   # HEAD at authoring time (pinned for reproducibility)
CKPT_URL=https://github.com/kxz18/UniMoMo/releases/download/v1.0/model.ckpt
CKPT_SIZE=420891881                            # verified content-length
LNR_URL="https://zenodo.org/records/13373108/files/LNR.tar.gz?download=1"
LNR_SIZE=10894516                              # verified content-length
ENV_YAML=env_cuda121.yaml                      # cuda 12.1 + pytorch 2.1.2 (matches DL Base AMI driver)

# --- knobs (env-overridable) ---
N_SAMPLES=${N_SAMPLES:-100}                     # candidates per target (paper budget = 100)
TARGET_DOCKQ=${TARGET_DOCKQ:-0.759}            # reported codesign DockQ to reproduce
MAX_RUNTIME=${MAX_RUNTIME:-24h}                # dead-man's-switch deadline
DISK_GB=${DISK_GB:-250}

RUNID=unimomo-repro-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# =============================================================================
# On-instance driver. QUOTED heredoc -> nothing expands here; the driver reads env vars
# that UserData exports. Uploaded to S3; UserData pulls + runs it.
# =============================================================================
DRIVER=$(mktemp)
cat > "$DRIVER" <<'DRIVER_EOF'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
ROOT=/opt/unimomo-run
OUT_S3=${OUT_S3:?OUT_S3 required}
UNIMOMO_REPO=${UNIMOMO_REPO:?}
UNIMOMO_COMMIT=${UNIMOMO_COMMIT:?}
CKPT_URL=${CKPT_URL:?}
CKPT_SIZE=${CKPT_SIZE:?}
LNR_URL=${LNR_URL:?}
LNR_SIZE=${LNR_SIZE:?}
ENV_YAML=${ENV_YAML:?}
N_SAMPLES=${N_SAMPLES:-100}
TARGET_DOCKQ=${TARGET_DOCKQ:-0.759}

mkdir -p "$ROOT/status"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s","runid":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "$(basename "$OUT_S3")" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_results() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -d "$ROOT/UniMoMo/results" ] && aws s3 sync "$ROOT/UniMoMo/results" "$OUT_S3/results/" --only-show-errors || true
}
finish() {
  rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ]; then stage failed; fi
  sync_results
  shutdown -h now
  exit "$rc"
}
trap finish EXIT

# dead-man's-switch: hard deadline shutdown even if this shell hangs
if ! systemctl is-active --quiet unimomo-deadline.timer; then
  systemd-run --unit=unimomo-deadline --on-active="${MAX_RUNTIME:-24h}" /sbin/shutdown -h now || true
fi
# periodic result streaming
(while sleep 120; do sync_results; done) &
# spot interruption notice -> flush
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json" 2>/dev/null; then
    stage spot_interruption; sync_results; break
  fi
done) >/dev/null 2>&1 &

# ---- Miniforge (conda+mamba), fresh ----
stage installing_conda
for i in 1 2 3 4 5; do
  curl -fsSL -o /tmp/miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && break
  sleep 10
done
bash /tmp/miniforge.sh -b -p /opt/miniforge
source /opt/miniforge/etc/profile.d/conda.sh

# ---- clone UniMoMo @ pinned commit ----
stage cloning_unimomo
cd "$ROOT"
git clone "$UNIMOMO_REPO" UniMoMo
cd "$ROOT/UniMoMo"
git checkout "$UNIMOMO_COMMIT"
git rev-parse HEAD > "$ROOT/status/unimomo_commit.txt"

# ---- build UniMoMo env from its own yaml ----
stage building_env
conda env create -f "$ENV_YAML"
# conda's activate.d (libblas_mkl_activate.sh) references MKL_INTERFACE_LAYER unset -> trips `set -u`.
# Relax nounset across activation only, then restore. (This was the 2026-10-02 repro failure cause.)
set +u
conda activate UniMoMo
set -u
python -c 'import torch; print("torch", torch.__version__, "cuda", torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else "NO-GPU")' | tee "$ROOT/status/torch_check.txt"
conda list > "$ROOT/status/conda_list.txt" 2>&1 || true
sync_results

# ---- download checkpoint (verify size) ----
stage downloading_checkpoint
mkdir -p checkpoints
for i in 1 2 3 4 5; do
  wget -q -O checkpoints/model.ckpt "$CKPT_URL" && break
  echo "ckpt download attempt $i failed, retrying"; sleep 15
done
GOT=$(stat -c%s checkpoints/model.ckpt)
echo "checkpoint bytes: got=$GOT expected=$CKPT_SIZE" | tee "$ROOT/status/checkpoint_size.txt"
[ "$GOT" = "$CKPT_SIZE" ] || { echo "FATAL: checkpoint size mismatch"; exit 1; }

# ---- download + process LNR test set (verify size) ----
stage downloading_data
export PREFIX=./datasets/peptide
mkdir -p "$PREFIX"
for i in 1 2 3 4 5; do
  wget -q -O "$PREFIX/LNR.tar.gz" "$LNR_URL" && break
  echo "LNR download attempt $i failed, retrying"; sleep 15
done
GOT=$(stat -c%s "$PREFIX/LNR.tar.gz")
echo "LNR bytes: got=$GOT expected=$LNR_SIZE" | tee "$ROOT/status/lnr_size.txt"
[ "$GOT" = "$LNR_SIZE" ] || { echo "FATAL: LNR size mismatch"; exit 1; }
tar zxf "$PREFIX/LNR.tar.gz" -C "$PREFIX"
N_TARGETS=$(grep -cve '^[[:space:]]*$' "$PREFIX/LNR/test.txt" || true)
echo "LNR targets in test.txt: $N_TARGETS (expect 93)" | tee "$ROOT/status/n_targets.txt"

stage processing_data
python -m scripts.data_process.peptide.pepbench --index "$PREFIX/LNR/test.txt" --out_dir "$PREFIX/LNR/processed" --remove_het
sync_results

# ---- generation: 100 candidates/target on the LNR split ----
stage generating
# configs/test/test_pep.yaml already sets n_samples: 100, n_cycles: 0; honor N_SAMPLES override.
# Override form must be --key=value (utils.config_utils.format_args: bare key=value is read as a value).
python generate.py --config configs/test/test_pep.yaml --ckpt checkpoints/model.ckpt --gpu 0 \
  --save_dir ./results/pep --n_samples=$N_SAMPLES 2>&1 | tee "$ROOT/status/generate.log"
echo "results.jsonl lines: $(wc -l < ./results/pep/results.jsonl)" | tee "$ROOT/status/gen_count.txt"
sync_results

# ---- evaluation: co-design DockQ (+ AAR, RMSD) via upstream metrics, UNCHANGED ----
# PyRosetta intentionally NOT installed -> upstream dG path returns 0 (handled); DockQ unaffected.
stage evaluating
NCPU=$(nproc)
echo "num_workers=$NCPU" | tee "$ROOT/status/ncpu.txt"
python -m scripts.metrics.peptide --results ./results/pep/results.jsonl --num_workers "$NCPU" 2>&1 | tee "$ROOT/status/eval.log"
cp -f ./results/pep/eval_final_.log "$ROOT/status/eval_final.log" 2>/dev/null || true
cp -f ./results/pep/eval_report_.jsonl "$ROOT/status/eval_report.jsonl" 2>/dev/null || true

# ---- parse headline metrics + write repro_summary.json ----
stage summarizing
python - "$TARGET_DOCKQ" "$N_SAMPLES" "$N_TARGETS" <<'PY'
import json, re, sys, os
target_dockq = float(sys.argv[1]); n_samples = int(sys.argv[2]); n_targets = sys.argv[3]
log = "./results/pep/eval_final_.log"
text = open(log).read() if os.path.exists(log) else ""
def grab(pat):
    m = re.search(pat, text)
    return float(m.group(1)) if m else None
dockq = grab(r"DockQ \(mean\):\s*([0-9.]+)")
aar   = grab(r"AAR \(mean\):\s*([0-9.]+)")
crmsd = grab(r"C_RMSD\(CA\) \(median\):\s*([0-9.]+)")
lrmsd = grab(r"L_RMSD\(CA\) \(median\):\s*([0-9.]+)")
out = {
  "benchmark": "UniMoMo peptide co-design, PepBench/LNR split",
  "split": "LNR test (93 targets)",
  "candidates_per_target": n_samples,
  "n_targets_processed": n_targets,
  "aggregation": "DockQ headline = mean over targets of max(DockQ over candidates) [oracle best-of-N, max]; AAR same; RMSD = min per target then median over targets",
  "reproduced_DockQ": dockq,
  "target_DockQ": target_dockq,
  "delta_vs_target": None if dockq is None else round(dockq - target_dockq, 4),
  "reproduced_AAR": aar,
  "reproduced_C_RMSD_CA_median": crmsd,
  "reproduced_L_RMSD_CA_median": lrmsd,
  "dG_reproduced": False,
  "note": "dG/ddG not reproduced (PyRosetta omitted); DockQ/AAR/RMSD by upstream code unchanged (DockQ==2.1.3).",
}
os.makedirs("/opt/unimomo-run/status", exist_ok=True)
open("/opt/unimomo-run/status/repro_summary.json", "w").write(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
PY
sync_results
stage complete
DRIVER_EOF

# --- upload driver + record exact metric-aggregation note alongside the run ---
aws s3 cp "$DRIVER" "$S3RUN/code/run_unimomo_repro.sh" --only-show-errors
aws s3 cp "$HERE/launch_unimomo_repro.sh" "$S3RUN/code/launch_unimomo_repro.sh" --only-show-errors
echo "uploaded driver -> $S3RUN/code/"

# --- UserData: pull driver, export env, run ---
UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/unimomo-boot.log 2>&1
mkdir -p /opt/unimomo-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/run_unimomo_repro.sh /opt/unimomo-run/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/unimomo-run/run.sh
OUT_S3=$S3RUN \\
UNIMOMO_REPO=$UNIMOMO_REPO \\
UNIMOMO_COMMIT=$UNIMOMO_COMMIT \\
CKPT_URL=$CKPT_URL \\
CKPT_SIZE=$CKPT_SIZE \\
LNR_URL="$LNR_URL" \\
LNR_SIZE=$LNR_SIZE \\
ENV_YAML=$ENV_YAML \\
N_SAMPLES=$N_SAMPLES \\
TARGET_DOCKQ=$TARGET_DOCKQ \\
MAX_RUNTIME=$MAX_RUNTIME \\
bash /opt/unimomo-run/run.sh
EOF
)

# --- spot-first across type x AZ combos; on-demand fallback (authorized) ---
# 24GB-GPU instances, more vCPU preferred (DockQ eval is CPU-bound).
declare -a COMBO=(
  "g5.4xlarge subnet-0254e4c3634b41bfc"    # 16 vCPU, A10G 24GB, 2c
  "g5.4xlarge subnet-03b277a7a08d388c1"    # 2b
  "g5.4xlarge subnet-09e4dce46682a6c60"    # 2a
  "g6.4xlarge subnet-0254e4c3634b41bfc"    # 16 vCPU, L4 24GB, 2c
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"    # 2d
  "g5.8xlarge subnet-0254e4c3634b41bfc"    # 32 vCPU, A10G 24GB, 2c
  "g6.8xlarge subnet-0254e4c3634b41bfc"    # 32 vCPU, L4 24GB, 2c
  "g5.2xlarge subnet-0254e4c3634b41bfc"    # 8 vCPU fallback, 2c
  "g5.2xlarge subnet-03b277a7a08d388c1"    # 2b
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"    # 8 vCPU fallback, 2d
)

launch_one() {   # $1=market (spot|ondemand)
  local market="$1" c TYPE SUBNET market_opt=""
  [ "$market" = spot ] && market_opt='--instance-market-options {"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}'
  for c in "${COMBO[@]}"; do
    set -- $c; TYPE=$1; SUBNET=$2
    echo "[$market] trying $TYPE in $SUBNET ..."
    IID=$(aws ec2 run-instances \
      --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
      --subnet-id "$SUBNET" --security-group-ids "$SG" \
      --iam-instance-profile Name=$PROFILE \
      $market_opt \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_GB,\"VolumeType\":\"gp3\"}}]" \
      --user-data "$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && [ "$IID" != "None" ] \
      && { echo "LAUNCHED [$market] $TYPE $SUBNET -> $IID"; return 0; }
    echo "  no capacity ([$market] $TYPE $SUBNET), trying next"
  done
  return 1
}

IID=""
launch_one spot || launch_one ondemand || true
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity (spot or on-demand) across all combos"; rm -f "$DRIVER"; exit 1; }

rm -f "$DRIVER"
echo "=============================================================="
echo "RUNID    = $RUNID"
echo "INSTANCE = $IID"
echo "S3 RESULT= $S3RUN/"
echo "  status : $S3RUN/status/status.json"
echo "  summary: $S3RUN/status/repro_summary.json  (reproduced DockQ vs $TARGET_DOCKQ)"
echo "  results: $S3RUN/results/   (candidates/<id>/<n>.pdb, references/, results.jsonl, eval_*)"
echo "=============================================================="
