#!/usr/bin/env bash
# Launch v7 DPO training: v6 SFT adapter + checker-grounded preference pairs.
#
# v7 input pairs: synthetic_pairs.jsonl (built offline by build_dpo_pairs.py
# --mode synthetic) plus optional rejection-sampled pairs collected from v6.
#
# Pipeline:
#   v6 SFT adapter → merged into base → fresh LoRA → DPO loss against (chosen, rejected)
#
# Expected runtime: ~4-6hr (DPO is faster than SFT — fewer epochs, smaller loss).
#
# Usage:
#   bash scripts/train_v7.sh                            # synthetic pairs only
#   bash scripts/train_v7.sh data/.../merged_pairs.jsonl  # custom pair file

set -euo pipefail

cd "$(dirname "$0")/.."

DPO_PAIRS=${1:-data/regulatory_training/dpo/synthetic_pairs.jsonl}
V6_ADAPTER=models/regulatory_llm_v6/lora_adapter

if [[ ! -d "$V6_ADAPTER" ]]; then
    echo "[train_v7] ERROR: v6 adapter not found at $V6_ADAPTER"
    echo "Run scripts/train_v6.sh first."
    exit 1
fi

if [[ ! -f "$DPO_PAIRS" ]]; then
    echo "[train_v7] ERROR: DPO pairs not found at $DPO_PAIRS"
    echo "Run: python scripts/build_dpo_pairs.py --mode synthetic"
    exit 1
fi

echo "[train_v7] using $(wc -l < "$DPO_PAIRS") DPO pairs from $DPO_PAIRS"
echo "[train_v7] resuming from v6 adapter at $V6_ADAPTER"

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
        --dpo \
        --dpo-data "$DPO_PAIRS" \
        --resume "$V6_ADAPTER" \
        --output models/regulatory_llm_v7 \
        --epochs 2 \
        --batch-size 1 \
        --grad-accum 16 \
        --lora-r 16 \
        --lora-alpha 32 \
        --lr 2e-4 \
        2>&1 | tee logs/train_v7_$(date +%Y%m%d_%H%M%S).log
