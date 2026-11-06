#!/bin/bash
set -euo pipefail
# Termination behavior is set by RunInstances. Timer is installed before downloads.
shutdown -h +180
mkdir -p /opt/biomate-trial
exec > >(tee -a /opt/biomate-trial/bootstrap.log) 2>&1
nvidia-smi
systemctl start docker
# Image digest is recorded for reproducibility; pin this digest for the client bundle.
docker pull vllm/vllm-openai:latest
docker inspect vllm/vllm-openai:latest --format '{{json .RepoDigests}}' > /opt/biomate-trial/image-digest.json
docker run -d --name biomate-local-llm --gpus all --ipc=host \
  -p 127.0.0.1:8000:8000 -v /opt/biomate-trial/hf:/root/.cache/huggingface \
  vllm/vllm-openai:latest Qwen/Qwen3.8-27B \
  --tensor-parallel-size 4 --max-model-len 32768 --max-num-seqs 4 \
  --gpu-memory-utilization 0.90 --enable-auto-tool-choice --tool-call-parser qwen3_coder
