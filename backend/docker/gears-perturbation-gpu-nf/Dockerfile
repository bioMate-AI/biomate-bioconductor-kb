# BioMate gears_perturbation_gpu container (GPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/gears_perturbation_gpu
# GEARS (Roohani et al. 2024 Nature Biotech): graph-based gene perturbation
# prediction on GPU.
#
# Instance: g4dn.xlarge (T4 16 GB).
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gears-perturbation-gpu-nf:1.0 \
#     --push -f backend/docker/gears-perturbation-gpu-nf/Dockerfile .

FROM --platform=linux/amd64 pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="BioMate Team"
LABEL description="gears-perturbation-gpu-nf: GEARS gene-perturbation prediction (torch-geometric)"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget unzip ca-certificates build-essential libhdf5-dev libxml2-dev \
    && curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        anndata==0.10.8 \
        scanpy==1.10.1 \
        h5py==3.11.0 \
        scvi-tools==1.1.6

# torch-geometric stack must match the torch 2.2 / CUDA 12.1 base
RUN pip install --no-cache-dir \
        torch-scatter \
        torch-sparse \
        torch-cluster \
        torch-spline-conv \
        -f https://data.pyg.org/whl/torch-2.2.0+cu121.html
RUN pip install --no-cache-dir torch-geometric==2.5.3 cell-gears==0.1.2

WORKDIR /work
