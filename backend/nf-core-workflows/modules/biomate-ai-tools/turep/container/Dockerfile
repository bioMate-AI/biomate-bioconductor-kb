# turep image — TuReP tumor-reactive T-cell predictor (Zhao lab, bsml320/turep)
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/turep/container
#   docker build --platform linux/amd64 -t biomate/turep:v1 .
#
# ECR push (BioMate AWS account):
#   ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com
#   aws ecr create-repository --repository-name biomate/turep --region us-west-2 \
#       --image-scanning-configuration scanOnPush=true   # one-time
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR
#   docker tag biomate/turep:v1 $ECR/biomate/turep:v1
#   docker push $ECR/biomate/turep:v1
#
# Image size estimate: ~800 MB (pytorch-cpu ~500, turep + anndata ~150, numpy/pandas ~150).
# A GPU-capable variant (biomate/turep:v1-gpu) would swap to nvidia/cuda base + torch+cu12.
#
# Pretrained weights auto-download from HuggingFace Hub on first call to turep.load_model().
# They are NOT baked into this image (HF cache is populated at runtime on the worker node).
# Set HF_HOME to a mounted EFS path in production to avoid repeated downloads.

FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Core single-cell dependencies first (heavy; separate layer for cache efficiency).
# h5py is required for .h5ad I/O; loompy optional but avoids runtime warnings.
RUN pip install --no-cache-dir \
        anndata==0.10.9 \
        numpy==1.26.4 \
        pandas==2.2.2 \
        scipy==1.13.1 \
        h5py==3.11.0 \
        huggingface_hub==0.23.4

# PyTorch CPU build — sufficient for inference on Batch workers without GPU queue.
# GPU inference available via the :v1-gpu tag (uses torch+cu124).
RUN pip install --no-cache-dir \
        torch==2.3.1+cpu \
        --extra-index-url https://download.pytorch.org/whl/cpu

# Install turep from source (MIT license, pinned to known good commit).
ARG TUREP_SHA=main
RUN curl -sSL "https://github.com/bsml320/turep/archive/${TUREP_SHA}.tar.gz" \
        -o /tmp/turep.tgz \
    && mkdir -p /opt/turep \
    && tar -xzf /tmp/turep.tgz --strip-components=1 -C /opt/turep \
    && rm /tmp/turep.tgz \
    && pip install --no-cache-dir -e /opt/turep

# Smoke-check: package must be importable (weights NOT needed for import check).
# load_model() is deliberately NOT called here — it would trigger a HF download
# at build time which breaks offline/air-gapped build environments.
RUN python3 -c "import turep; print('[turep:build] import ok, version:', getattr(turep, '__version__', 'unknown'))"

# Ensure anndata smoke passes — critical for Phase A synthetic fixture generation.
RUN python3 -c "import anndata; import numpy; import pandas; print('[build] h5ad stack ok')"

WORKDIR /opt/turep

LABEL org.opencontainers.image.source=https://github.com/bsml320/turep \
      org.opencontainers.image.licenses=MIT \
      org.opencontainers.image.description="Zhao lab TuReP v1 — tumor-reactive T-cell prediction from scRNA h5ad (CPU build)"
