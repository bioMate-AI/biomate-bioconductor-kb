#!/bin/bash
# Lightweight bootstrap for a CPU disk box that only builds/fetches the mid-training corpus
# (no GPU, no vLLM/bitsandbytes). Use as BOOTSTRAP=fetch_bootstrap.sh for the corpus-build launch.
set -euo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
mkdir -p "$SCRATCH/data" "$SCRATCH/midtrain_corpus"
if ! command -v aws >/dev/null; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install)
fi
command -v git >/dev/null || (sudo apt-get update -q && sudo apt-get install -y -q git)
pip install -q -U "datasets" "huggingface_hub" "zstandard"
echo "FETCH_BOOTSTRAP_DONE scratch=$SCRATCH"
