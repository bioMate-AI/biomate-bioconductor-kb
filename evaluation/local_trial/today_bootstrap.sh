#!/usr/bin/env bash
set -euo pipefail
if ! python3 -c 'import ensurepip' 2>/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv
fi
python3 -m venv --system-site-packages /opt/biomate-cpt-venv
/opt/biomate-cpt-venv/bin/pip install --disable-pip-version-check \
  torch==2.14.1 transformers==5.18.0 trl==1.14.1 peft==0.21.2 \
  datasets==5.0.1 accelerate==1.15.0 bitsandbytes==0.50.2 flash-linear-attention
/opt/biomate-cpt-venv/bin/pip freeze > /opt/biomate-cpt-venv/requirements.resolved.txt
