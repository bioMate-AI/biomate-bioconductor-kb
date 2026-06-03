# BioMate TranscriptFormer GPU Container (full)
#
# Workflow: virtual_cell/transcriptformer_gpu/main.nf
#
# FULL GPU implementation of cell-state embedding / classification /
# perturbation using CZI TranscriptFormer (Apache 2.0). Bakes
# `transcriptformer` so the workflow no longer pip-installs at runtime.
#
# Reference:
#   - CZI TranscriptFormer v0.6.0 (Apache 2.0)
#   - https://github.com/czi-ai/transcriptformer
#   - Trained on 112M cells across 12 species
#
# Instance requirements:
#   - g5.2xlarge (A10G 24GB VRAM) recommended
#
# ECR build (x86_64 for AWS Batch):
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/transcriptformer-gpu-nf:1.0 \
#     --push -f backend/docker/transcriptformer-gpu-nf/Dockerfile .
#
# Local build:
#   docker build -t biomate/transcriptformer-gpu-nf:latest \
#     -f backend/docker/transcriptformer-gpu-nf/Dockerfile .

FROM --platform=linux/amd64 pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

LABEL maintainer="BioMate Team"
LABEL description="transcriptformer-gpu-nf: CZI TranscriptFormer GPU embed/classify/perturb"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV TORCH_HOME=/models/torch_cache
ENV HF_HOME=/models/huggingface_cache
ENV TRANSFORMERS_CACHE=/models/huggingface_cache
ENV TRANSCRIPTFORMER_DIR=/models/transcriptformer

# ── System dependencies ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        wget \
        build-essential \
        libhdf5-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        awscli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Core single-cell data stack ────────────────────────────────────────────
RUN pip install --no-cache-dir \
        anndata==0.10.8 \
        scanpy==1.10.1 \
        h5py==3.11.0 \
        scipy==1.13.1 \
        numpy==1.26.4 \
        pandas==2.2.2 \
        transformers==4.41.2

# ── CZI TranscriptFormer (PyPI release) ───────────────────────────────────
RUN pip install --no-cache-dir transcriptformer==0.6.1

WORKDIR /work
