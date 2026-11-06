#!/usr/bin/env bash
# Light bootstrap for the paired CPT-800 MCQA eval box.
#  - /opt/eval-tf   : transformers TEXT-backbone path (the proven reference engine). Mirrors the
#                     training env (today_bootstrap.sh): torch 2.14.1 / transformers 5.18.0 /
#                     peft 0.21.2 so Qwen3.5 + the ckpt-800 adapter load exactly as they trained.
#  - /opt/eval-vllm : vLLM (attempted first; isolated venv so vLLM's own torch can't poison tf).
# ROOT-CAUSE NOTE: the DL AMI's venv ships pip 22.0.2, whose resolver hits
# `assert len(weights) == expected_node_count` (AssertionError) on the transformers dep graph.
# Upgrading pip FIRST in every venv is the fix (not a retry). vLLM install stays best-effort.
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

echo "=== transformers venv (reference engine) ==="
python3 -m venv --system-site-packages /opt/eval-tf
/opt/eval-tf/bin/pip install -q --disable-pip-version-check -U pip setuptools wheel || { echo "TF_PIP_UPGRADE_FAILED"; exit 19; }
/opt/eval-tf/bin/pip install -q --disable-pip-version-check \
  torch==2.14.1 transformers==5.18.0 peft==0.21.2 accelerate==1.15.0 datasets safetensors "huggingface_hub>=0.25" || {
    echo "TF_VENV_PIP_FAILED"; exit 20; }
/opt/eval-tf/bin/pip freeze > /opt/eval-tf-requirements.txt
echo "TF_VENV_OK"

echo "=== vllm venv (attempted engine; best-effort) ==="
python3 -m venv /opt/eval-vllm
if /opt/eval-vllm/bin/pip install -q --disable-pip-version-check -U pip setuptools wheel \
   && /opt/eval-vllm/bin/pip install -q --disable-pip-version-check vllm openai "huggingface_hub>=0.25" ; then
  /opt/eval-vllm/bin/pip freeze > /opt/eval-vllm-requirements.txt
  echo "VLLM_VENV_OK"
else
  echo "VLLM_VENV_FAILED (will use transformers engine)"
fi

echo "BOOTSTRAP_DONE"
