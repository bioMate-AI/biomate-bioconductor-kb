# TorchGWAS image — bakes the Zhi-lab CLI + shipped toy dataset for smoke runs.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/container
#   docker build --platform linux/amd64 -t biomate/torchgwas:v1 .
#
# ECR push (BioMate AWS account, mirrors the scGWAS pattern shipped earlier):
#   ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com
#   aws ecr create-repository --repository-name biomate/torchgwas --region us-west-2 \
#       --image-scanning-configuration scanOnPush=true   # one-time
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR
#   docker tag biomate/torchgwas:v1 $ECR/biomate/torchgwas:v1
#   docker push $ECR/biomate/torchgwas:v1

FROM python:3.11-slim

# PyTorch CPU build is plenty for the toy dataset (64 samples × 12 variants).
# GPU build is a separate image tag (biomate/torchgwas:v1-gpu) when GPU
# dispatch is needed for realistic 1000G / UKB scale.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Pinned to a known good commit; bump SHA when re-cutting.
ARG TORCHGWAS_SHA=main
RUN curl -sSL "https://github.com/ZhiGroup/TorchGWAS/archive/${TORCHGWAS_SHA}.tar.gz" \
        -o /tmp/torchgwas.tgz \
    && mkdir -p /opt/torchgwas \
    && tar -xzf /tmp/torchgwas.tgz --strip-components=1 -C /opt/torchgwas \
    && rm /tmp/torchgwas.tgz

# Install with editable so the `torchgwas` CLI lands in PATH.
# Upstream pyproject.toml omits pandas-plink and bgen-reader (used in io.py
# for PLINK and BGEN genotype sources). Install them explicitly; without
# pandas-plink the CLI fails on import. Filed mental note to upstream
# the dependency declaration in a follow-up.
RUN pip install --no-cache-dir -e /opt/torchgwas \
    && pip install --no-cache-dir 'pandas-plink>=2.2' 'bgen-reader>=4.0' \
    && torchgwas --help | head -5

# Toy dataset already at /opt/torchgwas/examples/toy/ (64 samples × 12 variants
# × 3 phenotypes × 4 covariates), shipped with the upstream repo.

WORKDIR /opt/torchgwas

LABEL org.opencontainers.image.source=https://github.com/ZhiGroup/TorchGWAS \
      org.opencontainers.image.licenses=MIT \
      org.opencontainers.image.description="ZhiGroup/TorchGWAS CPU + shipped toy dataset"
