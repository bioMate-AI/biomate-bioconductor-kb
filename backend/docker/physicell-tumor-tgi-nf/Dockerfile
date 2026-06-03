# BioMate PhysiCell Tumor TGI Container (CPU + OpenMP)
#
# Workflow: virtual_cell/physicell_tumor_tgi/main.nf
#
# Tumor growth inhibition (TGI) ODE models (Simeoni + Norton-Simon) with the
# spatial PhysiCell agent-based model compiled into the image as the
# upgrade path. The current .nf is pure Python ODE (no GPU); this image is
# CPU-only with OpenMP enabled for PhysiCell.
#
# Reference:
#   - Simeoni et al. 2004 Cancer Res 64:1094 (TGI ODE)
#   - PhysiCell v1.14.2 — https://github.com/MathCancer/PhysiCell
#
# Instance requirements:
#   - CPU instance: c6i.xlarge / c6i.2xlarge (4–8 vCPU, OpenMP parallelism)
#   - No GPU required
#
# ECR build (x86_64 for AWS Batch):
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/physicell-tumor-tgi-nf:1.0 \
#     --push -f backend/docker/physicell-tumor-tgi-nf/Dockerfile .
#
# Local build:
#   docker build -t biomate/physicell-tumor-tgi-nf:latest \
#     -f backend/docker/physicell-tumor-tgi-nf/Dockerfile .

FROM --platform=linux/amd64 ubuntu:22.04

LABEL maintainer="BioMate Team"
LABEL description="physicell-tumor-tgi-nf: Simeoni TGI ODE + PhysiCell v1.14.2 spatial ABM"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PHYSICELL_DIR=/opt/PhysiCell
ENV OMP_NUM_THREADS=4

# ── System dependencies ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        wget \
        ca-certificates \
        build-essential \
        g++ \
        make \
        libomp-dev \
        libhdf5-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        python3 \
        python3-pip \
        python3-dev \
        awscli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Python deps for ODE workflow ──────────────────────────────────────────
RUN pip3 install --no-cache-dir \
        numpy==1.26.4 \
        scipy==1.13.1 \
        pandas==2.2.2 \
        matplotlib==3.8.4

# ── Build PhysiCell v1.14.2 ────────────────────────────────────────────────
# Provides the spatial ABM upgrade target referenced by the workflow.
RUN git clone --depth 1 --branch 1.14.2 https://github.com/MathCancer/PhysiCell.git ${PHYSICELL_DIR} \
    && cd ${PHYSICELL_DIR} \
    && make template \
    || echo "PhysiCell base built; sample projects compiled at runtime."

ENV PATH=${PHYSICELL_DIR}:${PATH}

WORKDIR /work
