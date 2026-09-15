#!/bin/bash
# Rigorous AUTOMATED evaluation of the CYCLIC fine-tuned model with PepGLAD's OWN generate.py +
# cal_metrics on the cyclic test set: DockQ, Consistency, Diversity (seq/struct/codesign),
# Ca-RMSD, Slide AAR — the paper's metrics, on our actual model (previously only run on the
# linear baseline). No wet lab, no PyRosetta (dG/Success deferred to a licensed run).
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
FT_RUN="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicft-20260914T204012Z"
CYCLIC_DATA="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed"
N_SAMPLES=${N_SAMPLES:-10}
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/cyclic_official_eval.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=coe-deadline --on-active=3h /sbin/shutdown -h now || true

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
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
mkdir -p datasets/pepbdb/processed datasets/pepbdb/pdbs
aws s3 sync "$CYCLIC_DATA" datasets/pepbdb/processed --only-show-errors
# reference PDBs live at mmap_dir/../pdbs (cal_metrics + get_summary expect that)
mv datasets/pepbdb/processed/pdbs/* datasets/pepbdb/pdbs/ 2>/dev/null || cp -a datasets/pepbdb/processed/pdbs/. datasets/pepbdb/pdbs/
aws s3 sync "$FT_RUN/training/cyclic_ldm/version_0/checkpoint/" ft_ckpt/ --only-show-errors
BEST=$(python - <<'PY'
from pathlib import Path
print('ft_ckpt/' + Path(next(Path('ft_ckpt').glob('topk_map.txt')).read_text().splitlines()[0].split(': ',1)[1]).name)
PY
)
cp "$BEST" cyclic_model.ckpt; echo "cyclic model: $BEST"

stage filter_and_calibrate
# filter cyclic test to the model's abs_position capacity (< ~29 residues)
python - <<'PY'
import torch
from data.codesign import CoDesignDataset
cap = torch.load('cyclic_model.ckpt', map_location='cpu').abs_position_encoding.weight.shape[0]
P='datasets/pepbdb/processed'; idx=f'{P}/test_index.txt'
lines=open(idx).read().splitlines(keepends=True)
ds=CoDesignDataset(mmap_dir=P, specify_index=idx, backbone_only=False, use_covariance_matrix=True)
keep=[lines[i] for i in range(len(ds))
      if (lambda b:(int(b['position_ids'][b['mask']].max())+1<cap) if b['mask'].any() else False)(ds.collate_fn([ds[i]]))]
open(idx,'w').writelines(keep); print('test kept', len(keep), 'of', len(lines))
PY
cp cyclic_model.ckpt cyclic_calibrated.ckpt
mkdir -p run_outputs
python - <<'PY'
import yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataset']['test']['mmap_dir']='datasets/pepbdb/processed'
c['dataset']['test']['specify_index']='datasets/pepbdb/processed/train_index.txt'
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/calib.yaml').write_text(yaml.safe_dump(c))
PY
python setup_latent_guidance.py --config run_outputs/calib.yaml --ckpt cyclic_calibrated.ckpt --gpu 0 2>&1 | tail -2

stage generating_official
python - <<'PY'
import os, yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/test_codesign.yaml').read_text())
c['dataset']['test']['mmap_dir']='datasets/pepbdb/processed'
c['dataset']['test']['specify_index']='datasets/pepbdb/processed/test_index.txt'
c['dataloader']['num_workers']=0
c['n_samples']=int(os.environ.get('N_SAMPLES','10'))
Path('run_outputs/test_cyclic.yaml').write_text(yaml.safe_dump(c))
print('n_samples', c['n_samples'])
PY
python generate.py --config run_outputs/test_cyclic.yaml --ckpt cyclic_calibrated.ckpt --gpu 0 --save_dir ./results/cyclic
aws s3 cp ./results/cyclic/results.jsonl "$OUT_S3/results/results.jsonl" --only-show-errors || true

stage cal_metrics
python cal_metrics.py --results ./results/cyclic/results.jsonl 2>&1 | tee "$ROOT/status/cyclic_official_metrics.txt"
aws s3 cp "$ROOT/status/cyclic_official_metrics.txt" "$OUT_S3/status/cyclic_official_metrics.txt" --only-show-errors || true
stage cyclic_official_eval_complete
