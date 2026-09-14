#!/bin/bash
# Build the PepBDB CYCLIC processed dataset in PepGLAD format, on a cheap CPU instance.
# Decoupled from the GPU fine-tune so the data stage is verified + reusable. Syncs the processed
# cyclic dataset (mmap + train/valid/test indices) to S3 for the fine-tune to consume.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/cyclic-prep
BUCKET=knowledge-datasets-1759951976
OUT_S3=${OUT_S3:?}
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/dataprep.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=prep-deadline --on-active="${MAX_RUNTIME:-2h}" /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv git
python3 -m venv "$ROOT/venv"; source "$ROOT/venv/bin/activate"
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cpu   # CPU torch: pepbdb.py imports data modules that need torch
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' 'tqdm==4.67.1' 'boto3>=1.36,<2'

stage preparing_repo
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout bad015ca50c312a89482adb5220c3d907f13df5c

stage extract_pepbdb
mkdir -p datasets/pepbdb
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/pepbdb/20200318/pepbdb-20200318.tgz" /tmp/pepbdb.tgz --only-show-errors
tar -xzf /tmp/pepbdb.tgz -C datasets/pepbdb   # -> datasets/pepbdb/pepbdb/<entry>/... + datasets/pepbdb/peptidelist.txt
ls datasets/pepbdb | head
test -f datasets/pepbdb/peptidelist.txt
test -d datasets/pepbdb/pepbdb

stage filter_cyclic
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/pepbdb/20200318/pepbdb_cyclic_split.json" /tmp/split.json --only-show-errors
python - <<'PY'
import json, re, random
random.seed(20260912)
split = json.load(open('/tmp/split.json'))
train_ids = list(split['train']); test_ids = set(split['test'])
cyclic = set(train_ids) | test_ids
# filter the master peptidelist to cyclic entries (key = pdbid_pepchain, matching our detection)
kept = []
with open('datasets/pepbdb/peptidelist.txt') as f:
    for line in f:
        parts = re.split(r'\s+', line.strip())
        if len(parts) < 5:
            continue
        key = parts[0] + '_' + parts[1]
        if key in cyclic:
            kept.append(line if line.endswith('\n') else line + '\n')
open('datasets/pepbdb/cyclic_list.txt', 'w').writelines(kept)
# carve valid from train (~10%), keep test as-is
tr = list(train_ids); random.shuffle(tr)
n_val = max(1, len(tr) // 10)
valid_ids, train2 = tr[:n_val], tr[n_val:]
for name, ids in [('train', train2), ('valid', valid_ids), ('test', sorted(test_ids))]:
    open(f'datasets/pepbdb/{name}.txt', 'w').write('\n'.join(ids) + '\n')
summary = {'cyclic_total': len(cyclic), 'peptidelist_lines_kept': len(kept),
           'split': {'train': len(train2), 'valid': len(valid_ids), 'test': len(test_ids)}}
json.dump(summary, open('/opt/cyclic-prep/status/filter_summary.json','w'), indent=2)
print(json.dumps(summary))
PY

stage process_mmap
python -m scripts.data_process.pepbdb --index datasets/pepbdb/cyclic_list.txt --out_dir datasets/pepbdb/processed
python -m scripts.data_process.split --train_index datasets/pepbdb/train.txt --valid_index datasets/pepbdb/valid.txt --test_index datasets/pepbdb/test.txt --processed_dir datasets/pepbdb/processed/
python - <<'PY'
import json, os
d='datasets/pepbdb/processed'
def n(f):
    p=os.path.join(d,f); return sum(1 for _ in open(p)) if os.path.exists(p) else 0
summ={'index_txt': n('index.txt'), 'train_index': n('train_index.txt'),
      'valid_index': n('valid_index.txt'), 'test_index': n('test_index.txt')}
json.dump(summ, open('/opt/cyclic-prep/status/processed_summary.json','w'), indent=2)
print(json.dumps(summ))
PY

stage upload
aws s3 sync datasets/pepbdb/processed "$OUT_S3/pepbdb_cyclic_processed/" --only-show-errors
stage dataprep_complete
