#!/usr/bin/env bash
# Training-only bootstrap: inference server and retriever packages are separate.
set -euo pipefail
if ! python3 -c 'import ensurepip' 2>/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv
fi
python3 -m venv --system-site-packages /opt/biomate-cpt-venv
/opt/biomate-cpt-venv/bin/pip install --disable-pip-version-check \
  'transformers>=4.44' 'trl>=0.9' 'peft>=0.12' datasets accelerate bitsandbytes
/opt/biomate-cpt-venv/bin/pip freeze > /opt/biomate-cpt-venv/requirements.resolved.txt
