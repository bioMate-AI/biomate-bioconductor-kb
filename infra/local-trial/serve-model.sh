#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
# This checkpoint has already completed a verified S3 upload and full restore.
exec llama.cpp/build/bin/llama-server -m quantized-checkpoint/qwen-00001-of-00005.gguf --alias Qwen/Qwen3.8-27B --host 127.0.0.1 --port 8000 --ctx-size 32768 --parallel 1 --threads 16 --jinja --reasoning off --chat-template-kwargs '{"enable_thinking":false}'
