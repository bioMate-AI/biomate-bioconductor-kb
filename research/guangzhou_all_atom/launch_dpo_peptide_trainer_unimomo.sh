#!/bin/bash
# =============================================================================
# launch_dpo_peptide_trainer_unimomo.sh
#
# Run the GENERATOR-POLICY Diffusion-DPO "close-back" (dpo_unimomo_adapter.py) warm-started from the
# VERIFIED UniMoMo base (reproduced DockQ 0.7754 vs 0.759; run unimomo-repro-20261002T043221Z) — so the
# close-back lands on the actual-best model. The adapter imports the architecture-agnostic Diffusion-DPO
# core from dpo_peptide_trainer.py and only swaps the forward-fn / policy-build / data-encode for UniMoMo
# (LDMMolDesign = frozen CondIterAutoEncoder + trainable FullDPM; forward returns loss_dict{'X','H','total'}).
#
# LAUNCHER: uploads an on-instance driver + the dpo code bundle to S3, starts a GPU instance (SPOT-first
# across type x AZ combos, ON-DEMAND fallback — authorized), self-terminating (shutdown=terminate) +
# dead-man's-switch + streams outputs to S3 every 120s. Builds UniMoMo's OWN env from env_cuda121.yaml
# (NOT the baked pepglad env), with the set +u/set -u guard around `conda activate` (the MKL_INTERFACE_LAYER
# unbound-var fix that caused the 2026-10-02 repro failure).
#
# INPUTS (env-overridable):
#   PAIRS_S3        dpo_pairs PairSet jsonl (chosen>-rejected preference pairs)
#   DATASET_CFG_S3  UniMoMo dataset yaml (create_dataset) pointed at the featurized designs the PairSet
#                   references (ids must match chosen_id/rejected_id). REQUIRED for a real run.
#   WARM_CKPT_URL   UniMoMo ckpt to warm-start from (default = the verified public release model.ckpt).
#
# Usage:   PAIRS_S3=s3://... DATASET_CFG_S3=s3://... bash research/guangzhou_all_atom/launch_dpo_peptide_trainer_unimomo.sh
# Verify:  bash -n research/guangzhou_all_atom/launch_dpo_peptide_trainer_unimomo.sh
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2

BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-04f7da1c787a89267}              # Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)
SG=${SG:-sg-011121fdf81073ec8}
KEY=${KEY:-biomate-trial-resume-20260912}
PROFILE=${PROFILE:-AutoimmuneCorpusProfile}
UNIMOMO_REPO=${UNIMOMO_REPO:-https://github.com/kxz18/UniMoMo.git}
UNIMOMO_COMMIT=${UNIMOMO_COMMIT:-f58f117d43975d45dc2521b34ae3066a095582f0}   # same pin as the verified reproduce
ENV_YAML=${ENV_YAML:-env_cuda121.yaml}
WARM_CKPT_URL=${WARM_CKPT_URL:-https://github.com/kxz18/UniMoMo/releases/download/v1.0/model.ckpt}
WARM_CKPT_SIZE=${WARM_CKPT_SIZE:-420891881}

# inputs (REQUIRED for a real run)
PAIRS_S3=${PAIRS_S3:-s3://$BUCKET/cyclic_peptide/dpo/pairsets/latest.jsonl}
DATASET_CFG_S3=${DATASET_CFG_S3:-}             # UniMoMo dataset yaml for the featurized designs

# training knobs (Diffusion-DPO: large beta, low lr; see design note Part 2)
BETA=${BETA:-2000.0}
LR=${LR:-1.0e-6}
STEPS=${STEPS:-400}
GRAD_CLIP=${GRAD_CLIP:-1.0}
MAX_RUNTIME=${MAX_RUNTIME:-6h}
DISK_GB=${DISK_GB:-250}

RUNID=dpo-unimomo-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- preflight: fail BEFORE spending an instance ---
echo "preflight: checking inputs on S3 ..."
aws s3 ls "$PAIRS_S3" >/dev/null 2>&1 || { echo "FATAL: PAIRS_S3 not found: $PAIRS_S3"; exit 1; }
echo "  ok $PAIRS_S3"
if [ -z "$DATASET_CFG_S3" ]; then
  echo "FATAL: DATASET_CFG_S3 is required (UniMoMo dataset yaml pointed at the featurized designs the"
  echo "       PairSet references). Featurize the designs into a UniMoMo dataset and pass its config."
  exit 1
fi
aws s3 ls "$DATASET_CFG_S3" >/dev/null 2>&1 || { echo "FATAL: DATASET_CFG_S3 not found: $DATASET_CFG_S3"; exit 1; }
echo "  ok $DATASET_CFG_S3"
for f in dpo_unimomo_adapter.py dpo_peptide_trainer.py; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing code file $HERE/$f"; exit 1; }
done

# --- upload the dpo code bundle (adapter + shared core) ---
aws s3 cp "$HERE/dpo_unimomo_adapter.py" "$S3RUN/code/dpo_unimomo_adapter.py" --only-show-errors
aws s3 cp "$HERE/dpo_peptide_trainer.py" "$S3RUN/code/dpo_peptide_trainer.py" --only-show-errors
aws s3 cp "$HERE/launch_dpo_peptide_trainer_unimomo.sh" "$S3RUN/code/launch_dpo_peptide_trainer_unimomo.sh" --only-show-errors

# =============================================================================
# On-instance driver (QUOTED heredoc; reads env exported by UserData).
# =============================================================================
DRIVER=$(mktemp)
cat > "$DRIVER" <<'DRIVER_EOF'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
ROOT=/opt/dpo-unimomo-run
OUT_S3=${OUT_S3:?}
UNIMOMO_REPO=${UNIMOMO_REPO:?}
UNIMOMO_COMMIT=${UNIMOMO_COMMIT:?}
ENV_YAML=${ENV_YAML:?}
WARM_CKPT_URL=${WARM_CKPT_URL:?}
WARM_CKPT_SIZE=${WARM_CKPT_SIZE:?}
PAIRS_S3=${PAIRS_S3:?}
DATASET_CFG_S3=${DATASET_CFG_S3:?}
BETA=${BETA:-2000.0}; LR=${LR:-1.0e-6}; STEPS=${STEPS:-400}; GRAD_CLIP=${GRAD_CLIP:-1.0}
MAX_RUNTIME=${MAX_RUNTIME:-6h}

mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data" "$ROOT/ckpts"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage(){ printf '{"stage":"%s","time":"%s","runid":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "$(basename "$OUT_S3")" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
sync_results(){ aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; [ -d "$ROOT/ckpts" ] && aws s3 sync "$ROOT/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed; sync_results; shutdown -h now; exit "$rc"; }
trap finish EXIT

if ! systemctl is-active --quiet dpo-unimomo-deadline.timer; then
  systemd-run --unit=dpo-unimomo-deadline --on-active="${MAX_RUNTIME:-6h}" /sbin/shutdown -h now || true
fi
(while sleep 120; do sync_results; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json" 2>/dev/null; then
    stage spot_interruption; sync_results; break
  fi
done) >/dev/null 2>&1 &

# ---- Miniforge ----
stage installing_conda
for i in 1 2 3 4 5; do curl -fsSL -o /tmp/miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && break; sleep 10; done
bash /tmp/miniforge.sh -b -p /opt/miniforge
source /opt/miniforge/etc/profile.d/conda.sh

# ---- clone UniMoMo @ pinned commit ----
stage cloning_unimomo
cd "$ROOT"
git clone "$UNIMOMO_REPO" UniMoMo
cd "$ROOT/UniMoMo"; git checkout "$UNIMOMO_COMMIT"; git rev-parse HEAD > "$ROOT/status/unimomo_commit.txt"

# ---- build UniMoMo env ----
stage building_env
conda env create -f "$ENV_YAML"
# conda activate.d references MKL_INTERFACE_LAYER unset -> trips `set -u`; relax across activation only.
set +u
conda activate UniMoMo
set -u
python -c 'import torch; print("torch",torch.__version__,"cuda",torch.cuda.is_available())' | tee "$ROOT/status/torch_check.txt"

# ---- pull inputs: dpo code bundle, warm-start ckpt, pairs, dataset config ----
stage fetching_inputs
aws s3 cp "$OUT_S3/code/dpo_unimomo_adapter.py" "$ROOT/code/dpo_unimomo_adapter.py" --only-show-errors
aws s3 cp "$OUT_S3/code/dpo_peptide_trainer.py" "$ROOT/code/dpo_peptide_trainer.py" --only-show-errors
aws s3 cp "$PAIRS_S3" "$ROOT/data/pairs.jsonl" --only-show-errors
aws s3 cp "$DATASET_CFG_S3" "$ROOT/data/dataset.yaml" --only-show-errors
mkdir -p checkpoints
for i in 1 2 3 4 5; do wget -q -O checkpoints/warm.ckpt "$WARM_CKPT_URL" && break; echo "warm ckpt attempt $i failed"; sleep 15; done
GOT=$(stat -c%s checkpoints/warm.ckpt); echo "warm ckpt bytes: got=$GOT expected=$WARM_CKPT_SIZE" | tee "$ROOT/status/warm_ckpt_size.txt"
[ "$GOT" = "$WARM_CKPT_SIZE" ] || { echo "FATAL: warm ckpt size mismatch"; exit 1; }
sync_results

# ---- run the Diffusion-DPO close-back on the UniMoMo base ----
# UNIMOMO_ROOT lets dpo_unimomo_adapter resolve `import models` from the cloned repo; $ROOT/code holds the
# adapter + shared core on PYTHONPATH.
stage training_dpo
export UNIMOMO_ROOT="$ROOT/UniMoMo"
export PYTHONPATH="$ROOT/code:$ROOT/UniMoMo:${PYTHONPATH:-}"
cd "$ROOT/UniMoMo"
python "$ROOT/code/dpo_unimomo_adapter.py" \
  --pairs "$ROOT/data/pairs.jsonl" \
  --warm_start_ckpt "$ROOT/UniMoMo/checkpoints/warm.ckpt" \
  --dataset_config "$ROOT/data/dataset.yaml" \
  --beta "$BETA" --lr "$LR" --steps "$STEPS" --grad_clip "$GRAD_CLIP" --gpu 0 \
  --out "$ROOT/ckpts/dpo_unimomo_policy.ckpt" \
  --report "$ROOT/status/dpo_report.json" 2>&1 | tee "$ROOT/status/train.log"
sync_results
stage complete
DRIVER_EOF

aws s3 cp "$DRIVER" "$S3RUN/code/run_dpo_unimomo.sh" --only-show-errors
echo "uploaded driver -> $S3RUN/code/"

UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/dpo-unimomo-boot.log 2>&1
mkdir -p /opt/dpo-unimomo-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/run_dpo_unimomo.sh /opt/dpo-unimomo-run/run.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/dpo-unimomo-run/run.sh
OUT_S3=$S3RUN \\
UNIMOMO_REPO=$UNIMOMO_REPO \\
UNIMOMO_COMMIT=$UNIMOMO_COMMIT \\
ENV_YAML=$ENV_YAML \\
WARM_CKPT_URL=$WARM_CKPT_URL \\
WARM_CKPT_SIZE=$WARM_CKPT_SIZE \\
PAIRS_S3=$PAIRS_S3 \\
DATASET_CFG_S3=$DATASET_CFG_S3 \\
BETA=$BETA LR=$LR STEPS=$STEPS GRAD_CLIP=$GRAD_CLIP MAX_RUNTIME=$MAX_RUNTIME \\
bash /opt/dpo-unimomo-run/run.sh
EOF
)

declare -a COMBO=(
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-03b277a7a08d388c1"
  "g5.4xlarge subnet-09e4dce46682a6c60"
  "g6.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
)
launch_one() {
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
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity (spot or on-demand)"; rm -f "$DRIVER"; exit 1; }
rm -f "$DRIVER"
echo "=============================================================="
echo "RUNID    = $RUNID"
echo "INSTANCE = $IID"
echo "poll     : aws s3 cp $S3RUN/status/status.json -"
echo "report   : aws s3 cp $S3RUN/status/dpo_report.json -"
echo "ckpt     : aws s3 ls $S3RUN/ckpts/ --recursive"
echo "=============================================================="
