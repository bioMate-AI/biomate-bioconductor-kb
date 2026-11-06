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
res_pos = model.autoencoder.aa_feature.aa_embedding.res_pos_embedding.weight.shape[0]
abs_pos = model.abs_position_encoding.weight.shape[0]
rep['res_pos_table'] = res_pos; rep['abs_pos_table'] = abs_pos
# scan ALL entries: max indices + count entries exceeding each table + run forward per entry
mS = mpos = nblk = -1
over_respos = []; over_abspos = []; crashers = []; ok = 0
for i in range(len(ds)):
    b = ds.collate_fn([ds[i]])
    s_hi = int(b['S'].max()); p_hi = int(b['position_ids'].max())
    mS = max(mS, s_hi); mpos = max(mpos, p_hi); nblk = max(nblk, int(b['S'].shape[0]))
    if p_hi >= res_pos: over_respos.append((i, p_hi))
    # abs_pos only sees masked (peptide) positions +1; check those
    pep_pos = int((b['position_ids'][b['mask']].max().item()) if b['mask'].any() else -1)
    if pep_pos + 1 >= abs_pos: over_abspos.append((i, pep_pos))
    if len(crashers) < 3:
        try:
            model(**b); ok += 1
        except Exception as e:
            crashers.append((i, type(e).__name__, str(e)[:200], s_hi, p_hi, pep_pos))
    else:
        ok += 1
rep.update(scan_max_S=mS, scan_max_position_id=mpos, scan_max_blocks=nblk,
           n_over_res_pos_table=len(over_respos), n_peptide_pos_over_abs_table=len(over_abspos),
           examples_over_abs=over_abspos[:5], forwards_ok=ok, n_crashers=len(crashers))
print("PROBE_REPORT " + json.dumps(rep))
for c in crashers:
    print("CRASHER", c)
PY
cp /opt/cyclic-probe/status/probe_out.txt /opt/cyclic-probe/status/ 2>/dev/null || true
stage probe_complete
