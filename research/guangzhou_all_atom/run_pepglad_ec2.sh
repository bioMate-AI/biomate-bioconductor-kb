#!/bin/bash
# Bounded canonical all-heavy-atom PepGLAD baseline; not a novel trained model.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
OUT_S3=${OUT_S3:?}
mkdir -p "$ROOT/status" "$ROOT/PepGLAD/run_outputs"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1
stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_results() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  aws s3 sync "$ROOT/PepGLAD/run_outputs" "$OUT_S3/training/" --only-show-errors || true
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
# Instance shutdown behavior is terminate. Watchdog also runs if this shell hangs.
if ! systemctl is-active --quiet peptide-deadline.timer; then
  if [ -n "${DEADLINE_UTC:-}" ]; then
    systemd-run --unit=peptide-deadline --on-calendar="$DEADLINE_UTC" /sbin/shutdown -h now
  else
    systemd-run --unit=peptide-deadline --on-active=4h /sbin/shutdown -h now
  fi
fi
(while sleep 120; do sync_results; done) &
stage installing
if [ "${RESUME_SETUP:-0}" != 1 ]; then
apt-get update -qq
apt-get install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"
source "$ROOT/venv/bin/activate"
pip install --disable-pip-version-check 'pip==25.0.1'
pip install 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'tensorboard==2.19.0' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'requests==2.32.3' 'boto3>=1.36,<2'
fi
source "$ROOT/venv/bin/activate"
pip freeze > "$ROOT/status/environment.txt"
python -c 'import torch,torch_scatter; assert torch.cuda.is_available(); print(torch.__version__,torch.cuda.get_device_name(0))'
stage collecting
python "$ROOT/code/collect_pepbench.py" --bucket knowledge-datasets-1759951976 --out "$ROOT/raw" --metadata "$ROOT/code/pepbench_zenodo.json" --include train_valid.tar.gz LNR.tar.gz README.md
cp "$ROOT/raw/acquisition_manifest.json" "$ROOT/status/"
python "$ROOT/code/collect_pepbench.py" --bucket knowledge-datasets-1759951976 --out "$ROOT/raw/augmentation" --metadata "$ROOT/code/pepbench_zenodo.json" --include ProtFrag.tar.gz > "$ROOT/status/augmentation.log" 2>&1 &
AUG_PID=$!
sync_results
stage preparing
if [ ! -d "$ROOT/upstream/.git" ]; then
  git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/upstream"
fi
cd "$ROOT/upstream"
git checkout bad015ca50c312a89482adb5220c3d907f13df5c
git rev-parse HEAD > "$ROOT/status/upstream_commit.txt"
# Keep actual source in the known checkpoint sync path.
cp -a . "$ROOT/PepGLAD/"
cd "$ROOT/PepGLAD"
mkdir -p datasets
python - <<'PY'
import tarfile
from pathlib import Path
archive=Path('/opt/guangzhou-peptide/raw/train_valid.tar.gz')
out=Path('datasets').resolve()
with tarfile.open(archive) as tf:
    for member in tf.getmembers():
        path=(out/member.name).resolve()
        if not path.is_relative_to(out) or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            raise ValueError('Unsafe archive member: '+member.name)
    tf.extractall(out)
PY
python -m scripts.data_process.process --index datasets/train_valid/all.txt --out_dir datasets/train_valid/processed
python -m scripts.data_process.split --train_index datasets/train_valid/train.txt --valid_index datasets/train_valid/valid.txt --processed_dir datasets/train_valid/processed/
python - <<'PY'
import json
from pathlib import Path
p=Path('datasets/train_valid')
sets={s:{line.split()[0] for line in (p/(s+'.txt')).read_text().splitlines() if line.strip()} for s in ['train','valid']}
assert sets['train'] and sets['valid'] and not sets['train']&sets['valid']
r={'train_complex_ids':len(sets['train']),'valid_complex_ids':len(sets['valid']),'id_overlap':0,
   'split_policy':'published PepBench v2; further sequence/target leakage audit pending',
   'held_out_LNR':'archived, never extracted or used for fitting/checkpoint selection',
   'ProtFrag':'collected and reserved; not included in this initial run'}
Path('run_outputs/split_audit.json').write_text(json.dumps(r,indent=2))
PY
# Fail visibly instead of upstream's zero-loss replacement on NaN/OOM.
python "$ROOT/code/patch_training_integrity.py" --root "$ROOT/PepGLAD"
python "$ROOT/code/configure_pepglad.py" --root "$ROOT/PepGLAD" --stage autoencoder
stage training_autoencoder
python train.py --gpus 0 --seed 20260912 --config run_outputs/autoencoder.yaml
sync_results
CKPT=$(python - <<'PY'
from pathlib import Path
p=next(Path('run_outputs/autoencoder').glob('version_*/checkpoint/topk_map.txt'))
print(p.read_text().splitlines()[0].split(': ',1)[1])
PY
)
python "$ROOT/code/configure_pepglad.py" --root "$ROOT/PepGLAD" --stage ldm --checkpoint "$CKPT"
stage training_latent_diffusion
python train.py --gpus 0 --seed 20260912 --config run_outputs/ldm.yaml
stage initial_training_complete
sync_results
stage waiting_for_augmentation_archive
wait "$AUG_PID"
cp "$ROOT/raw/augmentation/acquisition_manifest.json" "$ROOT/status/augmentation_manifest.json"
stage initial_training_and_collection_complete
sync_results
