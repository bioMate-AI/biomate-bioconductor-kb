#!/bin/bash
# Phase-1 guidance-only closure smoke: on the EXISTING (non-cyclic-trained) checkpoint, does the
# head-to-tail closure guidance raise the decoded-peptide closure rate vs default guidance?
# Cheap directional signal BEFORE any cyclic fine-tuning. No claim about design quality.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
CKPT_S3=${CKPT_S3:?}
LIMIT=${LIMIT:-20}
ATTEMPTS=${ATTEMPTS:-2}
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/closure_smoke.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=smoke-deadline --on-active="${MAX_RUNTIME:-2h}" /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install -q 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'requests==2.32.3' 'boto3>=1.36,<2'
# MacroGuide 'ph' mode dep (differentiable persistent homology). Non-fatal: ph_closure_guidance.py
# falls back to the head-to-tail term if this import is unavailable (logged), so default/cyclic are unaffected.
pip install -q 'torch_topological==0.1.7' 2>&1 | tail -1 || echo "torch_topological install FAILED -> ph mode will fall back to head-to-tail term"
python -c 'import torch; assert torch.cuda.is_available(); print(torch.__version__, torch.cuda.get_device_name(0))'
python -c 'import torch_topological; print("torch_topological", torch_topological.__version__)' || echo "WARN: torch_topological unavailable (ph mode = fallback)"

stage preparing
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/generate_validation.py" "$ROOT/code/generate_validation.py" --only-show-errors
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/patch_training_integrity.py" "$ROOT/code/patch_training_integrity.py" --only-show-errors
# MacroGuide guidance module (imported lazily by generate_validation.py only in --guidance ph).
aws s3 cp "s3://$BUCKET/cyclic_peptide/code/ph_closure_guidance.py" "$ROOT/code/ph_closure_guidance.py" --only-show-errors || echo "ph_closure_guidance.py missing on S3 -> ph mode will error; upload it first"
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
python "$ROOT/code/patch_training_integrity.py" --root "$ROOT/PepGLAD" || true
mkdir -p datasets
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/pepbench/v2/train_valid.tar.gz" /tmp/tv.tar.gz --only-show-errors
python - <<'PY'
import tarfile
from pathlib import Path
out=Path('datasets').resolve()
with tarfile.open('/tmp/tv.tar.gz') as tf:
    for m in tf.getmembers():
        p=(out/m.name).resolve()
        if not p.is_relative_to(out) or m.issym() or m.islnk() or not (m.isfile() or m.isdir()): raise ValueError('unsafe '+m.name)
    tf.extractall(out)
PY
python -m scripts.data_process.process --index datasets/train_valid/all.txt --out_dir datasets/train_valid/processed
python -m scripts.data_process.split --train_index datasets/train_valid/train.txt --valid_index datasets/train_valid/valid.txt --processed_dir datasets/train_valid/processed/

stage fetch_and_calibrate
mkdir -p run_outputs/ldm/version_0/checkpoint
aws s3 cp "$CKPT_S3" ckpt.ckpt --only-show-errors
python - <<'PY'
import yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/calib.yaml').write_text(yaml.safe_dump(c))
PY
python setup_latent_guidance.py --config run_outputs/calib.yaml --ckpt ckpt.ckpt --gpu 0  # sets consec_dist, saves back

run_mode() { # $1 = default|cyclic
  local mode="$1"
  stage "generating_$mode"
  PYTHONPATH="$PWD" python "$ROOT/code/generate_validation.py" --checkpoint ckpt.ckpt \
    --output "run_outputs/smoke_$mode" --attempts "$ATTEMPTS" --limit "$LIMIT" --guidance "$mode" \
    > "$ROOT/status/gen_$mode.log" 2>&1 || echo "MODE $mode FAILED (see gen_$mode.log)"
  cp -f "run_outputs/smoke_$mode/summary.json" "$ROOT/status/summary_$mode.json" 2>/dev/null || true
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
run_mode default
run_mode cyclic
run_mode ph        # MacroGuide persistent-homology ring-closure guidance (the new arm)
stage closure_smoke_complete
