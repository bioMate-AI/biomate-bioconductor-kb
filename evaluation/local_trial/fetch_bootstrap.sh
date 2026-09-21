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
# Pin numpy<2 + a matching pyarrow: bare `pip -U datasets` pulls numpy 2.x against a pyarrow built
# for numpy 1.x -> segfault ("Aborted (core dumped)") on the first arrow->numpy op while streaming.
pip install -q "numpy<2" "pyarrow>=14,<17" "datasets>=2.18,<3" "huggingface_hub>=0.23" "fsspec" "aiohttp" "zstandard"
python3 -c "import numpy,pyarrow,datasets;print('deps:',numpy.__version__,pyarrow.__version__,datasets.__version__)"
echo "FETCH_BOOTSTRAP_DONE scratch=$SCRATCH"
