# BioMate trl-training image — preference-optimization / RL fine-tuning (DPO/GRPO).
#
# SEPARATE from ml-training.Dockerfile on purpose: TRL 0.24 needs newer
# torch/transformers/pyarrow than Ludwig 0.10.4's pins (torch==2.2.2,
# pyarrow<15) allow. Co-installing them in one image is unresolvable, so DPO/GRPO
# ship here. Both images expose the SAME `python -m ml_training.cli` entrypoint;
# the CLI dispatches trl_dpo/trl_grpo to trl_trainer.py, which lazy-imports trl.
#
# The executor picks this image for model_type in {trl_dpo, trl_grpo} via
# TRL_TRAINING_IMAGE (executor_payload._resolve_container +
# nextflow_executor.py container auto-select).
#
# Build context = repo root (so the COPY path resolves). See
# .github/workflows/trl-training-image.yml.
FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# procps → `ps` (Nextflow task wrapper); build/runtime libs for torch.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libgomp1 curl unzip ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 — the .nf TRAIN process stages S3 inputs/outputs with `aws s3 cp`.
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Python deps.
#  - CPU-only torch FIRST from the PyTorch CPU index so the nvidia-cuda stack
#    (~3GB) never lands in a CPU image (bloat + CI-runner disk overflow). A GPU
#    variant swaps this for a CUDA wheel later.
#  - transformers PINNED to 4.56.1: TRL 0.24's boolean feature guards (e.g.
#    `if is_mergekit_available():`) rely on transformers' `_is_package_available`
#    returning a bool. transformers 5.x changed it to return a (bool, version)
#    TUPLE, which is always truthy → the guard fires → TRL eagerly imports the
#    optional `mergekit` extra and `from trl import DPOTrainer` dies with
#    "No module named 'mergekit'". Diagnosed live on the test box 2026-07-29:
#    unpinned `transformers` resolved to 5.14.1; pinning 4.56.1 (TRL 0.24's
#    floor) makes is_mergekit_available() correctly False → clean import, NO
#    mergekit needed. TRL 0.24 requires transformers>=4.56.1,!=4.57.0.
RUN pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cpu \
         torch==2.5.1+cpu \
    && pip install --prefer-binary "trl==0.24.0" "transformers==4.56.1" accelerate peft datasets

# The ml_training package at top-level → `python -m ml_training.cli`.
COPY backend/lib/galaxy/ai/ml_training /app/ml_training
RUN rm -rf /app/ml_training/tests
WORKDIR /app
ENV PYTHONPATH=/app

# Build-time smoke: package + REAL trainer imports (catches missing trainer
# submodule deps like mergekit at build, not on Batch) + CLI arg-parse.
RUN python -c "import ml_training.config, ml_training.cli, ml_training.trl_trainer; import trl; from trl import DPOTrainer, DPOConfig, GRPOTrainer, GRPOConfig; print('trl-training image OK', trl.__version__)" \
    && python -m ml_training.cli --help >/dev/null

# NO ENTRYPOINT — this is a Nextflow PROCESS image (see ml-training.Dockerfile).
