#!/bin/bash
set -Eeuo pipefail
ROOT=${ROOT:-/opt/unimomo-run}
OUT_S3=${OUT_S3:?Set the S3 prefix of the parent CUDA smoke run}
OUT=$ROOT/SIMULATED_dpo_integration
mkdir -p "$OUT"
exec > >(tee -a "$OUT/integration.log") 2>&1
finish(){ rc=$?; trap - EXIT; printf '{"exit_code":%s}\n' "$rc" > "$OUT/exit_status.json"; aws s3 sync "$OUT" "$OUT_S3/SIMULATED_dpo_integration/" --exclude '*.ckpt' --exclude '*.sqlite' --region us-west-2 --only-show-errors; exit "$rc"; }
trap finish EXIT
while [ ! -f "$ROOT/status/smoke_report.json" ]; do
  if grep -q '"stage":"failed"' "$ROOT/status/status.json"; then echo 'CUDA training smoke failed; DPO not started'; exit 1; fi
  sleep 30
done
source /opt/miniforge/etc/profile.d/conda.sh
set +u; conda activate UniMoMo; set -u
export UNIMOMO_ROOT=$ROOT/UniMoMo
export PYTHONPATH=$ROOT/integration_code:$ROOT/UniMoMo
cd "$ROOT/UniMoMo"
python "$ROOT/integration_code/run_unimomo_dpo_smoke.py" --dataset "$ROOT/UniMoMo/datasets/peptide/cyclic/processed" --checkpoint "$ROOT/UniMoMo/checkpoints/model.ckpt" --out "$OUT"

python "$ROOT/integration_code/audit_unimomo_splits.py" --train "$ROOT/UniMoMo/datasets/peptide/cyclic/processed/train_index.txt" --valid "$ROOT/UniMoMo/datasets/peptide/cyclic/processed/valid_index.txt" --test "$ROOT/UniMoMo/pepbdb_test_index.txt" --out "$OUT/split_audit.json"
