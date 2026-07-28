# BioMate ml_training image — the low-code DL training CLI + framework deps.
#
# Runs `python -m ml_training.cli` STANDALONE: the ml_training package is copied
# to the image top-level, and its training path uses only relative imports
# (never galaxy.ai / httpx / drug_discovery), so ludwig's pinned deps
# (pydantic 1.10, numpy<2) stay fully isolated from the Galaxy backend image.
# Validated locally 2026-07-19: `python -m ml_training.cli --model-type
# ludwig_tabular` trains a real Ludwig NN with no galaxy backend present.
#
# Build context = repo root (so the COPY path resolves). See
# .github/workflows/ml-training-image.yml.
FROM python:3.9-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

# System libs RDKit/torch need + tooling for the AWS CLI install.
# procps provides `ps`, which Nextflow's task wrapper requires to collect
# metrics — without it the TRAIN process exits 1 ("Command 'ps' ... not found").
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libgomp1 libxrender1 libxext6 libsm6 curl unzip ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 — the .nf TRAIN process stages S3 inputs/outputs with `aws s3 cp`.
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Python deps.
#  - blis (spaCy transitive via ludwig) fails to build from source on some
#    arches — install the prebuilt wheel first.
#  - Install CPU-only torch FIRST from the PyTorch CPU index. Otherwise ludwig
#    drags in the full nvidia-cuda-cu12 stack (~3GB) that a CPU training image
#    never uses — which both bloats the image and overflows the CI runner disk
#    ("No space left on device"). Pinned to the versions ludwig 0.10.4 resolves.
RUN pip install --upgrade pip \
    && pip install --only-binary :all: blis \
    && pip install --extra-index-url https://download.pytorch.org/whl/cpu \
         torch==2.2.2+cpu torchvision==0.17.2+cpu torchaudio==2.2.2+cpu \
    && pip install --prefer-binary ludwig rdkit PyTDC scikit-learn joblib \
    && pip install --prefer-binary peft accelerate datasets

# The ml_training package at top-level → `python -m ml_training.cli`.
COPY backend/lib/galaxy/ai/ml_training /app/ml_training
RUN rm -rf /app/ml_training/tests
WORKDIR /app
# Nextflow runs .command.sh in the TASK work dir (not /app), so put /app on the
# import path explicitly — otherwise `python -m ml_training.cli` fails with
# ModuleNotFoundError once the CWD is no longer /app.
ENV PYTHONPATH=/app

# Build-time smoke: package imports + CLI arg-parse resolve (no training run).
RUN python -c "import ml_training.config, ml_training.cli, ml_training.ludwig_adapter; print('ml_training image OK')" \
    && python -m ml_training.cli --help >/dev/null

# NO ENTRYPOINT on purpose: this is a Nextflow PROCESS image. Nextflow runs the
# container to exec its own `.command.sh` (bash), which calls
# `python -m ml_training.cli …` explicitly. A pinned ENTRYPOINT would hijack
# Nextflow's bash invocation as CLI args → "error: --dataset is required" (exit
# 2). For manual use, run: `docker run <img> python -m ml_training.cli --help`.
