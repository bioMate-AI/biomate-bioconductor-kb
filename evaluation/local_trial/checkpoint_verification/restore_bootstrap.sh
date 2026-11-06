#!/bin/bash
set -euo pipefail
python3 -m venv "$SCRATCH/restore-venv" || { apt-get update -qq; apt-get install -y python3-venv; python3 -m venv "$SCRATCH/restore-venv"; }
"$SCRATCH/restore-venv/bin/pip" install --disable-pip-version-check torch==2.14.1 transformers==5.18.0 peft==0.21.2 accelerate==1.15.0 safetensors==0.8.0 tokenizers==0.23.2
