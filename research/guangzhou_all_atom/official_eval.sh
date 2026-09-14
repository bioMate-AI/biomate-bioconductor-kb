#!/bin/bash
# Faithful PepGLAD evaluation: run the repo's OWN generate.py + cal_metrics.py on the LNR test
# set with our trained checkpoint, so results are comparable to the paper's Table 1 (minus dG/
# Success, which need PyRosetta). Removes any doubt that our custom eval harness misgenerates.
set -Eeuo pipefail  # fail loudly: a broken step must not blunder on to an empty results.jsonl
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
CKPT_S3=${CKPT_S3:?}
mkdir -p "$ROOT/status"
exec > >(tee -a "$ROOT/status/official_eval.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
sync_all(){ aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync_all; shutdown -h now; exit $rc' EXIT
systemd-run --unit=eval-deadline --on-active="${MAX_RUNTIME:-3h}" /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install -q 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'requests==2.32.3' 'boto3>=1.36,<2'
python -c 'import torch,torch_scatter; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'

stage preparing_repo_and_data
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
python "$ROOT/code/patch_training_integrity.py" --root "$ROOT/PepGLAD" || true
mkdir -p datasets
safe_extract() { python - "$1" <<'PY'
import sys, tarfile
from pathlib import Path
out=Path('datasets').resolve()
with tarfile.open(sys.argv[1]) as tf:
    for m in tf.getmembers():
        p=(out/m.name).resolve()
        if not p.is_relative_to(out) or m.issym() or m.islnk() or not (m.isfile() or m.isdir()):
            raise ValueError('unsafe member '+m.name)
    tf.extractall(out)
PY
}
# train_valid — REQUIRED by setup_latent_guidance (calibration reads train_valid/processed/train_index.txt)
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/pepbench/v2/train_valid.tar.gz" /tmp/tv.tar.gz --only-show-errors
safe_extract /tmp/tv.tar.gz
python -m scripts.data_process.process --index datasets/train_valid/all.txt --out_dir datasets/train_valid/processed
python -m scripts.data_process.split --train_index datasets/train_valid/train.txt --valid_index datasets/train_valid/valid.txt --processed_dir datasets/train_valid/processed/
# LNR test set (for the official generation)
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/pepbench/v2/LNR.tar.gz" /tmp/LNR.tar.gz --only-show-errors
safe_extract /tmp/LNR.tar.gz
python -m scripts.data_process.process --index datasets/LNR/test.txt --out_dir datasets/LNR/processed

stage fetch_checkpoint
mkdir -p run_outputs/ldm/version_0/checkpoint
aws s3 cp "$CKPT_S3" run_outputs/ldm/version_0/checkpoint/provided.ckpt --only-show-errors
CKPT="$PWD/run_outputs/ldm/version_0/checkpoint/provided.ckpt"

stage calibrating
python - <<'PY'
import yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/calib.yaml').write_text(yaml.safe_dump(c))
PY
python setup_latent_guidance.py --config run_outputs/calib.yaml --ckpt "$CKPT" --gpu 0

stage generating_official
# lower n_samples than the paper's 40 to bound cost; still a real multi-sample eval.
export N_SAMPLES=${N_SAMPLES:-10}
python - <<'PY'
import os, yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/test_codesign.yaml').read_text())
c['dataloader']['num_workers']=0
c['n_samples']=int(os.environ['N_SAMPLES'])
Path('run_outputs/test_codesign.yaml').write_text(yaml.safe_dump(c))
print('n_samples =', c['n_samples'])
PY
python generate.py --config run_outputs/test_codesign.yaml --ckpt "$CKPT" --gpu 0 --save_dir ./results/codesign
aws s3 cp ./results/codesign/results.jsonl "$OUT_S3/results/results.jsonl" --only-show-errors || true

stage cal_metrics
# No --filter_dG / --rosetta => Consistency, Diversity (seq/struct/codesign), RMSD, DockQ, Slide AAR.
python cal_metrics.py --results ./results/codesign/results.jsonl 2>&1 | tee "$ROOT/status/official_metrics.txt"
aws s3 cp "$ROOT/status/official_metrics.txt" "$OUT_S3/status/official_metrics.txt" --only-show-errors || true
stage official_eval_complete
sync_all
