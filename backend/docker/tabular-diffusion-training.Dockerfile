# BioMate tabular-diffusion-training image — generic tabular-data structure-diffusion
# training / fine-tuning (tabular_diffusion: TabDDPM / TabSyn).
#
# SEPARATE from ml-training.Dockerfile, trl-training.Dockerfile and
# sc-diffusion-training.Dockerfile on purpose: TabDDPM/TabSyn pull a torch-CUDA
# stack + pandas that conflict with Ludwig's pins (ml-training) and TRL's
# transformers pin (trl-training). All images expose the SAME
# `python -m ml_training.cli` entrypoint; the CLI dispatches
# model_type=tabular_diffusion to tabular_diffusion_trainer.py, which
# lazy-imports the framework + pandas.
#
# The executor picks this image for model_type in DIFFUSION_MODEL_TYPES
# (tabular_diffusion) via TABULAR_DIFFUSION_TRAINING_IMAGE
# (executor_payload._resolve_container + nextflow_executor.py container
# auto-select). The TRAIN process carries `label 'process_gpu'` → GPU Batch queue.
#
# Build context = repo root (so the COPY path resolves). See
# .github/workflows/tabular-diffusion-training-image.yml (CI/ops — build is a later step).
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

# AWS CLI v2 — the .nf TRAIN process stages the feature matrix + outputs with `aws s3 cp`.
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Python deps.
#  - torch-cuda (CUDA 12.1 wheel) FIRST so the diffusion backbone runs on GPU.
#  - pandas/pyarrow for CSV/parquet load + per-column distribution metrics.
#  - TabDDPM (rotot0/tab-ddpm) — default framework: denoising diffusion over a
#    mixed numeric/categorical feature matrix with class-conditional synthesis.
#    TabSyn (amazon-science/tabsyn, latent diffusion) is the alternative; installed
#    from GitHub (no PyPI wheel). Pinned pip installs from source are wired at
#    CI/ops time.
RUN pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
         torch==2.5.1 \
    && pip install --prefer-binary pandas pyarrow numpy scipy scikit-learn mlflow
# TabDDPM (default) + TabSyn (alt) frameworks — no PyPI wheels, installed from
# GitHub. TODO(ops): pin each to a reviewed commit (append @<sha>) and verify the
# build resolves against torch 2.5.1 / pandas before a real run. tabular_diffusion
# lazy-imports the framework, so a build without these still passes the import
# smoke, but a real run needs them present.
RUN pip install --no-build-isolation "git+https://github.com/rotot0/tab-ddpm.git" || \
      echo "WARN: tab-ddpm install failed — pin a reviewed commit and resolve deps" \
    && pip install --no-build-isolation "git+https://github.com/amazon-science/tabsyn.git" || \
      echo "WARN: TabSyn install failed — pin a reviewed commit and resolve deps"

# The ml_training package at top-level → `python -m ml_training.cli`.
COPY backend/lib/galaxy/ai/ml_training /app/ml_training
RUN rm -rf /app/ml_training/tests
WORKDIR /app
ENV PYTHONPATH=/app

# Build-time smoke: package + trainer imports (the trainer must import WITHOUT
# the framework/torch present — lazy-import guard) + CLI arg-parse. The concrete
# TabDDPM/TabSyn import is exercised at runtime on GPU, not at build.
RUN python -c "import ml_training.config, ml_training.cli, ml_training.tabular_diffusion_trainer; print('tabular-diffusion-training image OK')" \
    && python -m ml_training.cli --help >/dev/null

# NO ENTRYPOINT — this is a Nextflow PROCESS image (see ml-training.Dockerfile).
