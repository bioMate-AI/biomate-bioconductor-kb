#!/usr/bin/env bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
OUTPUT=s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immune_llm_models/all_collected_20260912/source_preflight/
PACKAGE=s3://knowledge-datasets-1759951976/immune_llm_baseline/releases/20260912_all_collected_69e1356e/header_release.tar.gz
EXPECTED=69e1356e0cf7bae0fa5db5b8ced17b1bc65cfe1d752b43287d8b680456c08442
LOG=/var/log/immune_source_preflight.log
exec > >(tee -a "$LOG") 2>&1
mkdir -p /opt/immune_headers/results
cleanup() {
  rc=$?
  trap - EXIT
  echo "Source preflight exit code: $rc at $(date -u)"
  if command -v aws >/dev/null; then
    aws s3 cp "$LOG" "${OUTPUT}run.log" || true
    aws s3 sync /opt/immune_headers/results "${OUTPUT}results/" || true
  fi
  shutdown -h now
}
trap cleanup EXIT
( sleep 21600; echo 'Six-hour preparation deadline reached'; shutdown -h now ) &
dnf install -y python3.12 python3.12-pip awscli-2
python3.12 -m venv /opt/immune_headers/venv
PY=/opt/immune_headers/venv/bin/python
$PY -m pip install 'anndata==0.13.2' 'h5py==3.16.0' 's3fs==2026.7.0' 'numpy==2.4.6' 'scipy==1.18.0' 'pandas==3.0.3' 'boto3==1.43.49'
cd /opt/immune_headers
aws s3 cp "$PACKAGE" source.tar.gz --only-show-errors
echo "$EXPECTED  source.tar.gz" | sha256sum --check
tar -xzf source.tar.gz
$PY - <<'PY'
import hashlib,json
from pathlib import Path
for name,expected in json.loads(Path('payload_manifest.json').read_text()).items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==expected,name
print('All package files verified')
PY
( while true; do aws s3 cp "$LOG" "${OUTPUT}run.log" --only-show-errors || true; sleep 60; done ) &
$PY -u preflight_all_source_headers.py --manifest object_manifest.json --policy cellxgene_header_policy.json --paired-manifest paired_vocabulary.json --out results --workers 4
$PY - <<'PY'
import json,gzip,shutil
from pathlib import Path
p=Path('results/header_manifest.json');m=json.loads(p.read_text())
summary={'candidate_sources':m['candidate_sources'],'reported_sources':m['reported_sources'],'vocab':len(m['vocab']),'statuses':{}}
for source in m['sources']:
    key=source['status'];summary['statuses'][key]=summary['statuses'].get(key,0)+1
Path('results/summary.json').write_text(json.dumps(summary,indent=2))
for p in [Path('results/header_manifest.json'),Path('results/source_headers.jsonl')]:
    with p.open('rb') as src,gzip.open(str(p)+'.gz','wb') as dst:shutil.copyfileobj(src,dst)
    p.unlink()
print(json.dumps(summary))
PY
aws s3 sync results "${OUTPUT}results/" --only-show-errors
