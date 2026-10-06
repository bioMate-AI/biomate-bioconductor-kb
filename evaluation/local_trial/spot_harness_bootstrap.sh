#!/usr/bin/env bash
# Bootstrap for the RealBio LLM+HARNESS eval box. Same proven transformers env as
# spot_cpt800_bootstrap.sh (torch 2.14.1 / transformers 5.18.0 / peft 0.21.2 so Qwen3.5 + the
# cpt1200/sft adapters load exactly as trained), PLUS the OpenAI-shim serving deps
# (fastapi/uvicorn/pydantic) and the openai client the harness runner uses.
set -uo pipefail

echo "=== AWS CLI check ==="
command -v aws >/dev/null || {
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && ./aws/install) || sudo /tmp/aws/install
}

if ! python3 -c 'import ensurepip' 2>/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv
fi

echo "=== transformers venv (reference engine + shim + harness client) ==="
python3 -m venv --system-site-packages /opt/eval-tf
/opt/eval-tf/bin/pip install -q --disable-pip-version-check -U pip setuptools wheel || { echo "TF_PIP_UPGRADE_FAILED"; exit 19; }
/opt/eval-tf/bin/pip install -q --disable-pip-version-check \
  torch==2.14.1 transformers==5.18.0 peft==0.21.2 accelerate==1.15.0 datasets safetensors "huggingface_hub>=0.25" \
  fastapi "uvicorn[standard]" pydantic openai || { echo "TF_VENV_PIP_FAILED"; exit 20; }
/opt/eval-tf/bin/pip freeze > /opt/eval-tf-requirements.txt
echo "TF_VENV_OK"
echo "BOOTSTRAP_DONE"
