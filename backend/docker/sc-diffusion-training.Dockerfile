# BioMate sc-diffusion-training image — single-cell expression structure-diffusion
# training / fine-tuning (scrna_diffusion: scDiffusion / CFGen).
#
# SEPARATE from ml-training.Dockerfile and trl-training.Dockerfile on purpose:
# scDiffusion/CFGen pull a torch-CUDA stack + scanpy/anndata that conflict with
# both Ludwig's pins (ml-training) and TRL's transformers pin (trl-training).
# All three images expose the SAME `python -m ml_training.cli` entrypoint; the
# CLI dispatches model_type=scrna_diffusion to scrna_diffusion_trainer.py, which
# lazy-imports the framework + anndata.
#
# The executor picks this image for model_type in DIFFUSION_MODEL_TYPES
# (scrna_diffusion) via SC_DIFFUSION_TRAINING_IMAGE
# (executor_payload._resolve_container + nextflow_executor.py container
# auto-select). The TRAIN process carries `label 'process_gpu'` → GPU Batch queue.
#
# Build context = repo root (so the COPY path resolves). See
# .github/workflows/sc-diffusion-training-image.yml (CI/ops — build is a later step).
#
# NOTE: unlike the CPU trl/ml images, this MUST be a CUDA base for real runs.
# The tag below is the GPU variant; a CPU smoke variant can swap the torch wheel.
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive

# python3.10 + procps (`ps` for the Nextflow task wrapper) + build/runtime libs.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3-pip build-essential libgomp1 curl unzip ca-certificates procps \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 — the .nf TRAIN process stages the h5ad + outputs with `aws s3 cp`.
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Python deps.
#  - torch-cuda (CUDA 12.1 wheel) FIRST so the diffusion backbone runs on GPU.
#  - scanpy/anndata for h5ad load + marker-gene metrics.
#  - scDiffusion (EperLuo/scDiffusion) — default framework: denoising diffusion
#    over scRNA-seq embeddings with a fine-tunable SCimilarity autoencoder +
#    classifier-guided conditional generation. CFGen (theislab/CFGen,
#    flow-matching) is the alternative; installed from GitHub (no PyPI wheel).
#    Pinned pip installs from source are wired at CI/ops time.
RUN pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
         torch==2.5.1 \
    && pip install --prefer-binary scanpy anndata numpy scipy mlflow
# scDiffusion / CFGen are installed from GitHub at CI/ops time (no PyPI wheels):
#   pip install "git+https://github.com/EperLuo/scDiffusion.git"
#   pip install "git+https://github.com/theislab/CFGen.git"
# Pinned to a reviewed commit in the CI workflow.

# The ml_training package at top-level → `python -m ml_training.cli`.
COPY backend/lib/galaxy/ai/ml_training /app/ml_training
RUN rm -rf /app/ml_training/tests
WORKDIR /app
ENV PYTHONPATH=/app

# Build-time smoke: package + trainer imports (the trainer must import WITHOUT
# the framework/torch present — lazy-import guard) + CLI arg-parse. The concrete
# scDiffusion/CFGen import is exercised at runtime on GPU, not at build.
RUN python -c "import ml_training.config, ml_training.cli, ml_training.scrna_diffusion_trainer; print('sc-diffusion-training image OK')" \
    && python -m ml_training.cli --help >/dev/null

# NO ENTRYPOINT — this is a Nextflow PROCESS image (see ml-training.Dockerfile).
