#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
until test -f CPU_READY; do sleep 3; done
python3 -m venv venv
venv/bin/pip install --quiet boto3
sudo cp scripts/biomate-backup.service scripts/biomate-backup.timer scripts/biomate-spot-notice.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now biomate-backup.timer biomate-spot-notice.service
venv/bin/python - <<'PY'
import json,sqlite3,sys
from pathlib import Path
import boto3
sys.path.insert(0,'scripts')
from checkpoint_store import restore,verify,READY
client=boto3.client('s3')
for receipt_name,directory in [('quantized-backup-receipt.json','quantized-checkpoint'),('knowledge-backup-receipt.json','knowledge')]:
    receipt=json.loads((Path('scripts')/receipt_name).read_text())
    destination=Path(directory)
    if destination.exists():
        verify(destination,json.loads((destination/READY).read_text()))
    else:
        restore(receipt['bucket'],receipt['manifest_key'],destination,client,receipt['manifest_sha256'])
    Path(receipt_name).write_text(json.dumps(receipt,indent=2))
with sqlite3.connect('file:knowledge/galaxy_ai_tools.db?mode=ro',uri=True) as db:
    assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
Path('recovery-verification.json').write_text(json.dumps({'model_hashes_verified':True,'knowledge_hashes_verified':True,'sqlite_quick_check':'ok'}))
PY
revision=3057bb66c86c46d5781e50e85462a760ba7d1feb
if [ ! -d llama.cpp/.git ]; then
  git init llama.cpp
  git -C llama.cpp remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C llama.cpp fetch --depth 1 origin "$revision"
git -C llama.cpp checkout --detach "$revision"
git -C llama.cpp rev-parse HEAD > llama-source-revision.txt
cmake -S llama.cpp -B llama.cpp/build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build llama.cpp/build --config Release -j 8 --target llama-server
cp scripts/serve-model.sh .
sudo cp scripts/biomate-local-llm.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now biomate-local-llm.service
venv/bin/python scripts/backup_status.py
