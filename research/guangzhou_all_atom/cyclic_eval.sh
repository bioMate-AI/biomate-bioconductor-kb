#!/bin/bash
# Eval-only: diagnose + fix the fine-tuned cyclic model's guided-generation 0-serialized issue.
# Runs generate_validation on the cyclic test with guidance none/default/cyclic, syncing
# attempts.json (per-sample errors) so we can see exactly why guided sampling fails.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
FT_RUN="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicft-20260914T204012Z"
CYCLIC_DATA="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed"
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/cyclic_eval.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=ceval-deadline --on-active=2h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install -q 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'requests==2.32.3' 'boto3>=1.36,<2'

stage preparing
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/generate_validation.py" "$ROOT/code/generate_validation.py" --only-show-errors
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
mkdir -p datasets/pepbdb/processed datasets/pepbdb/pdbs
aws s3 sync "$CYCLIC_DATA" datasets/pepbdb/processed --only-show-errors
# get_summary reads reference PDBs from mmap_dir/../pdbs; pepbdb.py wrote them into processed/pdbs.
mv datasets/pepbdb/processed/pdbs/* datasets/pepbdb/pdbs/ 2>/dev/null || cp -a datasets/pepbdb/processed/pdbs/. datasets/pepbdb/pdbs/
echo "reference pdbs at datasets/pepbdb/pdbs: $(ls datasets/pepbdb/pdbs | wc -l)"
# fetch best fine-tuned cyclic checkpoint
aws s3 sync "$FT_RUN/training/cyclic_ldm/version_0/checkpoint/" ft_ckpt/ --only-show-errors
BEST=$(python - <<'PY'
from pathlib import Path
print('ft_ckpt/' + Path(next(Path('ft_ckpt').glob('topk_map.txt')).read_text().splitlines()[0].split(': ',1)[1]).name)
PY
)
echo "best fine-tuned ckpt: $BEST"; cp "$BEST" cyclic_model.ckpt

stage filter_test
# re-apply the position filter to the test split (S3 copy is unfiltered 88)
python - <<'PY'
import torch
from data.codesign import CoDesignDataset
cap = torch.load('cyclic_model.ckpt', map_location='cpu').abs_position_encoding.weight.shape[0]
P='datasets/pepbdb/processed'; idx=f'{P}/test_index.txt'
lines=open(idx).read().splitlines(keepends=True)
ds=CoDesignDataset(mmap_dir=P, specify_index=idx, backbone_only=False, use_covariance_matrix=True)
kept=[lines[i] for i in range(len(ds))
      if (lambda b:(int(b['position_ids'][b['mask']].max())+1<cap) if b['mask'].any() else False)(ds.collate_fn([ds[i]]))]
open(idx,'w').writelines(kept); print('test kept', len(kept), 'of', len(lines), 'cap', cap)
PY

stage calibrating
mkdir -p run_outputs
cp cyclic_model.ckpt cyclic_calibrated.ckpt
python - <<'PY'
import yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataset']['test']['mmap_dir']='datasets/pepbdb/processed'
c['dataset']['test']['specify_index']='datasets/pepbdb/processed/train_index.txt'
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/cyclic_calib.yaml').write_text(yaml.safe_dump(c))
PY
python setup_latent_guidance.py --config run_outputs/cyclic_calib.yaml --ckpt cyclic_calibrated.ckpt --gpu 0 2>&1 | tail -3

stage evaluating
run_one(){ # $1 guidance  $2 ckpt
  local g="$1" ck="$2"
  PYTHONPATH="$PWD" python "$ROOT/code/generate_validation.py" --checkpoint "$ck" \
    --dataset-dir datasets/pepbdb/processed --index test_index.txt --guidance "$g" --attempts 4 \
    --output "run_outputs/ceval_$g" > "$ROOT/status/ceval_$g.log" 2>&1 || echo "eval $g nonzero exit"
  cp -f "run_outputs/ceval_$g/summary.json" "$ROOT/status/summary_$g.json" 2>/dev/null || true
  cp -f "run_outputs/ceval_$g/attempts.json" "$ROOT/status/attempts_$g.json" 2>/dev/null || true
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
run_one none cyclic_model.ckpt          # unguided control (no calibration needed)
run_one default cyclic_calibrated.ckpt  # PepGLAD geometry guidance
run_one cyclic cyclic_calibrated.ckpt   # + head-to-tail closure
stage cyclic_eval_complete
