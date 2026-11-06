#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
sudo apt-get update -qq
sudo apt-get install -y -qq postgresql libpq-dev libmagic1 xz-utils
mkdir -p runtimes
cd runtimes
curl -fsSLO https://nodejs.org/dist/v22.18.0/node-v22.18.0-linux-x64.tar.xz
curl -fsSLO https://nodejs.org/dist/v22.18.0/SHASUMS256.txt
python3 - <<'PY'
from pathlib import Path
import hashlib
name='node-v22.18.0-linux-x64.tar.xz'
expected=next(line.split()[0] for line in Path('SHASUMS256.txt').read_text().splitlines() if line.split()[-1]==name)
assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==expected
PY
tar -xf node-v22.18.0-linux-x64.tar.xz
export PATH=/opt/biomate-trial/runtimes/node-v22.18.0-linux-x64/bin:$PATH
cd /opt/biomate-trial/app/frontend
npm ci --no-audit --no-fund > /opt/biomate-trial/app-npm-install.log 2>&1
cd /opt/biomate-trial
python3 -m venv app-venv
app-venv/bin/pip install --quiet 'torch==2.11.0+cpu' --index-url https://download.pytorch.org/whl/cpu
app-venv/bin/pip install --quiet -r app/backend/lib/galaxy/dependencies/pinned-requirements.txt > app-python-install.log 2>&1
app-venv/bin/pip freeze > app-python-environment.txt
printf 'dependencies installed\n' > APP_DEPENDENCIES_READY
