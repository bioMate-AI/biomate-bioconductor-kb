#!/bin/bash
# =====================================================================================================
# launch_cyclic_benchmark_eval.sh — launch cyclic_benchmark_eval.sh on the PRE-BAKED AMI to score a LIST
# of checkpoints on the SAME PepBDB-cyclic benchmark PepGLAD reports on, so we get an apples-to-apples
# DockQ to compare against PepGLAD's real PepBDB-cyclic number (0.403).
#
# Default list (evaluated on ONE instance, in a loop, to save cost):
#   base         -> s3://.../RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt   (released PepGLAD-class
#                   warm-start; NOT cyclic-trained -> honest LOWER-BOUND baseline on the cyclic test set)
#   current_m2c  -> s3://.../runs/m2c-ldm-finetune-20260930T153141Z/.../epoch39_step320.ckpt  (our CURRENT M2c)
# Each checkpoint writes its own DockQ-on-PepBDB-cyclic result JSON to $S3RUN/<label>/result.json, and a
# combined $S3RUN/summary.json collects both side-by-side with the 0.403 reference.
#
# Mirrors launch_m2c_retrain_enlarged.sh's proven baked-AMI pattern EXACTLY where it matters:
#   * AMI = ami-06e366a5b89d12344 (baked cyclic-peptide stack; M2c venv at /opt/pepglad-venv -> ACTIVATE,
#     no torch cold-install). Only the small DockQ v1.0 build toolchain (git/build-essential/gfortran,
#     git-clone+make on first `evaluation.dockq` import; bake did not prebuild it) is apt-installed ONCE.
#   * SPOT-FIRST, ON-DEMAND FALLBACK (user-authorized) across the known-good type/subnet ladder.
#   * self-terminate (instance-initiated-shutdown=terminate) + systemd dead-man's-switch + 60s S3 streaming.
#
# It launches ONE GPU instance and nothing else.
# Poll:    aws s3 cp $S3RUN/status/status.json -
# Results: aws s3 cp $S3RUN/base/result.json - ; aws s3 cp $S3RUN/current_m2c/result.json -
# Summary: aws s3 cp $S3RUN/summary.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
AMI=${AMI:-ami-06e366a5b89d12344}      # PRE-BAKED cyclic-peptide AMI (us-west-2); /opt/pepglad-venv ready
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# The SAME PepBDB-cyclic test set + PepGLAD commit the 0.506 number was produced on (0.403-comparable lineage).
CYCLIC_DATA=${CYCLIC_DATA:-s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed}
PEPGLAD_COMMIT=${PEPGLAD_COMMIT:-bad015ca50c312a89482adb5220c3d907f13df5c}
N_SAMPLES=${N_SAMPLES:-10}             # matches the 0.506 run's default (keeps the number comparable)
MAX_RUNTIME=${MAX_RUNTIME:-4h}         # two 10-sample evals + DockQ builds; generous ceiling

