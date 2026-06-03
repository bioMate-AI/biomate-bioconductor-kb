# BioMate ode_signaling_simulation container (CPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/ode_signaling_simulation
# Replaces previous reliance on the heavyweight biomni-tools image.
#
# Base (biomate-nextflow-base) already provides: python3.11, awscli v2,
# numpy<2 (RDKit ABI), scipy, pandas, biopython, rdkit, procps, gget.
# This image adds only matplotlib for plot generation.
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ode-signaling-nf:1.0 \
#     --push -f backend/docker/ode-signaling-nf/Dockerfile .

FROM --platform=linux/amd64 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="ode-signaling-nf: ODE signaling pathway simulator (numpy/scipy + matplotlib)"
LABEL version="1.0.0"

RUN pip install --no-cache-dir matplotlib==3.9.2

WORKDIR /work
