#!/usr/bin/env bash
# Launch v6 SFT training in the GPU Docker container.
#
# v6 corpus: 5,892 train / 326 dev / 326 test (stratified across 7 tasks)
# Built by scripts/build_v6_sft_mix.py from task1, task3, task5-9.
#
# Expected runtime: ~10-12hr on sm_121 (Blackwell GB10). Adjust epochs as needed.
#
# Usage:
#   bash scripts/train_v6.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Rebuild mix if any task file is newer than the split
if [[ ! -f data/regulatory_training/tasks/splits_v6/train.jsonl ]] || \
   find data/regulatory_training/tasks/task[1-9]*.jsonl \
        -newer data/regulatory_training/tasks/splits_v6/train.jsonl 2>/dev/null | grep -q .; then
    echo "[train_v6] rebuilding SFT mix..."
    python scripts/build_v6_sft_mix.py
fi

docker run --rm \
    --gpus all \
    --ipc=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v "$PWD":/workspace \
    -w /workspace \
    biomate/regulatory-llm-train:latest \
    python scripts/finetune_regulatory_llm.py \
        --model qwen3-8b \
        --data data/regulatory_training/tasks/splits_v6 \
        --output models/regulatory_llm_v6 \
        --epochs 3 \
        --batch-size 1 \
        --grad-accum 16 \
        --lora-r 16 \
        --lora-alpha 32 \
        --lr 2e-4 \
        2>&1 | tee logs/train_v6_$(date +%Y%m%d_%H%M%S).log