# Checkpoint list: ';'-separated entries, each "label|s3uri". Override via CKPTS to score other checkpoints.
BASE_CKPT=${BASE_CKPT:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
CURR_CKPT=${CURR_CKPT:-s3://$BUCKET/cyclic_peptide/runs/m2c-ldm-finetune-20260930T153141Z/ckpts/m2c_ldm_finetune/version_0/checkpoint/epoch39_step320.ckpt}
CKPTS=${CKPTS:-base|$BASE_CKPT;current_m2c|$CURR_CKPT}

RUNID=cyclic-benchmark-eval-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- preflight: fail BEFORE spending an instance if inputs are missing ------------------------------
echo "preflight: checking checkpoints + benchmark data on S3 ..."
IFS=';' read -ra _CK <<< "$CKPTS"
for e in "${_CK[@]}"; do
  lbl=${e%%|*}; uri=${e#*|}
  aws s3 ls "$uri" >/dev/null 2>&1 || { echo "FATAL: checkpoint not found ($lbl): $uri"; exit 1; }
  echo "  ok $lbl -> $uri"
done
aws s3 ls "$CYCLIC_DATA/test_index.txt" >/dev/null 2>&1 || { echo "FATAL: benchmark test_index.txt not found under $CYCLIC_DATA"; exit 1; }
[ -f "$HERE/cyclic_benchmark_eval.sh" ] || { echo "FATAL: missing cyclic_benchmark_eval.sh next to launcher"; exit 1; }
echo "preflight OK"

# --- upload the eval script (+ optional AE shim for fork-AE checkpoints like M2c) ---------------------
aws s3 cp "$HERE/cyclic_benchmark_eval.sh" "$S3RUN/code/cyclic_benchmark_eval.sh" --only-show-errors
echo "uploaded cyclic_benchmark_eval.sh -> $S3RUN/code/"
# m1_closure_ae.py defines ClosureAwareAutoEncoder (the M2c ckpt's pickled AE). Ship it so the eval can
# import it before torch.load. Harmless for stock-AE ckpts (base/FT). AE_SHIM_LOCAL overridable; set to
# "" to skip (stock-AE-only runs).
AE_SHIM_LOCAL=${AE_SHIM_LOCAL:-$HERE/m1_closure_ae.py}
AE_SHIM_S3=""
if [ -n "$AE_SHIM_LOCAL" ] && [ -f "$AE_SHIM_LOCAL" ]; then
  AE_SHIM_S3="$S3RUN/code/m1_closure_ae.py"
  aws s3 cp "$AE_SHIM_LOCAL" "$AE_SHIM_S3" --only-show-errors
  echo "uploaded AE shim m1_closure_ae.py -> $AE_SHIM_S3"
else
  echo "NOTE: no AE shim shipped (fork-AE checkpoints like M2c would fail to unpickle without it)"
fi
echo "  CKPTS=$CKPTS"
echo "  CYCLIC_DATA=$CYCLIC_DATA  N_SAMPLES=$N_SAMPLES  MAX_RUNTIME=$MAX_RUNTIME  AE_SHIM_S3=${AE_SHIM_S3:-<none>}"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "/tmp/cbe_driver.$$" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
export ROOT
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/results"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -f "$ROOT/summary.json" ] && aws s3 cp "$ROOT/summary.json" "$OUT_S3/summary.json" --only-show-errors || true
}
finish() { rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage failed || true; sync_all; shutdown -h now; exit "$rc"; }
trap finish EXIT

# periodic heartbeat (every 60s) + best-effort spot-interruption capture
(while sleep 60; do sync_all; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json"; then
    stage spot_interruption; sync_all; break
  fi
done) >/dev/null 2>&1 &

# ---- BAKED AMI: activate the pre-built M2c/PepGLAD venv (NO torch/torch-scatter cold install) -------
stage activating
source /opt/pepglad-venv/bin/activate
# DockQ v1.0 build toolchain ONCE (evaluation.dockq git-clones+makes DockQ on first import; bake did not
# prebuild it). git/build-essential/gfortran — the same top-up the m2c baked-AMI launcher does.
for attempt in 1 2 3 4 5 6; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; [ "$attempt" = 6 ] && echo "WARN: apt update flaky"; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git build-essential gfortran || echo "WARN: DockQ toolchain apt failed; eval may report DockQ unavailable"
python -c 'import torch,torch_scatter,rdkit,Bio,scipy,yaml; assert torch.cuda.is_available(); print("pepglad venv ok", torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/cyclic_benchmark_eval.sh" "$ROOT/code/cyclic_benchmark_eval.sh" --only-show-errors
chmod +x "$ROOT/code/cyclic_benchmark_eval.sh"

# ---- loop over the checkpoint list; one eval per checkpoint; one bad ckpt does NOT kill the others ----
echo "[]" > "$ROOT/summary.json"
IFS=';' read -ra CK <<< "$CKPTS"
for e in "${CK[@]}"; do
  LBL=${e%%|*}; URI=${e#*|}
  stage "eval_${LBL}"
  echo "=== evaluating $LBL ($URI) ==="
  # Each checkpoint -> its own per-label OUT_S3 result dir. `|| true` so the loop continues on failure
  # (the eval script writes an error result.json itself, so nothing is silently skipped).
  OUT_S3="$OUT_S3/$LBL" CKPT_S3="$URI" CKPT_LABEL="$LBL" \
    CYCLIC_DATA="$CYCLIC_DATA" PEPGLAD_COMMIT="$PEPGLAD_COMMIT" N_SAMPLES="$N_SAMPLES" ROOT="$ROOT" \
    AE_SHIM_S3="${AE_SHIM_S3:-}" \
    bash "$ROOT/code/cyclic_benchmark_eval.sh" || echo "WARN: eval failed for $LBL (continuing)"
  # pull this checkpoint's result.json back and append to the combined summary
  aws s3 cp "$OUT_S3/$LBL/result.json" "$ROOT/results/${LBL}.json" --only-show-errors || true
  python - "$ROOT/summary.json" "$ROOT/results" <<'PY'
import json, sys
from pathlib import Path
summ_p, res_dir = Path(sys.argv[1]), Path(sys.argv[2])
items = []
for p in sorted(res_dir.glob('*.json')):
    try: items.append(json.loads(p.read_text()))
    except Exception as ex: items.append({"ckpt": p.stem, "status": "parse_error", "error": str(ex)})
out = {
  "benchmark": "PepBDB-cyclic",
  "reference": {"PepGLAD_PepBDB_cyclic_DockQ": 0.403, "our_original_cyclic_FT_DockQ": 0.506},
  "results": items,
}
summ_p.write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
PY
  sync_all
done

stage complete
sync_all
echo "=== ALL CHECKPOINTS DONE -> $OUT_S3/summary.json ==="
DRIVER
aws s3 cp "/tmp/cbe_driver.$$" "$S3RUN/code/driver.sh" --only-show-errors
rm -f "/tmp/cbe_driver.$$"

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=cbe-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +300 &
exec > /var/log/cbe-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN CKPTS='$CKPTS' CYCLIC_DATA=$CYCLIC_DATA PEPGLAD_COMMIT=$PEPGLAD_COMMIT \
  N_SAMPLES=$N_SAMPLES MAX_RUNTIME=$MAX_RUNTIME AE_SHIM_S3='$AE_SHIM_S3' \
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
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:     aws s3 cp $S3RUN/status/status.json -"
echo "base:     aws s3 cp $S3RUN/base/result.json -"
echo "current:  aws s3 cp $S3RUN/current_m2c/result.json -"
echo "summary:  aws s3 cp $S3RUN/summary.json -"
