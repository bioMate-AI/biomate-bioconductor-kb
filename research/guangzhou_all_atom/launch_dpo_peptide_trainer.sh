#!/bin/bash
# =====================================================================================================
# launch_dpo_peptide_trainer.sh — launch the GENERATOR-POLICY Diffusion-DPO "close-back" (dpo_peptide_
# trainer.py) on the PRE-BAKED cyclic-peptide AMI. Consumes a dpo_pairs.py PairSet (chosen>-rejected
# preference pairs from the VERIFY_SELECT / ACTIVITY / EXPERT streams) + the CoDesignDataset mmap holding
# the featurized designs, and fine-tunes the PepGLAD latent-diffusion generator (LDMPepDesign: frozen v1
# AE + warm-started diffusion) with Diffusion-DPO (Wallace et al. 2023 — NOT TRL; the generator is a
# diffusion model, not a sequence LM; see docs/20261002_GENERATOR_DPO_TRAINER_DESIGN.md).
#
# It emits a fine-tuned policy ckpt (same pickle format as epoch-221 / m2c) ready to re-eval on the
# PepBDB-cyclic benchmark via launch_cyclic_benchmark_eval.sh.
#
# Mirrors launch_cyclic_benchmark_eval.sh's proven baked-AMI pattern EXACTLY where it matters:
#   * AMI = ami-06e366a5b89d12344 (baked cyclic-peptide stack; M2c venv at /opt/pepglad-venv -> ACTIVATE,
#     no torch / torch-scatter cold install).
#   * SPOT-FIRST, ON-DEMAND FALLBACK (user-authorized) across the known-good type/subnet ladder.
#   * self-terminate (instance-initiated-shutdown=terminate) + systemd dead-man's-switch + 60s S3 streaming.
#
# It launches ONE GPU instance and nothing else.
# Poll:    aws s3 cp $S3RUN/status/status.json -
# Ckpt:    aws s3 ls  $S3RUN/ckpts/ --recursive
# Report:  aws s3 cp $S3RUN/dpo_report.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-06e366a5b89d12344}      # PRE-BAKED cyclic-peptide AMI (us-west-2); /opt/pepglad-venv ready
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# --- inputs (env-overridable) ------------------------------------------------------------------------
# (a) diffusion warm-start = THE BEST in-house generator, so the DPO close-back lands on the best model.
#     Default = cyclic-FT 0.506 (PepBDB-cyclic DockQ), same PepGLAD arch -> drops in directly as the
#     diffusion warm-start (its .autoencoder is dropped in warm_start_diffusion; the FROZEN AE is V1_AE_S3).
#     Ranked above epoch-221 base (0.291) and the target-conditioned M2c (0.326); see
#     docs/20261002_BEST_PEPTIDE_LLM_PROGRAM.md + project_cyclic_peptide_sota_reality memory.
#     UniMoMo (0.759, different arch) is the ultimate base -> needs the DPO-trainer PORT (scoped separately).
#     Override WARM_LDM_S3 to warm-start from any other ckpt (e.g. epoch-221 base for an ablation).
WARM_LDM_S3=${WARM_LDM_S3:-s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicft-20260914T204012Z/training/cyclic_ldm/version_0/checkpoint/epoch59_step1920.ckpt}
# (b) M1 v1 AE (production AE) -> becomes the FROZEN autoencoder of the policy + reference.
V1_AE_S3=${V1_AE_S3:-s3://$BUCKET/cyclic_peptide/runs/m1-ae-midtrain-20260928T225554Z/ckpts/m1_ae_midtrain/version_0/checkpoint/epoch39_step3520.ckpt}
# (c) the dpo_pairs PairSet jsonl (full-provenance lines; chosen_id/rejected_id index into the mmap below).
PAIRS_S3=${PAIRS_S3:-s3://$BUCKET/cyclic_peptide/dpo/pairsets/latest.jsonl}
# (d) the CoDesignDataset mmap holding the FEATURIZED designs the pairs reference (m2c_process_complexes
#     format). The policy encodes each design to the v1-AE latent exactly as m2c does.
MMAP_S3=${MMAP_S3:-s3://$BUCKET/cyclic_peptide/dpo/designs_mmap}

# training knobs (Diffusion-DPO: large beta, low lr; see design note)
BETA=${BETA:-2000.0}
LR=${LR:-1.0e-6}
STEPS=${STEPS:-400}
GRAD_CLIP=${GRAD_CLIP:-1.0}
MAX_RUNTIME=${MAX_RUNTIME:-4h}

RUNID=dpo-peptide-trainer-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- preflight: fail BEFORE spending an instance if inputs are missing ------------------------------
echo "preflight: checking inputs on S3 ..."
for uri in "$WARM_LDM_S3" "$V1_AE_S3" "$PAIRS_S3"; do
  aws s3 ls "$uri" >/dev/null 2>&1 || { echo "FATAL: input not found: $uri"; exit 1; }
  echo "  ok $uri"
done
aws s3 ls "$MMAP_S3/" >/dev/null 2>&1 || { echo "FATAL: mmap dir not found: $MMAP_S3"; exit 1; }
echo "  ok $MMAP_S3/"
# code bundle: the trainer + its import chain (m2_train_ldm.warm_start_diffusion; the register-only M1/M2
# modules imported at module load; dpo_pairs for the PairSet schema) + the m2c model config + PepGLAD runtime.
for f in dpo_peptide_trainer.py dpo_pairs.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
         m2_train_ldm.py m2c_train_ldm.py m2c_ldm_finetune.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f next to launcher"; exit 1; }
done
echo "preflight OK"

# --- build + upload the code bundle ------------------------------------------------------------------
TMP=$(mktemp -d)
for f in dpo_peptide_trainer.py dpo_pairs.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
         m2_train_ldm.py m2c_train_ldm.py m2c_ldm_finetune.yaml; do
  cp "$HERE/$f" "$TMP/"
done
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  dpo_peptide_trainer.py dpo_pairs.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
  m2_train_ldm.py m2c_train_ldm.py m2c_ldm_finetune.yaml pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  WARM_LDM_S3=$WARM_LDM_S3"
echo "  V1_AE_S3=$V1_AE_S3"
echo "  PAIRS_S3=$PAIRS_S3"
echo "  MMAP_S3=$MMAP_S3"
echo "  BETA=$BETA LR=$LR STEPS=$STEPS GRAD_CLIP=$GRAD_CLIP MAX_RUNTIME=$MAX_RUNTIME"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "/tmp/dpo_driver.$$" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
export ROOT
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data" "$ROOT/ckpts"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -d "$ROOT/ckpts" ] && aws s3 sync "$ROOT/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true
  [ -f "$ROOT/dpo_report.json" ] && aws s3 cp "$ROOT/dpo_report.json" "$OUT_S3/dpo_report.json" --only-show-errors || true
}
finish() { rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed || true; sync_all; shutdown -h now; exit "$rc"; }
trap finish EXIT

# periodic heartbeat + checkpoint stream (every 60s) + best-effort spot-interruption capture
(while sleep 60; do sync_all; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json"; then
    stage spot_interruption; sync_all; break
  fi
done) >/dev/null 2>&1 &

# ---- BAKED AMI: activate the pre-built M2c/PepGLAD venv (torch + torch-scatter already installed) -----
stage activating
source /opt/pepglad-venv/bin/activate
python -c 'import torch,torch_scatter,rdkit,Bio,scipy,yaml; print("pepglad venv ok", torch.__version__, torch.cuda.is_available())'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_data
aws s3 cp "$WARM_LDM_S3" "$ROOT/data/warm_ldm.ckpt" --only-show-errors   # diffusion warm-start
aws s3 cp "$V1_AE_S3"    "$ROOT/data/v1_ae.ckpt"    --only-show-errors   # FROZEN autoencoder
aws s3 cp "$PAIRS_S3"    "$ROOT/data/pairs.jsonl"   --only-show-errors   # dpo_pairs PairSet
mkdir -p "$ROOT/data/designs_mmap"
aws s3 sync "$MMAP_S3" "$ROOT/data/designs_mmap" --only-show-errors      # featurized designs (mmap)

cd "$ROOT/code"

# ---- AE_MODE=warm : matched-latent option. If the pairs' designs were generated by the WARM ckpt's own
# AE (not the v1 AE), swap the frozen AE to the warm ckpt's .autoencoder so the encoded latent matches the
# diffusion's prior. Default AE_MODE=v1 keeps the M1 v1 production AE (the m2c lineage).
if [ "${AE_MODE:-v1}" = "warm" ]; then
  python -c "import sys; sys.path.insert(0,'runtime/PepGLAD'); import torch, models, m1_closure_ae; \
    ldm=torch.load('$ROOT/data/warm_ldm.ckpt', map_location='cpu', weights_only=False); \
    torch.save(ldm.autoencoder, '$ROOT/data/v1_ae.ckpt'); print('[AE_MODE=warm] frozen AE = warm ckpt .autoencoder')"
fi

GPU_FLAG="--gpu 0"
python -c 'import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)' || GPU_FLAG="--gpu -1"

stage training
python dpo_peptide_trainer.py \
  --pairs "$ROOT/data/pairs.jsonl" \
  --config "$ROOT/code/m2c_ldm_finetune.yaml" \
  --warm_start_ldm_ckpt "$ROOT/data/warm_ldm.ckpt" \
  --autoencoder_ckpt "$ROOT/data/v1_ae.ckpt" \
  --mmap_dir "$ROOT/data/designs_mmap" \
  --beta "$BETA" --lr "$LR" --steps "$STEPS" --grad_clip "$GRAD_CLIP" \
  $GPU_FLAG \
  --out "$ROOT/ckpts/dpo_policy.ckpt" \
  --report "$ROOT/dpo_report.json"
cp "$ROOT/dpo_report.json" "$ROOT/status/dpo_report.json" 2>/dev/null || true

stage complete
sync_all
echo "=== DPO fine-tune DONE -> $OUT_S3/ckpts/dpo_policy.ckpt  (report: $OUT_S3/dpo_report.json) ==="
DRIVER
aws s3 cp "/tmp/dpo_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors
rm -f "/tmp/dpo_driver.$$"

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=dpo-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +300 &
exec > /var/log/dpo-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN WARM_LDM_S3=$WARM_LDM_S3 V1_AE_S3=$V1_AE_S3 PAIRS_S3=$PAIRS_S3 MMAP_S3=$MMAP_S3 \
  BETA=$BETA LR=$LR STEPS=$STEPS GRAD_CLIP=$GRAD_CLIP MAX_RUNTIME=$MAX_RUNTIME AE_MODE=${AE_MODE:-v1} \
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
  "g4dn.xlarge subnet-0254e4c3634b41bfc"
  "g4dn.xlarge subnet-03b277a7a08d388c1"
  "g4dn.xlarge subnet-09e4dce46682a6c60"
  "g4dn.xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
)
if [ -n "${COMBO_OVERRIDE:-}" ]; then
  mapfile -t COMBO <<< "$COMBO_OVERRIDE"
fi

# launch: ONE run-instances attempt per market mode ("spot" or "ondemand")
try_launch() {
  local mode=$1 c TYPE SUBNET market_opt
  for c in "${COMBO[@]}"; do
    set -- $c; TYPE=$1; SUBNET=$2
    if [ "$mode" = "spot" ]; then
      market_opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}')
    else
      market_opt=()   # on-demand
    fi
    echo "[$mode] trying $TYPE in $SUBNET ..."
    IID=$(aws ec2 run-instances \
      --image-id "$AMI" --instance-type "$TYPE" ${KEY:+--key-name $KEY} \
      --subnet-id "$SUBNET" --security-group-ids "$SG" \
      --iam-instance-profile Name=AutoimmuneCorpusProfile \
      "${market_opt[@]}" \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
      --user-data "$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide},{Key=market,Value=$mode}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $TYPE $SUBNET -> $IID"; return 0; }
    echo "  no capacity ($TYPE $SUBNET)"
  done
  return 1
}

IID=""
# spot-first; on-demand fallback (user-authorized) if every spot combo is out of capacity
try_launch spot || { echo "all spot combos exhausted -> falling back to ON-DEMAND"; try_launch ondemand; } || true
[ -z "$IID" ] && { echo "FATAL: no GPU capacity across all combos (spot AND on-demand)"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:    aws s3 cp $S3RUN/status/status.json -"
echo "ckpt:    aws s3 ls  $S3RUN/ckpts/ --recursive"
echo "report:  aws s3 cp $S3RUN/dpo_report.json -"
