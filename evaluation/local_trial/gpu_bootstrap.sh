#!/bin/bash
# GPU box bootstrap for the on-prem BioMate LLM pipeline.
# Target AMI: AWS Deep Learning Base GPU AMI (Ubuntu). Instance profile: AutoimmuneCorpusProfile
# (S3 read/write to biomate-models-...). Fast local scratch: /opt/dlami/nvme.
# NOTE: Ubuntu 24.04 has no `awscli` apt package -> install AWS CLI v2 from the official zip.
set -euo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
mkdir -p "$SCRATCH/data" "$SCRATCH/models" "$SCRATCH/out"

echo "=== AWS CLI v2 (Ubuntu 24.04 has no apt awscli) ==="
if ! command -v aws >/dev/null; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install)
fi

echo "=== python deps ==="
pip install -q -U "transformers>=4.44" "trl>=0.9" "peft>=0.12" "datasets" "accelerate" \
  "bitsandbytes" "sentence-transformers" "vllm" "scikit-learn"

echo "=== pull training data from S3 ==="
aws s3 cp $S3/sft/multitask_sft_enriched.jsonl "$SCRATCH/data/sft_enriched.jsonl"
aws s3 cp $S3/midtrain_corpus/midtrain_all.jsonl "$SCRATCH/data/midtrain_all.jsonl"
aws s3 cp $S3/retriever/bge-routing-contrastive/ "$SCRATCH/models/bge-routing-contrastive/" --recursive
# holdout for eval (family/temporal split lives beside the SFT set)
aws s3 cp $S3/sft/holdout.jsonl "$SCRATCH/data/holdout.jsonl" || echo "(no holdout.jsonl yet — build one from a family/temporal split)"

echo "BOOTSTRAP_DONE  scratch=$SCRATCH"
echo "Next: MODEL_SIZE=small bash gpu_run_pipeline.sh   (then MODEL_SIZE=large ...)"
