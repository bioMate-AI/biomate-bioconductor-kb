# BioMate cpa_synergy_gpu container (GPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/cpa_synergy_gpu
# Compositional Perturbation Autoencoder (Lotfollahi et al. 2023 MSB) on GPU
# for drug-combination synergy prediction.
#
# Base matches ai-tools/state convention (pytorch 2.2 + CUDA 12.1).
# Bakes in deps previously pip-installed at workflow runtime (eliminates Gap-3).
#
# Instance: g4dn.xlarge (T4 16 GB) or g5.xlarge (A10G 24 GB).
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cpa-synergy-gpu-nf:1.0 \
#     --push -f backend/docker/cpa-synergy-gpu-nf/Dockerfile .

FROM --platform=linux/amd64 pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="BioMate Team"
LABEL description="cpa-synergy-gpu-nf: Compositional Perturbation Autoencoder (CPA) + scvi-tools, drug-combo synergy"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget unzip ca-certificates build-essential libhdf5-dev libxml2-dev \
    && curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws /var/lib/apt/lists/*

# Let cpa-tools resolve its compatible scvi-tools/anndata pins (older cpa-tools
# is incompatible with scvi-tools 1.1.x; pip resolves the right combo).
RUN pip install --no-cache-dir \
        cpa-tools==0.8.6 \
        scanpy \
        h5py \
        rdkit==2024.3.3

WORKDIR /work
