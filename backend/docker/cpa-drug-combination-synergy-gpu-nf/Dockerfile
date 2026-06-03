# BioMate cpa_drug_combination_synergy container (GPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/cpa_drug_combination_synergy
# Same CPA stack as cpa-synergy-gpu-nf but separate image keeps drug-combo
# scoring deps isolated and independently versionable (Bliss/Loewe scoring,
# combo-specific helpers can diverge without touching the cell-line image).
#
# Instance: g4dn.xlarge (T4 16 GB) or g5.xlarge (A10G 24 GB).
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cpa-drug-combination-synergy-gpu-nf:1.0 \
#     --push -f backend/docker/cpa-drug-combination-synergy-gpu-nf/Dockerfile .

FROM --platform=linux/amd64 pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="BioMate Team"
LABEL description="cpa-drug-combination-synergy-gpu-nf: CPA + scvi-tools + synergy scoring (Bliss/Loewe)"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget unzip ca-certificates build-essential libhdf5-dev libxml2-dev \
    && curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws /var/lib/apt/lists/*

# Let cpa-tools resolve its compatible scvi-tools/anndata pins
RUN pip install --no-cache-dir \
        cpa-tools==0.8.6 \
        scanpy \
        h5py \
        rdkit==2024.3.3 \
        synergy==1.0.0

WORKDIR /work
