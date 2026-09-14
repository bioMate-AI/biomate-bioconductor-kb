#!/bin/bash
# Diagnose the cyclic fine-tune CUDA device-side assert on CPU (clean IndexError, no async mask).
# Scans the cyclic data's max residue-index (S) and max position_id vs the base model's embedding
# table sizes, then runs one forward on CPU to pinpoint the failing op.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/cyclic-probe
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
PUBMATCH="s3://$BUCKET/cyclic_peptide/runs/pepglad-pubmatch-20260914T043137Z"
CYCLIC_DATA="s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed"
mkdir -p "$ROOT/status"
exec > >(tee -a "$ROOT/status/probe.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=probe-deadline --on-active=90min /sbin/shutdown -h now || true

stage installing
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git unzip curl
command -v aws >/dev/null 2>&1 || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cpu
pip install -q 'torch-scatter==2.1.2' -f https://data.pyg.org/whl/torch-2.5.1+cpu.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'sympy==1.13.1' 'boto3>=1.36,<2'

stage preparing
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c
mkdir -p datasets/pepbdb/processed
aws s3 sync "$CYCLIC_DATA" datasets/pepbdb/processed --only-show-errors
aws s3 cp "$PUBMATCH/training/ldm/version_0/checkpoint/epoch99_step17000.ckpt" warmstart.ckpt --only-show-errors

stage probing
python - <<'PY' 2>&1 | tee /opt/cyclic-probe/status/probe_out.txt
import sys, os, json, traceback
sys.path.insert(0, os.getcwd())
import torch
from data.codesign import CoDesignDataset
from data.format import VOCAB

model = torch.load('warmstart.ckpt', map_location='cpu').eval()
ds = CoDesignDataset(mmap_dir='datasets/pepbdb/processed',
                     specify_index='datasets/pepbdb/processed/train_index.txt',
                     backbone_only=False, use_covariance_matrix=True)
rep = {'dataset_len': len(ds), 'vocab_block': len(VOCAB.idx2block), 'vocab_atom': len(VOCAB.idx2atom)}
ape = getattr(model, 'abs_position_encoding', None)
rep['abs_pos_num_embeddings'] = getattr(ape, 'num_embeddings', str(type(ape)))
# scan cyclic data for max residue index (S) and max position_id
mS = mpos = -1; nblk_max = 0
for i in range(min(len(ds), 300)):
    b = ds.collate_fn([ds[i]])
    mS = max(mS, int(b['S'].max())); mpos = max(mpos, int(b['position_ids'].max()))
    nblk_max = max(nblk_max, int(b['S'].shape[0]))
rep['scan_max_S'] = mS; rep['scan_max_position_id'] = mpos; rep['scan_max_blocks'] = nblk_max
# embedding param shapes
for name, p in model.named_parameters():
    if any(k in name.lower() for k in ('embed', 'position', 'aa_')):
        rep.setdefault('embed_params', {})[name] = list(p.shape)
print("PROBE_REPORT " + json.dumps(rep))
# forward on CPU -> clean traceback if an index is out of range
b = ds.collate_fn([ds[0]])
try:
    out = model(**b)
    print("FORWARD_OK on CPU (crash may be GPU-specific / shape)")
except Exception:
    print("FORWARD_TRACEBACK:")
    traceback.print_exc()
PY
cp /opt/cyclic-probe/status/probe_out.txt /opt/cyclic-probe/status/ 2>/dev/null || true
stage probe_complete
