#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
while [ ! -f MODEL_READY ]; do
  if systemctl is-failed --quiet biomate-cpu-prepare; then exit 1; fi
  sleep 15
done
cmake --build llama.cpp/build -j 2 --target llama-gguf-split
if [ ! -d quantized-checkpoint ]; then
  split_stage=$(mktemp -d /opt/biomate-trial/quantized-split.XXXXXX)
  trap 'rm -rf -- "$split_stage"' EXIT
  llama.cpp/build/bin/llama-gguf-split --split-max-size 4G model-q4_k_m.gguf "$split_stage/qwen"
  mv "$split_stage" quantized-checkpoint
  trap - EXIT
fi
venv/bin/python - <<'PY'
import re
from pathlib import Path
files = sorted(Path('quantized-checkpoint').glob('qwen-*-of-*.gguf'))
parts = [re.fullmatch(r'qwen-(\d+)-of-(\d+)\.gguf', p.name) for p in files]
assert parts and all(parts), 'Missing or invalid quantized shard inventory'
count = int(parts[0][2])
assert len(parts) == count and [int(p[1]) for p in parts] == list(range(1, count + 1)) and all(int(p[2]) == count for p in parts), 'Incomplete quantized checkpoint; restore a committed snapshot or rebuild in a fresh directory'
PY
cp base-model-manifest.json model-size-check.json llama-source-revision.txt python-environment.txt quantized-checkpoint/
venv/bin/python - <<'PY'
import json
from pathlib import Path
base=json.loads(Path('base-model-manifest.json').read_text())
Path('quantized-metadata.json').write_text(json.dumps({'kind':'artifact_bundle','scope':'BioMate CPU inference checkpoint; not fine-tuned','base_model':base['model'],'base_model_revision':base['revision'],'quantization':'Q4_K_M'}))
PY
venv/bin/python scripts/checkpoint_store.py seal quantized-checkpoint --metadata quantized-metadata.json > quantized-sealed.json
venv/bin/python scripts/checkpoint_store.py push quantized-checkpoint --bucket biomate-models-399683337364 --prefix biomate-core-local-trial/20260912/cpu-inference > quantized-backup-receipt.json
first=$(find quantized-checkpoint -maxdepth 1 -name 'qwen-00001-of-*.gguf' -print -quit)
test -n "$first"
exec llama.cpp/build/bin/llama-server -m "$first" --alias Qwen/Qwen3.8-27B --host 127.0.0.1 --port 8000 --ctx-size 32768 --parallel 1 --threads 16 --jinja --reasoning off --chat-template-kwargs '{"enable_thinking":false}'
