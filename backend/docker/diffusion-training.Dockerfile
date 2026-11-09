# BioMate diffusion-training image — protein/peptide structure diffusion (RFdiffusion).
#
# SEPARATE from ml-training.Dockerfile AND trl-training.Dockerfile on purpose:
# RFdiffusion runs on the RoseTTAFold2 SE(3)-Transformer, which needs a torch-cuda
# build plus dgl / e3nn / hydra / se3-transformer pins that conflict with BOTH
# Ludwig 0.10.4's pins (torch==2.2.2, pyarrow<15) and TRL 0.24's
# (transformers==4.56.1). Co-installing is unresolvable, so structure diffusion
# ships in its own image. All three images expose the SAME
# `python -m ml_training.cli` entrypoint; the CLI dispatches
# model_type=protein_diffusion → diffusion_trainer.py, which lazy-imports
# rfdiffusion/torch.
#
# The executor picks this image for model_type=protein_diffusion via
# DIFFUSION_TRAINING_IMAGE (executor_payload._resolve_container +
# nextflow_executor.py container auto-select). The .nf wrapper carries
# `label 'process_gpu'`, so it lands on the GPU Batch queue.
#
# Build context = repo root (so the COPY path resolves). This is a SPEC — the
# actual build/push is a CI/ops step (see .github/workflows; a
# diffusion-training-image.yml mirrors trl-training-image.yml). It is NOT built in
# this session (no speculative GPU/Batch spend — CLAUDE.md).
#
# --- Base: CUDA + Python ---------------------------------------------------
# RFdiffusion targets CUDA 11.x. Use the runtime CUDA base (devel only if a
# source build of SE(3)-Transformer is needed). A GPU builder/runner is required.
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive

# procps → `ps` (Nextflow task wrapper); git for the RFdiffusion source; build libs.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3-pip python3.10-dev build-essential git \
        libgomp1 curl unzip ca-certificates procps \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 — the .nf TRAIN process stages the S3 structure set + outputs.
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Python deps.
#  - CUDA torch to match the base image's CUDA 11.8.
#  - RFdiffusion's SE(3) stack: dgl (cuda build), e3nn, hydra-core, omegaconf,
#    icecream, and the RFdiffusion package + its SE3Transformer submodule (installed
#    from source; the released weights are fetched separately at run time or baked
#    into a data layer — NOT vendored in this spec).
#  - biotite/biopython for PDB/mmCIF parsing in load_structure_set.
#  - mlflow so the tracker's real backend is available.
RUN python -m pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cu118 \
         torch==2.1.2+cu118 \
    && pip install \
         "dgl==1.1.3" e3nn==0.5.1 hydra-core==1.3.2 omegaconf==2.3.0 icecream \
         biotite biopython numpy scipy mlflow

# RFdiffusion from source (RosettaCommons/RFdiffusion, BSD-2). The SE3Transformer
# submodule is installed as an editable package. Weights (Base_ckpt.pt, etc.) are
# provided at run time via DIFFUSION_WEIGHTS_DIR / an S3 data layer — see the
# design doc §deferred; they are large and license-gated so are NOT baked here.
RUN git clone --depth 1 https://github.com/RosettaCommons/RFdiffusion.git /opt/RFdiffusion \
    && pip install /opt/RFdiffusion/env/SE3Transformer \
    && pip install --no-deps -e /opt/RFdiffusion
ENV PYTHONPATH=/opt/RFdiffusion:/app

# The ml_training package at top-level → `python -m ml_training.cli`.
COPY backend/lib/galaxy/ai/ml_training /app/ml_training
RUN rm -rf /app/ml_training/tests
WORKDIR /app

# Build-time smoke: package + CLI + the diffusion trainer import (the trainer
# lazy-imports rfdiffusion so this succeeds even before the weights are staged;
# it catches missing trainer submodule deps at build, not on Batch).
RUN python -c "import ml_training.config, ml_training.cli, ml_training.diffusion_trainer; import torch, rfdiffusion; print('diffusion-training image OK', torch.__version__)" \
    && python -m ml_training.cli --help >/dev/null

# NO ENTRYPOINT — this is a Nextflow PROCESS image (see ml-training.Dockerfile).
