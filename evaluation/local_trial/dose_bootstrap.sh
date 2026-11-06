#!/bin/bash
# Minimal bootstrap for the on-prem dose eval: AWS CLI (if missing) + vLLM.
set -uo pipefail
if ! command -v aws >/dev/null; then
  curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip
  (cd /tmp && unzip -q a.zip && sudo ./aws/install)
fi
pip install -q -U vllm 2>&1 | tail -2 || pip3 install -q -U vllm 2>&1 | tail -2 || true
echo "BOOTSTRAP_DONE"
