#!/bin/bash
# Phase-1 cyclic fine-tune: warm-start the LDM from the pubmatch checkpoint, fine-tune on the
# PepBDB cyclic train split (697), then calibrate + evaluate on the 88 cyclic test with default
# vs cyclic (head-to-tail closure) guidance. Does fine-tuning + guidance actually close them?
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
PUBMATCH="s3://$BUCKET/cyclic_peptide/runs/pepglad-pubmatch-20260914T043137Z"
CYCLIC_DATA="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed"
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/finetune.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
sync_ckpts(){ aws s3 sync "$ROOT/PepGLAD/run_outputs/cyclic_ldm" "$OUT_S3/training/cyclic_ldm/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=ft-deadline --on-active="${MAX_RUNTIME:-4h}" /sbin/shutdown -h now || true
# periodic checkpoint backup (spot safety)
(while sleep 120; do sync_ckpts; done) &

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install -q 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'tensorboard==2.19.0' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'requests==2.32.3' 'boto3>=1.36,<2'
python -c 'import torch,torch_scatter; from torch.utils.tensorboard import SummaryWriter; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage preparing
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/generate_validation.py" "$ROOT/code/generate_validation.py" --only-show-errors
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/patch_training_integrity.py" "$ROOT/code/patch_training_integrity.py" --only-show-errors
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
python "$ROOT/code/patch_training_integrity.py" --root "$ROOT/PepGLAD" || true
mkdir -p datasets/pepbdb/processed run_outputs
aws s3 sync "$CYCLIC_DATA" datasets/pepbdb/processed --only-show-errors
wc -l datasets/pepbdb/processed/train_index.txt datasets/pepbdb/processed/valid_index.txt datasets/pepbdb/processed/test_index.txt

stage fetch_warmstart
aws s3 sync "$PUBMATCH/training/autoencoder/version_0/checkpoint/" ae_ckpt/ --only-show-errors
AE_BASENAME=$(python - <<'PY'
from pathlib import Path
print(Path(next(Path('ae_ckpt').glob('topk_map.txt')).read_text().splitlines()[0].split(': ',1)[1]).name)
PY
)
export AE_CKPT="$PWD/ae_ckpt/$AE_BASENAME"
aws s3 cp "$PUBMATCH/training/ldm/version_0/checkpoint/epoch99_step17000.ckpt" ldm_warmstart.ckpt --only-show-errors
export LDM_CKPT="$PWD/ldm_warmstart.ckpt"
echo "AE_CKPT=$AE_CKPT  LDM_CKPT=$LDM_CKPT"; test -f "$AE_CKPT"; test -f "$LDM_CKPT"

stage finetuning
python - <<'PY'
import os, yaml
from pathlib import Path
c = yaml.safe_load(Path('configs/pepbench/ldm/train_codesign.yaml').read_text())
P = 'datasets/pepbdb/processed'
mk = lambda idx: {'class':'CoDesignDataset','mmap_dir':P,'specify_index':f'{P}/{idx}',
                  'backbone_only':False,'use_covariance_matrix':True}  # no cluster (optional)
c['dataset'] = {'train': mk('train_index.txt'), 'valid': mk('valid_index.txt')}
c['dataloader']['num_workers'] = 0
c['dataloader']['wrapper']['ubound_per_batch'] = 40000  # A10G-safe (60000 OOMs)
c['trainer']['config'].update(max_epoch=int(os.environ.get('FT_EPOCHS','60')), save_topk=3,
                              val_freq=5, patience=15, save_dir='run_outputs/cyclic_ldm', grad_clip=1.0)
c['model']['autoencoder_ckpt'] = os.environ['AE_CKPT']
c['load_ckpt'] = os.environ['LDM_CKPT']  # warm-start weights (load_state_dict from full model)
Path('run_outputs/cyclic_ldm.yaml').write_text(yaml.safe_dump(c, sort_keys=False))
print('fine-tune config written; max_epoch', c['trainer']['config']['max_epoch'])
PY
python train.py --gpus 0 --seed 20260912 --config run_outputs/cyclic_ldm.yaml
sync_ckpts

stage calibrating
BEST=$(python - <<'PY'
from pathlib import Path
print(next(Path('run_outputs/cyclic_ldm').glob('version_*/checkpoint/topk_map.txt')).read_text().splitlines()[0].split(': ',1)[1])
PY
)
cp "$BEST" cyclic_calibrated.ckpt
python - <<'PY'
import yaml
from pathlib import Path
c = yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataset']['test']['mmap_dir'] = 'datasets/pepbdb/processed'
c['dataset']['test']['specify_index'] = 'datasets/pepbdb/processed/train_index.txt'
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/cyclic_calib.yaml').write_text(yaml.safe_dump(c))
PY
python setup_latent_guidance.py --config run_outputs/cyclic_calib.yaml --ckpt cyclic_calibrated.ckpt --gpu 0

stage evaluating
for mode in default cyclic; do
  PYTHONPATH="$PWD" python "$ROOT/code/generate_validation.py" --checkpoint cyclic_calibrated.ckpt \
    --dataset-dir datasets/pepbdb/processed --index test_index.txt --guidance "$mode" --attempts 4 \
    --output "run_outputs/cyclic_eval_$mode" > "$ROOT/status/eval_$mode.log" 2>&1 || echo "eval $mode failed"
  cp -f "run_outputs/cyclic_eval_$mode/summary.json" "$ROOT/status/summary_$mode.json" 2>/dev/null || true
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
done
aws s3 sync run_outputs/cyclic_ldm "$OUT_S3/training/cyclic_ldm/" --only-show-errors || true
stage cyclic_finetune_complete
