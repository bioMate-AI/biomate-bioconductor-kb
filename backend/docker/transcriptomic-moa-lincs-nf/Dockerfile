# BioMate transcriptomic_moa_lincs container (CPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/transcriptomic_moa_lincs
# Queries LINCS L1000 connectivity-map signatures via REST + scores MOA matches.
#
# Base (biomate-nextflow-base) provides numpy<2, scipy, pandas, awscli, gget.
# This image adds requests for HTTP API calls.
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/transcriptomic-moa-lincs-nf:1.0 \
#     --push -f backend/docker/transcriptomic-moa-lincs-nf/Dockerfile .

FROM --platform=linux/amd64 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="transcriptomic-moa-lincs-nf: LINCS L1000 MOA signature scoring (REST + pandas)"
LABEL version="1.0.0"

RUN pip install --no-cache-dir requests==2.32.3

WORKDIR /work
